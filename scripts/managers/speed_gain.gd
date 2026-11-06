class_name SpeedGain
extends RefCounted
## THE SPEED-RESPONSE CURVE (Milestone 1.9): how much progress one valid alternating tap adds, as a pure function of the
## measured time since the previous alternating tap. There is NO fixed number of taps: the faster and the more evenly the
## player alternates, the more each tap is worth, so progress per SECOND grows faster than the tapping speed itself.
##
##   interval >= useful      -> 0           slower than the minimum useful speed: no progress at all (and the slowest 8 % of the
##                                          useful window earns nothing either, so tapping at the very edge cannot creep forward)
##   optimal < interval < useful            gain = peak * ((useful - interval) / (useful - optimal)) ^ exponent
##   interval <= optimal     -> the full peak gain, but scaled by interval / optimal, so tapping faster than the optimal
##                              interval never raises the progress per second (physically unrealistic speeds are not rewarded)
##
## Example (level 1: peak 6 %, optimal 130 ms, useful 340 ms, exponent 1.4):  4 taps/s (250 ms) -> 1.8 % per tap
## = 7.3 % per second;  5 taps/s (200 ms) -> 3.4 % = 17 % per second;  6 taps/s (167 ms) -> 4.6 % = 27 % per second.

## Share of the useful window (counted from its slow end) that earns nothing.
const DEAD_ZONE := 0.08

static func gain(interval_msec: float, peak: float, optimal_msec: float, useful_msec: float, exponent: float) -> float:
	if interval_msec <= 0.0 or interval_msec >= useful_msec:
		return 0.0
	var x := 1.0
	if useful_msec > optimal_msec:
		x = clampf((useful_msec - interval_msec) / (useful_msec - optimal_msec), 0.0, 1.0)
	# A small dead zone just inside the useful limit: tapping barely faster than the minimum speed earns exactly nothing,
	# so a player hovering at the edge of the rhythm cannot creep forward (decay wins), and the gain then rises smoothly.
	x = clampf((x - DEAD_ZONE) / (1.0 - DEAD_ZONE), 0.0, 1.0)
	if x <= 0.0:
		return 0.0
	var shape := pow(x, maxf(exponent, 0.1))
	var cap := minf(1.0, interval_msec / maxf(optimal_msec, 1.0))
	return peak * shape * cap

## Progress per second a steady tapper at this interval earns (before resistance and decay).
static func rate_per_second(interval_msec: float, peak: float, optimal_msec: float, useful_msec: float, exponent: float) -> float:
	if interval_msec <= 0.0:
		return 0.0
	return gain(interval_msec, peak, optimal_msec, useful_msec, exponent) * 1000.0 / interval_msec
