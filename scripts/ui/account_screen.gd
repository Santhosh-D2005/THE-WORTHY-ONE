class_name AccountScreen
extends OverlayScreen
## The account: logged in or not, the username, a short player id, and LOG OUT / LOG IN. Playing never requires being logged in; logging in
## puts the player's runs into the online Hall of Fame and keeps their progress on the server, so it comes back after a reinstall.
## It says honestly that a forgotten password cannot be reset (there is no email).

signal login_requested

var _status: Label
var _name_label: Label
var _id_label: Label
var _info: Label
var _login_button: Button
var _logout_button: Button
var _delete_button: Button
var _confirm: VBoxContainer
var _confirm_message: Label
var _password: LineEdit
var _confirm_button: Button
var _cancel_button: Button
var _main_nodes: Array = []
var _confirming: bool = false
var _busy: bool = false

func screen_title() -> String:
	return "ACCOUNT"

func _build_content(parent: VBoxContainer) -> void:
	_status = make_label("", 46, UiStyle.GOLD_BRIGHT, false)
	_status.name = "Status"
	parent.add_child(_status)
	_name_label = make_label("", 38, UiStyle.PARCHMENT)
	_name_label.name = "Name"
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(_name_label)
	_id_label = make_label("", 26, UiStyle.PARCHMENT_DIM)
	_id_label.name = "PlayerId"
	parent.add_child(_id_label)
	_info = make_label("", 28, UiStyle.PARCHMENT)
	_info.name = "Info"
	parent.add_child(_info)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)
	_login_button = make_button("LOG IN / CREATE ACCOUNT", true, "LoginButton", 34, 120)
	parent.add_child(_login_button)
	_logout_button = make_button("LOG OUT", false, "LogoutButton", 36, 110)
	parent.add_child(_logout_button)
	_delete_button = make_button("DELETE ACCOUNT", false, "DeleteAccountButton", 30, 100)
	parent.add_child(_delete_button)
	_wire(_delete_button)
	_wire(_login_button)
	_wire(_logout_button)

	# The confirmation: a warning and the password again. Shown instead of the rest of the screen.
	_confirm = VBoxContainer.new()
	_confirm.name = "DeleteConfirm"
	_confirm.visible = false
	_confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_theme_constant_override("separation", 18)
	parent.add_child(_confirm)
	_confirm.add_child(make_label("Delete this account for good?", 40, UiStyle.GOLD_BRIGHT, false))
	_confirm.add_child(make_label("Your progress, your runs and your place in the Hall of Fame are removed from the server. The name becomes free for anyone. This cannot be undone.", 28, UiStyle.PARCHMENT))
	_password = LineEdit.new()
	_password.name = "DeletePassword"
	_password.secret = true
	_password.placeholder_text = "Type your password to confirm"
	_password.max_length = CredentialRules.PASSWORD_MAX_BYTES
	_password.custom_minimum_size = Vector2(0, 100)
	_confirm.add_child(_password)
	_confirm_message = make_label("", 28, UiStyle.CAPTION)
	_confirm_message.name = "DeleteMessage"
	_confirm.add_child(_confirm_message)
	_confirm_button = make_button("DELETE FOREVER", true, "ConfirmDeleteButton", 34, 110)
	_confirm.add_child(_confirm_button)
	_wire(_confirm_button)
	_cancel_button = make_button("CANCEL", false, "CancelDeleteButton", 34, 100)
	_confirm.add_child(_cancel_button)
	_wire(_cancel_button)

	for node in parent.get_children():
		if node != _confirm:
			_main_nodes.append(node)

func _ready() -> void:
	super._ready()
	Account.changed.connect(_refresh)

func _on_opened() -> void:
	_confirming = false
	_password.text = ""
	_confirm_message.text = ""
	_refresh()

func _wire(button: Button) -> void:
	button.pressed.connect(_on_button_pressed.bind(button))

func _refresh() -> void:
	if _status == null:
		return
	if Account.logged_in:
		_status.text = "LOGGED IN"
		_name_label.text = Account.username
		_id_label.text = "PLAYER ID  %s" % Account.player_id.left(8).to_upper()
		_info.text = "Your progress is kept on the server under this name. After a reinstall, log in again to get it back. There is no email, so a forgotten password cannot be reset."
	else:
		_status.text = "NOT LOGGED IN"
		_name_label.text = "Playing on this phone only"
		_id_label.text = ""
		_info.text = "Log in or create an account to save your progress online and to appear in the Hall of Fame. You can keep playing without one."
	var main := not _confirming
	for node in _main_nodes:
		(node as Control).visible = main
	_login_button.visible = main and not Account.logged_in
	_logout_button.visible = main and Account.logged_in
	_delete_button.visible = main and Account.logged_in
	_logout_button.disabled = _busy
	_confirm.visible = _confirming
	_confirm_button.disabled = _busy

func login_button() -> Button:
	return _login_button

func logout_button() -> Button:
	return _logout_button

func info_text() -> String:
	return _info.text

func _on_action(button: Button) -> void:
	if button == _login_button:
		login_requested.emit()
	elif button == _logout_button and not _busy:
		_busy = true
		_refresh()
		await Backend.log_out()
		_busy = false
		_refresh()
	elif button == _delete_button and not _busy:
		_confirming = true
		_confirm_message.text = ""
		_refresh()
	elif button == _cancel_button and not _busy:
		_confirming = false
		_password.text = ""
		_refresh()
	elif button == _confirm_button and not _busy:
		await _delete()

func _delete() -> void:
	var password := _password.text
	if password.is_empty():
		_confirm_message.text = "Type your password to confirm."
		return
	_busy = true
	_confirm_message.text = "Deleting..."
	_refresh()
	var answer: Dictionary = await Backend.delete_account(password)
	_busy = false
	_password.text = ""
	if answer.get("ok", false):
		_confirming = false
		_confirm_message.text = ""
	else:
		_confirm_message.text = CredentialRules.message(str(answer.get("error", "network")), answer)
	_refresh()
