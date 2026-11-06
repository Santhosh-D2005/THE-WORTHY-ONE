class_name LoginScreen
extends OverlayScreen
## Log in / Create account. Shown by itself on the first launch (then it cannot be dismissed except with "PLAY OFFLINE FOR NOW", and Back does
## nothing), and opened from the account screen later (then it has CLOSE). The username and password are checked here with CredentialRules for
## instant feedback and again by the server. The password lives only in the text box until the call is made; it is wiped on success and
## never stored, logged or emitted.
## There is no email, so a forgotten password cannot be reset: the screen says so before the player creates an account.

signal finished   ## the player is logged in, or chose to play offline

## (register: bool, username: String, password: String) -> Dictionary (a coroutine). Tests replace it.
var authenticator: Callable = func(register: bool, username: String, password: String) -> Dictionary:
	if register:
		return await Backend.register_account(username, password)
	return await Backend.log_in(username, password)

var required: bool = false
var register_mode: bool = false
var busy: bool = false

var _tab_login: Button
var _tab_register: Button
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _confirm_caption: Label
var _confirm_edit: LineEdit
var _message: Label
var _note: Label
var _submit: Button
var _skip: Button

func screen_title() -> String:
	return "WELCOME"

func _build_content(parent: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_theme_constant_override("separation", 16)
	parent.add_child(tabs)
	_tab_login = make_button("LOG IN", false, "TabLogin", 34, 100)
	_tab_register = make_button("CREATE ACCOUNT", false, "TabRegister", 30, 100)
	tabs.add_child(_tab_login)
	tabs.add_child(_tab_register)
	_user_edit = _field(parent, "USERNAME", "UsernameEdit", false)
	_pass_edit = _field(parent, "PASSWORD", "PasswordEdit", true)
	_confirm_caption = make_label("CONFIRM PASSWORD", 24, UiStyle.CAPTION, false)
	parent.add_child(_confirm_caption)
	_confirm_edit = _edit("ConfirmEdit", true)
	parent.add_child(_confirm_edit)
	_message = make_label("", 28, UiStyle.GOLD_BRIGHT)
	_message.name = "Message"
	_message.custom_minimum_size = Vector2(0, 80)
	parent.add_child(_message)
	_note = make_label("", 26, UiStyle.PARCHMENT_DIM)
	_note.name = "Note"
	parent.add_child(_note)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)
	_submit = make_button("LOG IN", true, "SubmitButton", 40, 120)
	parent.add_child(_submit)
	_skip = make_button("PLAY OFFLINE FOR NOW", false, "SkipButton", 30, 100)
	parent.add_child(_skip)
	for edit in [_user_edit, _pass_edit, _confirm_edit]:
		edit.text_submitted.connect(func(_text: String) -> void: _submit_form())

func _field(parent: VBoxContainer, caption: String, node_name: String, secret: bool) -> LineEdit:
	parent.add_child(make_label(caption, 24, UiStyle.CAPTION, false))
	var edit := _edit(node_name, secret)
	parent.add_child(edit)
	return edit

func _edit(node_name: String, secret: bool) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = node_name
	edit.secret = secret
	edit.max_length = 72 if secret else CredentialRules.USERNAME_MAX
	edit.custom_minimum_size = Vector2(0, 90)
	edit.add_theme_font_override("font", UiStyle.font())
	edit.add_theme_font_size_override("font_size", 34)
	edit.context_menu_enabled = false
	edit.caret_blink = true
	return edit

## first launch: required = true (no CLOSE, Back does nothing, "play offline" offered).
func open_login(is_required: bool, start_in_register_mode: bool = false) -> void:
	required = is_required
	register_mode = start_in_register_mode
	open()

func _on_opened() -> void:
	_user_edit.text = ""
	_pass_edit.text = ""
	_confirm_edit.text = ""
	busy = false
	_apply_mode()

func _can_close() -> bool:
	return not required and not busy

func _apply_mode() -> void:
	close_button.visible = not required
	_skip.visible = required
	_confirm_caption.visible = register_mode
	_confirm_edit.visible = register_mode
	_submit.text = "CREATE ACCOUNT" if register_mode else "LOG IN"
	_submit.disabled = busy
	_tab_login.modulate = Color(1, 1, 1, 0.5 if register_mode else 1.0)
	_tab_register.modulate = Color(1, 1, 1, 1.0 if register_mode else 0.5)
	_message.text = ""
	_note.text = "There is no email, so a forgotten password cannot be reset. Choose one you will remember. Your progress is kept on the server under this name." if register_mode \
		else "Log in with the username and password you created. After a reinstall, logging in brings your progress back."

func set_register_mode(value: bool) -> void:
	if busy:
		return
	register_mode = value
	_apply_mode()

func submit_button() -> Button:
	return _submit

func skip_button() -> Button:
	return _skip

func tab_login() -> Button:
	return _tab_login

func tab_register() -> Button:
	return _tab_register

func username_edit() -> LineEdit:
	return _user_edit

func password_edit() -> LineEdit:
	return _pass_edit

func confirm_edit() -> LineEdit:
	return _confirm_edit

func message_text() -> String:
	return _message.text

func note_text() -> String:
	return _note.text

func _on_action(button: Button) -> void:
	if button == _tab_login:
		set_register_mode(false)
	elif button == _tab_register:
		set_register_mode(true)
	elif button == _submit:
		_submit_form()
	elif button == _skip:
		Account.skip_login()
		finished.emit()
		close()

func _submit_form() -> void:
	if busy or not is_showing:
		return
	var username := _user_edit.text.strip_edges()
	var password := _pass_edit.text
	if not register_mode and (username.is_empty() or password.is_empty()):
		_message.text = "Enter your username and password."
		return
	if register_mode:
		var problem := CredentialRules.username_error(username)
		if problem == "":
			problem = CredentialRules.password_error(password, username)
		if problem == "" and password != _confirm_edit.text:
			problem = "pw_mismatch"
		if problem != "":
			_message.text = CredentialRules.message(problem)
			return
	busy = true
	_submit.disabled = true
	_message.text = "Please wait..."
	var reply: Dictionary = await authenticator.call(register_mode, username, password)
	busy = false
	_submit.disabled = false
	if not is_showing:
		return
	if reply.get("ok", false):
		_pass_edit.text = ""
		_confirm_edit.text = ""
		finished.emit()
		required = false
		close()
	else:
		_message.text = CredentialRules.message(str(reply.get("error", "network")), reply)
