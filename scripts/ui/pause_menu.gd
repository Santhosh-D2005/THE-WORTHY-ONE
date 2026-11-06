class_name PauseMenu
extends CanvasLayer
## The pause menu opened by Android Back: PAUSED, RESUME (primary), MAIN MENU (secondary). Pure presentation - it only emits
## signals; LevelManager decides what resuming / leaving does. (The signal and accessor are still called quit_* so the wiring and the tests
## stay valid; since Milestone 1.15 that action returns to the main menu, and since 1.16 the button says so.)
## While visible it swallows every press (so no tap can reach gameplay or the "tap to resume"
## shortcut used after losing app focus), and ignores presses for a short moment after opening so
## a player who is still tapping cannot hit RESUME or MAIN MENU by accident.
## Touch: like FailureScreen, it handles InputEventScreenTouch itself because mouse emulation is off.
## Look (1.16): all styling comes from UiStyle - a darkened clearing with a soft vignette, an amber PAUSED heading with its divider, and the
## same two buttons as every other screen.

signal resume_requested
signal quit_requested

const LEAVE_TEXT := "MAIN MENU"
const CONFIRM_TEXT := "LEAVE THIS RUN?"
## Presses are ignored for this long after the menu opens (real time; the game tree is paused).
const INPUT_DELAY_MSEC := 350

var is_showing: bool = false
## When true, the first MAIN MENU press only asks "LEAVE THIS RUN?"; the second one leaves.
var confirm_before_quit: bool = false
var awaiting_confirmation: bool = false

var _root: Control
var _resume_button: Button
var _settings_button: Button
var _quit_button: Button
var _settings: SettingsScreen
var _settings_closed_frame: int = -1
var _opened_msec: int = 0
var _press_target: Button = null

func _ready() -> void:
	layer = 20  # above the HUD (10) and failure screen (15)
	process_mode = Node.PROCESS_MODE_ALWAYS  # the tree is paused while this is open
	_build()
	_settings = SettingsScreen.new()
	_settings.name = "SettingsScreen"
	add_child(_settings)
	_settings.closed.connect(func() -> void: _settings_closed_frame = Engine.get_process_frames())
	visible = false

func show_menu(confirm_quit: bool = false) -> void:
	confirm_before_quit = confirm_quit
	awaiting_confirmation = false
	_quit_button.text = LEAVE_TEXT
	_opened_msec = Time.get_ticks_msec()
	is_showing = true
	visible = true

func hide_menu() -> void:
	is_showing = false
	visible = false
	awaiting_confirmation = false
	_press_target = null

func is_interactive() -> bool:
	return is_showing and Time.get_ticks_msec() - _opened_msec >= INPUT_DELAY_MSEC

func resume_button() -> Button:
	return _resume_button

func quit_button() -> Button:
	return _quit_button

func settings_button() -> Button:
	return _settings_button

func settings_screen() -> SettingsScreen:
	return _settings

## The GameAudio of the level, so the settings panel can play its SFX preview click.
func set_preview_audio(audio: GameAudio) -> void:
	_settings.preview_audio = audio

## True while the settings panel is open, or closed during this very frame: Android Back then belongs to the panel (closing it),
## and must not also resume the game behind it. (The panel is a child of this node and sees the Back request first.)
func back_belongs_to_settings() -> bool:
	return _settings.is_showing or Engine.get_process_frames() == _settings_closed_frame

# ---- Input -----------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_showing:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press_target = _button_at(event.position) if is_interactive() else null
		else:
			var released_on := _button_at(event.position)
			if released_on != null and released_on == _press_target:
				_activate(released_on)
			_press_target = null
		get_viewport().set_input_as_handled()  # nothing behind the menu may react
	elif event is InputEventMouseButton:
		# Mouse clicks reach the Buttons through the GUI; just keep them away from everything else.
		if event.pressed and not is_interactive():
			get_viewport().set_input_as_handled()

func _button_at(point: Vector2) -> Button:
	for button in [_resume_button, _settings_button, _quit_button]:
		if button.get_global_rect().has_point(point):
			return button
	return null

func _on_button_pressed(button: Button) -> void:
	_activate(button)

func _activate(button: Button) -> void:
	if not is_interactive():
		return
	if button == _resume_button:
		resume_requested.emit()
	elif button == _settings_button:
		_settings.open()
	elif confirm_before_quit and not awaiting_confirmation:
		awaiting_confirmation = true
		_quit_button.text = CONFIRM_TEXT
		_opened_msec = Time.get_ticks_msec()  # brief guard so a double press cannot confirm
	else:
		quit_requested.emit()

# ---- Construction ----------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# The darkened clearing: a flat dim, a vignette and two soft bands (the stump stays faintly visible behind the buttons).
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.01, 0.0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_root.add_child(UiStyle.vignette())
	_root.add_child(UiStyle.scrim("TopScrim", true, 700, 0.5))
	_root.add_child(UiStyle.scrim("BottomScrim", false, 700, 0.5))

	var title := UiStyle.label("PAUSED", UiStyle.SIZE_HEADING, UiStyle.GOLD_BRIGHT)
	title.name = "Title"
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = 0.28
	title.anchor_bottom = 0.28
	title.offset_top = -60
	title.offset_bottom = 60
	_root.add_child(title)

	var divider := UiStyle.divider()
	divider.anchor_top = 0.28
	divider.anchor_bottom = 0.28
	divider.offset_top = 76
	divider.offset_bottom = 78
	_root.add_child(divider)

	var box := VBoxContainer.new()
	box.name = "Buttons"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 36)
	box.anchor_left = 0.14
	box.anchor_right = 0.86
	box.anchor_top = 0.42
	box.anchor_bottom = 0.42
	box.offset_top = 0
	box.offset_bottom = UiStyle.BUTTON_HEIGHT_PRIMARY + 36.0 + UiStyle.BUTTON_HEIGHT + 36.0 + UiStyle.BUTTON_HEIGHT
	_root.add_child(box)
	_resume_button = UiStyle.button("RESUME", true, "ResumeButton")
	_quit_button = UiStyle.button(LEAVE_TEXT, false, "QuitButton")
	_settings_button = UiStyle.button("SETTINGS", false, "SettingsButton")
	box.add_child(_resume_button)
	box.add_child(_settings_button)
	box.add_child(_quit_button)
	_resume_button.pressed.connect(_on_button_pressed.bind(_resume_button))
	_settings_button.pressed.connect(_on_button_pressed.bind(_settings_button))
	_quit_button.pressed.connect(_on_button_pressed.bind(_quit_button))
