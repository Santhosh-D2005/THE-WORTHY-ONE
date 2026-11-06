extends Node
## Gameplay integration tests (Milestone 1.1).
##
## Run (needs a window; it is forced to 540x960 so zone-boundary maths is pixel exact):
##   godot --path . res://tests/integration_tests.tscn
## (--headless works for most checks but its dummy 64x64 window cannot resolve the zone boundary.)
##
## WHAT THIS IS: simulated input. Events are built in code and fed to Godot's real input
## pipeline with Input.parse_input_event() (window coordinates -> content-scale transform ->
## viewport -> InputController._input), against the real main.tscn with all real managers.
## WHAT THIS IS NOT: a physical Android touchscreen test. No finger, no device driver, no
## Android lifecycle. Lifecycle (pause/resume) is simulated by sending the same engine
## notifications Godot delivers on focus loss; it does not prove the OS delivers them.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const SIDE_LEFT := TapSide.Side.LEFT
const SIDE_RIGHT := TapSide.Side.RIGHT

var _checks: int = 0
var _failures: int = 0
var _failed_labels: Array[String] = []
var _inconclusive_labels: Array[String] = []
var _unexpected_pauses: int = 0      # game paused by REAL window focus loss, not by the test
var _pause_expected: bool = false

var main: Node
var input: InputController
var extraction: ExtractionManager
var timers: TimerManager
var sword: SwordController
var difficulty_config: DifficultyConfig

# Per-fresh-scene recorders.
var accepted: Array[int] = []
var rejected: Array[int] = []
var progress_min: float = 1000.0
var progress_max: float = -1000.0
var completed_count: int = 0
var succeeded_events: Array[Vector2] = []  # x = level, y = level time

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep running (and awaiting) while the tree is paused
	Input.use_accumulated_input = false      # deliver events immediately, as an unbuffered device would
	difficulty_config = load("res://resources/difficulty/default_difficulty.tres")
	get_window().size = Vector2i(540, 960)
	get_window().always_on_top = true  # reduces (cannot eliminate) OS focus theft during the run
	get_window().grab_focus()
	GameManager.state_changed.connect(func(new_state: GameManager.State) -> void:
		if new_state == GameManager.State.PAUSED and not _pause_expected:
			_unexpected_pauses += 1
			print("  NOTE  the game was paused by a REAL window-focus loss (not caused by the test)"))
	await _frames(4)
	await _section_input()
	await _section_extraction()
	await _section_sword()
	await _section_levels()
	await _section_timers()
	print("\n==== %d checks, %d failed, %d inconclusive, %d unexpected focus-loss pause(s) ====" % [_checks, _failures, _inconclusive_labels.size(), _unexpected_pauses])
	for label in _failed_labels:
		print("  FAILED: ", label)
	for label in _inconclusive_labels:
		print("  INCONCLUSIVE (not counted as pass or fail): ", label)
	var invalid_run := _unexpected_pauses > 0 and _failures > 0
	if invalid_run:
		print("RESULT: INVALID RUN - the window lost OS focus during the test, so the game paused on its own and failures may be caused by that. Re-run without touching other windows.")
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

## Marks a check that could not be evaluated fairly (e.g. the machine was too slow for a
## "same instant" scenario). Reported separately; never counted as a pass.
func _inconclusive(label: String, reason: String) -> void:
	_inconclusive_labels.append("%s [%s]" % [label, reason])
	print("  SKIP  ", label, "  [", reason, "]")

## Sends two touches back to back; returns the milliseconds the pair took to deliver. The
## debounce only treats them as simultaneous if this is below the debounce interval.
func _touch_pair(x1: float, index1: int, x2: float, index2: int) -> int:
	var started := Time.get_ticks_msec()
	_touch(x1, index1)
	_touch(x2, index2)
	return Time.get_ticks_msec() - started

## Simulate an OS focus-loss notification on purpose (so it is not reported as unexpected).
func _simulate_focus_loss(notifications: Array) -> void:
	_pause_expected = true
	for what: int in notifications:
		get_tree().notification(what)
	await _frames(2)
	_pause_expected = false

func _near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance

## Wall-clock wait. (SceneTreeTimer can fire up to one frame EARLY after a long frame, which
## made 45 ms waits shorter than the 25 ms debounce. Time.get_ticks_msec() cannot.)
func _wait(seconds: float) -> void:
	await _wait_until(Time.get_ticks_msec() + int(seconds * 1000.0))

func _wait_until(deadline_msec: int) -> void:
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## Free the previous scene and start a clean one. Waits until the entrance has finished.
func _fresh_main(wait_for_ready: bool = true) -> void:
	if main != null:
		main.queue_free()
		await get_tree().process_frame
	get_tree().paused = false
	accepted.clear()
	rejected.clear()
	progress_min = 1000.0
	progress_max = -1000.0
	completed_count = 0
	succeeded_events.clear()
	main = load(MAIN_SCENE).instantiate()
	add_child(main)
	input = main.get_node("InputController")
	extraction = main.get_node("ExtractionManager")
	timers = main.get_node("TimerManager")
	sword = main.get_node("Stage/Sword")
	input.tap_accepted.connect(func(side: TapSide.Side) -> void: accepted.append(side))
	input.tap_rejected.connect(func(side: TapSide.Side) -> void: rejected.append(side))
	extraction.progress_changed.connect(func(value: float) -> void:
		progress_min = minf(progress_min, value)
		progress_max = maxf(progress_max, value))
	extraction.extraction_completed.connect(func() -> void: completed_count += 1)
	if not GameManager.extraction_succeeded.is_connected(_on_succeeded):
		GameManager.extraction_succeeded.connect(_on_succeeded)
	if wait_for_ready:
		await _wait_for_state(GameManager.State.READY, 5.0)
		if GameManager.state == GameManager.State.PAUSED:
			print("   [recover] resuming a game paused by real focus loss")
			get_window().grab_focus()
			_touch(LEFT_X)  # the normal tap-to-resume path
			await _frames(3)
			await _wait_for_state(GameManager.State.READY, 5.0)
		print("   [diag] fresh scene ready: state=%d input.enabled=%s extraction.active=%s window=%s" % [GameManager.state, input.enabled, extraction._active, get_window().size])

func _on_succeeded(level: int, level_time: float) -> void:
	succeeded_events.append(Vector2(level, level_time))

func _wait_for_state(state: GameManager.State, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while GameManager.state != state and Time.get_ticks_msec() < deadline:
		if GameManager.state == GameManager.State.PAUSED and state != GameManager.State.PAUSED and not _pause_expected:
			break  # real focus loss paused the game; let the caller recover
		await get_tree().process_frame
	return GameManager.state == state

## Convert a point in base-viewport coordinates (0..1080 x 0..1920) to window coordinates,
## which is what a real device / OS hands to the engine.
func _to_window(viewport_point: Vector2) -> Vector2:
	return get_viewport().get_screen_transform() * viewport_point

func _touch(x: float, index: int = 0, pressed: bool = true, y: float = 1500.0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = _to_window(Vector2(x, y))
	Input.parse_input_event(event)

func _mouse(button: MouseButton, x: float, pressed: bool = true, y: float = 1500.0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = _to_window(Vector2(x, y))
	event.global_position = event.position
	Input.parse_input_event(event)

## Width-relative x positions in base-viewport space (the zone split is at half the VISIBLE width).
var LEFT_X: float:
	get: return get_viewport().get_visible_rect().size.x * 0.25
var RIGHT_X: float:
	get: return get_viewport().get_visible_rect().size.x * 0.75
var HALF_X: float:
	get: return get_viewport().get_visible_rect().size.x * 0.5

## Tap the side the controller expects next (LEFT first), via a real touch event.
func _tap_expected() -> void:
	var next := input.expected_side()
	_touch(RIGHT_X if next == SIDE_RIGHT else LEFT_X)

## Alternate real touches (35 ms apart, above the 25 ms debounce) until the state leaves the
## play states. Returns the number of taps sent.
func _pump_until_extracted(max_taps: int = 120) -> int:
	var sent := 0
	while GameManager.is_input_allowed() and sent < max_taps:
		_tap_expected()
		sent += 1
		await _wait(0.035)
	return sent

# ======================================================================================
# 1. INPUT PIPELINE
# ======================================================================================

func _section_input() -> void:
	print("\n[1] INPUT PIPELINE (simulated events through Input.parse_input_event)")
	await _fresh_main()

	print(" - setup / calibration")
	var base_size := get_viewport().get_visible_rect().size
	print("   visible rect: ", base_size, "  window size: ", get_window().size,
		"  window pos of viewport x=540: ", _to_window(Vector2(540, 1500)))
	_check(not ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch"),
		"emulate_mouse_from_touch is OFF (no duplicate mouse event per touch)")
	_check(not ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse"),
		"emulate_touch_from_mouse is OFF (no duplicate touch event per click)")
	_check(input.enabled, "input enabled in READY state")

	print(" - left mouse click")
	_mouse(MOUSE_BUTTON_LEFT, LEFT_X)
	await _wait(0.06)
	_check(accepted == [SIDE_LEFT], "left click on LEFT half accepted as LEFT")
	_mouse(MOUSE_BUTTON_LEFT, LEFT_X, false)  # release
	await _wait(0.03)
	_check(accepted.size() == 1 and rejected.is_empty(), "mouse button release ignored (no extra tap)")
	_mouse(MOUSE_BUTTON_LEFT, RIGHT_X)
	await _wait(0.06)
	_check(accepted == [SIDE_LEFT, SIDE_RIGHT], "left click on RIGHT half accepted as RIGHT (alternation)")

	print(" - non-left mouse buttons / other events are ignored")
	var count_before := accepted.size()
	var progress_before := extraction.progress
	_mouse(MOUSE_BUTTON_RIGHT, LEFT_X)
	_mouse(MOUSE_BUTTON_MIDDLE, LEFT_X)
	_mouse(MOUSE_BUTTON_WHEEL_UP, LEFT_X)
	_mouse(MOUSE_BUTTON_WHEEL_DOWN, LEFT_X)
	var motion := InputEventMouseMotion.new()
	motion.position = _to_window(Vector2(LEFT_X, 1500))
	Input.parse_input_event(motion)
	var drag := InputEventScreenDrag.new()
	drag.position = _to_window(Vector2(LEFT_X, 1500))
	Input.parse_input_event(drag)
	await _wait(0.06)
	_check(accepted.size() == count_before and rejected.is_empty(),
		"right/middle click, wheel, mouse motion, screen drag produce no taps at all")
	_check(_near(extraction.progress, progress_before, 0.5), "ignored events do not move progress")

	print(" - screen touch")
	await _fresh_main()
	_touch(LEFT_X)
	await _wait(0.06)
	_check(accepted == [SIDE_LEFT], "InputEventScreenTouch press on left accepted")
	_touch(LEFT_X, 0, false)
	await _wait(0.03)
	_check(accepted.size() == 1 and rejected.is_empty(), "touch release ignored")
	_touch(RIGHT_X)
	await _wait(0.06)
	_check(accepted == [SIDE_LEFT, SIDE_RIGHT], "touch on right accepted, alternates")

	print(" - same-side rejection")
	_touch(RIGHT_X)
	await _wait(0.06)
	_check(accepted.size() == 2 and rejected == [SIDE_RIGHT], "second consecutive RIGHT touch rejected")
	var progress_after_reject := extraction.progress
	_mouse(MOUSE_BUTTON_LEFT, RIGHT_X)
	await _wait(0.06)
	_check(accepted.size() == 2 and rejected.size() == 2, "same-side rejection also applies to mouse clicks")
	_check(_near(extraction.progress, progress_after_reject, 0.01), "rejected taps never change progress")
	_touch(LEFT_X)
	await _wait(0.06)
	_check(accepted.size() == 3 and accepted[2] == SIDE_LEFT, "alternation resumes normally after rejections")

	print(" - debounce")
	await _fresh_main()
	var pair_ms := _touch_pair(LEFT_X, 0, RIGHT_X, 0)  # same frame, opposite side
	await _wait(0.06)
	var debounce_label := "opposite-side tap <25 ms after an accepted tap is rejected as double registration"
	if pair_ms >= input.min_tap_interval_msec:
		_inconclusive(debounce_label, "pair took %d ms to deliver on this machine" % pair_ms)
		await _fresh_main()
		_touch(LEFT_X)
		await _wait(0.06)
	else:
		_check(accepted == [SIDE_LEFT] and rejected == [SIDE_RIGHT], debounce_label)
	_touch(RIGHT_X)
	await _wait(0.06)
	_check(accepted == [SIDE_LEFT, SIDE_RIGHT], "same tap 60 ms later is accepted")

	print(" - debounce window is anchored to the last ACCEPTED tap")
	await _fresh_main()
	input.min_tap_interval_msec = 100
	_touch(LEFT_X)                 # accepted at t=0
	await _wait(0.12)
	_touch(LEFT_X)                 # outside the debounce window, so rejected for being SAME SIDE (t=120 ms)
	_check(rejected == [SIDE_LEFT], "the second LEFT was rejected for being same-side (not by debounce)")
	await _wait(0.06)              # t=180 ms: 180 ms after the accepted tap, only 60 ms after the rejected one
	_touch(RIGHT_X)
	await _wait(0.05)
	_check(accepted == [SIDE_LEFT, SIDE_RIGHT],
		"valid tap 180 ms after the last accepted tap is accepted, even though a rejected tap came 60 ms earlier")

	print(" - multiple simultaneous touches")
	await _fresh_main()
	var multi_ms := _touch_pair(LEFT_X, 0, RIGHT_X, 1)  # two fingers, same frame, opposite sides
	await _wait(0.06)
	var multi_label := "two fingers down in the same instant: exactly one tap counts"
	if multi_ms >= input.min_tap_interval_msec:
		_inconclusive(multi_label, "pair took %d ms to deliver on this machine" % multi_ms)
	else:
		_check(accepted.size() == 1 and rejected.size() == 1, multi_label)
	await _fresh_main()
	var same_side_ms := _touch_pair(LEFT_X, 0, LEFT_X + 40.0, 1)  # two fingers, same side
	await _wait(0.06)
	var same_side_label := "two fingers on the same side: one tap counts"
	if same_side_ms >= input.min_tap_interval_msec:
		_inconclusive(same_side_label, "pair took %d ms to deliver on this machine" % same_side_ms)
	else:
		_check(accepted == [SIDE_LEFT] and rejected == [SIDE_LEFT], same_side_label)
	await _fresh_main()
	_touch(LEFT_X, 0)              # finger 0 stays down (never released)
	await _wait(0.06)
	_touch(RIGHT_X, 1)             # finger 1 taps the other side while finger 0 is held
	await _wait(0.06)
	_touch(LEFT_X, 2)              # third finger
	await _wait(0.06)
	_check(accepted == [SIDE_LEFT, SIDE_RIGHT, SIDE_LEFT],
		"held finger + two more fingers alternating 60 ms apart: all three accepted, in order")

	print(" - boundary between zones (split at half the visible width)")
	await _fresh_main()
	var half := HALF_X
	var width := get_viewport().get_visible_rect().size.x
	var boundary_cases := [[0.0, SIDE_LEFT], [1.0, SIDE_LEFT], [half - 2.0, SIDE_LEFT], [half - 1.0, SIDE_LEFT],
		[half, SIDE_RIGHT], [half + 1.0, SIDE_RIGHT], [half + 2.0, SIDE_RIGHT], [width - 1.0, SIDE_RIGHT]]
	for case in boundary_cases:
		var x: float = case[0]
		var expected_side: int = case[1]
		input.reset_alternation()
		await _wait(0.04)
		var before := accepted.size()
		_touch(x)
		await _wait(0.04)
		var ok := accepted.size() == before + 1 and accepted[accepted.size() - 1] == expected_side
		_check(ok, "touch at x=%d (split at %d) -> %s" % [int(x), int(half), "LEFT" if expected_side == SIDE_LEFT else "RIGHT"])
	input.reset_alternation()
	await _wait(0.04)
	_touch(-20.0)
	await _wait(0.04)
	_check(accepted[accepted.size() - 1] == SIDE_LEFT, "touch left of the screen (x=-20) -> LEFT")
	input.reset_alternation()
	await _wait(0.04)
	_touch(width + 120.0)
	await _wait(0.04)
	_check(accepted[accepted.size() - 1] == SIDE_RIGHT, "touch beyond the right edge (x=width+120) -> RIGHT")

	print(" - viewport.push_input path")
	await _fresh_main()
	var pushed := InputEventScreenTouch.new()
	pushed.pressed = true
	pushed.position = _to_window(Vector2(LEFT_X, 1500))
	get_viewport().push_input(pushed)
	await _wait(0.04)
	_check(accepted == [SIDE_LEFT], "Viewport.push_input(ScreenTouch) reaches InputController")

	print(" - input is locked while a new sword is entering")
	await _fresh_main(false)  # do NOT wait: we are inside the entrance animation
	_check(GameManager.state == GameManager.State.EXTRACTING, "state is EXTRACTING during the entrance")
	_touch(LEFT_X)
	_mouse(MOUSE_BUTTON_LEFT, RIGHT_X)
	await _wait(0.05)
	_check(accepted.is_empty() and rejected.is_empty() and extraction.progress == 0.0,
		"touches during the entrance animation are ignored entirely")
	await _wait_for_state(GameManager.State.READY, 5.0)

# ======================================================================================
# 2. EXTRACTION
# ======================================================================================

func _section_extraction() -> void:
	print("\n[2] EXTRACTION (through the input pipeline)")
	await _fresh_main()
	var expected_progress := 0.0

	print(" - valid taps raise progress")
	var t_last := 0
	for k in 4:  # 1.8: 6.67 % per tap on level 1: 3 progress taps = 20 %, which decays to 0 within the 6.8 s waited below
		_tap_expected()
		t_last = Time.get_ticks_msec()
		await _wait(0.045)
		# 1.6 rule: the FIRST tap only starts the rhythm (0 progress); every later in-rhythm tap adds one gain.
		if k > 0:
			expected_progress += _gain_at(expected_progress)  # 1.9: each tap is worth what the speed curve gives for its measured interval
		_check(_near(extraction.progress, expected_progress, 0.001), "after tap %d progress = %.2f (actual %.3f, accepted=%d rejected=%d)" % [k + 1, expected_progress, extraction.progress, accepted.size(), rejected.size()])

	print(" - invalid taps do nothing")
	var snapshot := extraction.progress
	var last_side := input.last_accepted_side
	_touch(LEFT_X if last_side == SIDE_LEFT else RIGHT_X)  # same side again
	_mouse(MOUSE_BUTTON_RIGHT, LEFT_X)
	_touch(LEFT_X, 0, false)
	await _wait(0.06)
	_check(_near(extraction.progress, snapshot, 0.01), "same-side tap, right click, touch release: progress unchanged")

	print(" - decay after grace period")
	var p0 := extraction.progress
	await _wait_until(t_last + 350)
	_check(_near(extraction.progress, p0, 0.01), "no decay 0.35 s after the last valid tap (grace 0.5 s)")
	await _wait_until(t_last + 1800)
	var elapsed := float(Time.get_ticks_msec() - t_last) / 1000.0
	var expected_loss := extraction.decay_per_second * (elapsed - extraction.decay_grace_seconds)
	var loss := p0 - extraction.progress
	print("   %.2f s after last tap: expected loss ~%.2f, measured %.2f" % [elapsed, expected_loss, loss])
	_check(loss > 0.0 and absf(loss - expected_loss) < 0.6, "decayed at 5%/s after the grace period (within 0.6 points)")

	print(" - progress never negative")
	await _wait(5.0)
	_check(extraction.progress == 0.0, "progress settles at exactly 0")
	_check(progress_min >= 0.0, "minimum progress ever observed >= 0 (min=%.4f)" % progress_min)
	_check(not extraction.is_decaying, "decaying flag cleared at 0")

	print(" - extraction fires exactly once, progress capped at 100")
	await _fresh_main()
	var sent := 0
	for i in 90:  # far more taps than any speed needs, as fast as debounce allows
		_tap_expected()
		sent += 1
		await _wait(0.035)
	_check(completed_count == 1, "extraction_completed emitted exactly once (count=%d, taps sent=%d)" % [completed_count, sent])
	_check(succeeded_events.size() == 1, "extraction_succeeded emitted exactly once (count=%d)" % succeeded_events.size())
	_check(progress_max <= 100.0, "maximum progress ever observed <= 100 (max=%.3f)" % progress_max)
	# Bypass the input layer: call the manager directly after completion.
	for i in 5:
		extraction.register_valid_tap()
	_check(completed_count == 1, "direct register_valid_tap() calls after completion cannot re-trigger extraction")
	await _wait_for_state(GameManager.State.READY, 6.0)
	_check(GameManager.level == 2, "exactly one level gained after the spam (level=%d)" % GameManager.level)

# ======================================================================================
# 3. SWORD
# ======================================================================================

func _section_sword() -> void:
	print("\n[3] SWORD (real scene, real input)")
	await _fresh_main()
	var rest_y := sword._rest_position.y
	var lift := sword.full_lift

	print(" - height follows progress")
	for k in 6:
		_tap_expected()
		await _wait(0.25)
		var expected_y := rest_y + extraction.progress / 100.0 * lift
		_check(_near(sword.position.y, expected_y, 0.004),
			"progress %.0f%% -> sword y %.4f (expected %.4f)" % [extraction.progress, sword.position.y, expected_y])

	print(" - tap feedback")
	await _fresh_main()
	_tap_expected()
	_check(sword._kick == 0.0, "the first tap (rhythm start, no progress) gives no kick")
	await _wait(0.06)
	_tap_expected()
	_check(sword._kick == 1.0, "valid tap sets the full kick impulse immediately")
	await _wait(0.9)  # (1.10: the micro-motion effort fades over ~0.55 s; waiting longer would let this single tap decay into a failure)
	_check(sword._kick == 0.0 and sword._visual.position.length() < 0.001 and sword._visual.rotation.length() < 0.002,
		"kick fully settles; the micro-motion residue is under 1 mm / 0.1 degree (exactly zero follows within about 0.5 s more: see fx_tests)")
	var last := input.last_accepted_side
	_touch(LEFT_X if last == SIDE_LEFT else RIGHT_X)  # rejected same-side tap
	await _frames(2)
	_check(sword._kick == 0.0, "rejected tap gives no sword feedback")
	_tap_expected()  # re-anchor the rhythm (the 0.4 s settle wait above exceeded the allowed tap interval)
	await _wait(0.06)
	var kicks: Array[float] = []
	for k in 4:
		_tap_expected()
		kicks.append(sword._kick)
		await _wait(0.06)
	_check(kicks.all(func(v: float) -> bool: return v == 1.0), "every valid tap produces the same kick (consistent)")

	print(" - decay feedback is smooth")
	await _fresh_main()
	for k in 6:
		_tap_expected()
		await _wait(0.04)
	await _wait(0.6)  # past the grace period -> decaying
	_check(sword._slipping and extraction.is_decaying, "sword enters slipping state when decay starts")
	var samples: Array[float] = []
	var jitter_max := 0.0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 1500:
		await get_tree().process_frame
		samples.append(sword.position.y)
		jitter_max = maxf(jitter_max, absf(sword._visual.position.x))
	var monotonic := true
	var biggest_step := 0.0
	for i in range(1, samples.size()):
		if samples[i] > samples[i - 1] + 0.0001:
			monotonic = false
		biggest_step = maxf(biggest_step, absf(samples[i] - samples[i - 1]))
	print("   %d frames sampled, biggest per-frame step %.5f, max tremble %.5f" % [samples.size(), biggest_step, jitter_max])
	_check(monotonic, "sword height never rises while decaying (no pops)")
	_check(biggest_step < 0.02, "largest per-frame height change while decaying < 0.02")
	_check(jitter_max < 0.01, "slip tremble stays subtle (< 1 cm)")
	_tap_expected()  # after the long pause this is a TOO_SLOW tap: it must NOT stop the slipping
	await _wait(0.06)
	_check(sword._slipping, "a slow (no-progress) tap does not stop the slipping")
	_tap_expected()
	await _wait(0.3)
	_check(not sword._slipping, "slipping state clears after the next valid tap")

	print(" - extraction animation completes and re-embeds the sword")
	await _fresh_main()
	var peak_y := 0.0
	var plants := [0]
	sword.planted.connect(func() -> void: plants[0] += 1)
	var anim_started := Time.get_ticks_msec()
	var pump_done := [false]
	_pump_then_flag(pump_done)
	while not pump_done[0] or GameManager.state != GameManager.State.READY:
		await get_tree().process_frame
		peak_y = maxf(peak_y, sword.position.y)
		if Time.get_ticks_msec() - anim_started > 15000:
			break
	_check(GameManager.state == GameManager.State.READY, "state returns to READY after the animation")
	_check(peak_y >= rest_y + lift + 0.5, "sword was pulled fully clear of the stump (peak %.2f >= %.2f)" % [peak_y, rest_y + lift + 0.5])
	_check(_near(sword.position.y, rest_y, 0.00001) and sword.position.x == 0.0 and sword.position.z == 0.0,
		"sword is back at its embedded rest position")
	_check(sword._visual.position == Vector3.ZERO and sword._visual.rotation == Vector3.ZERO, "visual offsets reset")
	_check(not sword._animating and plants[0] == 1, "animation flags cleared and planted emitted once (%d)" % plants[0])

	print(" - no duplicated / overlapping tweens")
	await _fresh_main()
	await _wait(1.2)  # let the HUD hint tween etc. finish
	var baseline := get_tree().get_processed_tweens().size()
	sword.play_extraction()
	sword.play_extraction()  # second call while the first is running
	sword.play_entrance()    # and an entrance while extraction runs
	var running := get_tree().get_processed_tweens().size() - baseline
	_check(running == 1, "three overlapping play_* calls create exactly one tween (created %d)" % running)
	await _wait(3.0)

func _pump_then_flag(flag: Array) -> void:
	await _pump_until_extracted()
	flag[0] = true

# ======================================================================================
# 4. LEVEL TRANSITIONS (+ timers across levels)
# ======================================================================================

func _section_levels() -> void:
	print("\n[4] LEVEL TRANSITIONS: 6 consecutive extractions via real touch events")
	await _fresh_main()
	var rest_y := sword._rest_position.y
	var session_before := timers.session_seconds()
	var level_times: Array[float] = []
	_check(GameManager.level == 1 and session_before == 0.0, "start: level 1, session timer 0")

	for n in range(1, 7):
		print(" - level %d" % n)
		# ---- preconditions at the start of the level ----
		_check(GameManager.level == n, "level counter == %d" % n)
		_check(extraction.progress == 0.0, "progress reset to 0")
		_check(_near(extraction.gain_per_tap, difficulty_config.peak_gain_for_level(n), 0.0001)
			and _near(extraction.decay_per_second, difficulty_config.decay_for_level(n), 0.0001)
			and _near(extraction.decay_grace_seconds, difficulty_config.grace_for_level(n), 0.0001),
			"difficulty applied: gain %.2f decay %.2f grace %.2f" % [extraction.gain_per_tap, extraction.decay_per_second, extraction.decay_grace_seconds])
		_check(timers.level_seconds() == 0.0, "level timer reset to 0")
		_check(_near(sword.position.y, rest_y, 0.00001) and sword._visual.position == Vector3.ZERO and sword._visual.rotation == Vector3.ZERO,
			"sword at embedded rest pose")
		_check(input.last_accepted_side == TapSide.Side.NONE and input.enabled, "alternation reset, input enabled")
		var session_at_start := timers.session_seconds()
		_check(session_at_start >= session_before, "session timer did not go backwards (%.2f -> %.2f)" % [session_before, session_at_start])
		if n > 1:
			_check(session_at_start > 0.0, "session timer kept running across the transition (%.2f s)" % session_at_start)

		# ---- play the level ----
		var wall_start := Time.get_ticks_msec()
		_tap_expected()
		var first_tap_wall := Time.get_ticks_msec()
		await _wait(0.06)
		_check(timers.level_seconds() > 0.0 and timers.level_seconds() < 0.3, "level timer started on the first tap (%.3f s)" % timers.level_seconds())
		await _pump_until_extracted()
		var completion_wall := Time.get_ticks_msec()
		_check(GameManager.state == GameManager.State.EXTRACTING, "state EXTRACTING right after completion")
		if succeeded_events.size() < n:
			_check(false, "level %d never completed - aborting the level loop" % n)
			return
		var level_time_a := timers.level_seconds()
		await _wait(0.4)
		var level_time_b := timers.level_seconds()
		_check(_near(level_time_a, level_time_b, 0.0005), "level timer stopped at extraction (%.3f == %.3f)" % [level_time_a, level_time_b])
		_check(succeeded_events.size() == n and int(succeeded_events[n - 1].x) == n, "extraction_succeeded reported level %d" % n)
		var reported_time := succeeded_events[n - 1].y
		var wall_time := float(completion_wall - first_tap_wall) / 1000.0
		_check(_near(reported_time, wall_time, 0.12), "reported level time %.3f s matches wall clock %.3f s" % [reported_time, wall_time])
		level_times.append(reported_time)
		_check(timers.session_seconds() > session_at_start, "session timer still running during the success animation")
		session_before = timers.session_seconds()
		_check(await _wait_for_state(GameManager.State.READY, 6.0), "next level reached READY")
		wall_start = wall_start  # (kept for readability of the log above)

	_check(GameManager.level == 7, "level counter == 7 after six extractions")
	var sum_of_levels := 0.0
	for t in level_times:
		sum_of_levels += t
	_check(timers.session_seconds() >= sum_of_levels, "session time (%.2f s) >= sum of level times (%.2f s)" % [timers.session_seconds(), sum_of_levels])
	_check(completed_count == 6, "exactly 6 extraction_completed events (got %d)" % completed_count)
	_check(progress_min >= 0.0 and progress_max <= 100.0, "progress stayed within 0..100 for the whole run")
	var gains_decreasing := true
	for n in range(1, 8):
		if difficulty_config.peak_gain_for_level(n + 1) > difficulty_config.peak_gain_for_level(n):
			gains_decreasing = false
	_check(gains_decreasing, "the configured peak gain never increases between levels 1-8")

# ======================================================================================
# 5. TIMERS + PAUSE / RESUME
# ======================================================================================

func _section_timers() -> void:
	print("\n[5] TIMERS, PAUSE AND RESUME")
	await _fresh_main()

	print(" - nothing runs before the first valid tap")
	await _wait(0.3)
	_check(timers.level_seconds() == 0.0 and timers.session_seconds() == 0.0, "both timers at 0 while idle")
	_mouse(MOUSE_BUTTON_RIGHT, LEFT_X)
	_mouse(MOUSE_BUTTON_MIDDLE, RIGHT_X)
	_mouse(MOUSE_BUTTON_LEFT, LEFT_X, false)
	_touch(LEFT_X, 0, false)
	var drag := InputEventScreenDrag.new()
	drag.position = _to_window(Vector2(LEFT_X, 1500))
	Input.parse_input_event(drag)
	await _wait(0.3)
	_check(timers.level_seconds() == 0.0 and timers.session_seconds() == 0.0, "invalid input does not start either timer")
	_check(GameManager.state == GameManager.State.READY, "state still READY after invalid input")

	print(" - first valid tap starts both timers")
	_touch(LEFT_X)
	await _wait(0.3)
	var level_t := timers.level_seconds()
	var session_t := timers.session_seconds()
	_check(level_t >= 0.25 and level_t < 0.45 and _near(level_t, session_t, 0.02),
		"both started together (level %.3f, session %.3f)" % [level_t, session_t])
	_check(GameManager.state == GameManager.State.PLAYING, "state PLAYING after the first tap")

	print(" - pause freezes timers and decay (simulated focus loss)")
	_tap_expected()
	await _wait(0.1)
	var level_pre := timers.level_seconds()
	var session_pre := timers.session_seconds()
	var progress_pre := extraction.progress
	await _simulate_focus_loss([Node.NOTIFICATION_APPLICATION_FOCUS_OUT])
	_check(GameManager.state == GameManager.State.PAUSED and get_tree().paused, "focus-out pauses the game")
	_check(not input.enabled, "input disabled while paused")
	var level_frozen := timers.level_seconds()
	var session_frozen := timers.session_seconds()
	_check(_near(level_frozen, level_pre, 0.1) and _near(session_frozen, session_pre, 0.1), "timer value at pause is sane")
	await _wait(0.8)
	_check(_near(timers.level_seconds(), level_frozen, 0.001) and _near(timers.session_seconds(), session_frozen, 0.001),
		"both timers frozen for 0.8 s of paused real time")
	_check(_near(extraction.progress, progress_pre, 0.001), "progress frozen while paused (no decay)")

	print(" - repeated focus events pause only once")
	await _simulate_focus_loss([Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED])
	_check(GameManager.state == GameManager.State.PAUSED and _near(timers.level_seconds(), level_frozen, 0.001),
		"extra focus-loss notifications do not disturb the paused state or timers")

	print(" - resume (real touch) restores correct timing")
	var accepted_before := accepted.size()
	_touch(RIGHT_X)  # the resume tap
	await _frames(2)
	_check(GameManager.state == GameManager.State.PLAYING and not get_tree().paused, "tap resumes the game to the previous state")
	_check(accepted.size() == accepted_before, "the resume tap is not counted as a gameplay tap")
	_check(_near(extraction.progress, progress_pre, 0.001) or extraction.progress < progress_pre, "resume tap added no progress")
	await _wait(0.3)
	var level_after := timers.level_seconds()
	_check(level_after > level_frozen + 0.2 and level_after < level_frozen + 0.45,
		"level timer continued from the frozen value, excluding the 0.8 s pause (%.3f -> %.3f)" % [level_frozen, level_after])
	_check(timers.session_seconds() > session_frozen + 0.2 and timers.session_seconds() < session_frozen + 0.45,
		"session timer continued from the frozen value")

	print(" - pause before the first tap")
	await _fresh_main()
	await _simulate_focus_loss([Node.NOTIFICATION_APPLICATION_FOCUS_OUT])
	await _wait(0.4)
	_touch(LEFT_X)  # resume
	await _frames(2)
	_check(GameManager.state == GameManager.State.READY, "resume returns to READY (state=%d paused=%s)" % [GameManager.state, get_tree().paused])
	_check(timers.level_seconds() == 0.0 and timers.session_seconds() == 0.0, "timers still 0 (pause did not start them)")
	_tap_expected()
	await _wait(0.2)
	_check(timers.level_seconds() > 0.1, "first valid tap after resume starts the timers")

	print(" - pause during the success animation")
	await _fresh_main()
	var pumped := [false]
	_pump_then_flag(pumped)
	var wait_deadline := Time.get_ticks_msec() + 10000
	while GameManager.state != GameManager.State.EXTRACTING and Time.get_ticks_msec() < wait_deadline:
		await get_tree().process_frame
	_check(GameManager.state == GameManager.State.EXTRACTING, "reached EXTRACTING before pausing")
	await _wait(0.15)
	var y_before := sword.position.y
	var level_before_pause := GameManager.level
	await _simulate_focus_loss([Node.NOTIFICATION_APPLICATION_FOCUS_OUT])
	await _wait(0.5)
	_check(GameManager.state == GameManager.State.PAUSED, "paused during the success animation")
	_check(_near(sword.position.y, y_before, 0.05) and GameManager.level == level_before_pause,
		"sword animation and level progression are frozen while paused")
	_touch(LEFT_X)  # resume
	_check(await _wait_for_state(GameManager.State.READY, 8.0), "animation resumes and the next level starts")
	_check(GameManager.level == level_before_pause + 1, "level advanced exactly once")
	_check(_near(sword.position.y, sword._rest_position.y, 0.00001), "sword re-embedded after a paused-then-resumed animation")
	_check(extraction.progress == 0.0 and timers.level_seconds() == 0.0, "progress and level timer reset")

## 1.9: a tap is worth what the speed-response curve says for the interval the InputController measured (and the resistance
## at the height it arrives at). This is the independent expectation the tests compare the real progress against.
func _gain_at(progress_before: float) -> float:
	return SpeedGain.gain(input.last_interval_msec, extraction.gain_per_tap, extraction.optimal_interval_msec,
		extraction.useful_interval_msec, extraction.gain_exponent) * (1.0 - extraction.resistance * progress_before / 100.0)
