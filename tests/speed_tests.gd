extends Node
## Speed-based extraction tests (Milestone 1.9): the real main.tscn is played by a scripted "tapper" that alternates at exact
## wall-clock intervals (very fast, fast, normal, slow, same-side, irregular, stopping midway, levels 1-10).
##
## Run (best headless, so the clock is not tied to the display refresh):
##   godot --headless --path . res://tests/speed_tests.tscn
## SIMULATED INPUT ONLY: taps are injected with InputController.handle_tap. This is neither the Android touchscreen nor a person.
## Exit code: 0 = all passed, 1 = failures.

const MAIN_SCENE := "res://scenes/main/main.tscn"

var _checks := 0
var _failures := 0
var main: Node
var input: InputController
var extraction: ExtractionManager
var timers: TimerManager
var config: DifficultyConfig

var _completed := false
var _completed_wall := 0
var _level_seconds := -1.0
var _max_progress := 0.0
var _failed := false
var _progress_after_first := 0.0

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(540, 960)
	config = load("res://resources/difficulty/default_difficulty.tres")
	await _frames(3)
	await _t_speeds()
	await _t_slow_and_invalid()
	await _t_irregular_and_stop()
	await _t_levels()
	print("\n==== %d checks, %d failed ====" % [_checks, _failures])
	print("RESULT: ALL PASSED" if _failures == 0 else "RESULT: FAILURES")
	get_tree().quit(0 if _failures == 0 else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

# ---- Scene and tapper -------------------------------------------------------------------------

func _fresh(level: int = 1) -> void:
	if main != null:
		main.queue_free()
		await get_tree().process_frame
	get_tree().paused = false
	main = load(MAIN_SCENE).instantiate()
	add_child(main)
	input = main.get_node("InputController")
	extraction = main.get_node("ExtractionManager")
	timers = main.get_node("TimerManager")
	_completed = false
	_failed = false
	_level_seconds = -1.0
	_max_progress = 0.0
	extraction.progress_changed.connect(func(p: float) -> void: _max_progress = maxf(_max_progress, p))
	extraction.extraction_completed.connect(func() -> void:
		_completed = true
		_completed_wall = Time.get_ticks_msec())
	main.level_completed.connect(func(_l: int, seconds: float, _t: int, _i: float) -> void: _level_seconds = seconds)
	GameManager.run_failed.connect(func(_r: RunResult) -> void: _failed = true, CONNECT_ONE_SHOT)
	while GameManager.state != GameManager.State.READY:
		await get_tree().process_frame
	if level > 1:
		GameManager.level = level
		main.get_node("DifficultyManager").apply_for_level(level)
	await _wait(0.1)

## Alternating taps at intervals taken from `interval_for(tap_index)` (ms) until the level completes, the run fails or
## `max_seconds` pass. Returns {completed, failed, first_wall, wall (to completion), taps (all taps sent), progress}.
func _tap(interval_for: Callable, max_seconds: float) -> Dictionary:
	var side := TapSide.Side.LEFT
	var first_wall := Time.get_ticks_msec()
	var next := first_wall
	var sent := 0
	var deadline := first_wall + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and not _completed and not _failed:
		if Time.get_ticks_msec() >= next:
			input.handle_tap(side)
			side = TapSide.Side.RIGHT if side == TapSide.Side.LEFT else TapSide.Side.LEFT
			sent += 1
			next += int(interval_for.call(sent))
		await get_tree().process_frame
	return {"completed": _completed, "failed": _failed, "first_wall": first_wall, "taps": sent,
		"wall": float(_completed_wall - first_wall) / 1000.0 if _completed else -1.0}

func _steady(ms: float) -> Callable:
	return func(_i: int) -> float: return ms

# ---- 1. very fast, fast, normal: faster tapping extracts faster; no fixed tap count -------------

func _t_speeds() -> void:
	print("\n[1] STEADY ALTERNATING TAPPING AT DIFFERENT SPEEDS (level 1)")
	var speeds := {"very fast 8 taps/s (125 ms)": 125.0, "fast 6.7 taps/s (150 ms)": 150.0, "fast 5.9 taps/s (170 ms)": 170.0,
		"normal 5 taps/s (200 ms)": 200.0, "steady 4.3 taps/s (230 ms)": 230.0}
	var times: Array[float] = []
	var taps: Array[int] = []
	for label in speeds:
		var interval: float = speeds[label]
		await _fresh()
		var r := await _tap(_steady(interval), 40.0)
		var predicted := config.simulate_extraction_seconds(1, interval)
		print("   %-30s extraction %.2f s (predicted %.2f s), %d taps" % [label, r["wall"], predicted, r["taps"]])
		_check(r["completed"] and not r["failed"], "%s: the sword is extracted" % label)
		_check(absf(r["wall"] - predicted) <= 0.25, "%s: extraction time %.2f s matches the speed-response model (%.2f s)" % [label, r["wall"], predicted])
		_check(absf(_level_seconds - r["wall"]) < 0.1, "%s: the reported extraction time %.2f s equals the measured %.2f s (first tap to 100 %%)" % [label, _level_seconds, r["wall"]])
		_check(_max_progress <= 100.0, "%s: progress never exceeded 100 %% (%.4f)" % [label, _max_progress])
		times.append(r["wall"])
		taps.append(r["taps"])
	var faster_is_faster := true
	for i in range(1, times.size()):
		if times[i] <= times[i - 1]:
			faster_is_faster = false
	_check(faster_is_faster, "every step down in tapping speed makes the extraction take longer (%s s)" % [times.map(func(t: float) -> String: return "%.1f" % t)])
	_check(float(taps[taps.size() - 1]) > 1.6 * float(taps[0]), "the number of taps depends on the speed (%d at 8/s vs %d at 4.3/s): there is no fixed tap count" % [taps[0], taps[taps.size() - 1]])
	# Unrealistic speed: no extra reward below the optimal interval.
	await _fresh()
	var r60 := await _tap(_steady(60.0), 40.0)
	await _fresh()
	var r130 := await _tap(_steady(130.0), 40.0)
	_check(r60["completed"] and r130["completed"] and r60["wall"] >= r130["wall"] * 0.9, "tapping at an impossible 16 taps/s (60 ms) is not faster than the optimal 7.7 taps/s (%.2f s vs %.2f s)" % [r60["wall"], r130["wall"]])

# ---- 2. slow, same side, too slow ---------------------------------------------------------------

func _t_slow_and_invalid() -> void:
	print("\n[2] SLOW TAPPING, TOO-SLOW TAPS AND SAME-SIDE TAPS DO NOT PROGRESS")
	await _fresh()
	var r := await _tap(_steady(335.0), 6.0)  # alternating, inside the allowed gap (400 ms) but slower than the useful speed
	_check(not r["completed"] and _max_progress == 0.0 and r["failed"], "alternating at 3 taps/s (335 ms): no progress at all (max %.2f %%), and the stalled attempt fails" % _max_progress)
	await _fresh()
	r = await _tap(_steady(520.0), 6.0)  # slower than the allowed gap
	_check(not r["completed"] and _max_progress == 0.0, "alternating every 520 ms (too slow): no progress (max %.2f %%)" % _max_progress)
	# Hovering just above the useful speed: tiny gains, decay wins as soon as a single lapse happens.
	await _fresh()
	r = await _tap(_steady(300.0), 8.0)
	_check(not r["completed"], "tapping at 3.3 taps/s for 8 s does not extract level 1 (max %.1f %%)" % _max_progress)
	# Same side only.
	await _fresh()
	var accepted := [0]
	input.tap_accepted.connect(func(_s: TapSide.Side) -> void: accepted[0] += 1)
	input.handle_tap(TapSide.Side.LEFT)  # the first tap of the attempt
	var first_tap := Time.get_ticks_msec()
	for i in 4:
		await _wait(0.03)
		input.handle_tap(TapSide.Side.LEFT)  # same side again and again: rejected
	_check(accepted[0] == 1 and extraction.progress == 0.0, "5 taps on the same side: only the first is accepted, no progress")
	# An alternating tap (inside the stall window) after the rejected repeats still counts, measured from the first tap.
	while Time.get_ticks_msec() - first_tap < 160:
		await get_tree().process_frame
	input.handle_tap(TapSide.Side.RIGHT)
	await _wait(0.05)
	_check(accepted[0] == 2 and extraction.progress > 0.0, "an alternating tap after the rejected repeats still earns progress (%.2f %%, accepted %d, interval %.0f ms)" % [extraction.progress, accepted[0], input.last_interval_msec])

# ---- 3. irregular human rhythm, stopping midway -------------------------------------------------

func _t_irregular_and_stop() -> void:
	print("\n[3] IRREGULAR HUMAN-STYLE RHYTHM AND STOPPING MIDWAY")
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var irregular_times: Array[float] = []
	for trial in 3:
		await _fresh()
		var r := await _tap(func(_i: int) -> float: return rng.randf_range(150.0, 260.0), 40.0)
		irregular_times.append(r["wall"])
		_check(r["completed"] and _max_progress <= 100.0, "irregular rhythm (150-260 ms), trial %d: extracted in %.2f s" % [trial + 1, r["wall"]])
	var t150 := config.simulate_extraction_seconds(1, 150.0)
	var t260 := config.simulate_extraction_seconds(1, 260.0)
	var all_between := irregular_times.all(func(t: float) -> bool: return t > t150 - 0.3 and t < t260 + 0.3)
	_check(all_between, "an irregular tapper lands between the steady 150 ms (%.1f s) and 260 ms (%.1f s) results (%s)" % [t150, t260, irregular_times])
	# A steady tapper beats an irregular one with the same average interval (consistency pays): alternate 120/280 ms.
	await _fresh()
	var alt := await _tap(func(i: int) -> float: return 120.0 if i % 2 == 0 else 280.0, 60.0)
	var avg := config.simulate_extraction_seconds(1, 200.0)
	_check(alt["completed"] and alt["wall"] > avg, "a lopsided rhythm (120/280 ms, average 200 ms) is slower than steady 200 ms (%.1f s vs %.1f s): consistency is rewarded" % [alt["wall"], avg])
	# Stopping midway: tap for a while, stop, progress holds during grace, then decays at the level's rate.
	await _fresh()
	var stop_at := Time.get_ticks_msec() + 1500
	var side := TapSide.Side.LEFT
	var next := Time.get_ticks_msec()
	var last_tap := next
	while Time.get_ticks_msec() < stop_at:
		if Time.get_ticks_msec() >= next:
			last_tap = Time.get_ticks_msec()
			input.handle_tap(side)
			side = TapSide.Side.RIGHT if side == TapSide.Side.LEFT else TapSide.Side.LEFT
			next += 170
		await get_tree().process_frame
	var stopped_at := extraction.progress
	var t_stop := last_tap  # the grace period counts from the last valid tap
	_check(stopped_at > 15.0 and stopped_at < 90.0 and not _completed, "after 1.5 s of tapping at 170 ms the bar stands at %.1f %%" % stopped_at)
	await _wait(maxf(0.0, 0.35 - float(Time.get_ticks_msec() - t_stop) / 1000.0))  # 0.35 s after the LAST tap (the grace counts from it; 1.10: measured from the tap, not from the end of the loop, which sat right at the limit)
	_check(absf(extraction.progress - stopped_at) < 0.01, "0.35 s after stopping nothing is lost yet (grace 0.5 s)")
	await _wait(1.15)
	var elapsed := float(Time.get_ticks_msec() - t_stop) / 1000.0
	var expected_loss := config.decay_for_level(1) * (elapsed - config.grace_for_level(1))
	_check(absf((stopped_at - extraction.progress) - expected_loss) < 0.7, "after %.2f s the bar lost %.2f %% (decay 5 %%/s after the grace: expected %.2f %%)" % [elapsed, stopped_at - extraction.progress, expected_loss])
	_check(not _failed, "...and the attempt is still alive while progress is above 0")

# ---- 4. levels 1-10 ---------------------------------------------------------------------------

func _t_levels() -> void:
	print("\n[4] LEVELS 1-10 AT A FIXED SPEED (6.7 taps/s, 150 ms) AND AT THE LIMIT")
	var previous := 0.0
	var slower_each := true
	for level in range(1, 11):
		await _fresh(level)
		var r := await _tap(_steady(150.0), 40.0)
		var predicted := config.simulate_extraction_seconds(level, 150.0)
		_check(r["completed"] and absf(r["wall"] - predicted) <= 0.25 and absf(_level_seconds - r["wall"]) < 0.1,
			"level %d: extracted in %.2f s (model %.2f s, reported %.2f s)" % [level, r["wall"], predicted, _level_seconds])
		if r["wall"] < previous - 0.2:
			slower_each = false
		previous = r["wall"]
	_check(slower_each, "at the same speed a higher level never extracts faster than the one before")
	# At level 10 the same steady 250 ms tapper that finishes level 1 can no longer finish in a reasonable time.
	await _fresh(1)
	var easy := await _tap(_steady(250.0), 40.0)
	_check(easy["completed"], "level 1 can be extracted at 4 taps/s (%.1f s)" % easy["wall"])
	await _fresh(10)
	var hard := await _tap(_steady(250.0), 12.0)
	_check(not hard["completed"], "level 10 needs more than 4 taps/s: not finished in 12 s at that speed (max %.0f %%)" % _max_progress)
