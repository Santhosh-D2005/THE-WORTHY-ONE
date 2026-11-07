extends Node
## Failure-system integration tests (Milestone 1.2).
##
## Run (needs a window; forced to 540x960):
##   godot --path . res://tests/failure_tests.tscn [-- <screenshot_dir>]
## Exit code: 0 = all passed, 1 = failures, 2 = invalid run (the window lost OS focus).
##
## SIMULATED INPUT ONLY. Events are built in code and sent through Input.parse_input_event()
## into the real main.tscn (real managers, real HUD, real FailureScreen). This is NOT a test on
## a physical Android touchscreen. Lifecycle (pause) is simulated with engine notifications.
## Keep other windows alone while it runs: real focus loss pauses the game by design.

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

	await _t_wait_before_first_tap()
	await _t_one_tap_then_stop()
	await _t_exactly_one_failure_and_zero_detection()
	await _t_input_disabled_timers_stopped()
	await _t_sword_animation()
	await _t_failure_screen_content_and_spam()
	await _t_retry_by_mouse_and_immediate_restart()
	await _t_retry_by_touch_and_negative_cases()
	await _t_double_press_retry()
	await _t_level_reset_after_progress()
	await _t_failure_during_other_states()
	await _t_pause_while_failed()
	await _t_main_menu_button()
	await _t_retry_input_lock()

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
# 1. Before the first valid tap the player cannot fail
# ======================================================================================

func _t_wait_before_first_tap() -> void:
	print("\n[1] WAITING BEFORE THE FIRST VALID TAP")
	await _fresh_main()
	await _wait(3.5)
	_check(GameManager.state == GameManager.State.READY, "still READY after 3.5 s of doing nothing")
	_check(extraction.progress == 0.0 and failed_events.is_empty() and not GameManager.run_over, "progress stays 0, no failure, run not over")
	_check(timers.level_seconds() == 0.0 and timers.session_seconds() == 0.0, "timers inactive (both 0)")
	_check(input.enabled and not screen.is_showing, "input still enabled; no failure screen")
	# A depletion signal arriving here must be refused (cannot fail before the first valid tap).
	extraction.progress_depleted.emit()
	await _frames(3)
	_check(GameManager.state == GameManager.State.READY and failed_events.is_empty(),
		"a stray progress_depleted signal in READY is ignored")
	_tap_expected()
	await _wait(0.06)
	_tap_expected()
	await _wait(0.1)
	_check(GameManager.state == GameManager.State.PLAYING and extraction.progress > 0.0 and extraction.progress <= extraction.gain_per_tap + 0.001,
		"the first tap after the long wait starts the attempt and the next in-rhythm tap awards progress")

# ======================================================================================
# 2. One valid tap, then stop -> natural failure
# ======================================================================================

func _t_one_tap_then_stop() -> void:
	print("\n[2] ONE VALID TAP, THEN STOP")
	await _fresh_main()
	var seconds := await _fail_the_run()
	print("   failed %.2f s after the single tap (1.6 rule: the tap awards nothing; expected 0.35 s grace + 0.37 s allowed interval = 0.72 s at level 1)" % seconds)
	_check(seconds > 0.6 and seconds < 1.2, "a single tap with no follow-up fails after grace + the allowed interval (%.2f s)" % seconds)
	_check(GameManager.state == GameManager.State.FAILED and GameManager.run_over, "state FAILED, run marked over")
	_check(extraction.progress == 0.0 and progress_min >= 0.0, "progress is exactly 0 (never negative)")
	_check(failed_events.size() == 1, "exactly one failure event (%d)" % failed_events.size())
	var result := failed_events[0]
	_check(result.level_reached == 1 and result.extractions == 0, "result: level 1, 0 extractions")
	_check(result.session_seconds > 0.6 and result.final_level_seconds > 0.6, "result carries real elapsed times (%.2f s)" % result.session_seconds)
	_check(not input.enabled, "input disabled immediately")
	_check(not extraction._active, "extraction stopped (inactive)")

# ======================================================================================
# 3. Exactly one failure; zero detection is correct
# ======================================================================================

func _t_exactly_one_failure_and_zero_detection() -> void:
	print("\n[3] EXACTLY ONE FAILURE / ZERO DETECTION")
	await _fresh_main()
	# Six taps (the first awards nothing, then 5 x 2 % = 10 %), then stop. Sample EVERY frame while it decays: the
	# run must stay alive for as long as progress is above 0 and end on the first frame it is exactly 0.
	for i in 5:
		_tap_expected()
		await _wait(0.08)
	_tap_expected()
	var lowest_while_alive := 1000.0
	var frames_alive := 0
	var deadline := Time.get_ticks_msec() + 8000
	while GameManager.state != GameManager.State.FAILED and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if GameManager.state != GameManager.State.FAILED:
			lowest_while_alive = minf(lowest_while_alive, extraction.progress)
			frames_alive += 1
	_check(GameManager.state == GameManager.State.PLAYING or GameManager.state == GameManager.State.FAILED,
		"state was only ever PLAYING until the failure")
	_check(frames_alive > 60 and lowest_while_alive > 0.0,
		"the run stayed alive for %d frames while progress was above 0 (lowest %.3f%%)" % [frames_alive, lowest_while_alive])
	_check(GameManager.state == GameManager.State.FAILED and extraction.progress == 0.0, "failure happened exactly when progress reached 0")
	await _wait(0.5)
	_check(failed_events.size() == 1, "one failure event after natural failure")
	for i in 5:
		extraction.progress_depleted.emit()  # repeated attempts to trigger it again
	_check(not GameManager.begin_failure(), "begin_failure() refuses a second failure")
	await _wait(0.2)
	_check(failed_events.size() == 1, "five more depletion signals produced no extra failure event")
	await _wait_for(func() -> bool: return screen.is_showing, 5.0)
	await _wait(0.3)
	_check(screen.show_count == 1, "exactly one failure screen shown (%d)" % screen.show_count)

# ======================================================================================
# 4. Input disabled and timers stopped after failure
# ======================================================================================

func _t_input_disabled_timers_stopped() -> void:
	print("\n[4] INPUT DISABLED / TIMERS STOPPED")
	await _fresh_main()
	await _fail_the_run()
	var level_t := timers.level_seconds()
	var session_t := timers.session_seconds()
	var result := failed_events[0]
	_check(_near(level_t, result.final_level_seconds, 0.0001) and _near(session_t, result.session_seconds, 0.0001),
		"timers equal the captured result (level %.3f, session %.3f)" % [level_t, session_t])
	var accepted_before := accepted.size()
	var width := get_viewport().get_visible_rect().size.x
	for i in 12:  # hammer gameplay taps on both halves, plus clicks
		_touch_vp(Vector2(width * (0.25 if i % 2 == 0 else 0.75), 1000.0))
		_mouse_button_vp(Vector2(width * 0.25, 1000.0), true)
		await _wait(0.035)
	for i in 30:
		extraction.register_valid_tap()  # even bypassing input
	extraction.extraction_completed.emit()  # and a forced (bogus) completion
	await _wait(1.0)
	_check(accepted.size() == accepted_before, "no gameplay tap was accepted after failure")
	_check(extraction.progress == 0.0 and succeeded_count == 0,
		"progress stays 0; no extraction/level completion possible (even with 30 direct taps and a forced completion signal)")
	_check(GameManager.state == GameManager.State.FAILED and GameManager.level == 1, "still FAILED on level 1")
	_check(timers.level_seconds() == level_t and timers.session_seconds() == session_t,
		"timers did not move for 1 s (level %.3f, session %.3f)" % [timers.level_seconds(), timers.session_seconds()])

# ======================================================================================
# 5. Sword failure animation
# ======================================================================================

func _t_sword_animation() -> void:
	print("\n[5] SWORD FAILURE ANIMATION")
	await _fresh_main()
	var rest := sword._rest_position
	_tap_expected()
	await _wait_failed()
	var settled := [false]
	sword.failure_settled.connect(func() -> void: settled[0] = true)
	var baseline_tweens := get_tree().get_processed_tweens().size()
	sword.play_failure()      # a second failure animation
	sword.play_extraction()   # and an extraction animation, while the failure one runs
	sword.play_entrance()
	_check(get_tree().get_processed_tweens().size() == baseline_tweens,
		"extraction/entrance/second failure animation cannot start during the failure animation (tween count unchanged)")
	var samples: Array[float] = []
	var min_visual_y := 0.0
	var max_visual := 0.0
	var started := Time.get_ticks_msec()
	while not settled[0] and Time.get_ticks_msec() - started < 4000:
		await get_tree().process_frame
		samples.append(sword.position.y)
		min_visual_y = minf(min_visual_y, sword._visual.position.y)
		max_visual = maxf(max_visual, sword._visual.position.length())
	var duration := float(Time.get_ticks_msec() - started) / 1000.0
	print("   animation took %.2f s over %d frames; deepest seating dip %.4f; largest offset %.4f" % [duration, samples.size(), min_visual_y, max_visual])
	_check(settled[0] and duration > 0.6 and duration < 1.6, "animation completes (%.2f s)" % duration)
	var monotonic := true
	var overshoot := false
	for value in samples:
		if value < rest.y - 0.00001:
			overshoot = true
	for i in range(1, samples.size()):
		if samples[i] > samples[i - 1] + 0.00001:
			monotonic = false
	_check(monotonic and not overshoot, "sword only moves toward its embedded position, never above/below the path (no pops)")
	_check(min_visual_y < 0.0 and min_visual_y > -0.02 and max_visual < 0.02, "subtle resistance: small seating dip, no big movement")
	_check(sword.position == rest and sword._visual.position == Vector3.ZERO and sword._visual.rotation == Vector3.ZERO,
		"final pose is EXACTLY the original embedded position")
	_check(not sword._tween_running, "no tween left running")
	await _wait(0.2)
	_check(sword.position == rest, "sword stays at the embedded position afterwards")

# ======================================================================================
# 6. Failure screen content; spamming during the animation
# ======================================================================================

func _t_failure_screen_content_and_spam() -> void:
	print("\n[6] FAILURE SCREEN + TAPS DURING THE ANIMATION")
	await _fresh_main()
	_tap_expected()
	await _wait_failed()
	_check(not screen.visible or not screen.is_showing, "screen is not shown yet at the instant of failure")
	var try_button := _button("TryAgainButton")
	var spam_point := _center(try_button)
	# Hammer exactly where TRY AGAIN will appear, for the whole animation + fade (before it is interactive).
	var spam_until := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < spam_until:
		_tap_vp(spam_point)
		_mouse_button_vp(spam_point, true)
		_mouse_button_vp(spam_point, false)
		await _wait(0.035)
	_check(GameManager.state == GameManager.State.FAILED and GameManager.level == 1 and failed_events.size() == 1,
		"taps/clicks on the future TRY AGAIN spot during the animation changed nothing")
	_check(await _wait_for(func() -> bool: return screen.is_showing and screen.visible, 3.0), "the failure screen appears after the animation")
	_check(screen.show_count == 1 and not screen.buttons_ready, "shown exactly once; buttons not yet interactive (accident protection)")
	_check(screen.find_child("Title", true, false).text == "THE SWORD REMAINS", "title reads THE SWORD REMAINS")
	var result := failed_events[0]
	_check(screen.find_child("LevelValue", true, false).text == str(result.level_reached), "LEVEL REACHED shows %d" % result.level_reached)
	_check(screen.find_child("SessionValue", true, false).text == RunResult.format_time(result.session_seconds),
		"SESSION TIME shows %s" % RunResult.format_time(result.session_seconds))
	_check(screen.find_child("ExtractionsValue", true, false).text == str(result.extractions), "TOTAL EXTRACTIONS shows %d" % result.extractions)
	_check(_button("TryAgainButton").text == "TRY AGAIN" and _button("MainMenuButton").text == "MAIN MENU", "button labels are TRY AGAIN / MAIN MENU")
	# Pressing before the screen is interactive must do nothing.
	_click_vp(_center(try_button))
	_tap_vp(_center(try_button))
	await _frames(3)
	_check(GameManager.state == GameManager.State.FAILED, "pressing TRY AGAIN before the screen is interactive does nothing")
	await _wait_buttons_ready()
	await _wait(0.5)  # let the HUD fade finish for the screenshot
	_check(hud._fade_group[0].modulate.a < 0.05, "the gameplay HUD has stepped aside")
	_check(main.get_node("Stage").visible and sword.position == sword._rest_position, "stump and embedded sword remain visible")
	_save_screenshot("failure_screen.png")
	_check(await _wait_for(func() -> bool: return screen.buttons_ready, 1.0), "buttons become interactive after the delay")

# ======================================================================================
# 7. TRY AGAIN by real mouse click, then an immediate new extraction
# ======================================================================================

func _t_retry_by_mouse_and_immediate_restart() -> void:
	print("\n[7] TRY AGAIN (mouse) AND IMMEDIATE RESTART")
	await _fresh_main()
	await _fail_the_run()
	await _wait_buttons_ready()
	var expected_gain: float = difficulty_config.peak_gain_for_level(1)
	_click_vp(_center(_button("TryAgainButton")))
	await _frames(3)
	_check(GameManager.state == GameManager.State.READY, "state is READY after TRY AGAIN")
	_check(GameManager.level == 1 and GameManager.run_extractions == 0 and not GameManager.run_over and GameManager.last_result == null,
		"run data reset (level 1, 0 extractions, not over)")
	_check(extraction.progress == 0.0 and extraction._active and _near(extraction.gain_per_tap, expected_gain, 0.0001),
		"extraction reset to 0% and active with level-1 difficulty")
	_check(timers.level_seconds() == 0.0 and timers.session_seconds() == 0.0, "both run timers reset to 0")
	_check(sword.position == sword._rest_position and sword._visual.position == Vector3.ZERO and not sword._animating,
		"sword is at the initial embedded position and responsive")
	_check(input.enabled and input.last_accepted_side == TapSide.Side.NONE, "input re-enabled, alternation reset")
	_check(not screen.is_showing and not screen.visible, "failure screen hidden")
	_check(failed_events.size() == 1, "TRY AGAIN did not create a failure event")
	await _wait(0.5)
	_check(hud._fade_group[0].modulate.a > 0.95, "the gameplay HUD is back")
	_check(hud._level_label.text == "LEVEL 1", "HUD shows LEVEL 1")
	# Start another extraction (0.5 s have passed, so the default 0.4 s retry lock has expired).
	_tap_expected()
	await _wait(0.06)
	_tap_expected()
	await _wait(0.1)
	_check(GameManager.state == GameManager.State.PLAYING and extraction.progress > 0.0 and extraction.progress <= expected_gain + 0.001,
		"a new extraction works once the retry lock has expired (progress %.1f)" % extraction.progress)
	_check(timers.level_seconds() > 0.0 and timers.session_seconds() > 0.0, "timers start again on the first valid tap")
	var failed := await _wait_failed()
	_check(failed and failed_events.size() == 2, "the new run can fail again: exactly 2 failure events in total (%d)" % failed_events.size())
	await _wait_for(func() -> bool: return screen.is_showing and screen.visible, 4.0)
	await _wait(0.2)
	_check(screen.show_count == 2, "two failures -> two screens in total, never duplicated (%d)" % screen.show_count)
	_check(failed_events[1].level_reached == 1 and failed_events[1].extractions == 0, "second result is for the new run")
	# Idle after retry: waiting indefinitely before the first tap must not fail.
	await _wait_buttons_ready()
	_click_vp(_center(_button("TryAgainButton")))
	await _frames(3)
	await _wait(2.5)
	_check(GameManager.state == GameManager.State.READY and failed_events.size() == 2, "after a retry the player can again wait without failing")

# ======================================================================================
# 8. TRY AGAIN by touch; negative cases
# ======================================================================================

func _t_retry_by_touch_and_negative_cases() -> void:
	print("\n[8] TRY AGAIN (touch) AND NEGATIVE CASES")
	await _fresh_main()
	await _fail_the_run()
	await _wait_buttons_ready()
	var button := _button("TryAgainButton")
	var inside := _center(button)
	var outside := Vector2(540, 700)  # empty middle of the screen
	_touch_vp(inside, true)
	_touch_vp(outside, false)
	await _frames(3)
	_check(GameManager.state == GameManager.State.FAILED, "press on TRY AGAIN but release elsewhere does not retry")
	_touch_vp(outside, true)
	_touch_vp(inside, false)
	await _frames(3)
	_check(GameManager.state == GameManager.State.FAILED, "press elsewhere and release on TRY AGAIN does not retry")
	var accepted_before := accepted.size()
	_tap_vp(outside)
	await _frames(3)
	_check(GameManager.state == GameManager.State.FAILED and accepted.size() == accepted_before,
		"tapping the empty screen does nothing (no gameplay tap)")
	_tap_vp(inside)
	await _frames(3)
	_check(GameManager.state == GameManager.State.READY and GameManager.level == 1, "touch press+release on TRY AGAIN starts a fresh run")
	_check(sword.position == sword._rest_position and extraction.progress == 0.0, "fresh run: sword embedded, progress 0")

# ======================================================================================
# 9. Double press
# ======================================================================================

func _t_double_press_retry() -> void:
	print("\n[9] DOUBLE PRESS ON TRY AGAIN")
	await _fresh_main()
	await _fail_the_run()
	await _wait_buttons_ready()
	var point := _center(_button("TryAgainButton"))
	level_changed_count = 0
	_click_vp(point)
	_click_vp(point)
	_tap_vp(point)
	await _frames(4)
	_check(level_changed_count == 1, "the run was reset exactly once despite 3 rapid presses (%d)" % level_changed_count)
	# Since Milestone 1.3 the 2nd/3rd presses land inside the post-retry input lock, so they can
	# no longer start the next attempt by accident.
	_check(GameManager.state == GameManager.State.READY and extraction.progress == 0.0 and timers.level_seconds() == 0.0
		and failed_events.size() == 1 and not screen.is_showing,
		"after a triple press the run is cleanly READY (no accidental start), no extra failure, no screen")

# ======================================================================================
# 10. Level reset after real progress
# ======================================================================================

func _t_level_reset_after_progress() -> void:
	print("\n[10] FAILING ON LEVEL 3 AND RETRYING")
	await _fresh_main()
	for level in 2:
		await _pump_until_extracted()
		_check(await _wait_for_state(GameManager.State.READY, 6.0), "level %d completed, next level ready" % (level + 1))
	_check(GameManager.level == 3 and GameManager.run_extractions == 2, "reached level 3 with 2 extractions")
	var session_before_fail := timers.session_seconds()
	await _fail_the_run()
	var result := failed_events[0]
	_check(result.level_reached == 3 and result.extractions == 2, "failure result: level 3, 2 extractions")
	_check(result.session_seconds > session_before_fail, "session time covers the whole run (%.2f s)" % result.session_seconds)
	await _wait_for(func() -> bool: return screen.is_showing, 4.0)
	_check(screen.find_child("LevelValue", true, false).text == "3" and screen.find_child("ExtractionsValue", true, false).text == "2",
		"screen shows LEVEL REACHED 3 and TOTAL EXTRACTIONS 2")
	await _wait_buttons_ready()
	_click_vp(_center(_button("TryAgainButton")))
	await _frames(3)
	_check(GameManager.level == 1 and GameManager.run_extractions == 0, "level reset to 1, extractions reset to 0")
	_check(_near(extraction.gain_per_tap, difficulty_config.peak_gain_for_level(1), 0.0001)
		and _near(extraction.decay_per_second, difficulty_config.decay_for_level(1), 0.0001),
		"difficulty back to level-1 values")
	_check(hud._level_label.text == "LEVEL 1" and sword.position == sword._rest_position and timers.session_seconds() == 0.0,
		"HUD level, sword pose and session timer all reset")

# ======================================================================================
# 11. Failure signal arriving in other states
# ======================================================================================

func _t_failure_during_other_states() -> void:
	print("\n[11] DEPLETION DURING OTHER STATES (ANIMATION, ENTRANCE, PAUSE)")
	# (a) during the success animation
	await _fresh_main()
	await _pump_until_extracted()
	_check(GameManager.state == GameManager.State.EXTRACTING, "success animation running")
	extraction.progress_depleted.emit()
	await _frames(3)
	_check(GameManager.state == GameManager.State.EXTRACTING and failed_events.is_empty() and not GameManager.run_over,
		"a depletion signal during the success animation is ignored")
	_check(await _wait_for_state(GameManager.State.READY, 6.0) and GameManager.level == 2 and failed_events.is_empty(),
		"the level still advances exactly once; no failure, no failure screen")
	# (b) during the entrance animation of a brand-new scene
	await _fresh_main(false)
	_check(GameManager.state == GameManager.State.EXTRACTING, "entrance animation running")
	extraction.progress_depleted.emit()
	await _frames(2)
	_check(GameManager.state == GameManager.State.EXTRACTING and failed_events.is_empty(), "a depletion signal during the entrance is ignored")
	await _wait_for_state(GameManager.State.READY, 5.0)
	# (c) while paused: the stray signal is refused, and the real failure still happens later, once
	_tap_expected()
	await _wait(0.2)
	await _simulate_focus_loss()
	_check(GameManager.state == GameManager.State.PAUSED, "paused mid-attempt")
	extraction.progress_depleted.emit()
	await _frames(2)
	_check(GameManager.state == GameManager.State.PAUSED and failed_events.is_empty(), "a depletion signal while paused is ignored")
	_touch_vp(Vector2(270, 1500))  # resume tap
	await _frames(3)
	_check(GameManager.state == GameManager.State.PLAYING, "resumed to PLAYING")
	_check(await _wait_failed() and failed_events.size() == 1, "the natural failure afterwards still happens, exactly once")

# ======================================================================================
# 12. Pause while failed
# ======================================================================================

func _t_pause_while_failed() -> void:
	print("\n[12] PAUSE DURING AND AFTER FAILURE")
	await _fresh_main()
	_tap_expected()
	await _wait_failed()
	var level_t := timers.level_seconds()
	var session_t := timers.session_seconds()
	await _simulate_focus_loss()   # pause during the failure animation
	_check(GameManager.state == GameManager.State.PAUSED, "paused during the failure animation")
	await _wait(0.6)
	_check(not screen.is_showing, "no failure screen appears while paused")
	_touch_vp(Vector2(270, 1500))  # resume
	await _frames(3)
	_check(GameManager.state == GameManager.State.FAILED, "resume returns to FAILED (not to a playable state)")
	_check(await _wait_for(func() -> bool: return screen.is_showing, 4.0) and screen.show_count == 1,
		"the failure screen then appears exactly once")
	_check(sword.position == sword._rest_position, "sword ends at the embedded position even after a pause mid-animation")
	await _wait_buttons_ready()
	await _simulate_focus_loss()   # pause while the screen is up
	_check(GameManager.state == GameManager.State.PAUSED and not screen.visible, "failure screen steps aside while paused")
	_tap_vp(_center(_button("TryAgainButton")))  # lands on where TRY AGAIN is, but the game is paused
	await _frames(3)
	_check(GameManager.state == GameManager.State.FAILED and screen.visible and screen.show_count == 1,
		"the tap only resumed the game; it did not press TRY AGAIN; screen is back, not duplicated")
	_check(timers.level_seconds() == level_t and timers.session_seconds() == session_t, "timers never moved through any of it")

# ======================================================================================
# 13. MAIN MENU button
# ======================================================================================

func _t_main_menu_button() -> void:
	print("\n[13] MAIN MENU BUTTON")
	await _fresh_main()
	var requested_paths: Array[String] = []
	main.scene_changer = func(path: String) -> void: requested_paths.append(path)
	# 1.15: the real main menu scene now exists, so the button is enabled by default. The disabled behaviour is still checked by
	# pointing the button at a scene path that does not exist.
	_check(ResourceLoader.exists(screen.main_menu_scene_path), "the real main menu scene exists (%s)" % screen.main_menu_scene_path)
	_check(screen.is_main_menu_available(), "MAIN MENU is enabled by default now that the menu exists")
	screen.main_menu_scene_path = "res://scenes/ui/does_not_exist.tscn"
	screen.refresh_main_menu_button()
	await _fail_the_run()
	await _wait_buttons_ready()
	var menu_button := _button("MainMenuButton")
	_check(menu_button.disabled and not screen.is_main_menu_available() and _near(menu_button.modulate.a, 0.38, 0.01),
		"MAIN MENU is shown disabled (dimmed) when the menu scene path does not exist")
	_click_vp(_center(menu_button))
	_tap_vp(_center(menu_button))
	await _frames(3)
	_check(requested_paths.is_empty() and GameManager.state == GameManager.State.FAILED, "pressing the disabled MAIN MENU does nothing and does not break the screen")
	# Provide a menu scene: the button must switch on and work (mouse path).
	screen.main_menu_scene_path = STUB_MENU
	screen.refresh_main_menu_button()
	_check(screen.is_main_menu_available() and _near(menu_button.modulate.a, 1.0, 0.01), "with a menu scene present the button becomes enabled")
	var records_before := GameManager.last_result
	_click_vp(_center(menu_button))
	await _frames(3)
	_check(requested_paths == [STUB_MENU], "clicking MAIN MENU asks to open the menu scene")
	_check(GameManager.last_result == records_before and GameManager.state == GameManager.State.FAILED,
		"leaving does not alter the stored run result")
	# Touch path.
	await _fresh_main()
	var touch_paths: Array[String] = []
	main.scene_changer = func(path: String) -> void: touch_paths.append(path)
	screen.main_menu_scene_path = STUB_MENU
	await _fail_the_run()
	await _wait_buttons_ready()
	_tap_vp(_center(_button("MainMenuButton")))
	await _frames(3)
	_check(touch_paths == [STUB_MENU], "touch press+release on MAIN MENU also opens the menu scene (once)")

# ======================================================================================
# 14. Post-retry input lock (Milestone 1.3)
# ======================================================================================

func _retry_now() -> void:
	await _wait_buttons_ready()
	_click_vp(_center(_button("TryAgainButton")))
	await _frames(2)

func _t_retry_input_lock() -> void:
	print("\n[14] POST-RETRY INPUT LOCK")
	await _fresh_main()
	_check(not input.is_locked() and is_equal_approx(main.gameplay_config.retry_input_lock_seconds, 0.4),
		"fresh game: no lock; default configured lock is 0.4 s")
	await _fail_the_run()
	var accepted_before := accepted.size()
	await _retry_now()
	var retried_at := Time.get_ticks_msec()
	_check(GameManager.state == GameManager.State.READY and input.is_locked(), "TRY AGAIN restarts the run and engages the lock")
	_check(input.lock_remaining_seconds() > 0.2 and input.lock_remaining_seconds() <= 0.4, "lock time remaining is about 0.4 s (%.2f)" % input.lock_remaining_seconds())
	# Hammer gameplay taps and clicks for the whole lock; they must not start the attempt nor extend the lock.
	var width := get_viewport().get_visible_rect().size.x
	var spam_until := retried_at + 330
	while Time.get_ticks_msec() < spam_until:
		_tap_expected()
		_mouse_button_vp(Vector2(width * 0.25, 1000.0), true)
		_mouse_button_vp(Vector2(width * 0.75, 1000.0), true)
		await _wait(0.035)
	_check(GameManager.state == GameManager.State.READY and accepted.size() == accepted_before and extraction.progress == 0.0
		and timers.level_seconds() == 0.0 and timers.session_seconds() == 0.0,
		"extra taps during the lock: still READY, nothing accepted, progress 0, timers not started")
	_check(await _wait_for(func() -> bool: return not input.is_locked(), 1.0), "the lock expires automatically")
	var expired_after := float(Time.get_ticks_msec() - retried_at) / 1000.0
	_check(expired_after > 0.3 and expired_after < 0.7, "it expired about 0.4 s after the retry (%.2f s), not extended by the blocked taps" % expired_after)
	await _wait(0.06)
	_tap_expected()
	await _wait(0.06)
	_tap_expected()
	await _wait(0.1)
	_check(GameManager.state == GameManager.State.PLAYING and extraction.progress > 0.0 and extraction.progress <= extraction.gain_per_tap + 0.001 and timers.level_seconds() > 0.0,
		"normal gameplay works right after the lock (progress %.1f, timers running)" % extraction.progress)
	await _pump_until_extracted()
	_check(await _wait_for_state(GameManager.State.READY, 6.0) and GameManager.level == 2 and not input.is_locked(),
		"a full level completes normally afterwards and the lock is not re-applied by level transitions")

	# The retry button itself is never affected: a second failure and a second retry work normally.
	await _fail_the_run()
	await _retry_now()
	_check(GameManager.state == GameManager.State.READY and GameManager.level == 1, "the retry button responds normally the next time too")
	await _wait(0.6)

	# Configurable: a long lock.
	await _fresh_main()
	main.gameplay_config = main.gameplay_config.duplicate()  # do not modify the shared resource
	main.gameplay_config.retry_input_lock_seconds = 1.2
	await _fail_the_run()
	await _retry_now()
	_check(input.lock_remaining_seconds() > 0.9, "a 1.2 s configured lock is applied (%.2f s left)" % input.lock_remaining_seconds())
	await _wait(0.8)
	_tap_expected()
	await _frames(2)
	_check(GameManager.state == GameManager.State.READY and input.is_locked(), "a tap 0.8 s in is still blocked with the longer lock")
	await _wait_for(func() -> bool: return not input.is_locked(), 2.0)
	await _wait(0.06)
	_tap_expected()
	await _frames(3)
	_check(GameManager.state == GameManager.State.PLAYING, "then gameplay works")

	# Configurable: no lock at all.
	await _fresh_main()
	main.gameplay_config = main.gameplay_config.duplicate()
	main.gameplay_config.retry_input_lock_seconds = 0.0
	await _fail_the_run()
	await _retry_now()
	_check(not input.is_locked(), "a lock of 0 disables the protection")
	_tap_expected()
	await _frames(3)
	_check(GameManager.state == GameManager.State.PLAYING, "with no lock an immediate tap starts the attempt")

	# Flavour line: a built-in line always exists, and the AI line is never requested in headless runs.
	var sample := RunResult.new()
	sample.level_reached = 7
	_check(FailureScreen.fallback_verdict(sample) != "", "a built-in verdict line exists for a failure")
	sample.end_reason = RunResult.EndReason.COMPLETED
	_check(FailureScreen.fallback_verdict(sample) != FailureScreen.fallback_verdict(RunResult.new()), "the completed run has its own line")
	var screen := main.find_child("FailureScreen", true, false)
	_check(screen != null and screen.find_child("Verdict", true, false) != null, "the failure screen has a Verdict label")
	_check(screen != null and not screen.verdict_enabled, "headless runs never ask the server for a verdict")
