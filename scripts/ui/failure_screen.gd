class_name FailureScreen
extends CanvasLayer
## "THE SWORD REMAINS": the run-failure screen. Pure presentation + two buttons that emit
## signals; LevelManager decides what retrying / leaving actually does.
##
## Layout keeps the middle of the screen empty so the stump and its embedded sword stay visible.
## Built in code (like the HUD) so it adapts to any portrait aspect via anchors.
##
## TOUCH NOTE: the project disables mouse-from-touch emulation (it would double-count taps in
## InputController), and Godot's Button only reacts to MOUSE events. So this screen also handles
## InputEventScreenTouch itself (press and release on the same button), otherwise the buttons
## would be dead on a phone.

signal retry_requested
signal main_menu_requested
signal shown  ## emitted each time the screen starts to appear (tests use it to count screens)

const GOLD := UiStyle.GOLD
const GOLD_DIM := UiStyle.GOLD_DIM
const GOLD_BRIGHT := UiStyle.GOLD_BRIGHT
const PARCHMENT := UiStyle.PARCHMENT
const FONT_PATH := UiStyle.FONT_PATH

const FADE_SECONDS := 0.7
## Buttons ignore presses for this long after the fade finishes, so a player who is still
## frantically tapping when they fail cannot accidentally hit TRY AGAIN.
const INPUT_DELAY_SECONDS := 0.6

## The main menu does not exist yet. When this scene file exists the MAIN MENU button
## switches on automatically; until then it is shown disabled instead of pretending to work.
@export var main_menu_scene_path: String = "res://scenes/ui/main_menu.tscn"

var is_showing: bool = false
var buttons_ready: bool = false
var show_count: int = 0

var _root: Control
var _title: Label
var _subtitle: Label
var _status_label: Label
var _verdict_label: Label
var verdict_enabled := DisplayServer.get_name() != "headless"  ## headless test runs never reach the network
var _verdict_cache := {}
var _shown_result: RunResult = null
var _level_value: Label
var _session_value: Label
var _extractions_value: Label
var _try_again_button: Button
var _main_menu_button: Button
var _tween: Tween
var _acted: bool = false
var _touch_press_target: Button = null
var _safe_nodes: Array = []  # [control, is_top, base_offset_top, base_offset_bottom]

func _ready() -> void:
	layer = 15  # above the HUD (10)
	process_mode = Node.PROCESS_MODE_PAUSABLE  # inert while the game is paused
	_build()
	for top_node in [_title, _root.get_node("Divider"), _root.get_node("Subtitle")]:
		_safe_nodes.append([top_node, true, top_node.offset_top, top_node.offset_bottom])
	for bottom_node in [_root.get_node("StatsPanel"), _root.get_node("Stats"), _root.get_node("Buttons")]:
		_safe_nodes.append([bottom_node, false, bottom_node.offset_top, bottom_node.offset_bottom])
	refresh_safe_area()
	get_viewport().size_changed.connect(refresh_safe_area)
	visible = false
	GameManager.state_changed.connect(_on_state_changed)
	RunSync.status_changed.connect(func(_status: String) -> void: _refresh_status())

# ---- Public API ----------------------------------------------------------------------------

## Fade the screen in with the facts of the finished run. Ignored if already showing, so a
## second failure can never stack a second screen.
func show_result(result: RunResult) -> void:
	if is_showing:
		return
	is_showing = true
	buttons_ready = false
	_acted = false
	show_count += 1
	_level_value.text = str(result.level_reached)
	_apply_end_reason(result)
	_shown_result = result
	_refresh_status()
	_show_verdict(result)
	_session_value.text = RunResult.format_time(result.session_seconds)
	_extractions_value.text = str(result.extractions)
	refresh_main_menu_button()
	visible = true
	_root.modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(INPUT_DELAY_SECONDS)
	_tween.tween_callback(func() -> void: buttons_ready = true)
	shown.emit()

## The run-ended variant (Ruthless run left the foreground): same layout, different words.
func _apply_end_reason(result: RunResult) -> void:
	var invalidated := result.end_reason == RunResult.EndReason.INVALIDATED
	var completed := result.end_reason == RunResult.EndReason.COMPLETED
	_title.text = "THE WORTHY ONE" if completed else ("RUN ENDED" if invalidated else "THE SWORD REMAINS")
	_subtitle.text = "ALL %d SWORDS ARE DRAWN" % GameManager.MAX_LEVEL if completed else ("YOU LEFT THE FOREST" if invalidated else "THE WOOD HOLDS FAST")
	_try_again_button.text = "BEGIN AGAIN" if completed else ("NEW ATTEMPT" if invalidated else "TRY AGAIN")

## What to say about the Hall of Fame for a run, from the local facts and RunSync's status. Plain text, no network wait.
static func online_text(result: RunResult, sync_status: String) -> String:
	if result.end_reason == RunResult.EndReason.INVALIDATED:
		return "RUN ENDED EARLY. ONLY LEVELS ALREADY SENT TO THE HALL OF FAME COUNT."
	match sync_status:
		"signed_out":
			return "NOT LOGGED IN. THIS RUN COUNTS FOR YOUR OWN BEST BUT IS NOT SENT TO THE HALL OF FAME."
		"offline":
			return "OFFLINE RUN. IT COUNTS FOR YOUR OWN BEST BUT IS NOT SENT TO THE HALL OF FAME."
		"pending":
			return "WAITING TO REACH THE HALL OF FAME..."
		"submitted":
			return "SENT TO THE HALL OF FAME."
		"rejected":
			return "THE HALL OF FAME DID NOT ACCEPT THIS RUN."
		_:
			return ""

## Built-in lines, used offline and while the AI line is on its way. Always available.
static func fallback_verdict(result: RunResult) -> String:
	if result.end_reason == RunResult.EndReason.COMPLETED:
		return "Nothing is left in the stone. The forest knows your name."
	if result.end_reason == RunResult.EndReason.INVALIDATED:
		return "The forest keeps its silence until you return."
	if result.level_reached >= 100:
		return "Few hands have ever held a blade this stubborn."
	if result.level_reached >= 20:
		return "The wood remembers every sword you drew."
	return "The stone is patient. So must you be."

## Show the built-in line at once; then ask the server (which asks Gemini) for a fresher one and swap it in if this result is still showing.
func _show_verdict(result: RunResult) -> void:
	_verdict_label.text = fallback_verdict(result)
	if not verdict_enabled or not RunSync.enabled or not Account.logged_in:
		return
	var cache_key := "%d:%d:%d" % [result.mode, result.level_reached, result.end_reason]
	if _verdict_cache.has(cache_key):
		_verdict_label.text = _verdict_cache[cache_key]
		return
	var reasons: Array[String] = ["failure", "invalidated", "completed"]
	var reason: String = reasons[result.end_reason]
	var answer: Dictionary = await Backend.verdict(result.mode, result.level_reached, reason)
	if answer.get("ok", false) and _shown_result == result:
		var text := str(answer.get("text", "")).strip_edges()
		if text != "":
			_verdict_cache[cache_key] = text
			_verdict_label.text = text

func _refresh_status() -> void:
	if _shown_result == null or _status_label == null:
		return
	var best := Progress.best(_shown_result.mode)
	var lines: Array[String] = ["%s   BEST: LEVEL %d" % [GameMode.title(_shown_result.mode), int(best["best_level"])]]
	var online := online_text(_shown_result, RunSync.status)
	if online != "":
		lines.append(online)
	_status_label.text = "\n".join(lines)

func hide_screen() -> void:
	_shown_result = null
	is_showing = false
	buttons_ready = false
	_touch_press_target = null
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false

## Keep clear of camera cut-outs (top) and the gesture bar (bottom). No-op where the OS reports none.
func refresh_safe_area() -> void:
	var insets := SafeArea.insets_in_viewport(get_viewport())
	for entry in _safe_nodes:
		var node: Control = entry[0]
		var shift: float = insets.y if entry[1] else -insets.w
		node.offset_top = entry[2] + shift
		node.offset_bottom = entry[3] + shift

## Enable MAIN MENU only if its scene exists.
func refresh_main_menu_button() -> void:
	var available := ResourceLoader.exists(main_menu_scene_path)
	_main_menu_button.disabled = not available
	_main_menu_button.modulate.a = 1.0 if available else 0.38

func is_main_menu_available() -> bool:
	return not _main_menu_button.disabled

# ---- Input ---------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Touch path (mouse clicks reach the Button nodes directly through Godot's GUI).
	if not is_showing or not visible or not event is InputEventScreenTouch:
		return
	if event.pressed:
		_touch_press_target = _button_at(event.position) if buttons_ready else null
		if _touch_press_target != null:
			get_viewport().set_input_as_handled()
	else:
		var released_on := _button_at(event.position)
		if released_on != null and released_on == _touch_press_target:
			_activate(released_on)
			get_viewport().set_input_as_handled()
		_touch_press_target = null

func _button_at(point: Vector2) -> Button:
	for button in [_try_again_button, _main_menu_button]:
		if not button.disabled and button.get_global_rect().has_point(point):
			return button
	return null

func _on_button_pressed(button: Button) -> void:
	_activate(button)

## Single place where a button press becomes an action; guarded against double activation
## and against presses before the screen is interactive.
func _activate(button: Button) -> void:
	if not is_showing or not buttons_ready or _acted or button.disabled:
		return
	_acted = true
	if button == _try_again_button:
		retry_requested.emit()
	else:
		main_menu_requested.emit()

func _on_state_changed(state: GameManager.State) -> void:
	# While paused, step aside so the pause overlay (HUD layer) is readable.
	if is_showing:
		visible = state != GameManager.State.PAUSED

# ---- Construction ----------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Darkening: a flat dim plus a vignette; the centre stays clear enough to see the stump.
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.01, 0.0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_root.add_child(UiStyle.vignette())
	_root.add_child(UiStyle.scrim("BottomScrim", false, 700, 0.78))

	_title = _make_label("THE SWORD REMAINS", 78, GOLD_BRIGHT)
	_title.name = "Title"
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 170
	_title.offset_bottom = 290
	_root.add_child(_title)

	var divider := UiStyle.divider()
	divider.offset_top = 305
	divider.offset_bottom = 307
	_root.add_child(divider)

	# 1.16: one quiet line under the heading (not red, not dramatic: the wood simply holds).
	_subtitle = _make_label("THE WOOD HOLDS FAST", UiStyle.SIZE_CAPTION + 5, UiStyle.PARCHMENT_DIM)
	_subtitle.name = "Subtitle"
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_subtitle.offset_top = 330
	_subtitle.offset_bottom = 392
	_root.add_child(_subtitle)

	# Phase 6/7: the mode, the player's own best and what happened online, in two quiet lines. Never blocks the buttons.
	_status_label = _make_label("", 26, UiStyle.CAPTION)
	_status_label.name = "RunStatus"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_status_label.offset_left = 60
	_status_label.offset_right = -60
	_status_label.offset_top = 400
	_status_label.offset_bottom = 500
	_root.add_child(_status_label)

	# One short line of flavour text (Gemini via the server, or a built-in line). Decoration only; never blocks anything.
	_verdict_label = _make_label("", 30, UiStyle.PARCHMENT_DIM)
	_verdict_label.name = "Verdict"
	_verdict_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_verdict_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_verdict_label.offset_left = 70
	_verdict_label.offset_right = -70
	_verdict_label.offset_top = 540
	_verdict_label.offset_bottom = 660
	_root.add_child(_verdict_label)

	# 1.16: a quiet panel behind the three statistics, so they read as one group.
	var stats_panel := UiStyle.panel("StatsPanel")
	stats_panel.anchor_left = 0.03
	stats_panel.anchor_right = 0.97
	stats_panel.anchor_top = 1.0
	stats_panel.anchor_bottom = 1.0
	stats_panel.offset_top = -590
	stats_panel.offset_bottom = -370
	_root.add_child(stats_panel)

	var stats := HBoxContainer.new()
	stats.name = "Stats"
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.anchor_left = 0.05
	stats.anchor_right = 0.95
	stats.anchor_top = 1.0
	stats.anchor_bottom = 1.0
	stats.offset_top = -560
	stats.offset_bottom = -400
	stats.add_theme_constant_override("separation", 10)
	_root.add_child(stats)
	_level_value = _add_stat(stats, "LEVEL REACHED", "LevelValue")
	_session_value = _add_stat(stats, "SESSION TIME", "SessionValue")
	_extractions_value = _add_stat(stats, "TOTAL EXTRACTIONS", "ExtractionsValue")

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.anchor_left = 0.06
	buttons.anchor_right = 0.94
	buttons.anchor_top = 1.0
	buttons.anchor_bottom = 1.0
	buttons.offset_top = -330
	buttons.offset_bottom = -190
	buttons.add_theme_constant_override("separation", 36)
	_root.add_child(buttons)
	_try_again_button = _make_button("TRY AGAIN", true, "TryAgainButton")
	_main_menu_button = _make_button("MAIN MENU", false, "MainMenuButton")
	buttons.add_child(_try_again_button)
	buttons.add_child(_main_menu_button)
	_try_again_button.pressed.connect(_on_button_pressed.bind(_try_again_button))
	_main_menu_button.pressed.connect(_on_button_pressed.bind(_main_menu_button))
	refresh_main_menu_button()

func _add_stat(parent: Control, caption: String, value_name: String) -> Label:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	var caption_label := _make_label(caption, 25, UiStyle.CAPTION)
	column.add_child(caption_label)
	var value := _make_label("-", 60, PARCHMENT)
	value.name = value_name
	column.add_child(value)
	return value

func _make_label(text: String, font_size: int, color: Color) -> Label:
	return UiStyle.label(text, font_size, color)

func _make_button(text: String, primary: bool, node_name: String) -> Button:
	var button := UiStyle.button(text, primary, node_name, 40)
	button.custom_minimum_size = Vector2(0, 130)
	button.size_flags_stretch_ratio = 1.35 if primary else 1.0  # TRY AGAIN is the clearer, wider action
	return button
