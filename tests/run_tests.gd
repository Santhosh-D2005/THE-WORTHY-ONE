extends SceneTree
## Headless logic tests. Run:
##   godot --headless --path . -s res://tests/run_tests.gd
## Exits with code 1 if any check fails.

var _failures: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		_failures += 1

func _init() -> void:
	_test_extraction()
	_test_difficulty()
	_test_input()
	_test_timers()
	_test_depletion()
	_test_run_result()
	_test_difficulty_independence()
	_test_presets()
	_test_input_lock()
	_test_rhythm_rule()
	_test_rhythm_extraction()
	_test_rhythm_input()
	_test_rhythm_difficulty()
	_test_progress_design()
	print("\n%s (%d failure(s))" % ["ALL TESTS PASSED" if _failures == 0 else "TESTS FAILED", _failures])
	quit(1 if _failures > 0 else 0)

func _test_extraction() -> void:
	print("ExtractionManager")
	var manager := ExtractionManager.new()
	manager.configure(8.0, 5.0, 0.5)
	manager.reset()
	manager.set_active(true)
	manager.register_valid_tap()
	_check(is_equal_approx(manager.progress, 8.0), "valid tap adds configured gain (8%)")
	# Grace period: no decay before 0.5 s.
	manager._process(0.4)
	_check(is_equal_approx(manager.progress, 8.0), "no decay inside the grace period")
	manager._process(0.2)  # total idle 0.6 s -> decays for the whole 0.2 s frame
	_check(manager.progress < 8.0 and manager.is_decaying, "decay begins after the grace period")
	manager._process(100.0)
	_check(manager.progress == 0.0, "progress never falls below 0")
	var completed := [false]
	manager.extraction_completed.connect(func() -> void: completed[0] = true)
	manager.reset()
	manager.set_active(true)
	for i in 20:
		manager.register_valid_tap()
	_check(manager.progress == 100.0, "progress never exceeds 100")
	_check(completed[0], "extraction_completed emitted at 100%")
	manager.register_valid_tap()
	_check(manager.progress == 100.0, "taps after completion are ignored")
	manager.free()

func _test_difficulty() -> void:
	print("DifficultyConfig (Milestone 1.9: speed-based, no fixed tap count)")
	var config: DifficultyConfig = load("res://resources/difficulty/default_difficulty.tres")
	_check(is_equal_approx(config.peak_gain_for_level(1), 6.0) and is_equal_approx(config.max_interval_for_level(1), 400.0), "level 1: peak gain 6 %, longest allowed gap 400 ms")
	_check(is_equal_approx(config.decay_for_level(1), 5.0), "level 1 decay = 5")
	_check(is_equal_approx(config.grace_for_level(1), 0.5), "level 1 grace = 0.5")
	var monotonic := true
	for level in range(1, 200):
		# Difficulty only ever rises: the useful window of speeds shrinks, resistance and decay rise and the peak gain falls.
		if config.peak_gain_for_level(level + 1) > config.peak_gain_for_level(level) + 0.0001:
			monotonic = false
		if config.decay_for_level(level + 1) < config.decay_for_level(level) - 0.0001:
			monotonic = false
		if config.min_useful_interval_for_level(level + 1) > config.min_useful_interval_for_level(level) + 0.0001:
			monotonic = false
		if config.resistance_for_level(level + 1) < config.resistance_for_level(level) - 0.0001:
			monotonic = false
	_check(monotonic, "difficulty never eases as levels rise (peak gain never rises, useful interval never grows, resistance and decay never fall)")
	_check(config.peak_gain_for_level(1000) >= config.end_peak_gain - 0.01, "the peak gain stays at/above its floor")
	_check(config.decay_for_level(1000) <= config.end_decay_per_second + 0.01, "decay stays at/below the cap")

func _test_input() -> void:
	print("InputController")
	var controller := InputController.new()
	controller.min_tap_interval_msec = 0
	var accepted := [0]
	var rejected := [0]
	controller.tap_accepted.connect(func(_side: TapSide.Side) -> void: accepted[0] += 1)
	controller.tap_rejected.connect(func(_side: TapSide.Side) -> void: rejected[0] += 1)
	controller.handle_tap(TapSide.Side.LEFT)
	controller.handle_tap(TapSide.Side.LEFT)
	controller.handle_tap(TapSide.Side.RIGHT)
	controller.handle_tap(TapSide.Side.RIGHT)
	controller.handle_tap(TapSide.Side.LEFT)
	_check(accepted[0] == 3, "L, L, R, R, L accepts 3 alternating taps")
	_check(rejected[0] == 2, "repeated same-side taps rejected")
	controller.min_tap_interval_msec = 100000
	controller.reset_alternation()
	controller._last_tap_msec = -1000000
	controller.handle_tap(TapSide.Side.LEFT)
	controller.handle_tap(TapSide.Side.RIGHT)  # inside debounce window
	_check(accepted[0] == 4 and rejected[0] == 3, "second tap inside debounce window rejected")
	controller.free()

func _test_timers() -> void:
	print("TimerManager")
	var timers := TimerManager.new()
	_check(timers.level_seconds() == 0.0, "timers idle at 0 before first input")
	timers.notify_valid_input()
	OS.delay_msec(60)
	var running := timers.level_seconds()
	_check(running >= 0.05, "level timer runs after first valid input")
	timers.pause()
	var frozen := timers.level_seconds()
	OS.delay_msec(60)
	_check(is_equal_approx(timers.level_seconds(), frozen), "timer frozen while paused")
	timers.resume()
	OS.delay_msec(30)
	_check(timers.level_seconds() > frozen, "timer continues after resume")
	var level_time := timers.stop_level()
	timers.reset_level()
	_check(timers.level_seconds() == 0.0 and timers.session_seconds() >= level_time, "level resets; session keeps running")
	timers.free()

func _test_depletion() -> void:
	print("ExtractionManager.progress_depleted (Milestone 1.2)")
	var manager := ExtractionManager.new()
	manager.configure(8.0, 5.0, 0.5)
	manager.reset()
	manager.set_active(true)
	var depleted := [0]
	manager.progress_depleted.connect(func() -> void: depleted[0] += 1)
	manager._process(100.0)
	_check(depleted[0] == 0 and manager.progress == 0.0, "idle at 0% before the first tap never depletes")
	manager.register_valid_tap()
	manager._process(0.3)
	_check(depleted[0] == 0, "no depletion while progress is above 0")
	manager._process(0.3)   # 0.6 s idle: decay begins
	manager._process(1.0)   # 8 - 5 = 3 left
	_check(depleted[0] == 0 and manager.progress > 0.0, "still above 0 mid-decay")
	manager._process(1.0)   # reaches 0
	_check(depleted[0] == 1 and manager.progress == 0.0, "emits exactly when progress reaches 0")
	manager._process(5.0)
	manager._process(5.0)
	_check(depleted[0] == 1, "emits at most once per attempt")
	manager.reset()
	manager.set_active(true)
	manager.register_valid_tap()
	manager._process(0.6)
	manager._process(10.0)
	_check(depleted[0] == 2, "emits again for a new attempt after reset()")
	manager.reset()
	manager.set_active(true)
	manager.register_valid_tap()
	manager.set_active(false)
	manager._process(100.0)
	_check(depleted[0] == 2 and manager.progress == 8.0, "an inactive manager never depletes (progress frozen)")
	manager.free()

func _test_run_result() -> void:
	print("RunResult")
	var result := RunResult.new()
	result.level_reached = 4
	result.session_seconds = 75.5
	result.extractions = 3
	var data := result.to_dictionary()
	_check(data["level_reached"] == 4 and data["extractions"] == 3 and is_equal_approx(data["session_seconds"], 75.5),
		"to_dictionary carries the measured values")
	_check(not data.has("personal_best") and not data.has("lifetime_extractions"), "no invented lifetime statistics")
	_check(RunResult.format_time(0.0) == "0:00.00" and RunResult.format_time(75.5) == "1:15.50" and RunResult.format_time(5.04) == "0:05.04",
		"format_time matches the HUD format")

func _default_config() -> DifficultyConfig:
	return load("res://resources/difficulty/default_difficulty.tres")

func _test_difficulty_independence() -> void:
	print("Difficulty: the parameters are independent (1.3, extended in 1.7)")
	var base := _default_config()
	# Decay and grace are exactly the shipped curves from Milestone 1.3 (they must not get more aggressive).
	_check(is_equal_approx(base.decay_for_level(1), 5.0) and is_equal_approx(base.grace_for_level(1), 0.5),
		"default level-1 decay / grace unchanged (5 / 0.5)")
	_check(is_equal_approx(base.end_decay_per_second, 16.0) and is_equal_approx(base.end_decay_grace_seconds, 0.2) and is_equal_approx(base.ramp_levels, 7.0),
		"default asymptotes and ramp (1.25: 16 / 0.2, ramp 7, so levels 2-5 are clearly harder)")
	var levels := [1, 2, 5, 12, 30, 200]
	for which in ["peak", "resistance", "interval", "decay", "grace"]:
		var changed: DifficultyConfig = base.duplicate()
		match which:
			"peak":
				changed.start_peak_gain = 9.0
				changed.end_peak_gain = 7.0
			"resistance":
				changed.start_resistance = 0.2
				changed.end_resistance = 0.7
			"interval":
				changed.start_max_tap_interval_msec = 600.0
				changed.end_max_tap_interval_msec = 300.0
			"decay":
				changed.start_decay_per_second = 2.0
				changed.end_decay_per_second = 6.0
			"grace":
				changed.start_decay_grace_seconds = 1.5
				changed.end_decay_grace_seconds = 1.0
		var values := {
			"peak": func(c: DifficultyConfig, l: int) -> float: return c.peak_gain_for_level(l),
			"resistance": func(c: DifficultyConfig, l: int) -> float: return c.resistance_for_level(l),
			"interval": func(c: DifficultyConfig, l: int) -> float: return c.max_interval_for_level(l),
			"decay": func(c: DifficultyConfig, l: int) -> float: return c.decay_for_level(l),
			"grace": func(c: DifficultyConfig, l: int) -> float: return c.grace_for_level(l),
		}
		var others_same := true
		for level in levels:
			for other in values:
				if other != which and not is_equal_approx(values[other].call(changed, level), values[other].call(base, level)):
					others_same = false
		var target_differs: bool = values[which].call(changed, 1) != values[which].call(base, 1)
		_check(others_same and target_differs, "changing only %s leaves the other four untouched at levels 1-200" % which)
	var fast_decay: DifficultyConfig = base.duplicate()
	fast_decay.decay_ramp_levels = 3.0
	_check(fast_decay.decay_for_level(4) > base.decay_for_level(4) + 0.5
		and is_equal_approx(fast_decay.peak_gain_for_level(4), base.peak_gain_for_level(4))
		and is_equal_approx(fast_decay.grace_for_level(4), base.grace_for_level(4)),
		"decay_ramp_levels speeds up only the decay curve")
	var slow_gain: DifficultyConfig = base.duplicate()
	slow_gain.peak_gain_ramp_levels = 40.0
	_check(slow_gain.peak_gain_for_level(10) > base.peak_gain_for_level(10)
		and is_equal_approx(slow_gain.decay_for_level(10), base.decay_for_level(10))
		and is_equal_approx(slow_gain.max_interval_for_level(10), base.max_interval_for_level(10)),
		"peak_gain_ramp_levels slows only the gain curve")

func _test_presets() -> void:
	print("Playtest presets")
	var base := _default_config()
	var names := ["forgiving", "demanding", "grace_long", "decay_slow", "gain_high"]
	var all_load := true
	var all_sane := true
	for preset_name in names:
		var preset = load("res://resources/difficulty/presets/%s.tres" % preset_name)
		if not preset is DifficultyConfig:
			all_load = false
			continue
		for level in range(1, 201):
			var peak: float = preset.peak_gain_for_level(level)
			var decay: float = preset.decay_for_level(level)
			var grace: float = preset.grace_for_level(level)
			var gap: float = preset.max_interval_for_level(level)
			# Achievable: never faster than 5 taps/s (gap >= 200 ms), a bar that is neither trivial nor endless
			# (20-300 nominal taps, gain <= 5 % per tap), resistance well below "impossible", and a lapse of one
			# second never costs more than 15 % of the bar.
			# 1.8: the whole game is gentler (taps 10-110, gain up to 10 % per tap on level 1).
			# Achievable: the allowed gap never below 200 ms, a useful window of speeds that always exists (useful > optimal),
			# a sane peak gain, resistance well below "impossible". 1.9: no tap count exists any more.
			if gap < 200.0 - 0.001 or preset.min_useful_interval_for_level(level) <= preset.optimal_interval_msec + 20.0 or peak < 1.0 or peak > 12.0 or preset.resistance_for_level(level) > 0.6:
				all_sane = false
			if grace < 0.1 or decay * maxf(0.0, 1.0 - grace) > 15.0:
				all_sane = false
	_check(all_load, "all 5 presets load as DifficultyConfig")
	_check(all_sane, "every preset stays achievable over levels 1-200 (gap >= 200 ms, a useful speed window, peak gain 1-12 %, resistance <= 0.6, lapse cost <= 15 %)")
	var grace_only: DifficultyConfig = load("res://resources/difficulty/presets/grace_long.tres")
	var decay_only: DifficultyConfig = load("res://resources/difficulty/presets/decay_slow.tres")
	var taps_only: DifficultyConfig = load("res://resources/difficulty/presets/gain_high.tres")
	var isolated := true
	for level in [1, 5, 30]:
		if not (is_equal_approx(grace_only.peak_gain_for_level(level), base.peak_gain_for_level(level)) and is_equal_approx(grace_only.decay_for_level(level), base.decay_for_level(level))):
			isolated = false
		if not (is_equal_approx(decay_only.peak_gain_for_level(level), base.peak_gain_for_level(level)) and is_equal_approx(decay_only.grace_for_level(level), base.grace_for_level(level))):
			isolated = false
		if not (is_equal_approx(taps_only.decay_for_level(level), base.decay_for_level(level)) and is_equal_approx(taps_only.grace_for_level(level), base.grace_for_level(level))
				and is_equal_approx(taps_only.max_interval_for_level(level), base.max_interval_for_level(level))):
			isolated = false
	_check(isolated, "grace_long / decay_slow / gain_high each change exactly one parameter")
	_check(grace_only.grace_for_level(1) > base.grace_for_level(1) and decay_only.decay_for_level(1) < base.decay_for_level(1)
		and taps_only.peak_gain_for_level(1) > base.peak_gain_for_level(1), "isolated presets are easier in their own parameter")
	var forgiving: DifficultyConfig = load("res://resources/difficulty/presets/forgiving.tres")
	var demanding: DifficultyConfig = load("res://resources/difficulty/presets/demanding.tres")
	# At the same steady speed (5 taps/s) the forgiving preset extracts fastest and the demanding one slowest.
	_check(forgiving.simulate_extraction_seconds(10, 200.0) < base.simulate_extraction_seconds(10, 200.0)
		and base.simulate_extraction_seconds(10, 200.0) < demanding.simulate_extraction_seconds(10, 200.0),
		"forgiving < default < demanding in extraction time at 5 taps/s on level 10")
	# Selection helpers.
	_check(DifficultyManager.is_valid_preset_name("forgiving") and DifficultyManager.is_valid_preset_name("grace_long2"), "valid preset names accepted")
	_check(not DifficultyManager.is_valid_preset_name("") and not DifficultyManager.is_valid_preset_name("../secret")
		and not DifficultyManager.is_valid_preset_name("Upper") and not DifficultyManager.is_valid_preset_name("a b"), "empty / path-like / uppercase / spaced names rejected")
	_check(DifficultyManager.requested_preset_from_arguments(["--foo", "--difficulty-preset=demanding", "x"]) == "demanding"
		and DifficultyManager.requested_preset_from_arguments(["--foo"]) == "", "preset argument parsed from the command line")
	var manager := DifficultyManager.new()
	manager.config = base
	_check(manager.use_preset("forgiving") and manager.preset_name == "forgiving" and manager.config.start_peak_gain == 7.0,
		"use_preset loads a preset")
	var before := manager.config
	_check(not manager.use_preset("does_not_exist") and manager.config == before, "unknown preset falls back (config kept)")
	_check(not manager.use_preset("../x") and manager.config == before, "invalid name rejected (config kept)")
	manager.free()

func _test_input_lock() -> void:
	print("InputController post-retry lock (Milestone 1.3)")
	var controller := InputController.new()
	controller.min_tap_interval_msec = 0
	var accepted := [0]
	var rejected := [0]
	controller.tap_accepted.connect(func(_side: TapSide.Side) -> void: accepted[0] += 1)
	controller.tap_rejected.connect(func(_side: TapSide.Side) -> void: rejected[0] += 1)
	controller.lock_for(0.15)
	_check(controller.is_locked() and controller.lock_remaining_seconds() > 0.05, "lock_for() locks")
	controller.handle_tap(TapSide.Side.LEFT)
	controller.handle_tap(TapSide.Side.RIGHT)
	_check(accepted[0] == 0 and rejected[0] == 2 and controller.last_accepted_side == TapSide.Side.NONE,
		"taps during the lock are rejected and do not touch alternation")
	OS.delay_msec(60)
	controller.handle_tap(TapSide.Side.LEFT)   # blocked taps must not extend the lock
	_check(accepted[0] == 0, "still locked 60 ms in")
	OS.delay_msec(130)
	_check(not controller.is_locked() and controller.lock_remaining_seconds() == 0.0, "the lock expires by itself")
	controller.handle_tap(TapSide.Side.LEFT)
	controller.handle_tap(TapSide.Side.RIGHT)
	_check(accepted[0] == 2, "normal alternating taps work after the lock (blocked taps did not extend it)")
	controller.lock_for(0.0)
	_check(not controller.is_locked(), "a zero lock does nothing")
	controller.lock_for(0.5)
	controller.lock_for(0.05)
	_check(controller.lock_remaining_seconds() > 0.3, "a shorter lock never shortens a running one")
	controller.clear_lock()
	_check(not controller.is_locked(), "clear_lock() releases it")
	controller.free()

# ---- Milestone 1.6: minimum tapping speed -----------------------------------------------------

func _test_rhythm_rule() -> void:
	print("Tapping-speed rule (TapRhythm)")
	var FIRST := TapKind.Kind.FIRST
	var PROGRESS := TapKind.Kind.PROGRESS
	var SLOW := TapKind.Kind.TOO_SLOW
	_check(TapRhythm.classify(false, -1.0, 400.0) == FIRST, "no previous tap -> FIRST (awards nothing)")
	_check(TapRhythm.classify(false, 5.0, 400.0) == FIRST and TapRhythm.classify(false, 99999.0, 400.0) == FIRST, "FIRST ignores the interval")
	_check(TapRhythm.classify(true, 1.0, 400.0) == PROGRESS and TapRhythm.classify(true, 399.9, 400.0) == PROGRESS, "inside the window -> PROGRESS")
	_check(TapRhythm.classify(true, 400.0, 400.0) == PROGRESS, "exactly on the limit still counts (<=)")
	_check(TapRhythm.classify(true, 400.1, 400.0) == SLOW and TapRhythm.classify(true, 5000.0, 400.0) == SLOW, "beyond the limit -> TOO_SLOW")
	_check(TapRhythm.classify(true, 300.0, 250.0) == SLOW and TapRhythm.classify(true, 300.0, 450.0) == PROGRESS, "the limit is a parameter, not a constant")

func _test_rhythm_extraction() -> void:
	print("Rhythm in ExtractionManager")
	var m := ExtractionManager.new()
	m.configure(8.0, 5.0, 0.5)
	m.zero_progress_extra_seconds = 0.4
	m.reset()
	m.set_active(true)
	var depleted := [0]
	m.progress_depleted.connect(func() -> void: depleted[0] += 1)
	m._process(10.0)
	_check(m.progress == 0.0 and depleted[0] == 0, "before the first tap nothing can fail, however long the wait")
	m.begin_attempt()
	_check(m.progress == 0.0, "the first tap (begin_attempt) awards no progress")
	m._process(0.8)
	_check(depleted[0] == 0, "no failure inside grace + allowed interval (0.8 s < 0.9 s)")
	m._process(0.2)
	_check(depleted[0] == 1 and m.progress == 0.0, "stalled at 0 for grace + interval -> exactly one failure signal")
	m._process(5.0)
	_check(depleted[0] == 1, "the failure signal is never repeated")

	m.reset()
	m.set_active(true)
	m.begin_attempt()
	m._process(0.3)
	m.register_valid_tap()
	_check(is_equal_approx(m.progress, 8.0), "the first in-rhythm tap after begin_attempt awards one gain")
	m._process(0.45)
	m.register_slow_tap()
	_check(is_equal_approx(m.progress, 8.0), "a slow tap awards nothing")
	m._process(0.1)  # 0.55 s after the last PROGRESS tap: past the 0.5 s grace
	_check(m.is_decaying and m.progress < 8.0, "a slow tap does not restart the grace period: decay continues (cannot hold the bar)")
	# Same maths as before 1.6 for decay once it has started.
	var before := m.progress
	m._process(1.0)
	_check(is_equal_approx(before - m.progress, 5.0), "decay rate is unchanged (5 %/s)")

	var legacy := ExtractionManager.new()
	legacy.configure(8.0, 5.0, 0.5)
	legacy.reset()
	legacy.set_active(true)
	legacy._process(10.0)
	_check(legacy.zero_progress_extra_seconds == 0.0 and legacy.progress == 0.0, "extra stall time defaults to 0")

func _tap(controller: InputController, side: TapSide.Side) -> void:
	controller.handle_tap(side)

func _test_rhythm_input() -> void:
	print("Rhythm in InputController (monotonic clock)")
	var c := InputController.new()
	c.enabled = true
	c.max_interval_msec = 400.0
	var accepted := [0]
	var rejected := [0]
	c.tap_accepted.connect(func(_s: TapSide.Side) -> void: accepted[0] += 1)
	c.tap_rejected.connect(func(_s: TapSide.Side) -> void: rejected[0] += 1)
	_tap(c, TapSide.Side.LEFT)
	_check(c.last_kind == TapKind.Kind.FIRST and c.last_interval_msec < 0.0, "first tap is FIRST with no interval")
	OS.delay_msec(60)
	_tap(c, TapSide.Side.RIGHT)
	_check(c.last_kind == TapKind.Kind.PROGRESS and c.last_interval_msec >= 55.0 and c.last_interval_msec < 250.0,
		"alternating tap 60 ms later is PROGRESS (measured %.1f ms)" % c.last_interval_msec)
	OS.delay_msec(10)
	_tap(c, TapSide.Side.RIGHT)  # same side
	_check(rejected[0] == 1 and accepted[0] == 2 and c.last_kind == TapKind.Kind.PROGRESS, "a same-side repeat is rejected and changes nothing")
	OS.delay_msec(500)
	_tap(c, TapSide.Side.LEFT)  # alternating but 570 ms after the last accepted tap
	_check(c.last_kind == TapKind.Kind.TOO_SLOW and c.last_interval_msec > 450.0,
		"alternating tap after 0.5 s is TOO_SLOW, measured from the last ACCEPTED tap, not the rejected one (%.0f ms)" % c.last_interval_msec)
	OS.delay_msec(60)
	_tap(c, TapSide.Side.RIGHT)
	_check(c.last_kind == TapKind.Kind.PROGRESS, "a slow tap re-anchors the rhythm: the next quick tap counts again")
	# Two touches in the same instant (multi-touch or a duplicated event): only one may be accepted.
	OS.delay_msec(60)
	var accepted_before: int = accepted[0]
	_tap(c, TapSide.Side.LEFT)
	_tap(c, TapSide.Side.RIGHT)
	_check(accepted[0] == accepted_before + 1, "two taps in the same instant: exactly one accepted (debounce)")
	c.reset_alternation()
	OS.delay_msec(40)  # clear of the 25 ms double-registration debounce
	_tap(c, TapSide.Side.LEFT)
	_check(c.last_kind == TapKind.Kind.FIRST, "reset_alternation() (new level / retry / resume) makes the next tap FIRST again")
	var legacy := InputController.new()
	legacy.enabled = true
	legacy.rhythm_enabled = false
	_tap(legacy, TapSide.Side.LEFT)
	OS.delay_msec(700)
	_tap(legacy, TapSide.Side.RIGHT)
	_check(legacy.last_kind == TapKind.Kind.PROGRESS, "with rhythm_enabled = false every accepted tap is PROGRESS (old behaviour)")
	c.free()
	legacy.free()

func _test_rhythm_difficulty() -> void:
	print("Rhythm difficulty progression (gap 400 -> 280 ms, Milestone 1.25)")
	var config: DifficultyConfig = load("res://resources/difficulty/default_difficulty.tres")
	var values: Array[float] = []
	for level in range(1, 61):
		values.append(config.max_interval_for_level(level))
	_check(is_equal_approx(values[0], 400.0), "level 1 allows 400 ms between taps (the value players approved in 1.6)")
	var monotonic := true
	var biggest_step := 0.0
	for i in range(1, values.size()):
		if values[i] > values[i - 1] + 0.0001:
			monotonic = false
		biggest_step = maxf(biggest_step, values[i - 1] - values[i])
	_check(monotonic, "the allowed interval never gets longer as levels rise")
	_check(biggest_step < 18.0 and biggest_step > 10.0, "gradual: the biggest single-level tightening is %.1f ms (no jumps)" % biggest_step)
	_check(values[4] > 343.0 and values[4] < 353.0, "level 5 ~348 ms (%.0f)" % values[4])
	_check(values[9] > 308.0 and values[9] < 318.0, "level 10 ~313 ms (%.0f)" % values[9])
	_check(values[19] > 283.0 and values[19] < 293.0, "level 20 ~288 ms (%.0f)" % values[19])
	_check(values[59] >= 280.0 and values[59] < 283.0, "very high levels approach but never pass 280 ms (3.6 taps/s) (%.1f)" % values[59])
	var t10 := 1.0 - exp(-9.0 / 7.0)
	_check(is_equal_approx(config.decay_for_level(10), lerpf(5.0, 16.0, t10)) and is_equal_approx(config.grace_for_level(10), lerpf(0.5, 0.2, t10)),
		"level 10 decay / grace follow the 1.25 curves (ramp 7)")
	var variant := config.duplicate() as DifficultyConfig
	variant.start_max_tap_interval_msec = 600.0
	variant.end_max_tap_interval_msec = 300.0
	_check(is_equal_approx(variant.peak_gain_for_level(7), config.peak_gain_for_level(7)) and is_equal_approx(variant.decay_for_level(7), config.decay_for_level(7))
		and is_equal_approx(variant.grace_for_level(7), config.grace_for_level(7)) and variant.max_interval_for_level(7) > config.max_interval_for_level(7),
		"changing the interval curve leaves the peak gain / decay / grace alone")
	var own_ramp := config.duplicate() as DifficultyConfig
	own_ramp.interval_ramp_levels = 0.0  # follow ramp_levels (12). 1.8: the default ramp is 12 too, so make ramp_levels slower
	own_ramp.ramp_levels = 30.0
	_check(own_ramp.max_interval_for_level(10) > config.max_interval_for_level(10), "interval_ramp_levels = 0 follows ramp_levels (slower climb)")
	var forgiving: DifficultyConfig = load("res://resources/difficulty/presets/forgiving.tres")
	var demanding: DifficultyConfig = load("res://resources/difficulty/presets/demanding.tres")
	_check(forgiving.max_interval_for_level(1) > config.max_interval_for_level(1) and demanding.max_interval_for_level(1) < config.max_interval_for_level(1),
		"forgiving gives more time than default, demanding less")
	var manager := DifficultyManager.new()
	manager.config = config
	var seen: Array[float] = []
	var seen_resistance: Array[float] = []
	manager.rhythm_changed.connect(func(v: float) -> void: seen.append(v))
	manager.resistance_changed.connect(func(v: float) -> void: seen_resistance.append(v))
	manager.apply_for_level(1)
	manager.apply_for_level(6)
	_check(seen.size() == 2 and is_equal_approx(seen[0], config.max_interval_for_level(1)) and is_equal_approx(seen[1], config.max_interval_for_level(6)),
		"DifficultyManager announces the interval for each level it applies")
	_check(seen_resistance.size() == 2 and seen_resistance[0] == 0.0 and is_equal_approx(seen_resistance[1], config.resistance_for_level(6)),
		"...and the extraction resistance")
	manager.free()

func _test_progress_design() -> void:
	print("Speed-based progress (Milestone 1.9): the curve, the resistance, no fixed tap count")
	var config: DifficultyConfig = load("res://resources/difficulty/default_difficulty.tres")
	var peak := config.peak_gain_for_level(1)
	var opt := config.optimal_interval_msec
	var useful := config.min_useful_interval_for_level(1)
	var exp_ := config.gain_curve_exponent
	# The curve itself.
	_check(SpeedGain.gain(useful, peak, opt, useful, exp_) == 0.0 and SpeedGain.gain(useful + 50.0, peak, opt, useful, exp_) == 0.0 and SpeedGain.gain(2000.0, peak, opt, useful, exp_) == 0.0,
		"a tap at or beyond the minimum useful interval (%.0f ms) adds exactly 0" % useful)
	var strictly_falling := true
	var last := 1000.0
	var interval := opt
	while interval < useful:
		var g := SpeedGain.gain(interval, peak, opt, useful, exp_)
		if g > last + 0.000001:
			strictly_falling = false
		last = g
		interval += 5.0
	_check(strictly_falling, "between the optimal and the useful interval a slower tap is always worth less")
	_check(is_equal_approx(SpeedGain.gain(opt, peak, opt, useful, exp_), peak), "at the optimal interval a tap adds the peak gain")
	var rate_ok := true
	var rate_at_optimal := SpeedGain.rate_per_second(opt, peak, opt, useful, exp_)
	for fast in [100.0, 80.0, 60.0, 40.0]:
		if SpeedGain.rate_per_second(fast, peak, opt, useful, exp_) > rate_at_optimal + 0.0001:
			rate_ok = false
	_check(rate_ok, "tapping faster than the optimal interval never raises the progress per second (unrealistic speeds are not rewarded)")
	var rate_monotonic := true
	var previous_rate := -1.0
	for rate in [3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0]:
		var r := SpeedGain.rate_per_second(1000.0 / rate, peak, opt, useful, exp_)
		if r < previous_rate:
			rate_monotonic = false
		previous_rate = r
	_check(rate_monotonic, "progress per second rises with every step up in tapping speed (3 to 7 taps/s)")
	_check(SpeedGain.rate_per_second(1000.0 / 6.0, peak, opt, useful, exp_) > 1.5 * SpeedGain.rate_per_second(1000.0 / 4.0, peak, opt, useful, exp_),
		"faster is worth more than proportionally: 6 taps/s earns over 1.5x the progress per second of 4 taps/s")
	# Steady tappers at different speeds on every level 1-30: faster is always faster, and the slow ones cannot finish.
	var faster_is_faster := true
	var times_differ := true
	for level in range(1, 31):
		var t4 := config.simulate_extraction_seconds(level, 250.0)
		var t5 := config.simulate_extraction_seconds(level, 200.0)
		var t6 := config.simulate_extraction_seconds(level, 1000.0 / 6.0)
		var t7 := config.simulate_extraction_seconds(level, 1000.0 / 7.0)
		if not (t7 > 0.0 and t7 < t6 and t6 < t5 and (t4 < 0.0 or t5 < t4)):
			faster_is_faster = false
		if config.simulate_extraction_taps(level, 200.0) == config.simulate_extraction_taps(level, 1000.0 / 6.0):
			times_differ = false
	_check(faster_is_faster, "levels 1-30: 7 taps/s beats 6, 6 beats 5, 5 beats 4 (extraction time strictly falls as the speed rises)")
	_check(times_differ, "the number of taps a player makes depends on how fast they tap: there is no fixed tap count")
	var never := true
	for level in range(1, 31):
		if config.simulate_extraction_seconds(level, 1000.0 / 2.5) >= 0.0:
			never = false  # 2.5 taps/s is slower than the level-1 useful speed (2.94/s)
	_check(never, "tapping at 2.5 taps/s never extracts on any level 1-30 (slow tapping makes no progress)")
	var gets_harder := true
	for level in range(1, 30):
		if config.simulate_extraction_seconds(level + 1, 200.0) < config.simulate_extraction_seconds(level, 200.0) - 0.0001:
			gets_harder = false
	_check(gets_harder, "at a fixed 5 taps/s every level takes at least as long as the one before (levels 1-30)")
	var easy := config.simulate_extraction_seconds(1, 200.0)
	_check(easy > 4.0 and easy < 9.0, "level 1 at 5 taps/s takes %.1f s: an early game of moderate effort" % easy)
	# The real ExtractionManager reproduces the simulation tap for tap, at an exact speed.
	for level in [1, 5, 10, 30]:
		var m := ExtractionManager.new()
		m.configure(config.peak_gain_for_level(level), config.decay_for_level(level), config.grace_for_level(level))
		m.configure_speed(config.optimal_interval_msec, config.min_useful_interval_for_level(level), config.gain_curve_exponent)
		m.resistance = config.resistance_for_level(level)
		m.reset()
		m.set_active(true)
		var completions := [0]
		m.extraction_completed.connect(func() -> void: completions[0] += 1)
		m.begin_attempt()  # the first tap awards nothing
		var taps := 1
		var rising := true
		var last_progress := 0.0
		while completions[0] == 0 and taps < 3000:
			m.register_valid_tap(200.0)
			taps += 1
			if m.progress < last_progress:
				rising = false
			last_progress = m.progress
		_check(taps == config.simulate_extraction_taps(level, 200.0) and m.progress == 100.0 and completions[0] == 1 and rising,
			"level %d: the manager completes after %d taps at 5 taps/s, exactly as simulated (%d), once, never above 100 %%" % [level, taps, config.simulate_extraction_taps(level, 200.0)])
		m.free()
	# A slower tap is worth less inside the manager as well, and a useless one changes nothing.
	var m2 := ExtractionManager.new()
	m2.configure(6.0, 5.0, 0.5)
	m2.configure_speed(130.0, 340.0, 1.4)
	m2.reset()
	m2.set_active(true)
	m2.register_valid_tap(150.0)
	var fast_gain := m2.progress
	m2.reset()
	m2.set_active(true)
	m2.register_valid_tap(300.0)
	var slow_gain_value := m2.progress
	_check(fast_gain > 3.0 * slow_gain_value and slow_gain_value > 0.0, "a 150 ms tap adds %.2f %%, a 300 ms tap only %.2f %%" % [fast_gain, slow_gain_value])
	m2.reset()
	m2.set_active(true)
	m2._process(0.0)
	m2.register_valid_tap(350.0)
	_check(m2.progress == 0.0 and m2.last_gain == 0.0, "a 350 ms tap (slower than the minimum useful speed) adds nothing")
	m2.free()
	# Resistance: the last stretch needs faster tapping.
	_check(config.resistance_for_level(1) == 0.0 and config.resistance_for_level(5) > 0.0 and config.resistance_for_level(20) > config.resistance_for_level(10)
		and config.resistance_for_level(300) <= config.end_resistance + 0.001, "resistance starts at 0, rises with the level and stays under its cap")
	# The displayed percentage is a whole number that tracks the real progress.
	for level in [1, 4, 10, 30]:
		var m3 := ExtractionManager.new()
		m3.configure(config.peak_gain_for_level(level), 0.0, 5.0)
		m3.configure_speed(config.optimal_interval_msec, config.min_useful_interval_for_level(level), config.gain_curve_exponent)
		m3.resistance = config.resistance_for_level(level)
		m3.reset()
		m3.set_active(true)
		var last_percent := 0
		var biggest_jump := 0
		var consistent := true
		var steps := 0
		while not m3._completed and steps < 3000:
			m3.register_valid_tap(180.0)
			steps += 1
			var shown := ProgressFormat.percent_for(m3.progress)
			biggest_jump = maxi(biggest_jump, shown - last_percent)
			if shown > int(ceil(m3.progress)) or shown < int(floor(m3.progress)) and shown < 100:
				consistent = false
			last_percent = shown
		_check(biggest_jump <= int(ceil(peak)) and consistent and ProgressFormat.percent_for(m3.progress) == 100,
			"level %d: the shown percentage never jumps by more than one tap's gain, equals floor(progress) and reaches 100 only at completion" % level)
		m3.free()
	_check(ProgressFormat.percent_for(0.0) == 0 and ProgressFormat.percent_for(0.99) == 0 and ProgressFormat.percent_for(1.0) == 1 and ProgressFormat.percent_for(99.9) == 99 and ProgressFormat.percent_for(100.0) == 100,
		"ProgressFormat.percent_for: 0 -> 0, 0.99 -> 0, 1 -> 1, 99.9 -> 99 (never rounds up to 100), 100 -> 100")
