class_name TimerManager
extends Node
## Level timer and session timer, measured with a monotonic clock (not frame counting).
## Both start on the first valid input. The session timer survives level changes.

var _level_running: bool = false
var _level_accum_usec: int = 0
var _level_started_usec: int = 0

var _session_running: bool = false
var _session_accum_usec: int = 0
var _session_started_usec: int = 0

var _paused: bool = false

func level_seconds() -> float:
	return _elapsed_usec(_level_accum_usec, _level_running, _level_started_usec) / 1000000.0

func session_seconds() -> float:
	return _elapsed_usec(_session_accum_usec, _session_running, _session_started_usec) / 1000000.0

## Call on every valid tap; starts whichever timers are not yet running.
func notify_valid_input() -> void:
	if _paused:
		return
	var now := Time.get_ticks_usec()
	if not _level_running:
		_level_running = true
		_level_started_usec = now
	if not _session_running:
		_session_running = true
		_session_started_usec = now

## Stops the level timer and returns the level time in seconds.
func stop_level() -> float:
	var result := level_seconds()
	_level_accum_usec = int(result * 1000000.0)
	_level_running = false
	return result

func reset_level() -> void:
	_level_running = false
	_level_accum_usec = 0

func stop_session() -> float:
	var result := session_seconds()
	_session_accum_usec = int(result * 1000000.0)
	_session_running = false
	return result

func reset_session() -> void:
	_session_running = false
	_session_accum_usec = 0

## Freeze both timers so time spent paused or backgrounded is not counted.
func pause() -> void:
	if _paused:
		return
	var now := Time.get_ticks_usec()
	if _level_running:
		_level_accum_usec += now - _level_started_usec
	if _session_running:
		_session_accum_usec += now - _session_started_usec
	_paused = true

func resume() -> void:
	if not _paused:
		return
	var now := Time.get_ticks_usec()
	_level_started_usec = now
	_session_started_usec = now
	_paused = false

func _elapsed_usec(accum: int, running: bool, started: int) -> int:
	if running and not _paused:
		return accum + (Time.get_ticks_usec() - started)
	return accum
