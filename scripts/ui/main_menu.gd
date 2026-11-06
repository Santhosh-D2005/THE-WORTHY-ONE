class_name MainMenu
extends Node
## Milestone 1.15: the main menu. A quiet shot of the real clearing (the same forest, stump and sword the game uses, one light, no
## gameplay systems) behind a title block and two buttons: PLAY and QUIT.
##
## Built in code like the HUD / failure screen / pause menu, with anchors, so it follows any portrait aspect. It reuses the game's
## font (Cinzel) and its palette: deep forest dark, muted parchment text, amber-gold only for the title accent, the PLAY border and
## the faint glow in the stump's cracks (the 1.12/1.13 shader, held at a low, still level).
##
## TOUCH NOTE: as in FailureScreen / PauseMenu, Godot's Button only reacts to MOUSE events and the project disables
## mouse-from-touch emulation, so the menu also handles InputEventScreenTouch itself (press and release on the same button).
## NAVIGATION: PLAY loads res://scenes/main/main.tscn (LevelManager starts a fresh run in its own _ready); the gameplay scene is
## preloaded on a background thread while the menu is open so the switch is quick. A single `_acted` guard means rapid taps (touch
## AND mouse, or a double tap) can never start two games. QUIT (and Android Back) leaves the application; there is nothing behind
## the menu to go back to.

signal play_pressed
signal quit_pressed

const GAME_SCENE := "res://scenes/main/main.tscn"
const GOLD := UiStyle.GOLD
const GOLD_DIM := UiStyle.GOLD_DIM
const GOLD_BRIGHT := UiStyle.GOLD_BRIGHT
const PARCHMENT := UiStyle.PARCHMENT
## The menu's forest ambience level (dB below the file; the file itself peaks at 0.35). Very quiet.
const AMBIENCE_DB := -23.0
const FADE_IN_SECONDS := 0.9
const FADE_OUT_SECONDS := 0.35
## Presses are ignored until the fade-in is nearly done (a stray tap while the app opens must not start a game).
const INPUT_DELAY_SECONDS := 0.55

## How the PLAY button changes scene / how QUIT leaves. Variables so tests can observe them without leaving the test scene.
var scene_changer: Callable = func(path: String) -> void:
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED else null
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(path)
var app_quitter: Callable = func() -> void: get_tree().quit()

var buttons_ready: bool = false
@onready var _audio: GameAudio = get_node_or_null("Audio") as GameAudio
var _acted: bool = false
var _root: Control
var _fade: ColorRect
var _title_the: Label
var _title_main: Label
var _divider: ColorRect
var _subtitle: Label
var _play_button: Button
var _quit_button: Button
var _touch_press_target: Button = null
var _login_screen: LoginScreen = null
var _modes_button: Button
var _hall_button: Button
var _account_button: Button
var _mode_screen: ModeScreen
var _hall_screen: HallOfFameScreen
var _account_screen: AccountScreen
var _overlay_closed_frame: int = -1
var _tween: Tween
var _camera: Camera3D
var _camera_home := Vector3.ZERO
var _time := 0.0
var _safe_nodes: Array = []  # [control, is_top, base_offset_top, base_offset_bottom]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false  # arriving from a paused game (pause menu -> QUIT) must never leave the menu frozen
	_set_up_stage()
	_build_ui()
	for node in [_title_the, _title_main, _divider, _subtitle]:
		_safe_nodes.append([node, true, node.offset_top, node.offset_bottom])
	for node in [_play_button, _modes_button, _hall_button, _account_button, _quit_button]:
		_safe_nodes.append([node, false, node.offset_top, node.offset_bottom])
	refresh_safe_area()
	get_viewport().size_changed.connect(refresh_safe_area)
	# Warm the gameplay scene on a background thread: pressing PLAY then switches without a long stall.
	if ResourceLoader.exists(GAME_SCENE):
		ResourceLoader.load_threaded_request(GAME_SCENE)
	_login_screen = LoginScreen.new()
	_login_screen.name = "LoginScreen"
	add_child(_login_screen)
	_mode_screen = ModeScreen.new()
	_mode_screen.name = "ModeScreen"
	add_child(_mode_screen)
	_hall_screen = HallOfFameScreen.new()
	_hall_screen.name = "HallOfFameScreen"
	add_child(_hall_screen)
	_account_screen = AccountScreen.new()
	_account_screen.name = "AccountScreen"
	add_child(_account_screen)
	for panel_closed: Signal in [_login_screen.closed, _mode_screen.closed, _hall_screen.closed, _account_screen.closed]:
		panel_closed.connect(func() -> void: _overlay_closed_frame = Engine.get_process_frames())
	_mode_screen.mode_chosen.connect(start_game)
	_mode_screen.hall_requested.connect(func(mode: GameMode.Mode) -> void:
		_mode_screen.close()
		_hall_screen.open_for(mode))
	_account_screen.login_requested.connect(func() -> void:
		_account_screen.close()
		_login_screen.open_login(false))
	if Account.needs_login_prompt():
		_login_screen.open_login(true)  # a fresh install starts by logging in, creating an account, or choosing to play offline
	_fade.color.a = 1.0
	if _audio != null:
		_audio.play_ambience(AMBIENCE_DB, 2.5)  # the forest fades in slowly with the picture
	_tween = create_tween()
	_tween.tween_property(_fade, "color:a", 0.0, FADE_IN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(maxf(0.0, INPUT_DELAY_SECONDS - FADE_IN_SECONDS))
	_tween.tween_callback(func() -> void: buttons_ready = true)

## The 3D backdrop: the game's own clearing. The sword stays embedded; the cracks hold a low, still amber glow.
func _set_up_stage() -> void:
	var stump := get_node_or_null("Stage/Stump") as StumpBuilder
	if stump != null:
		stump.set_cracks(0.55, 0.42)
	_camera = get_node_or_null("Stage/Camera3D") as Camera3D
	if _camera != null:
		_camera_home = _camera.position

## One very slow, very small sideways drift of the camera: depth without any cost (one transform per frame).
func _process(delta: float) -> void:
	if _camera == null:
		return
	_time += delta
	_camera.position = _camera_home + Vector3(sin(_time * 0.35) * 0.10, 0.0, 0.0)

func refresh_safe_area() -> void:
	var insets := SafeArea.insets_in_viewport(get_viewport())
	for entry in _safe_nodes:
		var node: Control = entry[0]
		var shift: float = insets.y if entry[1] else -insets.w
		node.offset_top = entry[2] + shift
		node.offset_bottom = entry[3] + shift

func play_button() -> Button:
	return _play_button

func quit_button() -> Button:
	return _quit_button

func title_labels() -> Array[Label]:
	return [_title_the, _title_main, _subtitle]

# ---- Input -----------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not event is InputEventScreenTouch or overlay_open():
		return
	if event.pressed:
		_touch_press_target = _button_at(event.position) if buttons_ready and not _acted else null
		if _touch_press_target != null:
			_press_feedback(_touch_press_target, true)
			get_viewport().set_input_as_handled()
	else:
		var released_on := _button_at(event.position)
		if _touch_press_target != null:
			_press_feedback(_touch_press_target, false)
		if released_on != null and released_on == _touch_press_target:
			_activate(released_on)
			get_viewport().set_input_as_handled()
		_touch_press_target = null

func _button_at(point: Vector2) -> Button:
	for button in [_play_button, _modes_button, _hall_button, _account_button, _quit_button]:
		if button.get_global_rect().has_point(point):
			return button
	return null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# One Back press reaches every node. If it just closed a panel, it must not also quit the app.
		if overlay_open() or Engine.get_process_frames() == _overlay_closed_frame:
			return
		_activate(_quit_button)  # Android Back on the first screen leaves the app (same guard as the button)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_activate(_quit_button)  # Escape = Back on desktop

func _on_button_pressed(button: Button) -> void:
	_activate(button)

## The single place where a press becomes an action. Guarded against double activation (touch + mouse, double taps, Back during the
## launch) and against presses before the menu is interactive.
## True while the guest notice is on screen: the menu behind it is inert.
func login_open() -> bool:
	return _login_screen != null and _login_screen.is_showing

## True while any panel (login, modes, Hall of Fame, account) is on screen: the menu behind it is inert.
func overlay_open() -> bool:
	for screen in [_login_screen, _mode_screen, _hall_screen, _account_screen]:
		if screen != null and screen.is_showing:
			return true
	return false

func modes_button() -> Button:
	return _modes_button

func hall_button() -> Button:
	return _hall_button

func account_button() -> Button:
	return _account_button

func mode_screen() -> ModeScreen:
	return _mode_screen

func hall_screen() -> HallOfFameScreen:
	return _hall_screen

func account_screen() -> AccountScreen:
	return _account_screen

## Begin a run in `mode` (chosen on the mode screen). Goes through the same guarded path as PLAY.
func start_game(mode: GameMode.Mode) -> void:
	Progress.selected_mode = mode
	_mode_screen.close()
	_activate(_play_button)

func login_screen() -> LoginScreen:
	return _login_screen

func _activate(button: Button) -> void:
	if _acted or not buttons_ready or overlay_open():
		return
	if button == _modes_button or button == _hall_button or button == _account_button:
		if _audio != null:
			_audio.play(&"ui_tap")
		if button == _modes_button:
			_mode_screen.open()
		elif button == _hall_button:
			_hall_screen.open_for(Progress.selected_mode)
		else:
			_account_screen.open()
		return
	_acted = true
	if _audio != null:
		_audio.play(&"ui_play" if button == _play_button else &"ui_tap")
		_audio.stop_ambience(FADE_OUT_SECONDS)  # the forest fades out with the screen
	if button == _play_button:
		play_pressed.emit()
		_fade_out_then(func() -> void: scene_changer.call(GAME_SCENE))
	else:
		quit_pressed.emit()
		_fade_out_then(func() -> void: app_quitter.call())

func _fade_out_then(action: Callable) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_fade, "color:a", 1.0, FADE_OUT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(action)

## A short, lightweight touch response: the button dips a few percent while a finger is on it.
func _press_feedback(button: Button, down: bool) -> void:
	button.pivot_offset = button.size * 0.5
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(0.97, 0.97) if down else Vector2.ONE, 0.08)

# ---- Construction ----------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Ui"
	layer.layer = 10
	add_child(layer)
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_root)

	_root.add_child(UiStyle.scrim("TopScrim", true, 720, 0.82))
	_root.add_child(UiStyle.scrim("BottomScrim", false, 760, 0.85))

	_title_the = _make_label("THE", 62, GOLD)
	_title_the.name = "TitleThe"
	_title_the.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title_the.offset_top = 190
	_title_the.offset_bottom = 270
	_title_the.add_theme_constant_override("outline_size", 0)
	_root.add_child(_title_the)

	_title_main = _make_label("WORTHY ONE", 112, PARCHMENT)
	_title_main.name = "TitleMain"
	_title_main.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title_main.offset_top = 262
	_title_main.offset_bottom = 410
	_root.add_child(_title_main)

	_divider = UiStyle.divider()
	_divider.offset_top = 432
	_divider.offset_bottom = 434
	_root.add_child(_divider)

	_subtitle = _make_label("One sword. One tree. One challenge.", 34, Color(0.93, 0.90, 0.82, 0.78))
	_subtitle.name = "Subtitle"
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_subtitle.offset_top = 458
	_subtitle.offset_bottom = 520
	_root.add_child(_subtitle)

	_play_button = _make_button("PLAY", true, "PlayButton", 56)
	_play_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_play_button.offset_left = -310
	_play_button.offset_right = 310
	_play_button.offset_top = -540
	_play_button.offset_bottom = -400
	_root.add_child(_play_button)
	_play_button.pressed.connect(_on_button_pressed.bind(_play_button))

	_quit_button = _make_button("QUIT", false, "QuitButton", 38)
	_quit_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_quit_button.offset_left = -200
	_quit_button.offset_right = 200
	_quit_button.offset_top = -240
	_quit_button.offset_bottom = -130
	_root.add_child(_quit_button)
	_quit_button.pressed.connect(_on_button_pressed.bind(_quit_button))

	# The three secondary doors, in one row between PLAY and QUIT.
	var row_specs := [["MODES", "ModesButton", -470, -170], ["HALL OF FAME", "HallButton", -150, 150], ["ACCOUNT", "AccountButton", 170, 470]]
	for spec in row_specs:
		var small := _make_button(spec[0], false, spec[1], 30)
		small.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		small.offset_left = spec[2]
		small.offset_right = spec[3]
		small.offset_top = -370
		small.offset_bottom = -270
		_root.add_child(small)
		small.pressed.connect(_on_button_pressed.bind(small))
		match spec[1]:
			"ModesButton": _modes_button = small
			"HallButton": _hall_button = small
			_: _account_button = small

	# On top of everything: the fade from / to black.
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_fade)

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := UiStyle.label(text, font_size, color)
	label.add_theme_font_override("font", _title_font())  # the menu's display lettering is a little more open than the body text
	label.add_theme_constant_override("shadow_offset_y", 4)
	return label

var _wide_font: FontVariation = null
func _title_font() -> FontVariation:
	if _wide_font == null:
		_wide_font = FontVariation.new()
		_wide_font.base_font = UiStyle.font().base_font
		_wide_font.spacing_glyph = 5
	return _wide_font

func _make_button(text: String, primary: bool, node_name: String, font_size: int) -> Button:
	var button := UiStyle.button(text, primary, node_name, font_size)
	button.size_flags_horizontal = Control.SIZE_FILL
	return button
