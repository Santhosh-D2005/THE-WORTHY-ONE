extends Node
## Autoload "PerfProbe": a measurement aid, completely inert unless the game is started with --perf-log
## (on Android: export preset > Command Line > Extra Args, or `am start --esa command_line_params`).
##
## When enabled it writes user://perf_log.txt containing
##   * startup marks (ms since the engine started, plus the phone's wall clock so a host script can
##     compute launch -> first rendered frame),
##   * one line per rendered frame: time, frame delta (ms), game state, draw calls, primitives,
## and flushes it every few seconds and whenever the app is paused. Pull it with
##   adb shell run-as com.theworthyone.game cat files/perf_log.txt
## Nothing here touches gameplay; when disabled _process is switched off and mark() returns at once.

const FLAG := "--perf-log"
const LOG_PATH := "user://perf_log.txt"
const FLUSH_SECONDS := 4.0

var enabled: bool = false

var _lines: PackedStringArray = PackedStringArray()
var _flushed_count: int = 0
var _since_flush: float = 0.0
var _first_frame_logged: bool = false
var _file_started: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = FLAG in RenderQuality.launch_arguments()
	set_process(enabled)
	if not enabled:
		return
	_lines.append("# perf log | device=%s | gpu=%s | renderer=%s | screen=%s" % [
		OS.get_model_name(), RenderingServer.get_video_adapter_name(),
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), str(DisplayServer.screen_get_size())])
	_lines.append("# quality: " + RenderQuality.current().describe() + " | baked assets: " + str(not AssetCache.disabled))
	mark("autoload_ready")
	RenderingServer.frame_post_draw.connect(_on_first_frame_drawn, CONNECT_ONE_SHOT)
	GameManager.state_changed.connect(func(s: GameManager.State) -> void: mark("state_%s" % GameManager.State.keys()[s]))

## Record a named moment. `engine_ms` counts from engine start; `wall` is the device clock in seconds.
func mark(label: String) -> void:
	if not enabled:
		return
	_lines.append("M,%s,engine_ms=%d,wall=%.3f" % [label, Time.get_ticks_msec(), Time.get_unix_time_from_system()])

## One line per accepted gameplay tap: kind (0 first, 1 progress, 2 too slow), interval since the previous tap, progress after it.
func tap(kind: int, interval_msec: float, progress: float) -> void:
	if enabled:
		_lines.append("K,%d,%d,%.1f,%.1f" % [Time.get_ticks_msec(), kind, interval_msec, progress])

## Convenience for timing a block: var t := PerfProbe.begin(); ...; PerfProbe.end("label", t)
func begin() -> int:
	return Time.get_ticks_usec()

func end(label: String, started_usec: int) -> void:
	if enabled:
		_lines.append("T,%s,ms=%.1f" % [label, (Time.get_ticks_usec() - started_usec) / 1000.0])

func _on_first_frame_drawn() -> void:
	if not _first_frame_logged:
		_first_frame_logged = true
		mark("first_frame_drawn")

func _process(delta: float) -> void:
	var state_name: String = GameManager.State.keys()[GameManager.state]
	_lines.append("F,%d,%.2f,%s,%d,%d" % [
		Time.get_ticks_msec(), delta * 1000.0, state_name,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	_since_flush += delta
	if _since_flush >= FLUSH_SECONDS:
		flush()

func _notification(what: int) -> void:
	if enabled and (what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT):
		mark("app_paused")
		flush()

func flush() -> void:
	_since_flush = 0.0
	if _lines.size() == _flushed_count:
		return
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if _file_started else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	for i in range(_flushed_count, _lines.size()):
		file.store_line(_lines[i])
	file.close()
	_file_started = true
	_flushed_count = _lines.size()
	if _lines.size() > 4000:  # keep memory flat during long captures
		_lines = PackedStringArray()
		_flushed_count = 0
