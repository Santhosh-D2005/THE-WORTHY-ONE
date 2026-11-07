class_name DifficultyConfig
extends Resource
## All level-scaling tunables in one place. The defaults below ARE the game's hardness for every level in BOTH modes: they are the values that
## were tuned for Ruthless and judged right (ruthless_difficulty.tres holds the same numbers; server/schema.sql min_level_seconds mirrors them).
## Edit resources/difficulty/default_difficulty.tres
## (or the inspector) to rebalance without touching any script.
##
## Every value blends from its "start" (level 1) toward its "end" along a saturating curve:
##   t(level) = 1 - exp(-(level - 1) / ramp)
## t rises quickly early on, then flattens, so difficulty never explodes and always stays achievable.
##
## THE PARAMETERS (Milestone 1.9: SPEED-BASED extraction, no fixed tap count).
##   A. speed response   progress per alternating tap depends on how fast the player alternates (see SpeedGain):
##                         peak_gain          the most one tap can add (level 1: 5.2 %)
##                         optimal interval   tapping faster than this earns no more progress per second
##                         minimum useful     slower than this a tap adds nothing (a fraction of the max gap)
##                         exponent           how steeply faster tapping is rewarded
##   B. max_tap_interval   the longest allowed gap between alternating taps (the rhythm rule).
##   C. resistance         how hard the sword resists near the end: the gain of a tap is multiplied by
##                         (1 - resistance * progress / 100), so the last stretch needs faster tapping.
##   D. decay, E. grace    the slip-back after a lapse (unchanged since Milestone 1.3).
## Difficulty rises through B (a smaller window of useful speeds), C and a slightly smaller peak gain, NOT through a tap count.

@export_group("A. Speed response (progress per alternating tap)")
@export_range(0.5, 30.0, 0.1) var start_peak_gain: float = 5.2   ## % per tap at the optimal speed, level 1
@export_range(0.5, 30.0, 0.1) var end_peak_gain: float = 3.2     ## very high levels (more effort per extraction)
@export_range(0.0, 100.0, 0.5) var peak_gain_ramp_levels: float = 6.0  ## 0 = follow ramp_levels
@export_range(40.0, 400.0, 5.0) var optimal_interval_msec: float = 130.0  ## about 7.7 taps/s: faster earns no more per second
@export_range(0.3, 1.0, 0.01) var useful_fraction: float = 0.85  ## minimum useful speed = this x the level's max interval
@export_range(0.5, 4.0, 0.05) var gain_curve_exponent: float = 1.4  ## 1 = linear in the interval, above 1 = faster is rewarded more

@export_group("B. Tapping rhythm (longest allowed gap between alternating taps)")
@export_range(120.0, 1500.0, 5.0) var start_max_tap_interval_msec: float = 370.0  ## level 1 (2.7 taps/s)
@export_range(120.0, 1500.0, 5.0) var end_max_tap_interval_msec: float = 250.0    ## very high levels (4 taps/s)
@export_range(0.0, 100.0, 0.5) var interval_ramp_levels: float = 6.0  ## 0 = follow ramp_levels

@export_group("C. Extraction resistance (0 = none, 0.5 = the last stretch counts half)")
@export_range(0.0, 0.9, 0.01) var start_resistance: float = 0.08
@export_range(0.0, 0.9, 0.01) var end_resistance: float = 0.6
@export_range(0.0, 100.0, 0.5) var resistance_ramp_levels: float = 6.0  ## 0 = follow ramp_levels

@export_group("D/E. Slip-back after a lapse (unchanged since 1.3)")
@export_range(0.0, 20.0, 0.1) var start_decay_per_second: float = 7.0  ## % progress lost per second
@export_range(0.0, 3.0, 0.05) var start_decay_grace_seconds: float = 0.35  ## idle time before decay starts
@export_range(0.0, 40.0, 0.1) var end_decay_per_second: float = 18.0
@export_range(0.0, 3.0, 0.05) var end_decay_grace_seconds: float = 0.15

@export_group("Curve")
@export_range(1.0, 100.0, 0.5) var ramp_levels: float = 6.0  ## larger = slower difficulty climb

@export_group("Per-parameter curve speed (0 = use ramp_levels)")
@export_range(0.0, 100.0, 0.5) var decay_ramp_levels: float = 0.0
@export_range(0.0, 100.0, 0.5) var grace_ramp_levels: float = 0.0

@export_range(2, 10000, 1) var final_level: int = 100  ## difficulty stops rising here: every level from this one on plays the same
@export_range(0.0, 1.0, 0.01) var linear_share: float = 0.35  ## how much of the climb is a steady rise all the way to final_level

## 0.0 at level 1, 1.0 at final_level and beyond. A quick early rise (the exponential with its ramp, so the first levels get harder fast)
## blended with a steady rise that keeps going until final_level (so level 60 is still harder than level 30). Never decreases.
func difficulty_factor(level: int) -> float:
	return _curve(level, ramp_levels)

func _curve(level: int, ramp: float) -> float:
	var l := clampi(level, 1, final_level)
	var fast := 1.0 - exp(-float(l - 1) / ramp)
	var steady := float(l - 1) / float(final_level - 1)
	return (1.0 - linear_share) * fast + linear_share * steady

# ---- A. speed response ---------------------------------------------------------------------

func peak_gain_for_level(level: int) -> float:
	return lerpf(start_peak_gain, end_peak_gain, _factor(level, peak_gain_ramp_levels))

## Intervals (ms) at or above this earn nothing on this level: the minimum useful tapping speed.
func min_useful_interval_for_level(level: int) -> float:
	return max_interval_for_level(level) * useful_fraction

## Progress (percent) one alternating tap adds at 0 % progress when it arrives `interval_msec` after the previous one.
func gain_for_interval(level: int, interval_msec: float) -> float:
	return SpeedGain.gain(interval_msec, peak_gain_for_level(level), optimal_interval_msec, min_useful_interval_for_level(level), gain_curve_exponent)

## Seconds a player who alternates perfectly steadily at `interval_msec` needs to extract on this level (the first tap awards
## nothing, resistance included, no decay because the taps never pause). -1 = never: that speed is too slow to make progress.
func simulate_extraction_seconds(level: int, interval_msec: float) -> float:
	var resistance := resistance_for_level(level)
	var progress := 0.0
	var seconds := 0.0
	for tap in 3000:
		seconds += interval_msec / 1000.0
		var gain := gain_for_interval(level, interval_msec) * (1.0 - resistance * progress / 100.0)
		if gain <= 0.0:
			return -1.0
		progress += gain
		if progress >= 100.0 - 0.0001:
			return seconds
	return -1.0

## How many taps that same steady player makes (a RESULT of their speed, never a requirement).
func simulate_extraction_taps(level: int, interval_msec: float) -> int:
	var resistance := resistance_for_level(level)
	var progress := 0.0
	for tap in 3000:
		var gain := gain_for_interval(level, interval_msec) * (1.0 - resistance * progress / 100.0)
		if gain <= 0.0:
			return -1
		progress += gain
		if progress >= 100.0 - 0.0001:
			return tap + 2  # + the first tap, which awards nothing
	return -1

# ---- B. rhythm -------------------------------------------------------------------------------

## Longest gap (ms) between two alternating taps that still awards progress on this level.
func max_interval_for_level(level: int) -> float:
	return lerpf(start_max_tap_interval_msec, end_max_tap_interval_msec, _factor(level, interval_ramp_levels))

# ---- C. resistance ---------------------------------------------------------------------------

func resistance_for_level(level: int) -> float:
	return clampf(lerpf(start_resistance, end_resistance, _factor(level, resistance_ramp_levels)), 0.0, 0.9)

# ---- D/E. decay and grace (independent of A-C) -----------------------------------------------

func decay_for_level(level: int) -> float:
	return lerpf(start_decay_per_second, end_decay_per_second, _factor(level, decay_ramp_levels))

func grace_for_level(level: int) -> float:
	return lerpf(start_decay_grace_seconds, end_decay_grace_seconds, _factor(level, grace_ramp_levels))

func _factor(level: int, ramp_override: float) -> float:
	var ramp := ramp_levels if ramp_override <= 0.0 else ramp_override
	return _curve(level, ramp)
