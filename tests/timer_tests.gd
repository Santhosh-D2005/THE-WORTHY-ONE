extends Node
## Session-timer lifecycle tests (Milestone 1.4).
##
## Run (needs a window; forced to 540x960):  godot --path . res://tests/timer_tests.tscn
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

	await _t_full_lifecycle()
	await _t_failure_screen_and_retry_hud()
	await _t_pause_does_not_count()

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
# The required lifecycle, in order, in ONE continuous run
# ======================================================================================

func _hud_session_text() -> String:
	return hud._session_time_label.text

func _t_full_lifecycle() -> void:
	print("
[1] SESSION TIMER LIFECYCLE: READY -> tap -> extract -> next level -> fail")
	await _fresh_main()

	# READY: the timer stays at zero for as long as nothing is tapped.
	_check(GameManager.state == GameManager.State.READY, "starts in READY")
	await _wait(1.2)
	_check(timers.session_seconds() == 0.0 and timers.level_seconds() == 0.0, "READY for 1.2 s: session and level timers both exactly 0")
	_check(_hud_session_text() == "SESSION  0:00.00", "the HUD shows SESSION 0:00.00 while waiting (%s)" % _hud_session_text())

	# A tap that is not accepted does not start it (same side twice: the second is rejected).
	_tap_expected()
	await _wait(0.06)
	var first_value := timers.session_seconds()
	_check(first_value > 0.0, "the first valid alternating tap starts the session timer (%.3f s)" % first_value)
	_check(timers.level_seconds() > 0.0, "...and the level timer")
	var width := get_viewport().get_visible_rect().size.x
	var wrong_side_x := width * (0.25 if input.expected_side() == SIDE_RIGHT else 0.75)
	_touch_vp(Vector2(wrong_side_x, 1000.0))  # wrong side: not a valid tap
	_check(accepted.size() == 1, "a wrong-side tap is not accepted (still %d accepted)" % accepted.size())

	# Extract level 1.
	var before_extraction := timers.session_seconds()
	await _pump_until_extracted()
	await _wait_for(func() -> bool: return GameManager.level == 2, 6.0)
	_check(GameManager.level == 2 and succeeded_count == 1, "level 1 extracted, now on level 2")
	var after_extraction := timers.session_seconds()
	_check(after_extraction > before_extraction, "session timer kept counting through the extraction (%.2f -> %.2f)" % [before_extraction, after_extraction])

	# Next level: session keeps running even before the first tap of that level; level timer restarts from 0.
	await _wait_for_state(GameManager.State.READY, 6.0)
	var level2_ready := timers.session_seconds()
	_check(timers.level_seconds() == 0.0, "level 2: the LEVEL timer is back at 0 and waits for a tap")
	await _wait(0.3)
	_check(timers.session_seconds() > level2_ready + 0.2, "level 2: the SESSION timer is still running (%.2f -> %.2f)" % [level2_ready, timers.session_seconds()])
	_check(timers.level_seconds() == 0.0, "level 2: LEVEL timer still 0 until the first tap")
	_tap_expected()
	await _wait(0.1)
	_check(timers.level_seconds() > 0.0, "level 2: the first tap starts the level timer")

	# Failure: stop tapping; both timers freeze at the failure.
	var failed := await _wait_failed()
	_check(failed, "failed on level 2 after tapping stopped")
	var frozen_session := timers.session_seconds()
	var frozen_level := timers.level_seconds()
	await _wait(1.0)
	_check(timers.session_seconds() == frozen_session and timers.level_seconds() == frozen_level, "failure: both timers frozen for 1 s (session %.3f)" % frozen_session)
	_check(failed_events.size() == 1 and failed_events[0].session_seconds == frozen_session, "the run result carries exactly the frozen session time")
	_check(frozen_session > after_extraction, "the frozen session time covers both levels (%.2f s)" % frozen_session)

func _t_failure_screen_and_retry_hud() -> void:
	print("
[2] RETRY: the session timer resets to zero and waits for the first tap")
	await _wait_buttons_ready()
	_check(_hud_session_text() != "SESSION  0:00.00", "before retry the HUD still shows the frozen time (%s)" % _hud_session_text())
	_click_vp(_center(_button("TryAgainButton")))
	await _wait_for_state(GameManager.State.READY, 4.0)
	_check(GameManager.state == GameManager.State.READY and GameManager.level == 1, "retry: READY on level 1")
	_check(timers.session_seconds() == 0.0 and timers.level_seconds() == 0.0, "retry: both timers reset to exactly 0")
	await _wait(1.0)
	_check(timers.session_seconds() == 0.0 and timers.level_seconds() == 0.0, "retry: still 0 after waiting 1 s without a tap (does not run by itself)")
	_check(_hud_session_text() == "SESSION  0:00.00", "retry: the HUD shows SESSION 0:00.00")
	_tap_expected()
	await _wait(0.1)
	_check(timers.session_seconds() > 0.0 and timers.session_seconds() < 0.5, "retry: the first valid tap starts the session timer again from 0 (%.3f s)" % timers.session_seconds())

func _t_pause_does_not_count() -> void:
	print("
[3] BACKGROUNDING DOES NOT COUNT TOWARDS THE SESSION")
	await _fresh_main()
	_tap_expected()
	await _wait(0.2)
	await _simulate_focus_loss()
	var at_pause := timers.session_seconds()
	await _wait(1.0)
	_check(_near(timers.session_seconds(), at_pause, 0.001), "paused for 1 s: session timer did not move")
	_pause_expected = true
	_touch_vp(Vector2(270, 1500))  # resume tap
	await _frames(3)
	_pause_expected = false
	_check(GameManager.state != GameManager.State.PAUSED, "resumed")
	_check(timers.session_seconds() < at_pause + 0.3, "after resume the pause time was not added (%.2f -> %.2f)" % [at_pause, timers.session_seconds()])
