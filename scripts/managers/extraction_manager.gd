class_name ExtractionManager
extends Node
## Owns extraction progress (0..100). The only place progress is changed.
## It knows nothing about input, visuals or levels: it is fed valid taps and tuning values.

signal progress_changed(progress: float)
signal valid_tap_applied(gain: float, progress: float)
signal decay_started
signal decay_stopped
signal extraction_completed
## Progress fell back to exactly 0 after the player had started this attempt. Emitted at most
## once per attempt. It can never fire before the first valid tap (progress starts at 0 and
## only decays after a tap has raised it).
signal progress_depleted

const MAX_PROGRESS := 100.0

var progress: float = 0.0
var is_decaying: bool = false

## PEAK progress (%) one tap can add: the gain of a tap at the optimal tapping speed. What a tap really adds depends on how
## fast the player is alternating (SpeedGain), so there is no fixed gain and no fixed number of taps.
var gain_per_tap: float = 8.0
var optimal_interval_msec: float = 130.0
var useful_interval_msec: float = 340.0   ## slower than this a tap adds nothing
var gain_exponent: float = 1.4
## The gain and the interval of the most recent progress tap (for the HUD, tests and debugging).
var last_gain: float = 0.0
var last_interval_msec: float = -1.0
var decay_per_second: float = 5.0
var decay_grace_seconds: float = 0.5
## Extraction resistance (see DifficultyConfig): a tap adds gain * (1 - resistance * progress / 100).
var resistance: float = 0.0
## With the rhythm rule the first tap awards nothing, so progress can sit at 0 after an attempt began.
## If no progress-awarding tap arrives within decay_grace_seconds + this extra time (the level's allowed
## tap interval), the attempt fails like a decayed-to-zero bar. 0 keeps the grace period alone.
var zero_progress_extra_seconds: float = 0.0

var _active: bool = false
var _completed: bool = false
var _attempt_started: bool = false  # set by the first valid tap of this attempt
var _depleted: bool = false
var _seconds_since_tap: float = 0.0

## Apply tuning values (called by LevelManager from DifficultyManager output).
func configure(gain: float, decay: float, grace: float) -> void:
	gain_per_tap = gain
	decay_per_second = decay
	decay_grace_seconds = grace

## The speed-response curve of the level (see SpeedGain). Without it a tap earns the full peak gain.
func configure_speed(optimal_msec: float, useful_msec: float, exponent: float) -> void:
	optimal_interval_msec = optimal_msec
	useful_interval_msec = useful_msec
	gain_exponent = exponent

## Start a fresh extraction attempt at 0%.
func reset() -> void:
	progress = 0.0
	_completed = false
	_attempt_started = false
	_depleted = false
	_seconds_since_tap = 0.0
	_set_decaying(false)
	progress_changed.emit(progress)

func set_active(value: bool) -> void:
	_active = value

## First tap of an attempt: the attempt begins and the stall timer restarts, but no progress is awarded.
func begin_attempt() -> void:
	if not _active or _completed:
		return
	_attempt_started = true
	_seconds_since_tap = 0.0

## An alternating tap that was too slow: counts for nothing. It deliberately does NOT restart the
## grace / decay timer, so slow tapping cannot hold a bar in place.
func register_slow_tap() -> void:
	pass

## Progress a tap that arrives `interval_msec` after the previous alternating tap adds at this moment: the speed-response
## gain reduced by the resistance at this height. A negative interval means "at the optimal speed" (the full peak gain).
func current_gain(interval_msec: float = -1.0) -> float:
	var base := gain_per_tap if interval_msec < 0.0 		else SpeedGain.gain(interval_msec, gain_per_tap, optimal_interval_msec, useful_interval_msec, gain_exponent)
	return base * (1.0 - clampf(resistance, 0.0, 0.9) * progress / MAX_PROGRESS)

## An alternating tap within the allowed interval. Its worth depends on the measured interval (faster = more); a tap slower than
## the minimum useful speed is worth nothing and, like a slow tap, does not restart the grace / decay timer.
func register_valid_tap(interval_msec: float = -1.0) -> void:
	if not _active or _completed:
		return
	_attempt_started = true
	var gain := current_gain(interval_msec)
	last_interval_msec = interval_msec
	last_gain = gain
	if gain <= 0.0:
		return
	progress = clampf(progress + gain, 0.0, MAX_PROGRESS)
	if progress >= MAX_PROGRESS - 0.0001:
		progress = MAX_PROGRESS  # float sums of 100/N never land exactly on 100; this is the last tap
	_seconds_since_tap = 0.0
	_set_decaying(false)
	valid_tap_applied.emit(gain, progress)
	progress_changed.emit(progress)
	if progress >= MAX_PROGRESS:
		_completed = true
		_active = false
		extraction_completed.emit()

func _process(delta: float) -> void:
	if not _active or _completed:
		return
	if progress <= 0.0:
		# Attempt begun but nothing earned yet: fail once the player has stalled long enough.
		if _attempt_started and not _depleted:
			_seconds_since_tap += delta
			if _seconds_since_tap >= decay_grace_seconds + zero_progress_extra_seconds:
				_depleted = true
				progress_depleted.emit()
		return
	# Grace period: the player gets a short window to re-time their next tap.
	_seconds_since_tap += delta
	if _seconds_since_tap < decay_grace_seconds:
		return
	_set_decaying(true)
	progress = clampf(progress - decay_per_second * delta, 0.0, MAX_PROGRESS)
	progress_changed.emit(progress)
	if progress <= 0.0:
		_set_decaying(false)
		if _attempt_started and not _depleted:
			_depleted = true
			progress_depleted.emit()

func _set_decaying(value: bool) -> void:
	if value == is_decaying:
		return
	is_decaying = value
	if value:
		decay_started.emit()
	else:
		decay_stopped.emit()
