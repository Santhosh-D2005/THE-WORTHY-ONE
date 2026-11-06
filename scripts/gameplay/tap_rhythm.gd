class_name TapRhythm
extends RefCounted
## The minimum-tapping-speed rule as a pure function (no clock, no nodes), so it can be tested exactly.
##
##   no previous tap in this attempt          -> FIRST     (starts the attempt, awards nothing)
##   interval <= max_interval_msec            -> PROGRESS  (a valid alternating pair: awards progress)
##   interval  > max_interval_msec            -> TOO_SLOW  (awards nothing)
##
## The interval is the time between this tap and the previous ACCEPTED (alternating) tap, measured by the
## caller with a monotonic microsecond clock. Same-side repeats never reach this rule: they are rejected
## earlier and do not touch the timing at all.

static func classify(has_previous: bool, interval_msec: float, max_interval_msec: float) -> TapKind.Kind:
	if not has_previous:
		return TapKind.Kind.FIRST
	if interval_msec <= max_interval_msec:
		return TapKind.Kind.PROGRESS
	return TapKind.Kind.TOO_SLOW
