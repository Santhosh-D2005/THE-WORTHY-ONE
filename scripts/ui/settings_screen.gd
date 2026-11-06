class_name SettingsScreen
extends OverlayScreen
## "SETTINGS": the player's options in one panel, in two groups.
##   AUDIO         SOUND (the whole game, ambience included) and SFX (the effects), each in 10 % steps from 0 to 100 %.
##   OPTIMISATION  QUALITY (automatic, high, balanced or low) and FRAME RATE (unlimited, 60 or 30 FPS).
## CREDITS shows the credits as a second page of this same panel (BACK TO SETTINGS returns). One panel only, never a panel on a panel.
## Every button is a plain stepper or a tap target, not a slider: a touch drag is not reliable here (mouse-from-touch is off).
## All values come from the Settings autoload, which saves and applies them. The panel only shows and changes them.
## Opened from the main menu and from the pause menu. Pass `preview_audio` (the screen's GameAudio) so an SFX change plays a short click.

var preview_audio: GameAudio = null

var _settings_page: VBoxContainer
var _credits_page: VBoxContainer
var _sound_value: Label
var _sfx_value: Label
var _quality_button: Button
var _quality_note: Label
var _fps_button: Button
var _buttons_reset: Button
var _credits_button: Button
var _back_button: Button
var _showing_credits: bool = false
var _steppers := {}  # Button -> Callable: the action a stepper's [-] or [+] runs
var _choices := {}   # Button -> Callable: the action a choice button runs

func screen_title() -> String:
	return "SETTINGS"

func _build_content(parent: VBoxContainer) -> void:
	_settings_page = VBoxContainer.new()
	_settings_page.name = "SettingsPage"
	_settings_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_page.add_theme_constant_override("separation", 18)
	parent.add_child(_settings_page)
	_build_settings(_settings_page)

	_credits_page = VBoxContainer.new()
	_credits_page.name = "CreditsPage"
	_credits_page.visible = false
	_credits_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credits_page.add_theme_constant_override("separation", 14)
	parent.add_child(_credits_page)
	CreditsText.build(_credits_page)
	_back_button = make_button("BACK TO SETTINGS", false, "BackButton", 34, 110)
	_credits_page.add_child(_back_button)
	_wire(_back_button)

func _build_settings(parent: VBoxContainer) -> void:
	parent.add_child(_heading("AUDIO"))
	_sound_value = _stepper_row(parent, "SOUND", "SoundRow", func(delta: float) -> void: Settings.set_sound_volume(Settings.sound_volume + delta))
	_sfx_value = _stepper_row(parent, "SFX", "SfxRow", func(delta: float) -> void:
		Settings.set_sfx_volume(Settings.sfx_volume + delta)
		if preview_audio != null:
			preview_audio.play(&"ui_tap"))

	parent.add_child(_heading("OPTIMISATION"))
	_quality_button = _choice_row(parent, "QUALITY", "QualityRow", func() -> void: Settings.cycle_quality())
	_quality_note = make_label("", 26, UiStyle.CAPTION)
	_quality_note.name = "QualityNote"
	parent.add_child(_quality_note)
	_fps_button = _choice_row(parent, "FRAME RATE", "FpsRow", func() -> void: Settings.cycle_fps_cap())

	var caption := make_label("Graphics changes take effect on the next run. Lower frame rates save battery and heat.", 26, UiStyle.CAPTION)
	caption.name = "Caption"
	parent.add_child(caption)

	_buttons_reset = make_button("RESET TO DEFAULTS", false, "ResetButton", 32, 100)
	parent.add_child(_buttons_reset)
	_wire(_buttons_reset)

	_credits_button = make_button("CREDITS", false, "CreditsButton", 32, 100)
	parent.add_child(_credits_button)
	_wire(_credits_button)

func _on_opened() -> void:
	_show_credits(false)
	_refresh()
	if not Settings.changed.is_connected(_refresh):
		Settings.changed.connect(_refresh)

func _refresh() -> void:
	if _sound_value == null:
		return
	_sound_value.text = Settings.percent_text(Settings.sound_volume)
	_sfx_value.text = Settings.percent_text(Settings.sfx_volume)
	_quality_button.text = Settings.quality_text(Settings.quality)
	_quality_note.text = _quality_description(Settings.quality)
	_fps_button.text = Settings.fps_text(Settings.fps_cap)

func _quality_description(value: String) -> String:
	match value:
		"high": return "The full look: shadows, fog and soft lighting at native resolution."
		"balanced": return "The same scene drawn at a lower resolution and upscaled. Smooth on most phones."
		"low": return "The lightest look for weaker or hot devices. Softer textures and shadows."
		_: return "Chooses the setting that suits this device."

func _show_credits(on: bool) -> void:
	_showing_credits = on
	_settings_page.visible = not on
	_credits_page.visible = on
	title_label.text = "CREDITS" if on else "SETTINGS"

func showing_credits() -> bool:
	return _showing_credits

# ---- Back and Escape: the credits page first, the panel after -------------------------------------------

## While the credits page is open, Back and Escape return to the settings page instead of closing the panel.
func _can_close() -> bool:
	return not _showing_credits

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_showing and _showing_credits:
		_show_credits(false)
		return
	super._notification(what)

func _input(event: InputEvent) -> void:
	if is_showing and _showing_credits and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_show_credits(false)
		get_viewport().set_input_as_handled()
		return
	super._input(event)

# ---- Buttons ----------------------------------------------------------------------------------------------

func credits_button() -> Button:
	return _credits_button

func back_button() -> Button:
	return _back_button

func _on_action(button: Button) -> void:
	if _steppers.has(button):
		(_steppers[button] as Callable).call()
	elif _choices.has(button):
		(_choices[button] as Callable).call()
	elif button == _buttons_reset:
		Settings.reset_to_defaults()
		if preview_audio != null:
			preview_audio.play(&"ui_tap")
	elif button == _credits_button:
		_show_credits(true)
	elif button == _back_button:
		_show_credits(false)

## Mouse clicks reach a Button through its pressed signal; touches are handled by OverlayScreen itself (mouse-from-touch is off).
func _wire(button: Button) -> void:
	button.pressed.connect(_on_button_pressed.bind(button))

# ---- Rows -------------------------------------------------------------------------------------------------

func _heading(text: String) -> Label:
	var label := make_label(text, 40, UiStyle.GOLD_BRIGHT, false)
	label.name = "%sHeading" % text.capitalize().replace(" ", "")
	return label

## One row: NAME, the value, then [-] [+]. Returns the value label (refreshed by _refresh).
func _stepper_row(parent: VBoxContainer, title: String, node_name: String, action: Callable) -> Label:
	var row := HBoxContainer.new()
	row.name = node_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var name_label := make_label(title, 32, UiStyle.PARCHMENT, false)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value := make_label("", 32, UiStyle.GOLD_BRIGHT, false)
	value.name = "%sValue" % node_name
	value.custom_minimum_size = Vector2(180, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	var down := make_button("-", false, "%sDown" % node_name, 44, 100)
	down.custom_minimum_size.x = 110
	var up := make_button("+", false, "%sUp" % node_name, 44, 100)
	up.custom_minimum_size.x = 110
	row.add_child(down)
	row.add_child(up)
	_wire(down)
	_wire(up)
	_steppers[down] = func() -> void: action.call(-Settings.STEP)
	_steppers[up] = func() -> void: action.call(Settings.STEP)
	return value

## One row: NAME, then a single button that cycles through its choices. Returns the button.
func _choice_row(parent: VBoxContainer, title: String, node_name: String, action: Callable) -> Button:
	var row := HBoxContainer.new()
	row.name = node_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var name_label := make_label(title, 32, UiStyle.PARCHMENT, false)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var button := make_button("", false, "%sButton" % node_name, 32, 100)
	button.custom_minimum_size.x = 380
	row.add_child(button)
	_choices[button] = action
	_wire(button)
	return button

func steppers() -> Array:
	return _steppers.keys()

func choice_buttons() -> Array:
	return _choices.keys()

func reset_button() -> Button:
	return _buttons_reset
