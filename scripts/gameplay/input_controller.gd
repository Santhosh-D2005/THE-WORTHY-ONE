class_name InputController
extends Node
## Converts raw touch / mouse presses into alternating-tap events.
## The screen is split into a left and right half. A tap is accepted only if it is on the
## opposite side from the previous accepted tap.

signal tap_accepted(side: TapSide.Side)
## Same-side repeat or a tap arriving too soon after another one (double registration).
signal tap_rejected(side: TapSide.Side)

## Taps closer together than this are treated as accidental double registration.
@export_range(0, 120, 1) var min_tap_interval_msec: int = 25

var enabled: bool = false
var last_accepted_side: TapSide.Side = TapSide.Side.NONE

## Minimum-tapping-speed rule (see TapRhythm). The limit is set by LevelManager from the level's difficulty.
var rhythm_enabled: bool = true
var max_interval_msec: float = 400.0
## Classification of the most recent accepted tap and the time since the tap before it
## (valid while tap_accepted is being handled; -1 for a FIRST tap).
var last_kind: TapKind.Kind = TapKind.Kind.FIRST
var last_interval_msec: float = -1.0

var _has_previous_tap: bool = false
var _last_accepted_usec: int = 0

## Optional: returns an Array of Rect2 (screen areas) where presses are NOT game taps, e.g. the HUD's PAUSE button. A press inside one is
## left alone (not handled, not counted) so the control under it receives it.
var blocked_rects_provider: Callable = Callable()

var _last_tap_msec: int = -100000
var _locked_until_msec: int = 0

## The side the player should tap next (NONE before the first tap: either side is fine).
func expected_side() -> TapSide.Side:
	match last_accepted_side:
		TapSide.Side.LEFT:
			return TapSide.Side.RIGHT
		TapSide.Side.RIGHT:
			return TapSide.Side.LEFT
	return TapSide.Side.NONE

## Ignore all gameplay taps for `seconds` (used after TRY AGAIN). Never shortens a lock that
## is already running. Blocked taps do not extend the lock, so it always expires on time.
func lock_for(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_locked_until_msec = maxi(_locked_until_msec, Time.get_ticks_msec() + int(seconds * 1000.0))

func is_locked() -> bool:
	return Time.get_ticks_msec() < _locked_until_msec

func lock_remaining_seconds() -> float:
	return maxf(0.0, float(_locked_until_msec - Time.get_ticks_msec()) / 1000.0)

func clear_lock() -> void:
	_locked_until_msec = 0

## Forget the alternation AND the rhythm anchor: the next tap is a FIRST tap again (new attempt,
## new level, retry, or the tap that resumes the game after a pause).
func reset_alternation() -> void:
	last_accepted_side = TapSide.Side.NONE
	_has_previous_tap = false
	last_interval_msec = -1.0

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	var press_position := Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed:
		press_position = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		press_position = event.position  # desktop testing fallback
	else:
		return
	if blocked_rects_provider.is_valid():
		for blocked: Variant in blocked_rects_provider.call():
			if blocked is Rect2 and (blocked as Rect2).has_point(press_position):
				return
	get_viewport().set_input_as_handled()
	var half_width := get_viewport().get_visible_rect().size.x * 0.5
	handle_tap(TapSide.Side.LEFT if press_position.x < half_width else TapSide.Side.RIGHT)

## Public so tests (and later, keyboard shortcuts) can inject taps.
func handle_tap(side: TapSide.Side) -> void:
	var now := Time.get_ticks_msec()
	if now < _locked_until_msec:
		tap_rejected.emit(side)  # input lock (post-retry protection): not a valid tap
		return
	# Debounce is measured from the last ACCEPTED tap. (Previously a rejected same-side tap also
	# restarted the window, which could swallow a valid opposite-side tap that followed it.)
	if now - _last_tap_msec < min_tap_interval_msec:
		tap_rejected.emit(side)
		return
	if side == last_accepted_side:
		tap_rejected.emit(side)
		return
	_last_tap_msec = now
	# Rhythm: interval from the previous ACCEPTED tap, on a monotonic microsecond clock (never frames).
	var now_usec := Time.get_ticks_usec()
	last_interval_msec = float(now_usec - _last_accepted_usec) / 1000.0 if _has_previous_tap else -1.0
	# With the rule switched off (GameplayConfig.rhythm_enabled) every accepted tap counts, as before 1.6.
	last_kind = TapRhythm.classify(_has_previous_tap, last_interval_msec, max_interval_msec) if rhythm_enabled \
		else TapKind.Kind.PROGRESS
	_last_accepted_usec = now_usec
	_has_previous_tap = true
	last_accepted_side = side
	tap_accepted.emit(side)
