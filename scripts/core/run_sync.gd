extends Node
## Autoload "RunSync": reports the player's runs to the server so they can reach the Hall of Fame, and never blocks or changes gameplay.
##
## HOW IT WORKS. When a run starts, the server issues a run id (start_run). Each completed level and the end of the run are reported
## in order through a queue that is saved to disk, so a kill or a lost connection does not lose them. The server re-validates everything.
##   * Network trouble (offline, timeout, 5xx): the event stays queued and is retried with a growing delay (5 s ... 60 s).
##   * The server refuses an event (bad order, run not active, run expired, implausible time ...): that event and the rest of that run
##     are dropped, because a refused run can never become valid later. This is what keeps an invalidated Ruthless run from being
##     accepted after the player reconnects.
##   * A run that could not get a server run id (offline at the start) is an OFFLINE run: it still counts for the local record, but it is
##     never submitted to the Hall of Fame (there is no server clock to check it against).
## Honest limit: a Ruthless run's levels must reach the server within about a minute of each other, or the server expires the run.

signal status_changed(status: String)

## "disabled" | "offline" | "pending" | "submitted" | "rejected"
var status: String = "disabled"
## Tests and headless runs switch this off so they never reach the real server.
var enabled: bool = true
var server_run: String = ""

var _local_run: String = ""
var _opening: bool = false
var _waiting: Array[Dictionary] = []   # events that happened before the server run id arrived
var _flushing: bool = false
var _retry_seconds: float = 5.0
var _timer: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		enabled = false
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(flush)
	add_child(_timer)
	Progress.run_started.connect(_on_run_started)
	Progress.level_recorded.connect(_on_level_recorded)
	Progress.run_ended.connect(_on_run_ended)
	if enabled:
		flush.call_deferred()  # deliver anything left from the last session

func _queue() -> Array:
	return Progress.store.data["queue"]

func _set_status(value: String) -> void:
	if status != value:
		status = value
		status_changed.emit(value)

func _on_run_started(mode: GameMode.Mode, run_id: String) -> void:
	_local_run = run_id
	server_run = ""
	_waiting.clear()
	if not enabled:
		_set_status("disabled")
		return
	if Progress.run_start_level > 1:
		_set_status("offline")  # a continued run does not start at level 1, which the Hall of Fame cannot verify: local only
		return
	if not Account.logged_in:
		_set_status("signed_out")  # not logged in: the run counts for the phone's own best only
		return
	_set_status("pending")
	_open_run(mode, run_id)

func _open_run(mode: GameMode.Mode, local_id: String) -> void:
	_opening = true
	var reply := await Backend.call_server("start_run", {"p_mode": GameMode.key(mode)})
	_opening = false
	if local_id != _local_run:
		return  # a newer run began while we waited
	if reply.get("ok", false):
		server_run = str(reply["run_id"])
		for event in _waiting:
			_enqueue(event)
		_waiting.clear()
		flush()
	else:
		_waiting.clear()
		server_run = ""
		_set_status("signed_out" if str(reply.get("error", "")) == "not_logged_in" else "offline")  # this run is local only

func _on_level_recorded(_mode: GameMode.Mode, level: int, seconds: float, _new_best: bool) -> void:
	if not enabled or status == "offline" or status == "disabled" or status == "signed_out":
		return
	var event := {"kind": "level", "level": level, "seconds": seconds}
	if server_run == "":
		if _opening:
			_waiting.append(event)
		return
	_enqueue(event)
	flush()

func _on_run_ended(summary: Dictionary) -> void:
	var reason := str(summary.get("reason", ""))
	if not enabled or (server_run == "" and not _opening) or reason == "replaced":
		return
	var end_reason := "invalidated" if reason == "invalidated" else ("failed" if reason == "failed" else "left")
	var event := {"kind": "end", "reason": end_reason}
	if server_run == "":
		_waiting.append(event)
		return
	_enqueue(event)
	flush()

func _enqueue(event: Dictionary) -> void:
	var entry := event.duplicate()
	entry["run"] = server_run
	_queue().append(entry)
	Progress.store.save()

## Send queued events in order. Safe to call at any time; only one flush runs at once.
func flush() -> void:
	if _flushing or not enabled:
		return
	_flushing = true
	while not _queue().is_empty():
		var head: Dictionary = _queue()[0]
		var reply := await _send(head)
		if reply.get("ok", false):
			_queue().pop_front()
			Progress.store.save()
			_retry_seconds = 5.0
			if head["kind"] == "level" and head["run"] == server_run:
				_set_status("submitted")
			continue
		var error := str(reply.get("error", ""))
		if Backend.is_retryable(error):
			_timer.start(_retry_seconds)
			_retry_seconds = minf(_retry_seconds * 2.0, 60.0)
			_set_status("pending")
			_flushing = false
			return
		# Refused for good: drop this run's remaining events.
		var refused_run: String = head["run"]
		var kept: Array = []
		for entry in _queue():
			if entry["run"] != refused_run:
				kept.append(entry)
		Progress.store.data["queue"] = kept
		Progress.store.save()
		if refused_run == server_run:
			_set_status("signed_out" if error == "not_logged_in" else "rejected")
	_flushing = false

func _send(entry: Dictionary) -> Dictionary:
	if entry["kind"] == "level":
		return await Backend.call_server("submit_level", {"p_run": entry["run"], "p_level": entry["level"], "p_seconds": entry["seconds"]})
	return await Backend.call_server("end_run", {"p_run": entry["run"], "p_reason": entry["reason"]})
