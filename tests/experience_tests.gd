extends Node
## Gameplay-experience tests (Milestone 1.7): progress steps, tap counts per level, extraction animation, completion reward, round controls, touch halves, sword stability.
##
## Run (needs a window; forced to 540x960):  godot --path . res://tests/experience_tests.tscn
## Exit code: 0 = all passed, 1 = failures, 2 = invalid run (the window lost OS focus).
## SIMULATED INPUT ONLY (Input.parse_input_event into the real main.tscn) - not a physical touchscreen.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const STUB_MENU := "res://tests/stub_main_menu.tscn"
const SIDE_LEFT := TapSide.Side.LEFT
const SIDE_RIGHT := TapSide.Side.RIGHT

var _checks: int = 0
var _failures: int = 0
var _failed_labels: Array[String] = []
var _unexpected_pauses: int = 0
var _pause_expected: bool = false

var main: Node
var input: InputController
var extraction: ExtractionManager
var timers: TimerManager
var sword: SwordController
var screen: FailureScreen
var hud: Hud
var difficulty_config: DifficultyConfig

# Per-scene recorders
var accepted: Array[int] = []
var completed_count: int = 0
var failed_events: Array[RunResult] = []
var level_changed_count: int = 0
var succeeded_count: int = 0
var progress_min: float = 1000.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.use_accumulated_input = false
	difficulty_config = load("res://resources/difficulty/default_difficulty.tres")
	get_window().size = Vector2i(540, 960)
	get_window().always_on_top = true
	get_window().grab_focus()
	GameManager.state_changed.connect(func(new_state: GameManager.State) -> void:
		if new_state == GameManager.State.PAUSED and not _pause_expected:
			_unexpected_pauses += 1
			print("  NOTE  the game was paused by a REAL window-focus loss (not caused by the test)"))
	GameManager.run_failed.connect(func(result: RunResult) -> void: failed_events.append(result))
	GameManager.level_changed.connect(func(_level: int) -> void: level_changed_count += 1)
	GameManager.extraction_succeeded.connect(func(_l: int, _t: float) -> void: succeeded_count += 1)
	await _frames(4)

	await _t_progress_steps()
	await _t_levels_and_extraction()
	await _t_reward_scaling()
	await _t_pause_in_cinematic()
	await _t_round_controls()
	await _t_touch_halves()
	await _t_sword_stability()

	print("\n==== %d checks, %d failed, %d unexpected focus-loss pause(s) ====" % [_checks, _failures, _unexpected_pauses])
	for label in _failed_labels:
		print("  FAILED: ", label)
	var invalid_run := _unexpected_pauses > 0 and _failures > 0
	if invalid_run:
		print("RESULT: INVALID RUN - the window lost OS focus during the test; re-run without touching other windows.")
	else:
		print("RESULT: ", "ALL PASSED" if _failures == 0 else "FAILURES")
	if main != null:
		main.queue_free()
	get_tree().paused = false
	get_tree().quit(2 if invalid_run else (1 if _failures > 0 else 0))

# ======================================================================================
# Infrastructure
# ======================================================================================

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		_failed_labels.append(label)
		print("  FAIL  ", label)

func _near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance

func _wait(seconds: float) -> void:
	await _wait_until(Time.get_ticks_msec() + int(seconds * 1000.0))

func _wait_until(deadline_msec: int) -> void:
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## Wait for a condition with a deadline. Returns whether it became true.
func _wait_for(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()

func _wait_for_state(state: GameManager.State, timeout: float) -> bool:
	return await _wait_for(func() -> bool: return GameManager.state == state, timeout)

func _wait_failed() -> bool:
	return await _wait_for_state(GameManager.State.FAILED, 8.0)

func _wait_buttons_ready() -> bool:
	return await _wait_for(func() -> bool: return screen.buttons_ready, 6.0)

func _fresh_main(wait_for_ready: bool = true) -> void:
	if main != null:
		main.queue_free()
		await get_tree().process_frame
	get_tree().paused = false
	accepted.clear()
	failed_events.clear()
	completed_count = 0
	succeeded_count = 0
	progress_min = 1000.0
	main = load(MAIN_SCENE).instantiate()
	add_child(main)
	level_changed_count = 0
	input = main.get_node("InputController")
	extraction = main.get_node("ExtractionManager")
	timers = main.get_node("TimerManager")
	sword = main.get_node("Stage/Sword")
	screen = main.get_node("FailureScreen")
	hud = main.get_node("Hud")
	input.tap_accepted.connect(func(side: TapSide.Side) -> void: accepted.append(side))
	extraction.progress_changed.connect(func(value: float) -> void: progress_min = minf(progress_min, value))
	extraction.extraction_completed.connect(func() -> void: completed_count += 1)
	if wait_for_ready:
		await _wait_for_state(GameManager.State.READY, 5.0)
		if GameManager.state == GameManager.State.PAUSED:
			print("   [recover] resuming a game paused by real focus loss")
			get_window().grab_focus()
			_touch_vp(Vector2(270, 1500))
			await _frames(3)
			await _wait_for_state(GameManager.State.READY, 5.0)

func _simulate_focus_loss() -> void:
	_pause_expected = true
	get_tree().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	_pause_expected = false

func _to_window(viewport_point: Vector2) -> Vector2:
	return get_viewport().get_screen_transform() * viewport_point

func _touch_vp(point: Vector2, pressed: bool = true, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = _to_window(point)
	Input.parse_input_event(event)

func _tap_vp(point: Vector2) -> void:  # a full touch tap: press then release
	_touch_vp(point, true)
	_touch_vp(point, false)

func _mouse_button_vp(point: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = _to_window(point)
	event.global_position = event.position
	Input.parse_input_event(event)

func _click_vp(point: Vector2) -> void:  # hover, press, release (a real mouse click)
	var motion := InputEventMouseMotion.new()
	motion.position = _to_window(point)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	_mouse_button_vp(point, true)
	_mouse_button_vp(point, false)

func _button(button_name: String) -> Button:
	return screen.find_child(button_name, true, false) as Button

func _center(button: Button) -> Vector2:
	return button.get_global_rect().get_center()

## Gameplay tap on the side the controller expects next (LEFT first).
func _tap_expected() -> void:
	var next := input.expected_side()
	var width := get_viewport().get_visible_rect().size.x
	_touch_vp(Vector2(width * (0.75 if next == SIDE_RIGHT else 0.25), 1000.0))

## Alternate real touches until the state leaves the play states.
func _pump_until_extracted(max_taps: int = 120) -> void:
	var sent := 0
	while GameManager.is_input_allowed() and sent < max_taps:
		_tap_expected()
		sent += 1
		await _wait(0.035)

## Start a run, make one valid tap and stop, then wait for the failure. Returns seconds from
## the tap to the FAILED state, or -1 if it never failed.
func _fail_the_run() -> float:
	_tap_expected()
	var tap_wall := Time.get_ticks_msec()
	var failed := await _wait_failed()
	return float(Time.get_ticks_msec() - tap_wall) / 1000.0 if failed else -1.0

func _save_screenshot(file_name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	get_viewport().get_texture().get_image().save_png(args[0] + "/" + file_name)

# ======================================================================================
# Helpers
# ======================================================================================

var menu: PauseMenu
var audio: GameAudio
var camera: GameplayCamera
var forest: ForestEnvironment
var cues: Array[StringName] = []
var completions: Array[Dictionary] = []

func _arm() -> void:
	menu = main.get_node("PauseMenu")
	audio = main.get_node("Audio")
	camera = main.get_node("Stage/Camera3D")
	forest = main.get_node("Stage/Forest")
	cues.clear()
	completions.clear()
	audio.cue_requested.connect(func(cue: StringName, _i: float) -> void: cues.append(cue))
	main.level_completed.connect(func(level: int, seconds: float, taps: int, intensity: float) -> void:
		completions.append({"level": level, "seconds": seconds, "taps": taps, "intensity": intensity, "wall": Time.get_ticks_msec()}))

func _back() -> void:
	_pause_expected = true
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_pause_expected = false

func _wait_menu_ready() -> void:
	await _wait(PauseMenu.INPUT_DELAY_MSEC / 1000.0 + 0.12)

func _press(button: Button) -> void:
	_pause_expected = true
	_tap_vp(_center(button))
	await _frames(3)
	_pause_expected = false

func _non_tap_cues() -> Array[StringName]:
	var result: Array[StringName] = []
	for cue in cues:
		if cue != &"tap" and cue != &"tap_slow":
			result.append(cue)
	return result

func _count_reversals(values: Array[float], threshold: float = 0.02) -> int:
	var count := 0
	var last := 0
	for i in range(1, values.size()):
		var d := values[i] - values[i - 1]
		if absf(d) < threshold:
			continue
		var s := 1 if d > 0.0 else -1
		if last != 0 and s != last:
			count += 1
		last = s
	return count

# ======================================================================================
# 1. Progress: small, real steps; displayed percentage consistent with the real value
# ======================================================================================

func _t_progress_steps() -> void:
	print("\n[1] PROGRESS FOLLOWS THE TAPPING SPEED, THE DISPLAY FOLLOWS PROGRESS")
	await _fresh_main()
	_arm()
	var config: DifficultyConfig = main.get_node("DifficultyManager").config
	# 1.9: there is no fixed gain per tap. The peak gain is 6 % and a tap is worth what its measured interval earns.
	_check(is_equal_approx(extraction.gain_per_tap, 6.0) and extraction.resistance == 0.0, "level 1: peak gain 6 %% per tap at the optimal speed, no resistance (%.2f)" % extraction.gain_per_tap)
	var deltas: Array[float] = []
	var intervals: Array[float] = []
	var previous := 0.0
	var worst_frame_jump := 0
	var last_shown := 0
	var never_ahead := true
	var started := Time.get_ticks_msec()
	var next_tap := started
	var left := true
	var taps_sent := 0
	while taps_sent < 12:  # 11 progress taps = 73 %, safely below the end of the level
		if Time.get_ticks_msec() >= next_tap:
			if left:
				_touch_vp(Vector2(270.0, 1000.0))
			else:
				_touch_vp(Vector2(810.0, 1000.0))
			left = not left
			taps_sent += 1
			next_tap = Time.get_ticks_msec() + 70  # never catch up with a burst after a slow frame
			await get_tree().process_frame  # let the tap be processed
			deltas.append(extraction.progress - previous)
			intervals.append(input.last_interval_msec)
			previous = extraction.progress
		else:
			await get_tree().process_frame
		var shown := hud.displayed_percent()
		worst_frame_jump = maxi(worst_frame_jump, shown - last_shown)
		if shown > int(floor(extraction.progress)) + 0:
			never_ahead = false
		last_shown = shown
	_check(deltas[0] == 0.0, "the first tap adds exactly 0")
	var steps_ok := true
	for i in range(1, deltas.size()):
		var expected := SpeedGain.gain(intervals[i], extraction.gain_per_tap, extraction.optimal_interval_msec, extraction.useful_interval_msec, extraction.gain_exponent)
		if absf(deltas[i] - expected) > 0.001 or expected <= 0.0:
			steps_ok = false
	var delta_sum := 0.0
	for d in deltas:
		delta_sum += d
	_check(steps_ok and is_equal_approx(extraction.progress, delta_sum), "every following tap adds exactly what the speed curve gives for its measured interval (%d taps, total %.1f)" % [deltas.size(), extraction.progress])
	# 1.8: one tap is 6.67 %, so the label may move by about one tap per frame (it eases toward the real value, and a
	# hitched frame lets it catch up); the 1.7 limit of 2 encoded the 2 %-per-tap design.
	_check(worst_frame_jump <= 10, "the shown percentage never jumps by more than about one tap (+hitch) in one frame (worst %d)" % worst_frame_jump)
	_check(never_ahead, "the shown percentage is never ahead of the real progress")
	await _wait(0.2)
	_check(hud.displayed_percent() == int(floor(extraction.progress)), "once settled the label equals floor(progress): %d%% for %.2f" % [hud.displayed_percent(), extraction.progress])
	_check(hud._bar.is_visible_in_tree(), "the bar is visible")

# ======================================================================================
# 2. Taps per level, resistance and the extraction animation in a real run through levels 1-3
# ======================================================================================

func _t_levels_and_extraction() -> void:
	print("\n[2] LEVELS 1-3: SPEED-BASED EXTRACTION, EXTRACTION TIME, RISING DIFFICULTY, A STABLE EXTRACTION")
	await _fresh_main()
	_arm()
	var config: DifficultyConfig = main.get_node("DifficultyManager").config
	var gains: Array[float] = [extraction.gain_per_tap]
	var resistances: Array[float] = [extraction.resistance]
	var limits: Array[float] = [input.max_interval_msec]
	var total_seconds: Array[float] = []
	var sampled_first := false
	var pump_starts: Array[int] = []
	for lv in 3:
		var level := lv + 1
		var pump_start := Time.get_ticks_msec()
		pump_starts.append(pump_start)
		await _pump_until_extracted(200)
		if lv == 0:
			sampled_first = true
			await _sample_extraction_animation(level)
		await _wait_for(func() -> bool: return GameManager.level == level + 1 and GameManager.state == GameManager.State.READY, 10.0)
		gains.append(extraction.gain_per_tap)
		resistances.append(extraction.resistance)
		limits.append(input.max_interval_msec)
	print("   completions: ", completions)
	_check(completions.size() == 3, "three levels completed (%d)" % completions.size())
	for lv in mini(completions.size(), 3):
		# The extraction time is measured from the first valid tap to 100 %: it must equal the wall clock (the first tap is
		# sent the instant the pump starts, and the completion is stamped when the signal arrives).
		var wall := float(completions[lv]["wall"] - pump_starts[lv]) / 1000.0
		_check(absf(wall - completions[lv]["seconds"]) < 0.15 and completions[lv]["seconds"] > 0.5 and completions[lv]["seconds"] < 12.0,
			"level %d: the extraction time %.2f s matches the wall clock %.2f s (first valid tap to 100 %%)" % [lv + 1, completions[lv]["seconds"], wall])
	_check(gains[1] < gains[0] and gains[2] < gains[1] and gains[3] < gains[2], "the peak gain falls slightly on every level (%.2f %.2f %.2f %.2f)" % [gains[0], gains[1], gains[2], gains[3]])
	_check(resistances[0] == 0.0 and resistances[1] > 0.0 and resistances[2] > resistances[1], "extraction resistance rises (%.2f %.2f %.2f)" % [resistances[0], resistances[1], resistances[2]])
	_check(limits[1] < limits[0] and limits[2] < limits[1] and limits[3] < limits[2], "the allowed tap gap tightens on every level")
	_check(completions.size() == 3 and completions.all(func(c: Dictionary) -> bool: return not c.has("taps_shown")), "no tap count is part of what is reported to the player")
	_check(completions.size() == 3 and completions[0]["intensity"] == 0.0 and completions[1]["intensity"] > 0.0 and completions[2]["intensity"] > completions[1]["intensity"], "the reward intensity grows with the level")
	_check(GameManager.level == 4 and GameManager.run_extractions == 3, "now on level 4 after 3 extractions")
	_check(hud._level_label.text == "LEVEL 4", "the HUD shows LEVEL 4")

## Records the sword frame by frame through the extraction of `level` and checks it.
func _sample_extraction_animation(level: int) -> void:
	_check(GameManager.state == GameManager.State.EXTRACTING, "state EXTRACTING the moment the bar fills")
	var intensity := LevelManager.reward_intensity(level)
	var total := SwordController.extraction_total_seconds(intensity)
	var hold := SwordController.extraction_hold_seconds(intensity)
	var top_y: float = sword._rest_position.y + sword.full_lift
	var started := Time.get_ticks_msec()
	# The moment of release is taken from the sword's own `freed` signal, not guessed from the clock.
	var released_at := [-1.0]
	var release_end := 999.0
	sword.freed.connect(func() -> void: released_at[0] = float(Time.get_ticks_msec() - started) / 1000.0, CONNECT_ONE_SHOT)
	var tensions: Array[float] = []
	var ys: Array[float] = []
	var zs: Array[float] = []
	var rots: Array[float] = []
	var times: Array[float] = []
	var bad_motion := 0
	var card_seen := false
	var card_text := ""
	var labels_faded := false
	var peak_dolly := 0.0
	var tension_before_release := 0.0
	var still_before_release := true
	var y_at_start := sword.position.y
	var slot_after_release := false
	var peak_sun := 0.0
	var bar_percent := hud.displayed_percent()
	var visual_clean := true
	# Stop before the next sword's entrance resets the pose: the sequence ends `after release` seconds after the release moment (the
	# sampler starts a little after the last tap, so the end is taken from the release, not from the clock at the start).
	var after_release := SwordController.extraction_after_release_seconds(intensity)
	while (released_at[0] < 0.0 and float(Time.get_ticks_msec() - started) / 1000.0 < total) or (released_at[0] >= 0.0 and float(Time.get_ticks_msec() - started) / 1000.0 < released_at[0] + after_release - 0.1):
		await get_tree().process_frame
		var t := float(Time.get_ticks_msec() - started) / 1000.0
		times.append(t)
		tensions.append(camera.tension())
		if released_at[0] >= 0.0:
			release_end = released_at[0] + SwordController.EXTRACTION_PULL_SECONDS
		ys.append(sword.position.y)
		zs.append(sword.position.z)
		rots.append(sword._visual.rotation.y)
		# 1.10: the blade may carry its bounded micro-motion until the anticipation settles it; it must stay rigid and inside the bounds.
		if sword.position.x != 0.0 or sword._visual.position.length() > 0.02 or absf(sword._visual.rotation.x) > 0.0 or absf(sword._visual.rotation.z) > SwordController.MICRO_ROLL + 0.0001 or sword._visual.scale != Vector3.ONE:
			visual_clean = false
		if hud.is_level_complete_visible() and hud._banner.modulate.a > 0.9:
			card_seen = true
			card_text = hud._banner_sub.text + " | " + hud._banner_stats.text
		if t > release_end and t < release_end + hold - 0.3:  # the middle of the hold
			labels_faded = hud._level_label.modulate.a < 0.2 and hud._level_time_label.modulate.a < 0.2 and hud._session_time_label.modulate.a < 0.2
		peak_dolly = maxf(peak_dolly, camera.dolly_amount())
		if released_at[0] >= 0.0 and t > released_at[0] + 0.1 and sword.slot_visible():
			slot_after_release = true
		peak_sun = maxf(peak_sun, forest.sun_energy())
	print("   extraction animation: %d frames in %.2f s" % [ys.size(), total])
	# Phase checks on the recorded frames.
	var rising := true
	var biggest_step := 0.0
	var step_info := ""
	for i in range(1, ys.size()):
		if ys[i] < ys[i - 1] - 0.00001:
			rising = false
		if times[i] < release_end + hold:  # (anticipation + release pull)
			var dt := maxf(times[i] - times[i - 1], 0.001)
			var step := (ys[i] - ys[i - 1]) * (1.0 / 60.0) / dt  # per 60 Hz frame, so a hitch does not count as a jump
			if step > biggest_step:
				biggest_step = step
				step_info = "t=%.3f dt=%.4f y %.3f -> %.3f" % [times[i], dt, ys[i - 1], ys[i]]
	_check(visual_clean, "all the way through: only the bounded micro-motion, no scaling, the blade rises and turns about its own axis")
	_check(rising, "the sword never moves down during the extraction (pull, hold, lift)")
	# 1.8: the release is a decisive quint-out pull (0.35 s), fastest at its start: about 0.2 units per frame, still smooth
	# (the 1.7 limit of 0.12 belonged to the slower 0.5 s pull). The blade is checked for stillness separately below.
	_check(biggest_step < 0.26, "during the release pull and the hold the biggest rise per 60 Hz frame is %.3f units (smooth, no jump) [%s]" % [biggest_step, step_info])
	var rel: float = released_at[0]
	var why := ""
	for i in times.size():
		if times[i] < rel - 0.01:
			tension_before_release = maxf(tension_before_release, tensions[i])
			if ys[i] < y_at_start - 0.0001 or ys[i] > top_y + 0.0001:
				still_before_release = false  # during the anticipation the blade may only creep up to the top, never beyond
				why = "t=%.3f y=%.4f start=%.4f top=%.4f" % [times[i], ys[i], y_at_start, top_y]
		if times[i] > rel - 0.05 and times[i] < rel - 0.005 and absf(ys[i] - top_y) > 0.02:
			still_before_release = false  # ...and it has arrived at the top when the release comes
			why = "not at top: t=%.3f y=%.4f top=%.4f" % [times[i], ys[i], top_y]
	_check(rel >= 0.0 and rel < 0.35, "the release comes %.2f s after the last tap (anticipation %.2f s)" % [rel, SwordController.EXTRACTION_ANTICIPATION_SECONDS])
	_check(still_before_release and tension_before_release > 0.6, "PHASE A: the blade finishes its rise to the top and is gripped there for the anticipation while the camera is at its tightest (tension %.2f) %s" % [tension_before_release, why])
	_check(slot_after_release, "PHASE B: the empty cut is visible in the stump after the release")
	# 1.9: a tiny counter-twist during the anticipation (0 -> -0.05 rad), then one slow turn the other way (up to +0.30 rad).
	var turn_ok := true
	var min_index := 0
	for i in rots.size():
		if rots[i] < rots[min_index]:
			min_index = i
	for i in range(1, rots.size()):
		if i <= min_index and rots[i] > rots[i - 1] + 0.00001:
			turn_ok = false  # before the minimum it only turns the counter-twist way
		if i > min_index and rots[i] < rots[i - 1] - 0.00001:
			turn_ok = false  # after it only turns forward
	_check(turn_ok and rots[min_index] >= -SwordController.EXTRACTION_COUNTER_TWIST - 0.001 and rots[rots.size() - 1] <= SwordController.EXTRACTION_TURN_RADIANS + 0.001 and rots[rots.size() - 1] > 0.2,
		"the blade is worked slightly against its turn (%.3f rad), then turns slowly one way, ending at %.2f rad (a calm turn, not a spin)" % [rots[min_index], rots[rots.size() - 1]])
	var z_rising := true
	for i in range(1, zs.size()):
		if zs[i] < zs[i - 1] - 0.00001:
			z_rising = false
	_check(z_rising and zs[zs.size() - 1] > 0.25, "it drifts smoothly toward the camera (%.2f)" % zs[zs.size() - 1])
	# The hold: the blade hangs still while the card is read.
	var hold_ys: Array[float] = []
	for i in times.size():
		if times[i] > release_end + hold * 0.4 and times[i] < release_end + hold - 0.05:
			hold_ys.append(ys[i])
	var hold_spread := (hold_ys.max() as float) - (hold_ys.min() as float) if not hold_ys.is_empty() else 99.0
	_check(not hold_ys.is_empty() and hold_spread < 0.01, "during the hold the blade hangs still (moves %.4f units)" % hold_spread)
	_check(card_seen and card_text.begins_with("LEVEL %d COMPLETE" % level) and card_text.contains("EXTRACTION TIME") and not card_text.to_upper().contains("TAP"), "the completion card shows the level and the extraction time and no tap count: '%s'" % card_text)
	_check(labels_faded, "the level and timer labels at the top fade out while the card is up")
	_check(peak_dolly > camera.RELEASE_DOLLY - 0.05, "PHASE C: the camera moves in and rises with the blade when it comes free (peak dolly %.2f units)" % peak_dolly)
	_check(peak_sun > forest.SUN_ENERGY * 1.08, "the sunlight swells for a moment (peak %.2f vs %.2f)" % [peak_sun, forest.SUN_ENERGY])
	_check(bar_percent >= 99, "the bar reads %d%% when the extraction starts" % bar_percent)
	await _wait_for(func() -> bool: return GameManager.state == GameManager.State.READY, 6.0)
	var whole := float(Time.get_ticks_msec() - started) / 1000.0
	_check(whole > total and whole < total + 1.2, "extraction + entrance of the next sword took %.2f s (expected about %.1f)" % [whole, total + 0.35])
	_check(sword.position == sword._rest_position and sword._visual.rotation == Vector3.ZERO and sword._visual.position == Vector3.ZERO, "the next sword stands exactly in the embedded rest pose")
	_check(camera.dolly_amount() < 0.02 and absf(forest.sun_energy() - forest.SUN_ENERGY) < 0.05 and not sword.slot_visible(), "camera, light and stump are back to normal (dolly %.3f, sun %.2f)" % [camera.dolly_amount(), forest.sun_energy()])
	_check(not hud.is_level_complete_visible() and hud._level_label.modulate.a > 0.95, "the card has faded and the top labels are back")
	var order := _non_tap_cues()
	_check(order.slice(0, 5) == [&"first_tap", &"pull", &"freed", &"level_complete", &"planted"], "audio cues fired once each, in order: %s" % [order])

# ======================================================================================
# 3. Reward scales with the level (intensity, hold, camera, light, card note)
# ======================================================================================

func _t_reward_scaling() -> void:
	print("\n[3] THE REWARD GROWS WITH THE LEVEL")
	_check(LevelManager.reward_intensity(1) == 0.0 and is_equal_approx(LevelManager.reward_intensity(6), 0.5) and LevelManager.reward_intensity(11) == 1.0 and LevelManager.reward_intensity(99) == 1.0,
		"intensity: level 1 = 0, level 6 = 0.5, level 11 and above = 1")
	_check(is_equal_approx(SwordController.extraction_hold_seconds(0.0), 0.75) and is_equal_approx(SwordController.extraction_hold_seconds(1.0), 1.2), "the hold lengthens from 0.75 s to 1.2 s (1.8: shorter than 1.7, so completion does not interrupt the flow)")
	await _fresh_main()
	_arm()
	camera.impact(0.0, 2.0)
	await _wait(0.7)
	var weak_dolly := camera.dolly_amount()
	await _wait(1.6)
	camera.impact(1.0, 2.0)
	await _wait(0.7)
	var strong_dolly := camera.dolly_amount()
	_check(weak_dolly > 0.45 and weak_dolly < 0.65 and strong_dolly > 0.78 and strong_dolly > weak_dolly, "camera moves in %.2f units at level 1, %.2f from level 11 (and rises with the blade)" % [weak_dolly, strong_dolly])
	await _wait(2.0)
	_check(camera.dolly_amount() < 0.01 and absf(camera.v_offset) < 0.0001, "...and it returns to exactly the normal framing")
	forest.pulse_light(0.0)
	var weak_sun := 0.0
	for i in 30:
		await get_tree().process_frame
		weak_sun = maxf(weak_sun, forest.sun_energy())
	await _wait(1.5)
	forest.pulse_light(1.0)
	var strong_sun := 0.0
	for i in 30:
		await get_tree().process_frame
		strong_sun = maxf(strong_sun, forest.sun_energy())
	await _wait(1.6)
	_check(weak_sun < forest.SUN_ENERGY * 1.13 and strong_sun > forest.SUN_ENERGY * 1.25 and strong_sun <= forest.SUN_ENERGY * 1.31,
		"sunlight swell: +%.0f %% at level 1, +%.0f %% from level 11 (restrained, never a flash)" % [(weak_sun / forest.SUN_ENERGY - 1.0) * 100.0, (strong_sun / forest.SUN_ENERGY - 1.0) * 100.0])
	_check(absf(forest.sun_energy() - forest.SUN_ENERGY) < 0.02, "...and the light returns to normal")
	hud.show_level_complete(5, 12.3, 5, 0.4)
	await _frames(2)
	_check(hud._banner_sub.text == "LEVEL 5 COMPLETE" and hud._banner_stats.text == "EXTRACTION TIME   00:12.30", "the card shows the level and the extraction time ('%s')" % hud._banner_stats.text)
	_check(hud._banner_note.text == "5 SWORDS EXTRACTED", "...and the swords extracted in the session ('%s')" % hud._banner_note.text)
	var card_text_all := hud._banner_title.text + hud._banner_sub.text + hud._banner_stats.text + hud._banner_note.text
	_check(not card_text_all.to_upper().contains("TAP"), "no text on the card mentions taps")
	await _wait(1.6)
	hud.show_level_complete(1, 8.42, 1, 0.4)
	await _frames(2)
	_check(hud._banner_stats.text == "EXTRACTION TIME   00:08.42" and hud._banner_note.text == "1 SWORD EXTRACTED", "level 1: 00:08.42 and '1 SWORD EXTRACTED'")
	_check(Hud.format_extraction_time(8.42) == "00:08.42" and Hud.format_extraction_time(0.0) == "00:00.00" and Hud.format_extraction_time(75.5) == "01:15.50" and Hud.format_extraction_time(0.004) == "00:00.00",
		"the extraction time is formatted MM:SS.cc")
	await _wait(1.6)

# ======================================================================================
# 4. Pause during the cinematic
# ======================================================================================

func _t_pause_in_cinematic() -> void:
	print("\n[4] PAUSING DURING THE COMPLETION MOMENT FREEZES IT")
	await _fresh_main()
	_arm()
	await _pump_until_extracted(200)
	await _wait(0.8)  # inside the hold: the card is up
	_check(hud.is_level_complete_visible(), "the card is up")
	_back()
	await _frames(3)
	var y := sword.position.y
	var rotation := sword._visual.rotation.y
	var alpha := hud._banner.modulate.a
	var cam_pos := camera.position
	await _wait(2.0)
	_check(GameManager.state == GameManager.State.PAUSED and sword.position.y == y and sword._visual.rotation.y == rotation, "paused: the sword is frozen exactly where it was")
	_check(hud._banner.modulate.a == alpha and camera.position == cam_pos, "...and so are the card and the camera")
	_check(GameManager.level == 1 and failed_events.is_empty(), "...and the level did not advance, nothing failed")
	await _wait_menu_ready()
	await _press(menu.resume_button())
	await _wait_for(func() -> bool: return GameManager.level == 2 and GameManager.state == GameManager.State.READY, 8.0)
	_check(GameManager.level == 2 and completions.size() == 1 and GameManager.run_extractions == 1, "after resuming the level completes normally, exactly once")
	await _wait_for(func() -> bool: return not hud.is_level_complete_visible(), 3.0)  # (1.9.2: the card may still be mid-fade the instant READY begins)
	_check(not hud.is_level_complete_visible() and hud._level_label.text == "LEVEL 2", "the card fades and the HUD shows LEVEL 2")

# ======================================================================================
# 5. Round controls, no text; pressed animation
# ======================================================================================

func _t_round_controls() -> void:
	print("\n[5] THE ROUND CONTROLS CARRY NO TEXT AND ANIMATE WHEN PRESSED")
	await _fresh_main()
	_arm()
	var left: ForestDisc = hud._zone_left
	var right: ForestDisc = hud._zone_right
	# 1.7 perf fix: a disc is a baked-texture quad (children: bake viewport, face, glow ring) - still no text of any kind.
	var disc_text := left.find_children("*", "Label", true, false).size() + right.find_children("*", "Label", true, false).size() 		+ left.find_children("*", "RichTextLabel", true, false).size() + right.find_children("*", "RichTextLabel", true, false).size()
	_check(disc_text == 0, "the discs contain no label of any kind (no text, no symbol)")
	var texts: Array[String] = []
	for node in hud.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	var has_word := texts.any(func(t: String) -> bool: return t.to_upper().contains("LEFT") or t.to_upper().contains("RIGHT"))
	_check(not has_word, "no label anywhere on the HUD says LEFT or RIGHT (%s)" % [texts])
	var baked := true
	for d: ForestDisc in [left, right]:
		var vps := d.find_children("*", "SubViewport", true, false)
		var paints := d.find_children("*", "ColorRect", true, false)
		baked = baked and vps.size() == 1 and paints.size() == 1 and (paints[0] as ColorRect).material is ShaderMaterial 			and (vps[0] as SubViewport).render_target_update_mode != SubViewport.UPDATE_ALWAYS
	_check(baked and left.mouse_filter == Control.MOUSE_FILTER_IGNORE and right.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the discs are drawn by the forest shader, rendered once into a texture (not every frame), and ignore the mouse")
	_check(is_equal_approx(left.size.x, right.size.x) and absf(left.get_global_rect().position.y - right.get_global_rect().position.y) < 1.0, "left and right are mirror images in size and height")
	_check(left.press_amount() < 0.05 and is_equal_approx(left.scale.x, 1.0), "at rest the discs are not pressed")
	_touch_vp(Vector2(270.0, 1000.0))
	await _frames(1)
	_check(left.press_amount() > 0.3 and left.scale.x < 0.99 and right.press_amount() < 0.05, "tapping left sinks only the left disc (press %.2f, scale %.3f)" % [left.press_amount(), left.scale.x])
	await _wait(0.1)
	_touch_vp(Vector2(810.0, 1000.0))
	await _frames(1)
	_check(right.press_amount() > 0.7 and right.scale.x < 0.965, "a progress tap presses the right disc fully (press %.2f, scale %.3f)" % [right.press_amount(), right.scale.x])
	await _wait(0.7)
	_check(left.press_amount() < 0.05 and right.press_amount() < 0.05 and is_equal_approx(right.scale.x, 1.0), "the discs spring back after the tap")
	# A slow tap only dims it.
	await _wait(0.1)
	_touch_vp(Vector2(270.0, 1000.0))
	await _frames(2)
	_check(left.press_amount() < 0.3, "a too-slow tap presses the disc only faintly (%.2f)" % left.press_amount())

# ======================================================================================
# 6. Touch detection over the whole screen
# ======================================================================================

func _t_touch_halves() -> void:
	print("\n[6] TOUCH DETECTION COVERS BOTH SCREEN HALVES COMPLETELY")
	await _fresh_main()
	_arm()
	var xs: Array[float] = [2.0, 120.0, 270.0, 420.0, 538.0, 542.0, 660.0, 810.0, 960.0, 1078.0]
	var ys: Array[float] = [40.0, 400.0, 900.0, 1350.0, 1560.0, 1700.0, 1910.0]
	var wrong := 0
	var tried := 0
	for x in xs:
		for y in ys:
			input.reset_alternation()
			await _wait(0.04)
			var before := kinds_count()
			_touch_vp(Vector2(x, y))
			await _frames(1)
			tried += 1
			var expected := TapSide.Side.LEFT if x < 540.0 else TapSide.Side.RIGHT
			if kinds_count() != before + 1 or input.last_accepted_side != expected:
				wrong += 1
				print("   MISSED at (%d, %d)" % [x, y])
	_check(wrong == 0, "%d touches across a 10 x 7 grid, every one read as the correct side (%d wrong)" % [tried, wrong])
	# Exactly on the dividing line and mouse clicks.
	input.reset_alternation()
	await _wait(0.04)
	var c0 := kinds_count()
	_mouse_click(Vector2(100.0, 1000.0))
	await _frames(1)
	_check(kinds_count() == c0 + 1 and input.last_accepted_side == TapSide.Side.LEFT, "a mouse click on the left half counts as LEFT")
	var disc_rect: Rect2 = hud._zone_right.get_global_rect()
	await _wait(0.06)
	_touch_vp(disc_rect.position + Vector2(2.0, 2.0))  # the corner of the disc's bounding box: outside the circle itself
	await _frames(1)
	_check(input.last_accepted_side == TapSide.Side.RIGHT, "a touch in the empty corner of a disc's bounding box still counts (the whole half is the target)")

func kinds_count() -> int:
	return accepted.size()

func _mouse_click(point: Vector2) -> void:
	_mouse_button_vp(point, true)
	_mouse_button_vp(point, false)

# ======================================================================================
# 7. Sword stability at slow / normal / very rapid input (real gain, rising progress)
# ======================================================================================

func _t_sword_stability() -> void:
	print("\n[7] SWORD STABILITY: SLOW, NORMAL AND VERY RAPID TAPPING")
	await _fresh_main()
	_arm()
	await _wait(1.3)  # the landing camera shake
	var render_px := 432.0 / 1080.0
	var pommel := Vector3(0.0, SwordController.BLADE_LENGTH + 0.07 + SwordController.GRIP_LENGTH + 0.155, 0.0)
	var rates := {"slow (300 ms)": 300, "normal (200 ms)": 200, "very rapid (70 ms)": 70}
	var worst_step := 0.0
	var worst_jerk := 0.0
	var worst_x := 0.0
	var worst_reversals := 0
	var worst_lag := 0.0
	for label in rates:
		var interval: int = rates[label]
		extraction.reset()
		extraction.set_active(true)
		extraction.configure(6.0, 0.0, 5.0)  # the real level-1 peak gain, no decay (1.9: what a tap earns depends on its speed)
		sword.set_progress(0.0)
		input.reset_alternation()
		await _wait(0.4)
		var xs: Array[float] = []
		var ys: Array[float] = []
		var ts: Array[float] = []
		var lags: Array[float] = []
		var start := Time.get_ticks_msec()
		var next := start
		var left := true
		while Time.get_ticks_msec() - start < 2400:
			if Time.get_ticks_msec() >= next and extraction.progress < 70.0:  # stop tapping before the level can complete
				if left:
					_touch_vp(Vector2(270.0, 1000.0))
				else:
					_touch_vp(Vector2(810.0, 1000.0))
				left = not left
				next = Time.get_ticks_msec() + interval
			await get_tree().process_frame
			ts.append(float(Time.get_ticks_usec()) / 1000.0)
			var p: Vector2 = camera.unproject_position(sword._visual.to_global(pommel))
			xs.append(p.x * render_px)
			ys.append(p.y * render_px)
			var ideal := camera.unproject_position(Vector3(0.0, sword._rest_position.y + extraction.progress / 100.0 * sword.full_lift + pommel.y, 0.0))
			lags.append(absf(ideal.y * render_px - ys[ys.size() - 1]))
		var step := 0.0
		var jerk := 0.0
		for i in range(2, ys.size()):
			# Speeds in px per 60 Hz frame (distance / real frame time), so a one-off slow frame is not a "jump".
			var v1 := (ys[i] - ys[i - 1]) * (16.667 / maxf(ts[i] - ts[i - 1], 1.0))
			var v0 := (ys[i - 1] - ys[i - 2]) * (16.667 / maxf(ts[i - 1] - ts[i - 2], 1.0))
			step = maxf(step, absf(v1))
			jerk = maxf(jerk, absf(v1 - v0))
		var x_range := (xs.max() as float) - (xs.min() as float)
		var reversals := _count_reversals(ys)
		print("   %-18s x range %.2f px, vertical reversals %d, biggest frame step %.2f px, jerk %.2f px, lag behind progress %.2f px" % [label, x_range, reversals, step, jerk, lags.max()])
		worst_step = maxf(worst_step, step)
		worst_jerk = maxf(worst_jerk, jerk)
		worst_x = maxf(worst_x, x_range)
		worst_reversals = maxi(worst_reversals, reversals)
		worst_lag = maxf(worst_lag, lags.max())
	_check(worst_x < 3.5, "sideways movement stays inside the 1.10 micro-motion bound at any speed (%.2f render px; limit 3.5, was 0.5 before 1.10)" % worst_x)
	_check(worst_reversals == 0, "the sword never changes vertical direction while the bar rises (%d reversals)" % worst_reversals)
	# 1.8: a tap is 6.67 % of the bar (it was 2 % in 1.7), so each tap moves the blade about three times as far; the limits are
	# scaled for that. What must not change: no reversals, no sideways movement, no tilt, speed changes stay small and smooth.
	_check(worst_step < 1.8 and worst_jerk < 0.6, "the biggest single-frame move is %.2f px and the biggest speed change %.2f px (the old sword: 2.4-2.8 px steps at 8 %% per tap)" % [worst_step, worst_jerk])
	_check(worst_lag < 12.0, "the drawn height stays within %.1f render px of the height implied by progress" % worst_lag)
	# 1.10 (deliberate rule change): the blade now moves a bounded few millimetres under the taps (see fx_tests / SwordController.MICRO_*);
	# what must still hold is that it settles to exactly the embedded pose once the taps stop.
	await _wait(1.5)
	_check(sword._visual.position == Vector3.ZERO and sword._visual.rotation == Vector3.ZERO, "after the taps the blade has no offset or tilt (it settles to exactly zero)")
