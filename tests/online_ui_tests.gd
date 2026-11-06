extends Node
## Phases 6/7: menu navigation, mode selection, both Hall of Fame boards, the account screen and the result screen's online status.
## NO LIVE NETWORK: the Hall of Fame gets a scripted data source, Backend.transport is replaced by a guard that fails the test if anything
## reaches it unexpectedly, and RunSync is disabled in headless runs. Simulated touches only (nothing here proves behaviour on a phone).
## Run headless:   godot --headless --path . res://tests/online_ui_tests.tscn

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const FAILURE_SCENE := "res://scenes/ui/failure_screen.tscn"
const ACC := "user://online_ui_test_account.dat"
const UID := "11111111-2222-4333-8444-555555555555"

class Gate extends RefCounted:
	signal done
	var reply: Dictionary = {}
	var asked_mode: int = -1
	var asked_offset: int = -1

var _checks := 0
var _failures := 0
var forbidden_calls := 0
var scripted: Array[Dictionary] = []   # requests that reached the (fake) transport while it was allowed
var transport_allowed := false
var _answers: Dictionary = {}
var pending: Array[Gate] = []
var fetch_log: Array = []

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
	var saved_transport: Callable = Backend.transport
	Backend.transport = _transport
	_check(not RunSync.enabled, "RunSync is disabled in headless runs (no run reports leave the machine)")
	await _t_menu()
	await _t_hall()
	await _t_account()
	await _t_result()
	await _t_layout()
	_check(forbidden_calls == 0, "no test reached the network unexpectedly (%d forbidden calls)" % forbidden_calls)
	Backend.transport = saved_transport
	Backend.access_token = ""
	if FileAccess.file_exists(ACC):
		DirAccess.remove_absolute(ACC)
	Account.reset_for_test(Account.TEST_FILE_PATH)
	Account.login_skipped = true
	get_window().size = Vector2i(540, 960)
	print("\n==== %d checks, %d failed ====" % [_checks, _failures])
	print("RESULT: ALL PASSED" if _failures == 0 else "RESULT: FAILURES")
	get_tree().quit(0 if _failures == 0 else 1)

# ---- helpers ------------------------------------------------------------------------------------------------------------

func _transport(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	if not transport_allowed:
		forbidden_calls += 1
		print("     (forbidden network call: ", url.trim_prefix(BackendConfig.URL), ")")
		return {"status": 0, "body": "", "error": "offline"}
	var path := url.trim_prefix(BackendConfig.URL)
	scripted.append({"method": method, "path": path, "headers": headers, "body": body})
	for fragment: String in _answers:
		if path.contains(fragment):
			return _answers[fragment]
	return {"status": 404, "body": "{}", "error": ""}

func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

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

func _open_menu() -> MainMenu:
	Account.reset_for_test(ACC)
	Account.skip_login()   # these tests are not about the first-launch login screen (account_tests covers it)
	var menu: MainMenu = load(MENU_SCENE).instantiate()
	add_child(menu)
	await _wait(1.0)
	return menu

func _close_menu(menu: MainMenu) -> void:
	menu.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _gated(mode: GameMode.Mode, limit: int, offset: int) -> Dictionary:
	var gate := Gate.new()
	gate.asked_mode = mode
	gate.asked_offset = offset
	pending.append(gate)
	fetch_log.append([mode, limit, offset])
	await gate.done
	return gate.reply

func _board(total: int, names: Array, offset: int = 0, me: Variant = null, me_on_page: int = -1) -> Dictionary:
	var entries: Array = []
	for i in names.size():
		entries.append({"rank": offset + i + 1, "name": names[i], "level": 40 - offset - i, "seconds": 12.5 + i, "achieved_at": "2026-01-01", "is_me": i == me_on_page})
	return {"ok": true, "mode": "endless", "total": total, "offset": offset, "limit": 10, "entries": entries, "me": me}

func _row(screen: HallOfFameScreen, index: int) -> Dictionary:
	return screen._rows[index]

# ---- 1. menu navigation ---------------------------------------------------------------------------------------------------

func _t_menu() -> void:
	print("\n[1] MENU AND MODE SELECTION")
	var menu := await _open_menu()
	var changes: Array = []
	var quits: Array = []
	menu.scene_changer = func(path: String) -> void: changes.append(path)
	menu.app_quitter = func() -> void: quits.append(true)
	_check(menu.play_button().text == "PLAY" and menu.modes_button().text == "MODES" and menu.hall_button().text == "HALL OF FAME" and menu.account_button().text == "ACCOUNT" and menu.quit_button().text == "QUIT", "the menu has PLAY, MODES, HALL OF FAME, ACCOUNT and QUIT")
	_tap(menu, menu.modes_button())
	await _wait(0.9)
	var modes := menu.mode_screen()
	_check(modes.is_showing and menu.overlay_open(), "MODES opens the mode screen")
	_check(modes.begin_button(GameMode.Mode.ENDLESS).text == "BEGIN" and modes.hall_button(GameMode.Mode.RUTHLESS).text == "HALL OF FAME", "each mode has BEGIN and its own HALL OF FAME")
	_check(ModeScreen.DESCRIPTIONS[GameMode.Mode.RUTHLESS].contains("never be resumed") and ModeScreen.DESCRIPTIONS[GameMode.Mode.ENDLESS].contains("No ceiling"), "the descriptions say how the modes differ")
	_tap(menu, menu.play_button())
	_check(changes.is_empty(), "the menu behind an open panel ignores taps")
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)   # like Android: one Back press reaches every node
	await get_tree().process_frame
	_check(not modes.is_showing and quits.is_empty() and not menu._acted, "Android Back closes the panel and does NOT quit the app")
	await _wait(0.1)
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait(0.2)
	_check(not quits.is_empty() or menu._acted, "Back with nothing open still leaves the app (the quit path is reached)")
	await _close_menu(menu)
	# begin each mode
	for mode_value in [GameMode.Mode.ENDLESS, GameMode.Mode.RUTHLESS]:
		var mode: GameMode.Mode = mode_value
		menu = await _open_menu()
		changes = []
		menu.scene_changer = func(path: String) -> void: changes.append(path)
		_tap(menu, menu.modes_button())
		await _wait(0.9)
		_tap(menu.mode_screen(), menu.mode_screen().begin_button(mode))
		_tap(menu.mode_screen(), menu.mode_screen().begin_button(mode))   # a double tap
		await _wait(1.0)
		_check(Progress.selected_mode == mode and changes == [MainMenu.GAME_SCENE], "BEGIN %s selects that mode and starts the game exactly once" % GameMode.title(mode))
		await _close_menu(menu)
	# hall from the mode screen
	menu = await _open_menu()
	_tap(menu, menu.modes_button())
	await _wait(0.9)
	menu.hall_screen().fetcher = _gated
	pending.clear()
	_tap(menu.mode_screen(), menu.mode_screen().hall_button(GameMode.Mode.RUTHLESS))
	await _wait(0.2)
	_check(not menu.mode_screen().is_showing and menu.hall_screen().is_showing and menu.hall_screen().mode == GameMode.Mode.RUTHLESS, "the Ruthless HALL OF FAME button opens the Ruthless board")
	await _close_menu(menu)
	# the Hall of Fame button on the menu
	menu = await _open_menu()
	Progress.selected_mode = GameMode.Mode.ENDLESS
	menu.hall_screen().fetcher = _gated
	pending.clear()
	_tap(menu, menu.hall_button())
	await _wait(0.2)
	_check(menu.hall_screen().is_showing and menu.hall_screen().mode == GameMode.Mode.ENDLESS and menu.hall_screen().view_state == "loading", "HALL OF FAME on the menu opens the board (loading until the server answers)")
	await _close_menu(menu)
	pending.clear()

# ---- 2. Hall of Fame ------------------------------------------------------------------------------------------------------------

func _hall() -> HallOfFameScreen:
	var screen := HallOfFameScreen.new()
	add_child(screen)
	screen.fetcher = _gated
	return screen

func _answer(gate_index: int, reply: Dictionary) -> void:
	pending[gate_index].reply = reply
	pending[gate_index].done.emit()

func _t_hall() -> void:
	print("\n[2] HALL OF FAME")
	var hall := _hall()
	pending.clear()
	fetch_log.clear()
	hall.open_for(GameMode.Mode.ENDLESS)
	await _wait(0.1)
	_check(hall.view_state == "loading" and hall._message.text.contains("Consulting") and fetch_log.size() == 1, "while the server has not answered the screen says it is loading (1 request)")
	_check(fetch_log[0][0] == GameMode.Mode.ENDLESS and fetch_log[0][1] == 10 and fetch_log[0][2] == 0, "the request asks for the Endless board, 10 entries from 0")
	_answer(0, _board(25, ["Alpha", "Bravo", "Charlie"], 0, {"rank": 2, "level": 38, "seconds": 13.5}, 1))
	await _wait(0.1)
	_check(hall.view_state == "ready" and _row(hall, 0)["name"].text == "Alpha" and _row(hall, 0)["rank"].text == "#1" and _row(hall, 0)["level"].text == "40" and _row(hall, 0)["time"].text == "0:12.50", "a populated board shows rank, name, level and time as the server sent them")
	_check(_row(hall, 3)["row"].visible == false and _row(hall, 2)["row"].visible == true, "only the returned entries are shown (3 of 10 rows)")
	_check(_row(hall, 1)["name"].get_theme_color("font_color") == UiStyle.GOLD_BRIGHT and _row(hall, 0)["name"].get_theme_color("font_color") == UiStyle.PARCHMENT, "the current player's row is highlighted")
	_check(hall._me_label.text.contains("#2") and hall._me_label.text.contains("LEVEL 38"), "the player's own place is shown from the server's 'me'")
	_check(hall.title_label.text == "ENDLESS HALL OF FAME" and hall._page_label.text == "PAGE 1 / 3" and hall._prev.disabled and not hall._next.disabled, "Endless title, page 1 of 3 (25 entries), PREV disabled")
	# own place off the page
	hall.close()
	pending.clear()
	hall.open_for(GameMode.Mode.RUTHLESS)
	_answer(0, _board(120, ["P1", "P2"], 0, {"rank": 77, "level": 9, "seconds": 40.0}, -1))
	await _wait(0.1)
	_check(hall.title_label.text == "RUTHLESS HALL OF FAME" and fetch_log.back()[0] == GameMode.Mode.RUTHLESS, "the Ruthless board is requested with the Ruthless mode and titled so")
	_check(hall._me_label.text.contains("#77") and hall._me_label.text.contains("LEVEL 9"), "a player outside the page still sees their own rank (#77)")
	# pagination
	hall.close()
	pending.clear()
	fetch_log.clear()
	hall.open_for(GameMode.Mode.ENDLESS)
	_answer(0, _board(25, ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10"]))
	await _wait(0.1)
	while not hall.buttons_ready:
		await get_tree().process_frame
	_tap(hall, hall._next)
	await _wait(0.1)
	_check(fetch_log.size() == 2 and fetch_log[1][2] == 10, "NEXT asks the server for entries 10-19")
	_answer(1, _board(25, ["b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8", "b9", "b10"], 10))
	await _wait(0.1)
	_check(_row(hall, 0)["rank"].text == "#11" and _row(hall, 0)["name"].text == "b1" and hall._page_label.text == "PAGE 2 / 3", "page 2 shows ranks 11-20 (no overlap with page 1)")
	hall._go(20)
	await _wait(0.05)
	_answer(2, _board(25, ["c1", "c2", "c3", "c4", "c5"], 20))
	await _wait(0.1)
	_check(hall._next.disabled and not hall._prev.disabled and hall._page_label.text == "PAGE 3 / 3", "the last page disables NEXT")
	var requests_before := hall.requests_sent
	hall._go(30)
	await _wait(0.05)
	_check(hall.requests_sent == requests_before, "paging past the end sends nothing")
	# states
	for case in [[{"ok": false, "error": "offline"}, "offline", "offline"], [{"ok": false, "error": "timeout"}, "offline", "offline"], [{"ok": false, "error": "http_503"}, "error", "http_503"], [{"ok": true, "total": 0, "entries": [], "me": null}, "empty", "No one has claimed"]]:
		hall.close()
		pending.clear()
		hall.open_for(GameMode.Mode.ENDLESS)
		_answer(0, case[0])
		await _wait(0.1)
		_check(hall.view_state == case[1] and hall._message.text.contains(case[2]) and not _row(hall, 0)["row"].visible and hall._me_label.text == "", "answer %s -> state '%s' with a message and no rows" % [str(case[0]).left(40), case[1]])
	_check(hall._message.text.contains("No one has claimed") and hall._refresh.disabled == false, "the empty board has no invented entries and REFRESH is available")
	# duplicate taps and refresh
	hall.close()
	pending.clear()
	hall.open_for(GameMode.Mode.ENDLESS)
	_answer(0, {"ok": true, "total": 0, "entries": [], "me": null})
	await _wait(0.8)
	var base := hall.requests_sent
	_tap(hall, hall._refresh)
	_tap(hall, hall._refresh)
	hall._load()
	await _wait(0.05)
	_check(hall.requests_sent == base + 1 and pending.size() == 2, "refreshing several times at once sends ONE request")
	_answer(1, _board(1, ["Solo"], 0, null, 0))
	await _wait(0.1)
	_check(_row(hall, 0)["name"].text == "Solo", "...and its answer is shown")
	# stale answers
	hall.close()
	pending.clear()
	hall.open_for(GameMode.Mode.ENDLESS)          # request 0 (Endless), left unanswered
	await _wait(0.8)
	hall._switch(GameMode.Mode.RUTHLESS)           # request 1 (Ruthless)
	await _wait(0.05)
	_check(pending.size() == 2 and pending[1].asked_mode == GameMode.Mode.RUTHLESS, "switching tabs while loading asks for the other board")
	_answer(1, _board(1, ["RuthlessOnly"], 0))
	await _wait(0.1)
	_answer(0, _board(1, ["EndlessLate"], 0))       # the old answer arrives afterwards
	await _wait(0.1)
	_check(_row(hall, 0)["name"].text == "RuthlessOnly" and hall.mode == GameMode.Mode.RUTHLESS, "a late answer for the other tab is ignored (the board never mixes modes)")
	hall.close()
	pending.clear()
	hall.open_for(GameMode.Mode.ENDLESS)
	await _wait(0.1)
	hall.close()
	var state_before := hall.view_state
	_answer(0, _board(1, ["AfterClose"], 0))
	await _wait(0.1)
	_check(hall.view_state == state_before and not hall.is_showing, "an answer that arrives after the screen was closed is ignored")
	# a shrunken board
	hall.close()
	pending.clear()
	fetch_log.clear()
	hall.open_for(GameMode.Mode.ENDLESS)
	hall._offset = 10
	_answer(0, _board(3, ["x", "y", "z"], 0))
	await _wait(0.1)
	hall.close()
	pending.clear()
	hall.open_for(GameMode.Mode.ENDLESS)
	_answer(0, _board(5, ["a", "b"], 0))
	await _wait(0.1)
	hall._offset = 10
	hall._load()
	await _wait(0.05)
	_answer(1, {"ok": true, "total": 5, "entries": [], "me": null})
	await _wait(0.1)
	_check(fetch_log.back()[2] == 0 and pending.size() == 3, "a page that no longer exists sends the player back to the first page")
	_answer(2, _board(5, ["a", "b", "c", "d", "e"], 0))
	await _wait(0.1)
	# names are plain text
	hall.close()
	pending.clear()
	hall.open_for(GameMode.Mode.ENDLESS)
	var nasty := ["[b]bold[/b]", "[url=evil]click[/url]", "<script>alert(1)</script>", "x".repeat(60), "Line\nBreak", "[color=red]Red", "%s %d {0}"]
	_answer(0, _board(nasty.size(), nasty))
	await _wait(0.1)
	var literal := true
	for i in nasty.size():
		if _row(hall, i)["name"].text != nasty[i]:
			literal = false
	_check(literal, "names are shown exactly as sent: markup, tags and format characters are plain text")
	_check(hall.find_children("*", "RichTextLabel", true, false).is_empty(), "the board uses no rich-text label (nothing in a name can be interpreted as formatting)")
	var name_label: Label = _row(hall, 3)["name"]
	_check(name_label.clip_text and name_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "a very long name is trimmed to its column")
	hall.queue_free()
	await get_tree().process_frame

# ---- 3. account screen -----------------------------------------------------------------------------------------------------------

func _t_account() -> void:
	print("
[3] ACCOUNT SCREEN")
	var menu := await _open_menu()
	var screen := menu.account_screen()
	_tap(menu, menu.account_button())
	await _wait(0.9)
	_check(screen.is_showing and screen._status.text == "NOT LOGGED IN" and screen._name_label.text.contains("this phone only"), "ACCOUNT, not logged in: says so and that play is on this phone only")
	_check(screen.login_button().visible and not screen.logout_button().visible and screen.info_text().contains("without one"), "LOG IN / CREATE ACCOUNT is offered, LOG OUT is not, and playing without an account is allowed")
	# opening the login screen from here
	_tap(screen, screen.login_button())
	await _wait(0.9)
	var login := menu.login_screen()
	_check(not screen.is_showing and login.is_showing and not login.required and login.close_button.visible and not login.skip_button().visible, "LOG IN / CREATE ACCOUNT opens the login screen with CLOSE (not the first-launch one)")
	login.close()
	await _wait(0.1)
	# logged in
	Account.store_session(UID, "refresh-1")
	Account.set_logged_in(UID, "Test_Knight")
	_tap(menu, menu.account_button())
	await _wait(0.9)
	_check(screen._status.text == "LOGGED IN" and screen._name_label.text == "Test_Knight" and screen._id_label.text == "PLAYER ID  11111111", "logged in: status, username and a short player id")
	_check(not screen._id_label.text.contains(Account.refresh_token) and screen.info_text().contains("cannot be reset") and screen.info_text().contains("reinstall"), "the credential is never shown, and the screen says a forgotten password cannot be reset and that a reinstall needs a new login")
	_check(screen.logout_button().visible and not screen.login_button().visible, "LOG OUT is offered, LOG IN is not")
	# log out (the server call is scripted)
	transport_allowed = true
	scripted.clear()
	_answers.clear()
	_answers["rpc/logout"] = {"status": 200, "body": JSON.stringify({"ok": true}), "error": ""}
	Backend.access_token = "access-1"
	Backend.expires_at = int(Time.get_unix_time_from_system()) + 3000
	_tap(screen, screen.logout_button())
	_tap(screen, screen.logout_button())
	await _wait(0.4)
	transport_allowed = false
	_check(scripted.size() == 1 and scripted[0]["path"].ends_with("rpc/logout"), "tapping LOG OUT twice makes one logout call")
	_check(not Account.logged_in and Account.username == "" and Account.refresh_token == "" and screen._status.text == "NOT LOGGED IN", "after logging out the phone forgets the account and its session, and the screen shows it")
	await _close_menu(menu)

# ---- 4. result screen --------------------------------------------------------------------------------------------------------------

func _t_result() -> void:
	print("\n[4] RESULT SCREEN")
	_check(FailureScreen.online_text(_result(GameMode.Mode.ENDLESS), "offline").contains("NOT SENT TO THE HALL OF FAME") and FailureScreen.online_text(_result(GameMode.Mode.ENDLESS), "pending").contains("WAITING") and FailureScreen.online_text(_result(GameMode.Mode.ENDLESS), "submitted").contains("SENT TO THE HALL OF FAME") and FailureScreen.online_text(_result(GameMode.Mode.ENDLESS), "rejected").contains("DID NOT ACCEPT") and FailureScreen.online_text(_result(GameMode.Mode.ENDLESS), "disabled") == "",
		"each sync status has its own plain wording (offline runs are never described as submitted)")
	var invalid := _result(GameMode.Mode.RUTHLESS)
	invalid.end_reason = RunResult.EndReason.INVALIDATED
	_check(FailureScreen.online_text(invalid, "submitted").contains("ENDED EARLY") and not FailureScreen.online_text(invalid, "submitted").contains("SENT TO THE HALL OF FAME."), "an invalidated Ruthless run never claims its score is accepted")
	var screen: FailureScreen = load(FAILURE_SCENE).instantiate()
	add_child(screen)
	await get_tree().process_frame
	Progress.store.data = SaveStore.default_data()
	Progress.store.record("ruthless")["best_level"] = 6
	RunSync.status = "offline"
	GameManager.set_state(GameManager.State.FAILED)
	screen.show_result(_result(GameMode.Mode.RUTHLESS))
	var text: String = screen._status_label.text
	_check(text.contains("RUTHLESS") and text.contains("BEST: LEVEL 6") and text.contains("OFFLINE RUN"), "the result shows the mode, the local best and that this run was offline")
	RunSync.status = "pending"
	RunSync.status_changed.emit("pending")
	_check(screen._status_label.text.contains("WAITING"), "the status updates live while the screen is open (pending)")
	RunSync.status = "submitted"
	RunSync.status_changed.emit("submitted")
	_check(screen._status_label.text.contains("SENT TO THE HALL OF FAME"), "...and when it is submitted")
	await _wait(1.6)
	_check(screen.buttons_ready and not screen._try_again_button.disabled, "the buttons are usable whatever the network status (a result never waits for the server)")
	_check(not screen._status_label.text.to_lower().contains("tap"), "no tap count appears")
	screen.hide_screen()
	_check(screen._shown_result == null, "hiding the screen releases the result")
	RunSync.status = "disabled"
	GameManager.set_state(GameManager.State.READY)
	screen.queue_free()
	await get_tree().process_frame

func _result(mode: GameMode.Mode) -> RunResult:
	var result := RunResult.new()
	result.mode = mode
	result.level_reached = 4
	result.completed_level = 3
	return result

# ---- 5. layout at several screen shapes ----------------------------------------------------------------------------------------------

func _t_layout() -> void:
	print("\n[5] LAYOUT")
	for size in [Vector2i(540, 960), Vector2i(450, 1000), Vector2i(600, 800), Vector2i(400, 1000)]:
		get_window().size = size
		await _wait(0.2)
		var viewport := get_viewport().get_visible_rect()
		var menu := await _open_menu()
		var ok := true
		var rects: Array[Rect2] = []
		for button in [menu.play_button(), menu.modes_button(), menu.hall_button(), menu.account_button(), menu.quit_button()]:
			var rect: Rect2 = button.get_global_rect()
			rects.append(rect)
			if not viewport.encloses(rect) or rect.size.y < 100.0:
				ok = false
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				if rects[i].intersects(rects[j]):
					ok = false
		_check(ok, "at %dx%d the five menu buttons are on screen, at least 100 px tall and do not overlap" % [size.x, size.y])
		for screen_pair in [["modes", menu.mode_screen()], ["hall", menu.hall_screen()], ["account", menu.account_screen()], ["login", menu.login_screen()]]:
			var screen: OverlayScreen = screen_pair[1]
			if screen is HallOfFameScreen:
				(screen as HallOfFameScreen).fetcher = _gated
				pending.clear()
				(screen as HallOfFameScreen).open_for(GameMode.Mode.ENDLESS)
				_answer(0, _board(25, ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10"], 0, {"rank": 30, "level": 3, "seconds": 9.0}))
			else:
				screen.open()
			await _wait(0.2)
			var fits: bool = screen.column.get_combined_minimum_size().y <= screen.column.size.y + 1.0
			var inside: bool = viewport.encloses(screen.panel.get_global_rect().grow(-1.0))
			var buttons_ok := true
			for node in screen.panel.find_children("*", "Button", true, false):
				var button := node as Button
				if button.is_visible_in_tree() and (not viewport.encloses(button.get_global_rect()) or button.get_global_rect().size.y < 90.0):
					buttons_ok = false
			_check(fits and inside and buttons_ok, "at %dx%d the %s panel fits (content %.0f of %.0f px) with its buttons on screen and 90+ px tall" % [size.x, size.y, screen_pair[0], screen.column.get_combined_minimum_size().y, screen.column.size.y])
			screen.close()
		await _close_menu(menu)
	get_window().size = Vector2i(540, 960)
