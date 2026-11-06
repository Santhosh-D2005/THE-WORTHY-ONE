class_name OverlayScreen
extends CanvasLayer
## Base of the menu's full-screen panels (modes, Hall of Fame, account): a dim, one framed panel with a title, a content column and a
## CLOSE button, in the game's style. It owns what every such screen needs and the others got wrong before: touch buttons (Godot's Button
## only reacts to MOUSE events and mouse-from-touch is off in this project), no taps leaking to the menu behind, Android Back closes it,
## safe-area insets, and presses ignored for a moment after it appears.
## Subclasses override _build_content(column) and may call _refresh() when their data changes.

signal closed

const FADE_SECONDS := 0.3
const INPUT_DELAY_SECONDS := 0.3

var is_showing: bool = false
var buttons_ready: bool = false
var panel: Panel
var column: VBoxContainer
var title_label: Label
var close_button: Button

var _root: Control
var _tween: Tween
var _touch_press_target: Button = null
var _safe_nodes: Array = []

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_frame()
	_build_content(column)
	close_button = UiStyle.button("CLOSE", false, "CloseButton", 40)
	close_button.custom_minimum_size = Vector2(0, 120)
	column.add_child(close_button)
	close_button.pressed.connect(_on_button_pressed.bind(close_button))
	visible = false
	get_viewport().size_changed.connect(refresh_safe_area)

func screen_title() -> String:
	return ""

func _build_content(_parent: VBoxContainer) -> void:
	pass

func _on_opened() -> void:
	pass

func open() -> void:
	is_showing = true
	buttons_ready = false
	_touch_press_target = null
	refresh_safe_area()
	_on_opened()
	visible = true
	_root.modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(INPUT_DELAY_SECONDS)
	_tween.tween_callback(func() -> void: buttons_ready = true)

func close() -> void:
	if not is_showing:
		return
	is_showing = false
	buttons_ready = false
	_touch_press_target = null
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false
	DisplayServer.virtual_keyboard_hide()
	closed.emit()

func refresh_safe_area() -> void:
	var insets := SafeArea.insets_in_viewport(get_viewport())
	for entry in _safe_nodes:
		var node: Control = entry[0]
		node.offset_top = entry[1] + insets.y
		node.offset_bottom = entry[2] - insets.w

## Called by a subclass when a button is activated and it is not CLOSE. Return true if handled.
func _on_action(_button: Button) -> void:
	pass

# ---- Input -----------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_showing:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_press_target = _button_at(event.position) if buttons_ready else null
		else:
			var released_on := _button_at(event.position)
			if released_on != null and released_on == _touch_press_target:
				_activate(released_on)
			elif released_on == null and buttons_ready:
				_focus_edit_at(event.position)
			_touch_press_target = null
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _can_close():
			close()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_showing and _can_close():
		close()

## A screen that must not be dismissed (the first-launch login) returns false: Back and Escape then do nothing.
func _can_close() -> bool:
	return true

## Touches never reach a LineEdit (this screen handles them, and mouse-from-touch is off), so a tap on one focuses it by hand and asks
## Android for the on-screen keyboard. UNVERIFIED on a device until the phone test.
func _focus_edit_at(point: Vector2) -> void:
	for node in panel.find_children("*", "LineEdit", true, false):
		var edit := node as LineEdit
		if edit.is_visible_in_tree() and edit.get_global_rect().has_point(point):
			edit.grab_focus()
			DisplayServer.virtual_keyboard_show(edit.text, edit.get_global_rect(),
				DisplayServer.KEYBOARD_TYPE_PASSWORD if edit.secret else DisplayServer.KEYBOARD_TYPE_DEFAULT, edit.max_length, edit.caret_column)
			return
	DisplayServer.virtual_keyboard_hide()

func _button_at(point: Vector2) -> Button:
	for node in panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(point):
			return button
	return null

func _on_button_pressed(button: Button) -> void:
	_activate(button)

func _activate(button: Button) -> void:
	if not is_showing or not buttons_ready or button.disabled:
		return
	if button == close_button:
		close()
	else:
		_on_action(button)

# ---- Construction ----------------------------------------------------------------------------

func _build_frame() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.01, 0.0, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_root.add_child(UiStyle.vignette())
	panel = UiStyle.panel("Panel")
	panel.anchor_left = 0.045
	panel.anchor_right = 0.955
	panel.anchor_bottom = 1.0
	panel.offset_top = 110
	panel.offset_bottom = -110
	_root.add_child(panel)
	column = VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 40
	column.offset_right = -40
	column.offset_top = 34
	column.offset_bottom = -34
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	title_label = UiStyle.label(screen_title(), 54, UiStyle.GOLD_BRIGHT)
	title_label.name = "Title"
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size = Vector2(0, 80)
	column.add_child(title_label)
	column.add_child(UiStyle.divider())
	column.get_child(column.get_child_count() - 1).custom_minimum_size = Vector2(0, 2)
	_safe_nodes.append([panel, panel.offset_top, panel.offset_bottom])

# ---- helpers for subclasses ------------------------------------------------------------------------

func make_label(text: String, size: int, color: Color, wrap: bool = true) -> Label:
	var label := UiStyle.label(text, size, color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func make_button(text: String, primary: bool, node_name: String, size: int = 38, height: float = 110.0) -> Button:
	var button := UiStyle.button(text, primary, node_name, size)
	button.custom_minimum_size = Vector2(0, height)
	return button
