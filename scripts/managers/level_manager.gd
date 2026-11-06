class_name LevelManager
extends Node
## Orchestrator for the gameplay scene: wires systems together and runs the level loop
##   READY -> PLAYING -> EXTRACTING -> (next level) READY ...
##   PLAYING -> FAILED (progress reached 0 after the first valid tap) -> TRY AGAIN -> READY
## Runs while the tree is paused so it can handle pause / resume itself.

@onready var _input: InputController = $InputController
@onready var _extraction: ExtractionManager = $ExtractionManager
@onready var _difficulty: DifficultyManager = $DifficultyManager
@onready var _timers: TimerManager = $TimerManager
@onready var _sword: SwordController = $Stage/Sword
@onready var _camera: GameplayCamera = $Stage/Camera3D
@onready var _hud: Hud = $Hud
@onready var _failure_screen: FailureScreen = $FailureScreen
@onready var _pause_menu: PauseMenu = $PauseMenu
@onready var _audio: GameAudio = $Audio
@onready var _forest: ForestEnvironment = $Stage/Forest
@onready var _stump: StumpBuilder = $Stage/Stump
var _fx: ExtractionFx   ## 1.11-1.14: compression, cracks and glow, all driven by one smoothed progress value
var _finale: FinaleTheme  ## the look of level 9999

## A sword has been extracted: level, level time, tap count, how strong the reward moment is (0..1).
signal level_completed(level: int, seconds: float, taps: int, intensity: float)

## Debug-only switches (debug builds read them from user://launch_args.txt) used to find what the extraction costs on
## the phone: --no-cam-fx (no camera move), --no-light-fx (no sun change), --no-card (no level card), --no-slot (no cut).
var _debug_args: PackedStringArray = PackedStringArray()
var _level_taps: int = 0           # in-rhythm taps that added progress on the current level
var _completion: Dictionary = {}   # data of the extraction being celebrated, used when the blade comes free

## Non-difficulty gameplay settings (post-retry input lock). Falls back to defaults if unset.
@export var gameplay_config: GameplayConfig

## How the MAIN MENU button changes scene. A variable so tests can observe it without
## actually leaving the test scene.
var scene_changer: Callable = func(path: String) -> void: get_tree().change_scene_to_file(path)

## Where the pause menu's QUIT goes when there is no main menu yet: leave the application.
## (A variable so tests can observe it without ending the test process.)
var app_quitter: Callable = func() -> void: get_tree().quit()
const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"
## Level of the forest ambience during play (dB below the file): quieter than in the menu, so it never competes with the taps.
const AMBIENCE_DB := -27.0

func _ready() -> void:
	PerfProbe.mark("level_manager_ready")
	_debug_args = RenderQuality.launch_arguments()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if gameplay_config == null:
		gameplay_config = GameplayConfig.new()
	# Gameplay systems stop while paused; this node (and the pause overlay logic) keeps running.
	for system: Node in [_input, _extraction, _timers, $Stage]:
		system.process_mode = Node.PROCESS_MODE_PAUSABLE

	_difficulty.difficulty_changed.connect(_on_difficulty_changed)
	_difficulty.rhythm_changed.connect(_on_rhythm_changed)
	_difficulty.resistance_changed.connect(func(value: float) -> void: _extraction.resistance = value)
	_difficulty.speed_changed.connect(_extraction.configure_speed)
	_input.rhythm_enabled = gameplay_config.rhythm_enabled
	_input.tap_accepted.connect(_on_tap_accepted)
	_extraction.valid_tap_applied.connect(_on_valid_tap_applied)
	_extraction.progress_changed.connect(_sword.set_progress)
	_extraction.progress_changed.connect(_on_progress_for_tension)
	_extraction.decay_started.connect(_sword.set_slipping.bind(true))
	_extraction.decay_stopped.connect(_sword.set_slipping.bind(false))
	_extraction.extraction_completed.connect(_on_extraction_completed)
	_extraction.progress_depleted.connect(_on_progress_depleted)
	_failure_screen.retry_requested.connect(_restart_run)
	_failure_screen.main_menu_requested.connect(_open_main_menu)
	_pause_menu.resume_requested.connect(_resume_from_menu)
	_pause_menu.quit_requested.connect(_quit_from_menu)
	_pause_menu.set_preview_audio(_audio)
	_fx = ExtractionFx.new()
	_fx.name = "ExtractionFx"
	$Stage.add_child(_fx)  # under the Stage, so it pauses with it
	_fx.setup(_forest, _stump)
	_extraction.progress_changed.connect(_fx.set_progress)
	_finale = FinaleTheme.new()  # level 9999 only: a different sky, stump and sword (nothing is built until it is reached)
	_finale.name = "FinaleTheme"
	$Stage.add_child(_finale)
	_finale.setup(_forest, _stump, _sword)
	# 1.18: the forest ambience (very quiet) and a soft click for the existing buttons. Presentation only: nothing here touches gameplay.
	_audio.play_ambience(AMBIENCE_DB, 2.5)
	for button_signal: Signal in [_pause_menu.resume_requested, _pause_menu.quit_requested, _failure_screen.retry_requested, _failure_screen.main_menu_requested]:
		button_signal.connect(func() -> void: _audio.play(&"ui_tap"))
	_sword.planted.connect(_camera.shake.bind(0.7))
	_sword.planted.connect(func() -> void: _audio.play(&"planted"))
	_sword.freed.connect(_on_sword_freed)
	GameManager.state_changed.connect(_on_state_changed)
	_hud.setup(_extraction, _timers, _input)
	_hud.show_preset_label(_difficulty.preset_name)

	GameManager.reset_run()
	_timers.reset_session()
	_apply_mode_difficulty()
	Progress.begin_run(Progress.selected_mode)
	_start_level_sequence(true)

## Ruthless plays on its own, harder difficulty resource. Endless keeps the existing configuration. A --difficulty-preset given on the
## command line (playtesting) still wins, and nothing is shown on the HUD for either mode.
func _apply_mode_difficulty() -> void:
	if _difficulty.preset_name != "default":
		return
	var path := GameMode.difficulty_path(Progress.selected_mode)
	if ResourceLoader.exists(path):
		var loaded := load(path)
		if loaded is DifficultyConfig:
			_difficulty.config = loaded

## Prepare a fresh attempt for GameManager.level, then drop a new sword in.
func _start_level_sequence(first_level: bool) -> void:
	GameManager.set_state(GameManager.State.EXTRACTING)  # locks input during the entrance
	_finale.apply(GameManager.level >= GameManager.MAX_LEVEL)
	_difficulty.apply_for_level(GameManager.level)
	_extraction.reset()
	_timers.reset_level()
	_input.reset_alternation()
	_level_taps = 0
	_fx.reset()
	_sword.reset_pose()
	await _sword.play_entrance()
	_extraction.set_active(true)
	GameManager.set_state(GameManager.State.READY)

func _on_difficulty_changed(_level: int, gain: float, decay: float, grace: float) -> void:
	_extraction.configure(gain, decay, grace)

## The allowed tap interval for the current level (or the designer override).
func _on_rhythm_changed(level_max_interval_msec: float) -> void:
	var limit := float(gameplay_config.max_tap_interval_override_msec) if gameplay_config.max_tap_interval_override_msec > 0 \
		else level_max_interval_msec
	_input.max_interval_msec = limit
	_extraction.zero_progress_extra_seconds = limit / 1000.0 if gameplay_config.rhythm_enabled else 0.0

func _on_state_changed(state: GameManager.State) -> void:
	_input.enabled = GameManager.is_input_allowed()

func _on_tap_accepted(_side: TapSide.Side) -> void:
	if GameManager.state == GameManager.State.READY:
		GameManager.set_state(GameManager.State.PLAYING)
	_timers.notify_valid_input()  # the attempt (and both timers) start with the first accepted tap
	match _input.last_kind:
		TapKind.Kind.FIRST:
			_extraction.begin_attempt()  # anchors the rhythm; awards nothing
			_audio.play(&"first_tap")
		TapKind.Kind.PROGRESS:
			_level_taps += 1  # debug only (PerfProbe): taps are never shown to the player and never required
			_extraction.register_valid_tap(_input.last_interval_msec)  # the measured interval decides what the tap is worth
			_audio.play(&"tap", _extraction.progress / 100.0)
		TapKind.Kind.TOO_SLOW:
			_extraction.register_slow_tap()
			_audio.play(&"tap_slow")
	PerfProbe.tap(_input.last_kind, _input.last_interval_msec, _extraction.progress)

## Phase A of the extraction: the camera creeps in and the clearing dims a little as the last part of the pull nears.
func _on_progress_for_tension(progress: float) -> void:
	if "--no-cam-fx" not in _debug_args and "--no-cam-tension" not in _debug_args:
		_camera.set_tension_from_progress(progress)
	if "--no-light-fx" not in _debug_args:
		_forest.set_tension(smoothstep(70.0, 100.0, progress))

func _on_valid_tap_applied(_gain: float, _progress: float) -> void:
	_sword.on_valid_tap()

## How big the reward moment is: 0 on level 1, growing by a tenth per level up to 1 from level 11.
static func reward_intensity(level: int) -> float:
	return clampf(float(level - 1) / 10.0, 0.0, 1.0)

func _on_extraction_completed() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return  # a run that has failed (or is mid-animation) can never also complete a level
	GameManager.set_state(GameManager.State.EXTRACTING)  # state change happens immediately...
	var level_time := _timers.stop_level()
	var completed_level := GameManager.level
	GameManager.extraction_succeeded.emit(completed_level, level_time)
	var intensity := reward_intensity(completed_level)
	_completion = {"level": completed_level, "seconds": level_time, "taps": _level_taps, "intensity": intensity,
		"extractions": GameManager.run_extractions, "session": _timers.session_seconds()}
	level_completed.emit(completed_level, level_time, _level_taps, intensity)
	PerfProbe.mark("level_%d_done_taps_%d_secs_%.1f" % [completed_level, _level_taps, level_time])
	_audio.play(&"pull", intensity)
	_fx.anticipate()  # cracks and glow reach their maximum during the anticipation, before the blade is released
	await _sword.play_extraction(intensity)  # ...the cinematic runs without blocking anything else
	if completed_level >= GameManager.MAX_LEVEL:
		_complete_run()  # the last sword is drawn: there is no level 10000
		return
	GameManager.advance_level()
	_start_level_sequence(false)

## Level 9999 is done: the run ends in victory (recorded like any run, shown on the same screen with its own words).
func _complete_run() -> void:
	var result := RunResult.new()
	result.end_reason = RunResult.EndReason.COMPLETED
	result.mode = Progress.run_mode
	result.completed_level = GameManager.MAX_LEVEL
	result.level_reached = GameManager.MAX_LEVEL
	result.extractions = GameManager.run_extractions
	result.final_level_seconds = _timers.level_seconds()
	result.session_seconds = _timers.stop_session()
	Progress.end_run("completed")
	_extraction.set_active(false)
	GameManager.run_over = true
	GameManager.set_state(GameManager.State.FAILED)
	GameManager.publish_run_result(result)
	_failure_screen.show_result(result)

## The blade has left the wood: camera impact, a swell of sunlight, the level card and the sounds.
func _on_sword_freed() -> void:
	if _completion.is_empty():
		return
	var intensity: float = _completion["intensity"]
	_fx.release()  # the compression unwinds, the glow closes
	if "--no-cam-fx" not in _debug_args:
		_camera.impact(intensity, SwordController.extraction_after_release_seconds(intensity))
	if "--no-light-fx" not in _debug_args:
		_forest.pulse_light(intensity)
		_forest.gust(intensity)  # the undergrowth leans and settles as the sword comes free
	if "--no-card" not in _debug_args:
		_hud.show_level_complete(_completion["level"], _completion["seconds"], _completion["extractions"],
			SwordController.extraction_hold_seconds(intensity))
	_audio.play(&"freed", intensity)
	_audio.play(&"level_complete", intensity)

# ---- Failure ---------------------------------------------------------------------------------

## Progress reached 0 after the player started the attempt. begin_failure() is the single
## gate: it only succeeds once, and only while PLAYING (so never before the first valid tap,
## never during the success animation, never while paused).
func _on_progress_depleted() -> void:
	if not GameManager.begin_failure():
		return
	# From here input is already disabled (state is FAILED). Freeze everything that counts.
	_extraction.set_active(false)
	var result := RunResult.new()
	result.level_reached = GameManager.level
	result.completed_level = maxi(GameManager.level - 1, 0)
	result.mode = Progress.run_mode
	result.extractions = GameManager.run_extractions
	result.final_level_seconds = _timers.stop_level()
	result.session_seconds = _timers.stop_session()
	GameManager.publish_run_result(result)
	Progress.end_run("failed")
	_audio.play(&"failure")
	_fx.fade_out()
	await _sword.play_failure()
	if not GameManager.run_over:
		return  # the run was reset while the animation played; show nothing
	_failure_screen.show_result(result)

## TRY AGAIN: a completely fresh run. Lifetime records are not touched (none exist yet).
func _restart_run() -> void:
	if GameManager.state != GameManager.State.FAILED:
		return  # ignore stray / duplicate presses
	GameManager.reset_run()
	_finale.apply(false)  # back to the ordinary forest after the last level
	_timers.reset_level()
	_timers.reset_session()
	Progress.begin_run(Progress.selected_mode)
	_difficulty.apply_for_level(GameManager.level)
	_extraction.reset()
	_input.reset_alternation()
	_fx.reset()
	_sword.restore_embedded()
	_camera.reset_framing()
	_failure_screen.hide_screen()
	_extraction.set_active(true)
	GameManager.set_state(GameManager.State.READY)
	# Protect against the extra taps of a double-press on TRY AGAIN starting the next attempt.
	_input.lock_for(gameplay_config.retry_input_lock_seconds)

func _open_main_menu() -> void:
	var path := _failure_screen.main_menu_scene_path
	if GameManager.state != GameManager.State.FAILED or not ResourceLoader.exists(path):
		return
	scene_changer.call(path)

# ---- Pause / lifecycle -------------------------------------------------------------------------

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if not _invalidate_ruthless_run("background"):
				_pause()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_on_back_requested()

## RUTHLESS: leaving the foreground (Home, app switch, screen lock: all reach us as focus-out / paused notifications) ends the run.
## The invalidation is written to disk first, then the run-ended screen is prepared, so it is waiting when the player comes back.
## Ordinary things inside the game (level card, entrance, the in-app pause menu) never send these notifications. Returns true if it
## ended a run. Not detectable by Godot on Android: the notification shade (documented limitation).
func _invalidate_ruthless_run(reason: String) -> bool:
	if GameManager.state == GameManager.State.FAILED or not Progress.invalidate_run(reason):
		return false
	var result := RunResult.new()
	result.end_reason = RunResult.EndReason.INVALIDATED
	result.mode = Progress.run_mode
	result.completed_level = Progress.highest_completed_level()
	result.level_reached = GameManager.level
	result.extractions = GameManager.run_extractions
	result.final_level_seconds = _timers.stop_level()
	result.session_seconds = _timers.stop_session()
	Progress.end_run("invalidated")
	_extraction.set_active(false)
	_pause_menu.hide_menu()
	_hud.set_pause_overlay_suppressed(false)
	get_tree().paused = false  # the run-ended screen must be usable the moment the player returns
	GameManager.run_over = true
	GameManager.set_state(GameManager.State.FAILED)
	GameManager.publish_run_result(result)
	_failure_screen.show_result(result)
	return true

## Android Back (or Escape on desktop):
##  - while playing (READY / PLAYING / EXTRACTING) it pauses and opens the pause menu;
##  - while the menu is open it resumes (Back toggles);
##  - after losing focus (plain "tap to resume" pause) it upgrades to the menu;
##  - on the failure screen it does nothing: the run is already over and TRY AGAIN is on screen.
func _on_back_requested() -> void:
	if _pause_menu.back_belongs_to_settings():
		return  # Back closes the settings panel (it handles that itself); it must not resume the game
	match GameManager.state:
		GameManager.State.FAILED:
			return
		GameManager.State.PAUSED:
			if _pause_menu.is_showing:
				_resume_from_menu()
			else:
				_open_pause_menu()
		_:
			_pause()
			_open_pause_menu()

func _open_pause_menu() -> void:
	# A run is "in progress" once the first valid tap started the session timer.
	var run_in_progress := _timers.session_seconds() > 0.0
	_hud.set_pause_overlay_suppressed(true)
	_pause_menu.show_menu(gameplay_config.confirm_quit_during_run and run_in_progress)

## RESUME: exactly the state the player left (the tree was paused, so nothing moved).
func _resume_from_menu() -> void:
	_pause_menu.hide_menu()
	_hud.set_pause_overlay_suppressed(false)
	if GameManager.state != GameManager.State.PAUSED:
		return
	_input.reset_alternation()  # the resume press must not count as the next alternating tap
	_timers.resume()
	GameManager.resume_game()

## QUIT: abandons the session without a game-over. With no main menu yet this leaves the app.
## Nothing here emits run_failed or touches records.
func _quit_from_menu() -> void:
	Progress.end_run("left")
	_pause_menu.hide_menu()
	_hud.set_pause_overlay_suppressed(false)
	if ResourceLoader.exists(MAIN_MENU_PATH):
		_input.reset_alternation()
		_timers.resume()
		GameManager.resume_game()  # a new scene must not start paused
		scene_changer.call(MAIN_MENU_PATH)
	else:
		app_quitter.call()

func _pause() -> void:
	if GameManager.state == GameManager.State.PAUSED:
		return
	_timers.pause()
	GameManager.pause_game()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_on_back_requested()  # Escape = Back on desktop
		get_viewport().set_input_as_handled()
		return
	if GameManager.state != GameManager.State.PAUSED or _pause_menu.is_showing:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed)
	if pressed:
		_input.reset_alternation()  # a resume tap must not count as the next alternating tap
		_timers.resume()
		GameManager.resume_game()
		get_viewport().set_input_as_handled()
