extends Node
## Pause menu / Android Back tests (Milestone 1.5).
##
## Run (needs a window; forced to 540x960):  godot --path . res://tests/pause_tests.tscn
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

	await _t_back_in_ready()
	await _t_pause_mid_run_exact_state()
	await _t_input_guard_and_toggle()
	await _t_back_while_failed()
	await _t_back_during_extraction()
	await _t_quit()
	await _t_quit_confirmation()
	await _t_after_focus_loss()

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
# Pause menu / Android Back
# ======================================================================================

var menu: PauseMenu
var quit_calls: int = 0
var quit_paths: Array[String] = []

func _arm_menu() -> void:
	menu = main.get_node("PauseMenu")
	quit_calls = 0
	quit_paths.clear()
	main.app_quitter = func() -> void: quit_calls += 1
	# 1.15: a main menu scene now exists, so QUIT leaves to it (LevelManager._quit_from_menu) instead of ending the app. Both ways of
	# "leaving" are counted together, so every QUIT / confirmation / double-press rule below is still checked exactly as before.
	main.scene_changer = func(path: String) -> void:
		quit_calls += 1
		quit_paths.append(path)

func _back() -> void:
	_pause_expected = true
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)  # what Android Back sends
	_pause_expected = false

func _wait_menu_ready() -> void:
	await _wait(PauseMenu.INPUT_DELAY_MSEC / 1000.0 + 0.12)

func _press(button: Button) -> void:
	_pause_expected = true
	_tap_vp(_center(button))
	await _frames(3)
	_pause_expected = false

func _tap_side(left: bool) -> void:
	var width := get_viewport().get_visible_rect().size.x
	_touch_vp(Vector2(width * (0.25 if left else 0.75), 1000.0))

func _t_back_in_ready() -> void:
	print("\n[1] BACK IN READY OPENS THE MENU; RESUME RETURNS TO READY")
	await _fresh_main()
	_arm_menu()
	_back()
	await _frames(2)
	_check(GameManager.state == GameManager.State.PAUSED and menu.is_showing and menu.visible, "Back: PAUSED with the menu showing")
	_check(menu.resume_button().text == "RESUME" and menu.quit_button().text == PauseMenu.LEAVE_TEXT, "buttons are RESUME and MAIN MENU (1.16: the second button says what it does since 1.15)")
	_check(not hud._pause_overlay.visible, "the old 'tap to resume' text is hidden behind the menu")
	var taps_before := accepted.size()
	_tap_side(true)
	_tap_side(false)
	await _frames(3)
	_check(accepted.size() == taps_before and GameManager.state == GameManager.State.PAUSED, "gameplay taps while the menu is open do nothing (and do not resume)")
	await _wait_menu_ready()
	await _press(menu.resume_button())
	_check(GameManager.state == GameManager.State.READY and not menu.is_showing, "RESUME: back to READY, menu hidden")
	_check(timers.session_seconds() == 0.0 and timers.level_seconds() == 0.0 and not GameManager.run_over, "READY pause/resume did not start the timers or fail the run")

func _t_pause_mid_run_exact_state() -> void:
	print("\n[2] PAUSE MID-RUN FREEZES EVERYTHING; RESUME RESTORES THE EXACT STATE")
	await _fresh_main()
	_arm_menu()
	for i in 4:
		_tap_expected()
		await _wait(0.06)
	var progress := extraction.progress
	_check(GameManager.state == GameManager.State.PLAYING and progress > 3.0, "playing, progress %.1f" % progress)
	_back()
	await _frames(2)
	var p_at_pause := extraction.progress
	var level_t := timers.level_seconds()
	var session_t := timers.session_seconds()
	var accepted_at_pause := accepted.size()
	await _wait(2.5)  # far longer than the grace + decay would need to empty the bar
	_check(extraction.progress == p_at_pause, "progress unchanged after 2.5 s paused (%.2f)" % extraction.progress)
	_check(timers.level_seconds() == level_t and timers.session_seconds() == session_t, "level and session timers frozen")
	_check(GameManager.state == GameManager.State.PAUSED and failed_events.is_empty() and not GameManager.run_over, "no failure while paused")
	_tap_side(true)
	_tap_side(false)
	_tap_side(true)
	await _frames(3)
	_check(accepted.size() == accepted_at_pause and extraction.progress == p_at_pause, "taps while paused are not accepted and add no progress")
	await _wait_menu_ready()
	await _press(menu.resume_button())
	_check(GameManager.state == GameManager.State.PLAYING, "RESUME returns to PLAYING (the state before the pause)")
	_check(extraction.progress >= p_at_pause - 1.0 and extraction.progress <= p_at_pause + 0.01, "progress restored (%.2f -> %.2f)" % [p_at_pause, extraction.progress])
	_check(timers.session_seconds() >= session_t and timers.session_seconds() < session_t + 0.4, "the time spent paused was not added (%.2f -> %.2f)" % [session_t, timers.session_seconds()])
	_tap_expected()
	await _frames(2)
	_check(accepted.size() == accepted_at_pause + 1, "input works again after resuming")
	# And the failure system still works normally afterwards.
	var failed := await _wait_for_state(GameManager.State.FAILED, 14.0)
	_check(failed and failed_events.size() == 1, "after resume, stopping still fails the run exactly once")

func _t_input_guard_and_toggle() -> void:
	print("\n[3] PRESSES JUST AFTER OPENING ARE IGNORED; BACK TOGGLES")
	await _fresh_main()
	_arm_menu()
	_back()
	await _frames(2)
	_tap_vp(_center(menu.resume_button()))  # immediately: inside the guard window
	await _frames(2)
	_check(GameManager.state == GameManager.State.PAUSED and menu.is_showing, "a press right after opening is ignored")
	_tap_vp(_center(menu.quit_button()))
	await _frames(2)
	_check(quit_calls == 0, "...and so is a press on QUIT")
	await _wait_menu_ready()
	_back()  # Back again = resume
	await _frames(3)
	_check(GameManager.state == GameManager.State.READY and not menu.is_showing, "Back while the menu is open resumes")
	# Escape behaves like Back on desktop.
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	_pause_expected = true
	Input.parse_input_event(key)
	await _frames(3)
	_pause_expected = false
	_check(GameManager.state == GameManager.State.PAUSED and menu.is_showing, "Escape opens the menu too")
	await _wait_menu_ready()
	await _press(menu.resume_button())
	_check(GameManager.state == GameManager.State.READY, "resumed")

func _t_back_while_failed() -> void:
	print("\n[4] BACK ON THE FAILURE SCREEN DOES NOTHING")
	await _fresh_main()
	_arm_menu()
	_tap_expected()
	await _wait_failed()
	await _wait_buttons_ready()
	_back()
	await _frames(3)
	_check(GameManager.state == GameManager.State.FAILED and not menu.is_showing and screen.is_showing, "still FAILED, no menu, failure screen still showing")
	_check(failed_events.size() == 1, "still exactly one failure")

func _t_back_during_extraction() -> void:
	print("\n[5] PAUSE DURING THE EXTRACTION ANIMATION")
	await _fresh_main()
	_arm_menu()
	await _pump_until_extracted()
	_check(GameManager.state == GameManager.State.EXTRACTING, "extracting")
	_back()
	await _frames(2)
	var y_at_pause := sword.position.y
	await _wait(1.6)
	_check(GameManager.level == 1 and _near(sword.position.y, y_at_pause, 0.0001), "animation frozen and the level did not advance while paused")
	_check(failed_events.is_empty() and succeeded_count == 1, "no failure; exactly one success recorded")
	await _wait_menu_ready()
	await _press(menu.resume_button())
	_check(GameManager.state == GameManager.State.EXTRACTING, "resumed into the animation")
	await _wait_for(func() -> bool: return GameManager.level == 2 and GameManager.state == GameManager.State.READY, 6.0)
	_check(GameManager.level == 2 and succeeded_count == 1, "the level advanced once, to level 2")

func _t_quit() -> void:
	print("\n[6] QUIT DOES NOT CAUSE A GAME OVER")
	await _fresh_main()
	_arm_menu()
	for i in 3:
		_tap_expected()
		await _wait(0.06)
	_back()
	await _wait_menu_ready()
	await _press(menu.quit_button())
	_check(quit_calls == 1, "QUIT leaves (1.15: to the main menu), once")
	_check(quit_paths == [LevelManager.MAIN_MENU_PATH] and ResourceLoader.exists(LevelManager.MAIN_MENU_PATH), "...and the destination is the real main menu scene")
	_check(failed_events.is_empty() and not GameManager.run_over and GameManager.last_result == null, "no run_failed, no result recorded, run not marked over")
	await _press(menu.quit_button())
	_check(quit_calls == 1, "a second press after quitting does not repeat it" if not menu.is_showing else "(menu hidden after quit)")

func _t_quit_confirmation() -> void:
	print("\n[7] OPTIONAL QUIT CONFIRMATION (for a future Ruthless mode)")
	await _fresh_main()
	_arm_menu()
	var config := GameplayConfig.new()
	config.confirm_quit_during_run = true
	main.gameplay_config = config
	# Before any tap there is no run in progress: one press quits.
	_back()
	await _wait_menu_ready()
	_check(not menu.confirm_before_quit, "no confirmation needed before the first tap")
	await _press(menu.resume_button())
	# In a run: two presses.
	_tap_expected()
	await _wait(0.1)
	_back()
	await _wait_menu_ready()
	_check(menu.confirm_before_quit, "confirmation required once the run has started")
	await _press(menu.quit_button())
	_check(quit_calls == 0 and menu.quit_button().text == PauseMenu.CONFIRM_TEXT, "first MAIN MENU press only asks to confirm")
	await _wait_menu_ready()
	await _press(menu.resume_button())
	_check(GameManager.state != GameManager.State.PAUSED, "RESUME cancels the pending confirmation")
	_back()
	await _wait_menu_ready()
	_check(menu.quit_button().text == PauseMenu.LEAVE_TEXT and not menu.awaiting_confirmation, "reopening starts fresh")
	await _press(menu.quit_button())
	await _wait_menu_ready()
	await _press(menu.quit_button())
	_check(quit_calls == 1, "second QUIT press quits")

func _t_after_focus_loss() -> void:
	print("\n[8] FOCUS LOSS vs THE MENU")
	await _fresh_main()
	_arm_menu()
	_tap_expected()
	await _wait(0.1)
	await _simulate_focus_loss()
	_check(GameManager.state == GameManager.State.PAUSED and not menu.is_showing and hud._pause_overlay.visible, "losing focus shows the 'tap to resume' pause, not the menu")
	_back()
	await _frames(2)
	_check(menu.is_showing and not hud._pause_overlay.visible, "Back upgrades it to the menu")
	await _wait_menu_ready()
	await _press(menu.resume_button())
	_check(GameManager.state == GameManager.State.PLAYING and not menu.is_showing, "RESUME returns to PLAYING")
	_check(timers.session_seconds() > 0.0, "session timer running again")
