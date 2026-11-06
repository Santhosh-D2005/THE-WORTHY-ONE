extends Node
## Accounts (username + password): (1) the credential rules, checked against the SAME fixture files the server tests use, (2) what the device
## remembers (encrypted, never the password) and what log out forgets, (3) the login screen on the real main menu: first-launch behaviour,
## validation, success / failure messages, double taps, "play offline", the tabs, layout at several screen shapes.
## Run headless:   godot --headless --path . res://tests/account_tests.tscn
## DESKTOP, SIMULATED INPUT, NO NETWORK (the login call is replaced by a scripted function). Uses its own account files.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const TMP := "user://account_test.dat"
const UID := "11111111-2222-4333-8444-555555555555"

var _checks := 0
var _failures := 0

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(540, 960)
	await get_tree().process_frame
	_t_rules()
	_t_account()
	await _t_login_screen()
	_cleanup()
	Account.reset_for_test(Account.TEST_FILE_PATH)
	Account.login_skipped = true
	get_window().size = Vector2i(540, 960)
	print("\n==== %d checks, %d failed ====" % [_checks, _failures])
	print("RESULT: ALL PASSED" if _failures == 0 else "RESULT: FAILURES")
	get_tree().quit(0 if _failures == 0 else 1)

func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func _cleanup() -> void:
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(TMP + suffix):
			DirAccess.remove_absolute(TMP + suffix)

# ---- 1. the rules ---------------------------------------------------------------------------------------------------------

func _t_rules() -> void:
	print("\n[1] CREDENTIAL RULES (same fixtures as the server tests)")
	var names: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://server/username_fixtures.json"))
	var wrong := 0
	for entry in names:
		var got := CredentialRules.username_error(str(entry[0]))
		var want := "" if entry[1] == null else str(entry[1])
		if got != want:
			wrong += 1
			print("     username mismatch: ", JSON.stringify(entry[0]), " server=", want, " game=", got)
	_check(names is Array and (names as Array).size() >= 25 and wrong == 0, "the game agrees with the server on all %d username fixtures (%d disagreements)" % [(names as Array).size(), wrong])
	var passwords: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://server/password_fixtures.json"))
	wrong = 0
	for entry in passwords:
		var got := CredentialRules.password_error(str(entry[0]), str(entry[1]))
		var want := "" if entry[2] == null else str(entry[2])
		if got != want:
			wrong += 1
			print("     password mismatch for length ", str(entry[0]).length(), ": server=", want, " game=", got)
	_check(passwords is Array and (passwords as Array).size() >= 10 and wrong == 0, "...and on all %d password fixtures (%d disagreements)" % [(passwords as Array).size(), wrong])
	var every_code := ["too_short", "too_long", "bad_start", "bad_character", "reserved", "not_allowed", "pw_too_short", "pw_too_long", "pw_same_as_username", "pw_too_common", "pw_mismatch", "username_taken", "wrong_credentials", "rate_limited", "already_logged_in", "offline", "timeout", "network", "locked"]
	var all_have := true
	for code in every_code:
		if CredentialRules.message(code, {"wait_seconds": 600}).begins_with("Something went wrong"):
			all_have = false
	_check(all_have, "every rule and server error code has its own plain message")
	_check(CredentialRules.message("locked", {"wait_seconds": 600}).contains("10 minutes") and CredentialRules.message("locked", {"wait_seconds": 30}).contains("1 minute."), "the lock message says how many minutes to wait")
	_check(CredentialRules.message("weird_code").contains("weird_code"), "an unknown code still gets a safe message")

# ---- 2. what the device remembers --------------------------------------------------------------------------------------------

func _t_account() -> void:
	print("\n[2] WHAT THE DEVICE REMEMBERS")
	_cleanup()
	Account.reset_for_test(TMP)
	_check(not Account.logged_in and Account.username == "" and Account.needs_login_prompt(), "a fresh install is not logged in and wants the login prompt")
	Account.store_session(UID, "refresh-secret-1")
	Account.set_logged_in("99999999-8888-4777-8666-555555555555", "Sir_Kay")
	_check(Account.logged_in and Account.username == "Sir_Kay" and not Account.needs_login_prompt() and Account.persisted, "logging in is remembered")
	var raw := FileAccess.get_file_as_bytes(TMP).hex_encode()
	_check(not raw.contains("Sir_Kay".to_utf8_buffer().hex_encode()) and not raw.contains("refresh-secret-1".to_utf8_buffer().hex_encode()) and not raw.contains("username".to_utf8_buffer().hex_encode()), "the file is not readable text (no username, no credential, no key names)")
	var saved := AccountStore.new(TMP).read()
	var has_password_key := false
	for key in saved:
		if str(key).to_lower().contains("password") or str(saved[key]).to_lower().contains("password"):
			has_password_key = true
	_check(not has_password_key, "there is no password field anywhere in what is saved")
	var reloaded: Node = load("res://scripts/core/account.gd").new()
	reloaded.store = AccountStore.new(TMP)
	reloaded.load_data()
	_check(reloaded.logged_in and reloaded.username == "Sir_Kay" and reloaded.refresh_token == "refresh-secret-1" and reloaded.player_id.begins_with("99999999"), "after a restart the same account is still logged in")
	_check(not str(Account.public_info()).contains("refresh-secret-1") and not Account.public_info().has("refresh_token"), "the public profile never contains the session credential")
	# a different anonymous session = not logged in any more
	Account.store_session("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", "refresh-new")
	_check(not Account.logged_in and Account.username == "Sir_Kay", "a brand-new app session is not logged in (the player must log in again; the account lives on the server)")
	Account.set_logged_in("99999999-8888-4777-8666-555555555555", "Sir_Kay")
	Account.mark_logged_out()
	_check(not Account.logged_in, "the server saying 'not logged in' is remembered")
	Account.set_logged_in("99999999-8888-4777-8666-555555555555", "Sir_Kay")
	Account.clear_login()
	var after := AccountStore.new(TMP).read()
	_check(not Account.logged_in and Account.username == "" and Account.refresh_token == "" and str(after.get("refresh_token", "")) == "" and str(after.get("username", "")) == "", "logging out forgets the account AND the session, on disk too")
	reloaded.free()
	Account.skip_login()
	var skipped: Node = load("res://scripts/core/account.gd").new()
	skipped.store = AccountStore.new(TMP)
	skipped.load_data()
	_check(skipped.login_skipped and not skipped.needs_login_prompt(), "'play offline for now' is remembered, so the prompt does not nag")
	skipped.free()
	var other_device := FileAccess.open_encrypted_with_pass(TMP, FileAccess.READ, "some other key")
	_check(other_device == null, "the file cannot be opened with another device's key")

# ---- 3. the login screen ------------------------------------------------------------------------------------------------------

var _calls: Array = []
var _next_reply: Dictionary = {"ok": true}

func _auth(register: bool, username: String, password: String) -> Dictionary:
	_calls.append([register, username, password])
	await get_tree().create_timer(0.15).timeout
	return _next_reply

func _tap(target: Node, button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var down := InputEventScreenTouch.new()
	down.position = point
	down.pressed = true
	target._input(down)
	var up := InputEventScreenTouch.new()
	up.position = point
	up.pressed = false
	target._input(up)

func _open_menu(fresh: bool) -> MainMenu:
	Account.reset_for_test(TMP)
	if not fresh:
		Account.skip_login()
	var menu: MainMenu = load(MENU_SCENE).instantiate()
	add_child(menu)
	await _wait(1.0)
	return menu

func _t_login_screen() -> void:
	print("\n[3] THE LOGIN SCREEN")
	var menu := await _open_menu(true)
	var login := menu.login_screen()
	login.authenticator = _auth
	var changes: Array = []
	var quits: Array = []
	menu.scene_changer = func(path: String) -> void: changes.append(path)
	menu.app_quitter = func() -> void: quits.append(true)
	_check(login.is_showing and login.required and menu.login_open(), "a fresh install opens the login screen by itself")
	_check(not login.close_button.visible and login.skip_button().visible and login.skip_button().text == "PLAY OFFLINE FOR NOW", "first launch: no CLOSE, but 'PLAY OFFLINE FOR NOW'")
	_check(login.password_edit().secret and not login.username_edit().secret and login.confirm_edit().secret, "the password boxes hide what is typed; the username box does not")
	_tap(menu, menu.play_button())
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait(0.4)
	_check(changes.is_empty() and quits.is_empty() and login.is_showing, "behind the login screen PLAY does nothing, and Android Back neither closes it nor quits the app")
	# the tabs
	_check(login.submit_button().text == "LOG IN" and not login.confirm_edit().visible and login.note_text().contains("brings your progress back"), "the LOG IN tab: one password box")
	_tap(login, login.tab_register())
	await _wait(0.1)
	_check(login.register_mode and login.confirm_edit().visible and login.submit_button().text == "CREATE ACCOUNT", "the CREATE ACCOUNT tab: a confirm box and its own button")
	_check(login.note_text().contains("cannot be reset") and login.note_text().contains("no email"), "...and it says plainly that a forgotten password cannot be reset")
	# validation: nothing is sent for bad input
	var cases := [
		["1bad", "Correct-Horse-7", "Correct-Horse-7", "must start with a letter"],
		["ab", "Correct-Horse-7", "Correct-Horse-7", "at least 3"],
		["Admin", "Correct-Horse-7", "Correct-Horse-7", "reserved"],
		["Good_Name", "short", "short", "at least 8"],
		["Good_Name", "password123", "password123", "easy to guess"],
		["Good_Name", "Correct-Horse-7", "Correct-Horse-8", "not the same"],
		["Good_Name", "Good_Name", "Good_Name", "cannot be your username"],
	]
	for case in cases:
		login.username_edit().text = case[0]
		login.password_edit().text = case[1]
		login.confirm_edit().text = case[2]
		_tap(login, login.submit_button())
		await _wait(0.05)
		_check(login.message_text().contains(case[3]) and _calls.is_empty(), "'%s' / '%s...' is refused on the phone with: %s (nothing sent)" % [case[0], str(case[1]).left(6), login.message_text().left(40)])
	# server answers
	login.username_edit().text = "Taken_Name"
	login.password_edit().text = "Correct-Horse-7"
	login.confirm_edit().text = "Correct-Horse-7"
	for pair in [[{"ok": false, "error": "username_taken"}, "already taken"], [{"ok": false, "error": "offline"}, "offline"], [{"ok": false, "error": "rate_limited"}, "Too many new accounts"], [{"ok": false, "error": "http_500"}, "http_500"]]:
		_next_reply = pair[0]
		_calls.clear()
		_tap(login, login.submit_button())
		await _wait(0.4)
		_check(login.message_text().contains(pair[1]) and _calls.size() == 1 and login.is_showing and login.username_edit().text == "Taken_Name", "server answer %s -> '%s' (the screen stays open, the username is kept)" % [str(pair[0]), login.message_text().left(40)])
	# the login tab and its answers
	_tap(login, login.tab_login())
	await _wait(0.1)
	login.username_edit().text = ""
	login.password_edit().text = ""
	_calls.clear()
	_tap(login, login.submit_button())
	await _wait(0.05)
	_check(login.message_text().contains("Enter your username and password") and _calls.is_empty(), "logging in with empty boxes asks for both (nothing sent)")
	login.username_edit().text = "Sir_Kay"
	login.password_edit().text = "Wrong-Password-1"
	_next_reply = {"ok": false, "error": "wrong_credentials"}
	_tap(login, login.submit_button())
	await _wait(0.4)
	_check(login.message_text() == "Wrong username or password.", "a wrong login says only 'Wrong username or password.' (never which of the two was wrong)")
	_next_reply = {"ok": false, "error": "locked", "wait_seconds": 600}
	_tap(login, login.submit_button())
	await _wait(0.4)
	_check(login.message_text().contains("10 minutes"), "a locked username shows how long to wait")
	# double tap sends one request
	_calls.clear()
	_next_reply = {"ok": false, "error": "wrong_credentials"}
	_tap(login, login.submit_button())
	_tap(login, login.submit_button())
	login._submit_form()
	await _wait(0.5)
	_check(_calls.size() == 1, "tapping the button several times at once sends ONE request")
	# success
	var finished: Array = []
	login.finished.connect(func() -> void: finished.append(true))
	_next_reply = {"ok": true}
	_calls.clear()
	login.password_edit().text = "Correct-Horse-7"
	_tap(login, login.submit_button())
	await _wait(0.5)
	_check(_calls.size() == 1 and _calls[0][0] == false and _calls[0][1] == "Sir_Kay" and _calls[0][2] == "Correct-Horse-7", "a good login calls the authenticator with the mode, username and password")
	_check(finished.size() == 1 and not login.is_showing and login.password_edit().text == "" and login.confirm_edit().text == "", "success closes the screen once and wipes both password boxes")
	await _close_menu(menu)
	# play offline
	menu = await _open_menu(true)
	login = menu.login_screen()
	_tap(login, login.skip_button())
	await _wait(0.2)
	_check(not login.is_showing and Account.login_skipped and not Account.needs_login_prompt() and not Account.logged_in, "PLAY OFFLINE FOR NOW closes the screen and is remembered")
	await _close_menu(menu)
	menu = await _open_menu(false)
	_check(not menu.login_open(), "a player who chose offline is not interrupted again")
	await _close_menu(menu)
	# opened later, dismissible
	menu = await _open_menu(false)
	login = menu.login_screen()
	login.open_login(false)
	await _wait(0.9)
	_check(login.close_button.visible and not login.skip_button().visible, "opened from the account screen it has CLOSE and no 'play offline'")
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	_check(not login.is_showing and not menu._acted, "...and Android Back closes it without quitting the app")
	await _close_menu(menu)
	# layout
	for size in [Vector2i(540, 960), Vector2i(450, 1000), Vector2i(600, 800), Vector2i(400, 1000)]:
		get_window().size = size
		await _wait(0.2)
		menu = await _open_menu(true)
		login = menu.login_screen()
		login.set_register_mode(true)
		await _wait(0.2)
		var column: Control = login.column
		var viewport := get_viewport().get_visible_rect()
		var fits := column.get_combined_minimum_size().y <= column.size.y + 1.0 and viewport.encloses(login.panel.get_global_rect().grow(-1.0))
		var buttons_ok := true
		for node in login.panel.find_children("*", "Button", true, false):
			var button := node as Button
			if button.is_visible_in_tree() and (not viewport.encloses(button.get_global_rect()) or button.get_global_rect().size.y < 90.0):
				buttons_ok = false
		_check(fits and buttons_ok, "at %dx%d the sign-up form fits (content %.0f of %.0f px) with 90+ px buttons on screen" % [size.x, size.y, column.get_combined_minimum_size().y, column.size.y])
		await _close_menu(menu)
	get_window().size = Vector2i(540, 960)

func _close_menu(menu: MainMenu) -> void:
	menu.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
