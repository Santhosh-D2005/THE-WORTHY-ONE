extends Node
## Rhythm (minimum tapping speed) tests (Milestone 1.6).
##
## Run (needs a window; forced to 540x960):  godot --path . res://tests/rhythm_tests.tscn
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

	await _t_first_tap_and_pair()
	await _t_slow_taps()
	await _t_same_side()
	await _t_rapid_and_duplicates()
	await _t_difficulty_in_scene()
	await _t_pause_and_rhythm()
	await _t_failure_and_retry_rhythm()
	await _t_legacy_switch()
	await _t_controls()
	await _t_sword_motion()

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
var kinds: Array[int] = []

func _arm() -> void:
	menu = main.get_node("PauseMenu")
	kinds.clear()
	input.tap_accepted.connect(func(_s: TapSide.Side) -> void: kinds.append(input.last_kind))

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

func _tap_left() -> void:
	_touch_vp(Vector2(270.0, 1000.0))

func _tap_right() -> void:
	_touch_vp(Vector2(810.0, 1000.0))

# ======================================================================================
# 1-4. The rule through the real input pipeline (touch events)
# ======================================================================================

func _t_first_tap_and_pair() -> void:
	print("\n[1] FIRST TAP AWARDS NOTHING; THE FIRST VALID PAIR DOES")
	await _fresh_main()
	_arm()
	var gain := extraction.gain_per_tap
	var level1_limit: float = main.get_node("DifficultyManager").config.max_interval_for_level(1)
	_check(is_equal_approx(input.max_interval_msec, level1_limit) and is_equal_approx(level1_limit, difficulty_config.start_max_tap_interval_msec), "level 1 allows %.0f ms between taps (the configured start value; %.0f)" % [difficulty_config.start_max_tap_interval_msec, input.max_interval_msec])
	_tap_left()
	await _frames(2)
	_check(GameManager.state == GameManager.State.PLAYING and kinds == [TapKind.Kind.FIRST], "the first tap starts the attempt (PLAYING) as a FIRST tap")
	_check(extraction.progress == 0.0, "...and awards no progress")
	_check(timers.level_seconds() > 0.0 and timers.session_seconds() > 0.0, "...but it does start both timers")
	_check(sword._kick == 0.0, "...and gives no sword kick")
	await _wait(0.15)
	_tap_right()
	await _frames(2)
	_check(kinds.size() == 2 and kinds[1] == TapKind.Kind.PROGRESS, "an alternating tap 150 ms later is PROGRESS")
	var after_first := extraction.progress
	_check(after_first > 0.0 and _near(after_first, _gain_at(0.0), 0.001), "...and awards exactly the gain the speed curve gives for that interval (%.2f)" % extraction.progress)
	_check(input.last_interval_msec > 120.0 and input.last_interval_msec < 300.0, "the measured interval is real time (%.0f ms)" % input.last_interval_msec)
	await _wait(0.12)
	_tap_left()
	await _frames(2)
	_check(_near(extraction.progress, after_first + _gain_at(after_first), 0.001), "each further in-rhythm tap adds the gain of its own interval")

## 1.9: a tap is worth what the speed-response curve says for the interval the InputController measured (and the resistance
## at the height it arrives at). This is the independent expectation the tests compare the real progress against.
func _gain_at(progress_before: float) -> float:
	return SpeedGain.gain(input.last_interval_msec, extraction.gain_per_tap, extraction.optimal_interval_msec,
		extraction.useful_interval_msec, extraction.gain_exponent) * (1.0 - extraction.resistance * progress_before / 100.0)

func _t_slow_taps() -> void:
	print("\n[2] A SLOW ALTERNATING TAP AWARDS NOTHING (AND CANNOT HOLD THE BAR)")
	await _fresh_main()
	_arm()
	var gain := extraction.gain_per_tap
	_tap_left()
	await _wait(0.1)
	_tap_right()
	await _wait(0.1)
	_tap_left()
	await _frames(2)
	var before := extraction.progress
	_check(before > 0.0, "setup: two valid taps (%.1f)" % before)
	await _wait(0.6)  # longer than the allowed 400 ms (and past the 0.5 s grace, so decay has started)
	var decayed_to := extraction.progress
	_tap_right()
	await _frames(2)
	_check(kinds[kinds.size() - 1] == TapKind.Kind.TOO_SLOW, "an alternating tap after 0.6 s is TOO_SLOW")
	_check(extraction.progress <= decayed_to + 0.001, "...and does not raise progress (%.2f -> %.2f)" % [decayed_to, extraction.progress])
	_check(sword._kick == 0.0, "...and gives no sword kick")
	_check(hud._hint.text == "TAP FASTER" and hud._hint.modulate.a > 0.5, "the HUD shows a short 'TAP FASTER' reminder")
	_check(maxf(hud._flash_left, hud._flash_right) <= 0.25, "...and the tap panel flashes only faintly")
	_check(extraction.is_decaying or extraction.progress < before, "the slow tap did not stop the decay")
	await _wait(0.1)
	var p2 := extraction.progress
	_tap_left()
	await _frames(2)
	_check(kinds[kinds.size() - 1] == TapKind.Kind.PROGRESS and _near(extraction.progress, p2 + _gain_at(p2), 0.3),
		"the slow tap became the new anchor: the next quick tap counts (%.1f -> %.1f)" % [p2, extraction.progress])

	print(" - tapping steadily but too slowly never gets anywhere")
	await _fresh_main()
	_arm()
	var started := Time.get_ticks_msec()
	var peak := 0.0
	var left := true
	while GameManager.state != GameManager.State.FAILED and Time.get_ticks_msec() - started < 6000:
		if left:
			_tap_left()
		else:
			_tap_right()
		left = not left
		await _wait(0.55)
		peak = maxf(peak, extraction.progress)
	_check(peak == 0.0, "tapping every 0.55 s: progress stays exactly 0 (peak %.2f)" % peak)
	_check(GameManager.state == GameManager.State.FAILED, "...and the attempt fails (no stalling at 0 forever)")
	_check(kinds[0] == TapKind.Kind.FIRST and kinds.slice(1).all(func(k: int) -> bool: return k == TapKind.Kind.TOO_SLOW), "kinds: FIRST then only TOO_SLOW")

func _t_same_side() -> void:
	print("\n[3] REPEATED SAME-SIDE TAPS DO NOTHING")
	await _fresh_main()
	_arm()
	var gain := extraction.gain_per_tap
	_tap_left()
	await _wait(0.1)
	_tap_right()
	await _wait(0.06)
	var accepted_before := kinds.size()
	var p := extraction.progress
	for i in 3:
		_tap_right()
		await _wait(0.04)
	_check(kinds.size() == accepted_before and _near(extraction.progress, p, 0.001), "three same-side taps: none accepted, progress unchanged")
	# The interval is measured from the last ACCEPTED tap, not from the rejected repeats.
	await _wait(0.03)  # ~0.25 s after the last accepted tap, ~0.04 s after the last rejected one
	_tap_left()
	await _frames(2)
	_check(kinds[kinds.size() - 1] == TapKind.Kind.PROGRESS and _near(extraction.progress, p + _gain_at(p), 0.3),
		"the next alternating tap still counts: the rejected repeats did not disturb the timing")
	# Same side right after the FIRST tap
	await _fresh_main()
	_arm()
	_tap_left()
	await _wait(0.06)
	_tap_left()
	await _wait(0.06)
	_check(kinds.size() == 1 and extraction.progress == 0.0, "first tap then the same side again: only the first is accepted, no progress")

func _t_rapid_and_duplicates() -> void:
	print("\n[4] RAPID TAPS AND DUPLICATE EVENTS DO NOT CREATE EXTRA PROGRESS")
	await _fresh_main()
	_arm()
	extraction.configure(1.0, 0.0, 5.0)  # peak 1 %, no decay
	var applied_gains: Array[float] = []
	extraction.valid_tap_applied.connect(func(g: float, _p: float) -> void: applied_gains.append(g))
	var left := true
	for i in 30:
		if left:
			_tap_left()
			_tap_left()  # duplicate event in the same instant
		else:
			_tap_right()
			_tap_right()
		left = not left
		await _wait(0.04)
	await _frames(2)
	var progress_taps := kinds.filter(func(k: int) -> bool: return k == TapKind.Kind.PROGRESS).size()
	print("   accepted %d taps (%d progress), progress %.1f" % [kinds.size(), progress_taps, extraction.progress])
	_check(kinds.size() >= 25 and kinds.size() <= 30, "duplicates were refused: %d accepted out of 30 distinct taps" % kinds.size())
	_check(kinds[0] == TapKind.Kind.FIRST and kinds.slice(1).all(func(k: int) -> bool: return k == TapKind.Kind.PROGRESS), "every tap after the first is PROGRESS at 40 ms spacing")
	var gain_sum := 0.0
	for g in applied_gains:
		gain_sum += g
	_check(applied_gains.size() == progress_taps and _near(extraction.progress, gain_sum, 0.001), "progress == the sum of the gains of the valid pairs, one gain per valid pair, duplicates add nothing (%.2f)" % extraction.progress)
	# Two fingers at the same instant (one per side)
	var count := kinds.size()
	await _wait(0.06)
	_pause_expected = false
	var a := InputEventScreenTouch.new()
	a.index = 0
	a.pressed = true
	a.position = _to_window(Vector2(270.0, 1000.0))
	var b := InputEventScreenTouch.new()
	b.index = 1
	b.pressed = true
	b.position = _to_window(Vector2(810.0, 1000.0))
	Input.parse_input_event(a)
	Input.parse_input_event(b)
	await _frames(2)
	_check(kinds.size() == count + 1, "two fingers at once (left + right): exactly one tap accepted")

func _t_difficulty_in_scene() -> void:
	print("\n[5] THE ALLOWED INTERVAL FOLLOWS THE LEVEL")
	await _fresh_main()
	var config: DifficultyConfig = main.get_node("DifficultyManager").config
	_check(is_equal_approx(input.max_interval_msec, config.max_interval_for_level(1)), "level 1: %.0f ms" % input.max_interval_msec)
	var seen: Array[float] = [input.max_interval_msec]
	for lv in 2:
		await _pump_until_extracted()
		await _wait_for(func() -> bool: return GameManager.level == lv + 1 and GameManager.state == GameManager.State.READY, 8.0)
		seen.append(input.max_interval_msec)
	print("   intervals on levels 1-3: ", seen)
	_check(GameManager.level == 3 and seen[1] < seen[0] and seen[2] < seen[1], "the limit tightens on every level (%.0f -> %.0f -> %.0f ms)" % [seen[0], seen[1], seen[2]])
	_check(is_equal_approx(seen[2], config.max_interval_for_level(3)), "level 3 uses the configured curve value")
	_check(extraction.zero_progress_extra_seconds > 0.2 and is_equal_approx(extraction.zero_progress_extra_seconds, seen[2] / 1000.0), "the stall allowance follows the same interval")
	# Designer override, independent of the level curve.
	var override := GameplayConfig.new()
	override.max_tap_interval_override_msec = 150
	main.gameplay_config = override
	main.get_node("DifficultyManager").apply_for_level(7)
	_check(is_equal_approx(input.max_interval_msec, 150.0), "max_tap_interval_override_msec forces the limit on any level (150 ms)")
	_arm()
	_tap_left()
	await _wait(0.2)
	_tap_right()
	await _frames(2)
	_check(kinds[kinds.size() - 1] == TapKind.Kind.TOO_SLOW, "a 200 ms gap is too slow under the 150 ms override")

func _t_pause_and_rhythm() -> void:
	print("\n[6] PAUSE FREEZES THE RHYTHM; RESUME RE-ESTABLISHES IT")
	await _fresh_main()
	_arm()
	var gain := extraction.gain_per_tap
	_tap_left()
	await _wait(0.1)
	_tap_right()
	await _wait(0.1)
	var p := extraction.progress
	_check(p > 0.0 and _near(p, _gain_at(0.0), 0.001), "setup: one valid pair (%.1f)" % p)
	_back()
	await _frames(2)
	var kinds_at_pause := kinds.size()
	await _wait(2.0)  # far longer than the grace + interval: running clocks would have decayed / failed
	_check(extraction.progress == p and GameManager.state == GameManager.State.PAUSED and failed_events.is_empty(), "2 s paused: progress frozen, no failure")
	_tap_left()
	_tap_right()
	await _frames(3)
	_check(kinds.size() == kinds_at_pause and extraction.progress == p, "taps while paused do not count (no rhythm progress)")
	await _wait_menu_ready()
	await _press(menu.resume_button())
	_check(GameManager.state == GameManager.State.PLAYING and extraction.progress >= p - 0.5, "resumed into PLAYING with the progress intact (%.1f)" % extraction.progress)
	_tap_left()
	await _frames(2)
	_check(kinds[kinds.size() - 1] == TapKind.Kind.FIRST, "the first tap after resuming is a FIRST tap (the paused time is not counted as a slow gap)")
	_check(hud._hint.text != "TAP FASTER", "...so no 'TAP FASTER' reminder")
	var p_resume := extraction.progress
	await _wait(0.12)
	_tap_right()
	await _frames(2)
	_check(kinds[kinds.size() - 1] == TapKind.Kind.PROGRESS and _near(extraction.progress, p_resume + _gain_at(p_resume), 0.3), "the next quick tap counts again")

	print(" - the stall timer (progress 0 after the first tap) is frozen by a pause as well")
	await _fresh_main()
	_arm()
	_tap_left()
	await _wait(0.2)
	_back()
	await _frames(2)
	await _wait(1.5)  # > grace + interval (0.9 s)
	_check(GameManager.state == GameManager.State.PAUSED and failed_events.is_empty(), "paused with progress 0: no failure while paused")
	await _wait_menu_ready()
	await _press(menu.resume_button())
	await _wait(0.3)
	_check(GameManager.state == GameManager.State.PLAYING and failed_events.is_empty(), "after resuming the attempt is still alive")

func _t_failure_and_retry_rhythm() -> void:
	print("\n[7] FAILURE AND RETRY WITH THE RHYTHM RULE")
	await _fresh_main()
	_arm()
	_tap_left()
	var failed := await _wait_for_state(GameManager.State.FAILED, 3.0)
	_check(failed and failed_events.size() == 1, "one tap and nothing else: the attempt fails once")
	await _wait_buttons_ready()
	hud._hint.text = "TAP FASTER"
	_click_vp(_center(screen.find_child("TryAgainButton", true, false) as Button))
	await _wait_for_state(GameManager.State.READY, 4.0)
	_check(hud._hint.text == HINT_RESET_TEXT and hud._hint.modulate.a > 0.9, "retry restores the normal hint text")
	await _wait(0.5)
	_tap_left()
	await _frames(2)
	_check(kinds.size() >= 1 and kinds[kinds.size() - 1] == TapKind.Kind.FIRST and extraction.progress == 0.0, "after a retry the first tap is FIRST again")
	await _wait(0.1)
	_tap_right()
	await _frames(2)
	_check(extraction.progress > 0.0, "and the next quick tap awards progress")

const HINT_RESET_TEXT := Hud.HINT_TEXT

func _t_legacy_switch() -> void:
	print("\n[8] THE RULE CAN BE SWITCHED OFF")
	await _fresh_main()
	_arm()
	input.rhythm_enabled = false
	extraction.zero_progress_extra_seconds = 0.0
	_tap_left()
	await _frames(2)
	_check(_near(extraction.progress, extraction.gain_per_tap, 0.001) and kinds[0] == TapKind.Kind.PROGRESS, "rhythm_enabled = false: the first tap awards progress (pre-1.6 behaviour)")
	await _wait(0.7)
	_tap_right()
	await _frames(2)
	_check(kinds[kinds.size() - 1] == TapKind.Kind.PROGRESS, "...and slow taps count too")

# ======================================================================================
# 9. Controls
# ======================================================================================

func _t_controls() -> void:
	print("\n[9] ROUND CONTROLS: SMALLER FOOTPRINT, TAPS STILL WORK EVERYWHERE")
	await _fresh_main()
	_arm()
	var zl: Rect2 = hud._zone_left.get_global_rect()
	var zr: Rect2 = hud._zone_right.get_global_rect()
	var visible := get_viewport().get_visible_rect().size
	var scale := visible.x / 1080.0
	print("   discs %dx%d and %dx%d in a %dx%d viewport" % [int(zl.size.x), int(zl.size.y), int(zr.size.x), int(zr.size.y), int(visible.x), int(visible.y)])
	_check(absf(zl.size.x - zl.size.y) < 1.0 and absf(zr.size.x - zr.size.y) < 1.0, "both controls are perfectly round")
	var old_area := 485.0 * 340.0 * scale * scale
	var new_area := PI * pow(zl.size.x * 0.5, 2.0)
	_check(new_area < old_area * 0.45, "the visual footprint is under 45 %% of the old rectangular panels (%.0f %%)" % (new_area / old_area * 100.0))
	_check(absf(zl.size.x - zr.size.x) < 1.0 and absf(zl.get_center().y - zr.get_center().y) < 1.0, "left and right discs are the same size and at the same height")
	_check(absf(zl.get_center().x - visible.x * 0.25) < 1.0 and absf(zr.get_center().x - visible.x * 0.75) < 1.0, "each disc is centred in its screen half")
	_check(zl.size.x * (720.0 / visible.x) >= 160.0, "on a 720-px-wide phone each disc is still at least 160 px across (%d px)" % int(zl.size.x * 720.0 / visible.x))
	_check(zl.end.x <= visible.x * 0.5 and zr.position.x >= visible.x * 0.5, "each disc stays inside its own screen half")
	# Taps outside the visible discs (above them, in the margins) still register: the whole half is the touch area.
	_touch_vp(Vector2(20.0, 300.0))  # far top-left corner, nowhere near a disc
	await _frames(2)
	_check(kinds.size() == 1 and input.last_accepted_side == TapSide.Side.LEFT, "a tap far above the left disc still counts as LEFT")
	await _wait(0.1)
	_touch_vp(Vector2(1060.0, 1900.0))  # extreme bottom-right corner, in the margin below the disc
	await _frames(2)
	_check(kinds.size() == 2 and input.last_accepted_side == TapSide.Side.RIGHT and extraction.progress > 0.0, "a tap in the bottom-right margin counts as RIGHT")

# ======================================================================================
# 10. Sword motion while tapping
# ======================================================================================

func _t_sword_motion() -> void:
	print("\n[10] THE SWORD DOES NOT VIBRATE WHEN TAPPING FAST")
	await _fresh_main()
	_arm()
	await _wait(1.3)  # landing camera shake
	var camera: Camera3D = main.get_node("Stage/Camera3D")
	extraction.configure(0.4, 0.0, 5.0)  # tiny gain: the bar never fills during the measurement
	var pommel := Vector3(0.0, SwordController.BLADE_LENGTH + 0.07 + SwordController.GRIP_LENGTH + 0.155, 0.0)
	var render_px := 432.0 / 1080.0  # phone render pixels per viewport unit
	var rates := {"slow (800 ms)": 800, "normal (220 ms)": 220, "very rapid (70 ms)": 70}
	var max_x_range := 0.0
	var max_reversals := 0.0
	for label in rates:
		var interval: int = rates[label]
		extraction.reset()
		extraction.set_active(true)
		extraction.configure(0.4, 0.0, 5.0)
		sword.set_progress(0.0)
		input.reset_alternation()
		await _wait(0.4)
		var xs: Array[float] = []
		var ys: Array[float] = []
		var kicks_without_progress := 0
		var start := Time.get_ticks_msec()
		var next := start
		var left := true
		var duration := 2500
		var thump_max := 0.0
		while Time.get_ticks_msec() - start < duration:
			if Time.get_ticks_msec() >= next:
				if left:
					_tap_left()
				else:
					_tap_right()
				left = not left
				next += interval
			await get_tree().process_frame
			var p: Vector2 = camera.unproject_position(sword._visual.to_global(pommel))
			xs.append(p.x * render_px)
			ys.append(p.y * render_px)
			thump_max = maxf(thump_max, sword._visual.position.y)
		var x_range := (xs.max() as float) - (xs.min() as float)
		var reversals := 0
		var last_sign := 0
		for i in range(1, xs.size()):
			var d := xs[i] - xs[i - 1]
			if absf(d) < 0.02:
				continue
			var s := 1 if d > 0.0 else -1
			if last_sign != 0 and s != last_sign:
				reversals += 1
			last_sign = s
		var per_second := float(reversals) / (float(duration) / 1000.0)
		print("   %-18s sideways range %.2f px, direction reversals %.1f/s, biggest thump %.4f" % [label, x_range, per_second, thump_max])
		max_x_range = maxf(max_x_range, x_range)
		max_reversals = maxf(max_reversals, per_second)
		_check(thump_max <= 0.0101, "%s: the tap thump never exceeds 1 cm (%.4f)" % [label, thump_max])
	# 1.10 (deliberate rule change): the blade now has a heavy, bounded micro-motion (a slow lean that changes side at most every 0.45 s,
	# so it can never become a vibration). It was "under 1 px, under 2 reversals/s" in 1.7 when the sword had no motion at all. The new
	# bounds still sit far below the old shake (5-9 px, 13-29 reversals/s).
	_check(max_x_range < 3.5, "sideways pommel movement stays under 3.5 phone render pixels at every tapping speed (max %.2f px; the old shake gave 5-9 px)" % max_x_range)
	_check(max_reversals < 3.5, "no vibration: at most %.1f direction reversals per second (the old shake gave 13-29)" % max_reversals)
	# Slow taps award nothing and therefore must not move the sword at all.
	extraction.reset()
	extraction.set_active(true)
	sword.set_progress(0.0)
	input.reset_alternation()
	await _wait(0.5)
	_tap_left()
	await _wait(0.6)
	_tap_right()
	await _frames(2)
	_check(sword._kick == 0.0 and sword._visual.position.length() < 0.0001, "a TOO_SLOW tap gives no motion at all")
	# The position stays a pure function of progress: no drift from the rapid taps.
	await _wait(0.5)
	var expected_y := sword._rest_position.y + extraction.progress / 100.0 * sword.full_lift
	_check(_near(sword.position.y, expected_y, 0.004), "the sword base still follows progress exactly after all that tapping")
