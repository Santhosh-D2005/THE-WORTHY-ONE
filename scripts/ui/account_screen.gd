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

func _ready() -> void:
	super._ready()
	Account.changed.connect(_refresh)

func _on_opened() -> void:
	_refresh()

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
	_login_button.visible = not Account.logged_in
	_logout_button.visible = Account.logged_in
	_logout_button.disabled = _busy

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
