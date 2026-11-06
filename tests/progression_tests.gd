extends Node
## Milestone 1.20 content and progression audit. The game has no fixed level list: every level comes from the DifficultyConfig curves, so
## "every level works" means "every level's numbers are sane, ordered and reachable". Also audits the real loop (level counter, extraction
## count, failure -> retry reset, stale state on entry) and that opening and closing the game scene repeatedly never piles up connections
## on the GameManager autoload. Run headless:   godot --headless --path . res://tests/progression_tests.tscn
## SIMULATED INPUT ONLY (InputController.handle_tap). Exit code 0 = all passed.

const MAIN_SCENE := "res://scenes/main/main.tscn"

var _checks := 0
var _failures := 0
var config: DifficultyConfig
var main: Node
var input: InputController
var extraction: ExtractionManager
var timers: TimerManager
var _completed := false
var _level_changes := 0
var _success_signals := 0

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
	_t_numeric_audit()
	await _t_real_loop()
	await _t_stale_state()
	await _t_signal_connections()
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

# ---- 1. numeric audit of every level -----------------------------------------------------------------

func _t_numeric_audit() -> void:
	print("\n[1] DIFFICULTY CURVES, LEVELS -5 TO 1000")
	var finite := true
	var in_range := true
	var ordered := true
	var reachable := true
	var worst_reach := 0.0
	var bad_label := ""
	for level in range(-5, 1001):
		var peak := config.peak_gain_for_level(level)
		var useful := config.min_useful_interval_for_level(level)
		var gap := config.max_interval_for_level(level)
		var resistance := config.resistance_for_level(level)
		var decay := config.decay_for_level(level)
		var grace := config.grace_for_level(level)
		for value in [peak, useful, gap, resistance, decay, grace]:
			if is_nan(value) or is_inf(value):
				finite = false
				bad_label = "level %d" % level
		if peak <= 0.0 or useful <= config.optimal_interval_msec or gap <= useful or resistance < 0.0 or resistance > 0.9 or decay < 0.0 or grace <= 0.0:
			in_range = false
			bad_label = "level %d" % level
		if level >= 1:
			var prev := level - 1
			if prev >= 1:
				if config.peak_gain_for_level(level) > config.peak_gain_for_level(prev) + 1e-6 \
						or config.min_useful_interval_for_level(level) > config.min_useful_interval_for_level(prev) + 1e-6 \
						or config.max_interval_for_level(level) > config.max_interval_for_level(prev) + 1e-6 \
						or config.resistance_for_level(level) < config.resistance_for_level(prev) - 1e-6 \
						or config.decay_for_level(level) < config.decay_for_level(prev) - 1e-6 \
						or config.grace_for_level(level) > config.grace_for_level(prev) + 1e-6:
					ordered = false
					bad_label = "level %d" % level
				for interval in [125.0, 143.0, 167.0]:
					if config.simulate_extraction_seconds(level, interval) < config.simulate_extraction_seconds(prev, interval) - 0.02:
						ordered = false
						bad_label = "level %d at %.0f ms" % [level, interval]
			# A fast, steady, realistic tapper (7 taps/s = 143 ms, 6 taps/s = 167 ms) can always finish, and in a sane time.
			for interval in [143.0, 167.0]:
				var seconds := config.simulate_extraction_seconds(level, interval)
				worst_reach = maxf(worst_reach, seconds if interval == 167.0 else 0.0)
				if is_nan(seconds) or is_inf(seconds) or seconds <= 0.0 or seconds > 30.0:
					reachable = false
					bad_label = "level %d at %.0f ms = %s s" % [level, interval, str(seconds)]
	_check(finite, "every value is finite for levels -5..1000 %s" % bad_label if not finite else "every difficulty value is finite for levels -5..1000")
	_check(in_range, "every value is in range (gain > 0, optimal < useful < gap, resistance 0..0.9, decay >= 0, grace > 0)%s" % [" (" + bad_label + ")" if not in_range else ""])
	_check(ordered, "difficulty never gets easier as the level rises (gain, useful interval, gap, resistance, decay, grace, extraction time)%s" % [" (" + bad_label + ")" if not ordered else ""])
	_check(reachable, "a 6-7 taps/s steady player can finish EVERY level from 1 to 1000, slowest %.1f s at 6 taps/s%s" % [worst_reach, " (" + bad_label + ")" if not reachable else ""])
	# Beyond the ramps the curves have converged. They are exponential saturations (1 - e^-((level-1)/ramp), ramps of 12-14 levels), so they are
	# never exactly flat: at level 65 about 1 % of the climb remains. What matters is that there is no jump and no drift at high levels.
	var converged := true
	var worst := ""
	for level in range(100, 1000):
		var d_peak := absf(config.peak_gain_for_level(level) - config.peak_gain_for_level(999))
		var d_gap := absf(config.max_interval_for_level(level) - config.max_interval_for_level(999))
		var d_time := absf(config.simulate_extraction_seconds(level, 167.0) - config.simulate_extraction_seconds(999, 167.0))
		if d_peak > 0.03 or d_gap > 1.0 or d_time > 0.2:
			converged = false
			worst = "level %d: peak %.3f, gap %.2f ms, time %.2f s" % [level, d_peak, d_gap, d_time]
	_check(converged, "from level 100 on every value has converged (peak within 0.03 %%, gap within 1 ms, extraction time within 0.2 s of level 999; under 0.1 %% of the climb remains)%s" % [" (" + worst + ")" if not converged else ""])
	var smooth := true
	for level in range(1, 1000):
		if absf(config.simulate_extraction_seconds(level + 1, 167.0) - config.simulate_extraction_seconds(level, 167.0)) > 1.0:
			smooth = false
	_check(smooth, "no level-to-level jump: extraction time at 6 taps/s never changes by more than 1 s between neighbouring levels")
	_check(is_equal_approx(config.peak_gain_for_level(-5), config.peak_gain_for_level(1)) and is_equal_approx(config.max_interval_for_level(0), config.max_interval_for_level(1)), "levels 0 and below behave exactly like level 1")

# ---- 2. the real loop: levels, extraction count, failure, retry --------------------------------------

func _fresh() -> void:
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
	extraction.extraction_completed.connect(func() -> void: _completed = true)
	while GameManager.state != GameManager.State.READY:
		await get_tree().process_frame
	await _wait(0.1)

func _tap_until_complete(interval_ms: float, max_seconds: float) -> void:
	_completed = false
	var side := TapSide.Side.LEFT
	var next := Time.get_ticks_msec()
	var deadline := next + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and not _completed and GameManager.state != GameManager.State.FAILED:
		if Time.get_ticks_msec() >= next:
			input.handle_tap(side)
			side = TapSide.Side.RIGHT if side == TapSide.Side.LEFT else TapSide.Side.LEFT
			next += int(interval_ms)
		await get_tree().process_frame

func _t_real_loop() -> void:
	print("\n[2] THE REAL LOOP: LEVELS, COUNTS, FAILURE, RETRY")
	GameManager.level_changed.connect(func(_l: int) -> void: _level_changes += 1)
	GameManager.extraction_succeeded.connect(func(_l: int, _t: float) -> void: _success_signals += 1)
	await _fresh()
	_check(GameManager.level == 1 and GameManager.run_extractions == 0 and not GameManager.run_over and GameManager.last_result == null, "a new game starts at level 1 with no extractions and no result")
	_level_changes = 0
	_success_signals = 0
	var times: Array[float] = []
	for expected_level in [1, 2, 3]:
		await _tap_until_complete(150.0, 25.0)
		_check(_completed and GameManager.level == expected_level, "level %d completes (the counter still reads %d during the animation)" % [expected_level, GameManager.level])
		times.append(timers.level_seconds())
		var guard := Time.get_ticks_msec() + 9000
		while not (GameManager.level == expected_level + 1 and GameManager.state == GameManager.State.READY) and Time.get_ticks_msec() < guard:
			await get_tree().process_frame
		_check(GameManager.level == expected_level + 1 and GameManager.state == GameManager.State.READY, "...then the game is at level %d, READY" % (expected_level + 1))
		_check(extraction.progress == 0.0 and timers.level_seconds() == 0.0 and not GameManager.run_over, "...with progress 0, the level timer reset and the run not over")
	_check(GameManager.run_extractions == 3 and _success_signals == 3, "three extractions are counted exactly once each (%d / %d signals)" % [GameManager.run_extractions, _success_signals])
	_check(_level_changes == 3, "level_changed fired once per advance (%d times for 3 advances)" % _level_changes)
	var tuned: bool = is_equal_approx(extraction.gain_per_tap, config.peak_gain_for_level(4))
	_check(tuned, "level 4 uses level 4's tuning (peak gain %.2f)" % extraction.gain_per_tap)
	# Fail on level 4, then retry.
	input.handle_tap(TapSide.Side.LEFT)
	await _wait(0.1)
	_check(GameManager.state == GameManager.State.PLAYING, "the first tap starts the attempt")
	main._on_progress_depleted()
	var guard2 := Time.get_ticks_msec() + 6000
	while GameManager.state != GameManager.State.FAILED and Time.get_ticks_msec() < guard2:
		await get_tree().process_frame
	await _wait(1.6)
	_check(GameManager.state == GameManager.State.FAILED and GameManager.run_over and GameManager.last_result != null, "the run fails once and keeps its result")
	_check(GameManager.last_result.level_reached == 4 and GameManager.last_result.extractions == 3, "the result says level 4 reached, 3 extractions (%d / %d)" % [GameManager.last_result.level_reached, GameManager.last_result.extractions])
	main._on_progress_depleted()
	_check(GameManager.last_result.level_reached == 4, "a second failure signal changes nothing")
	main._restart_run()
	await _wait(0.5)
	_check(GameManager.level == 1 and GameManager.run_extractions == 0 and not GameManager.run_over and GameManager.last_result == null and GameManager.state == GameManager.State.READY, "TRY AGAIN: level 1, no extractions, not over, no stale result, READY")
	_check(extraction.progress == 0.0 and timers.level_seconds() == 0.0 and timers.session_seconds() == 0.0, "...with progress 0 and both timers at 0")
	_check(is_equal_approx(extraction.gain_per_tap, config.peak_gain_for_level(1)), "...and level 1's tuning is back (peak gain %.2f)" % extraction.gain_per_tap)
	await _tap_until_complete(150.0, 25.0)
	_check(_completed and GameManager.run_extractions == 1, "the retried run can complete level 1 and counts 1 extraction (not 4)")
	await _wait(0.2)

# ---- 3. entering the game with stale state ----------------------------------------------------------

func _t_stale_state() -> void:
	print("\n[3] ENTERING THE GAME WITH STALE STATE (as after leaving a run for the menu)")
	if main != null:
		main.queue_free()
		main = null
		await _frames(3)
	for stale in [GameManager.State.FAILED, GameManager.State.EXTRACTING, GameManager.State.PLAYING]:
		GameManager.level = 9
		GameManager.run_extractions = 8
		GameManager.run_over = true
		GameManager.last_result = RunResult.new()
		GameManager.state = stale
		get_tree().paused = false
		await _fresh()
		_check(GameManager.level == 1 and GameManager.run_extractions == 0 and not GameManager.run_over and GameManager.last_result == null and GameManager.state == GameManager.State.READY,
			"entering from a stale %s state starts a clean run at level 1, READY" % GameManager.State.keys()[stale])
		_check(input.enabled and not get_tree().paused, "...and input is enabled and the tree is not paused")
		main.queue_free()
		main = null
		await _frames(3)

# ---- 4. connections on the autoload do not pile up ----------------------------------------------------

func _t_signal_connections() -> void:
	print("\n[4] OPENING AND CLOSING THE GAME SCENE DOES NOT PILE UP CONNECTIONS")
	var names := ["state_changed", "level_changed", "extraction_succeeded", "run_failed"]
	var base := {}
	for n in names:
		base[n] = Signal(GameManager, n).get_connections().size()
	for i in 4:
		var game: Node = load(MAIN_SCENE).instantiate()
		add_child(game)
		while GameManager.state != GameManager.State.READY:
			await get_tree().process_frame
		await _frames(2)
		game.queue_free()
		await _frames(4)
	var stable := true
	var report := ""
	for n in names:
		var now: int = Signal(GameManager, n).get_connections().size()
		report += "%s %d->%d  " % [n, base[n], now]
		if now > base[n]:
			stable = false
	_check(stable, "after 4 open/close cycles no GameManager signal has gained connections (%s)" % report.strip_edges())
