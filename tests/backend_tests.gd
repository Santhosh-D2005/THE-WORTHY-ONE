extends Node
## The online service layer and run reporting, with the NETWORK replaced by a scripted fake (Backend.transport). Proves how the game behaves
## for each kind of answer: the app's anonymous session, token refresh, a dead session being replaced (never silently logged in), register /
## log in / log out, the password never stored or returned, offline and timeout handling, the retry queue, refusals, runs of a logged-out
## player. It proves nothing about Supabase itself: the server rules are tested in server/test_schema.mjs.
## Run headless:   godot --headless --path . res://tests/backend_tests.tscn

const ACC := "user://backend_test_account.dat"
const UID := "11111111-2222-4333-8444-555555555555"
const PID := "99999999-8888-4777-8666-555555555555"
const RUN1 := "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeee1"
const RUN2 := "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeee2"
const PASSWORD := "Correct-Horse-7"

var _checks := 0
var _failures := 0
var requests: Array[Dictionary] = []
var _answers: Dictionary = {}

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var saved_transport: Callable = Backend.transport
	Backend.transport = _fake
	_t_config()
	await _t_session()
	await _t_accounts()
	await _t_errors()
	await _t_sync()
	Backend.transport = saved_transport
	RunSync.enabled = false
	Backend.access_token = ""
	if FileAccess.file_exists(ACC):
		DirAccess.remove_absolute(ACC)
	Account.reset_for_test(Account.TEST_FILE_PATH)
	Account.login_skipped = true
	print("\n==== %d checks, %d failed ====" % [_checks, _failures])
	print("RESULT: ALL PASSED" if _failures == 0 else "RESULT: FAILURES")
	get_tree().quit(0 if _failures == 0 else 1)

# ---- the scripted fake network ------------------------------------------------------------------------------------

func _fake(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var path := url.trim_prefix(BackendConfig.URL)
	var parsed: Variant = JSON.parse_string(body)
	requests.append({"method": method, "path": path, "headers": headers, "body": parsed if parsed is Dictionary else {}})
	for fragment: String in _answers:
		if path.contains(fragment):
			var list: Array = _answers[fragment]
			return list[0] if list.size() == 1 else list.pop_front()
	return {"status": 404, "body": "{}", "error": ""}

func _ok(data: Dictionary, status: int = 200) -> Dictionary:
	return {"status": status, "body": JSON.stringify(data), "error": ""}

func _down(kind: String = "offline") -> Dictionary:
	return {"status": 0, "body": "", "error": kind}

func _answer_for(fragment: String, answers: Array) -> void:
	_answers[fragment] = answers

func _reset_fake() -> void:
	requests.clear()
	_answers.clear()

func _paths() -> Array:
	return requests.map(func(r: Dictionary) -> String: return str(r["path"]).get_slice("?", 0).trim_prefix("/rest/v1/rpc/").trim_prefix("/auth/v1/"))

func _header(request: Dictionary, name: String) -> String:
	for h: String in request["headers"]:
		if h.begins_with(name + ":"):
			return h.substr(name.length() + 2)
	return ""

func _tokens(access: String, refresh: String, user_id: String = UID) -> Dictionary:
	return _ok({"access_token": access, "refresh_token": refresh, "expires_in": 3600, "expires_at": int(Time.get_unix_time_from_system()) + 3600, "user": {"id": user_id, "is_anonymous": true}})

func _fresh_account() -> void:
	if FileAccess.file_exists(ACC):
		DirAccess.remove_absolute(ACC)
	Account.reset_for_test(ACC)
	Backend.access_token = ""
	Backend.expires_at = 0

func _signed_in_session() -> void:
	_fresh_account()
	Account.store_session(UID, "refresh-x")
	Backend.access_token = "access-x"
	Backend.expires_at = int(Time.get_unix_time_from_system()) + 3000

func _logged_in() -> void:
	_signed_in_session()
	Account.set_logged_in(PID, "Test_Knight")

func _settle() -> void:
	var guard := Time.get_ticks_msec() + 3000
	while (RunSync._flushing or RunSync._opening) and Time.get_ticks_msec() < guard:
		await get_tree().process_frame
	await get_tree().process_frame

# ---- 1. configuration ---------------------------------------------------------------------------------------------------

func _t_config() -> void:
	print("\n[1] CONFIGURATION")
	_check(BackendConfig.URL.begins_with("https://") and BackendConfig.PUBLISHABLE_KEY.begins_with("sb_publishable_"), "the project URL is https and the key is a publishable key")
	var leaks := 0
	for dir in ["res://scripts/", "res://scenes/"]:
		leaks += _scan_for_secrets(dir)
	for file in ["res://project.godot", "res://export_presets.cfg"]:
		if FileAccess.get_file_as_string(file).contains("service_role") or FileAccess.get_file_as_string(file).contains("sb_secret_"):
			leaks += 1
	_check(leaks == 0, "no secret / service-role key anywhere in the game's scripts, scenes or project files (%d findings)" % leaks)

func _scan_for_secrets(dir: String) -> int:
	var found := 0
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".gd") or name.ends_with(".tscn") or name.ends_with(".tres"):
			var text := FileAccess.get_file_as_string(dir + name)
			if text.contains("sb_secret_") or text.contains("eyJhbGci") or text.contains("SERVICE_ROLE_KEY"):
				found += 1
	for sub in DirAccess.get_directories_at(dir):
		found += _scan_for_secrets(dir + sub + "/")
	return found

# ---- 2. the app's anonymous session --------------------------------------------------------------------------------------

func _t_session() -> void:
	print("\n[2] THE APP'S ANONYMOUS SESSION")
	_reset_fake()
	_fresh_account()
	_answer_for("/auth/v1/signup", [_tokens("access-1", "refresh-1")])
	var result: Dictionary = await Backend.ensure_session()
	_check(result["ok"] and _paths() == ["signup"], "a fresh install asks for an anonymous session: one sign-up call and nothing else (no account is created)")
	_check(_header(requests[0], "apikey") == BackendConfig.PUBLISHABLE_KEY and _header(requests[0], "Authorization") == "", "...with the publishable key and no bearer token")
	_check(Account.auth_user_id == UID and Account.refresh_token == "refresh-1" and not Account.logged_in, "the session credential is saved; the player is NOT logged in")
	_check(AccountStore.new(ACC).read().get("refresh_token", "") == "refresh-1", "...in the encrypted account file")
	var before := requests.size()
	await Backend.ensure_session()
	_check(requests.size() == before, "a valid session makes no further requests")
	# refresh
	requests.clear()
	Backend.expires_at = 0
	_answer_for("grant_type=refresh_token", [_tokens("access-2", "refresh-2")])
	result = await Backend.ensure_session()
	_check(result["ok"] and _paths() == ["token"] and requests[0]["body"]["refresh_token"] == "refresh-1", "an expired token is refreshed with the stored credential")
	_check(Account.refresh_token == "refresh-2" and AccountStore.new(ACC).read().get("refresh_token", "") == "refresh-2" and Backend.access_token == "access-2", "the rotated credential is saved at once")
	# offline during a refresh
	requests.clear()
	Backend.expires_at = 0
	_answer_for("grant_type=refresh_token", [_down("offline")])
	result = await Backend.ensure_session()
	_check(not result["ok"] and result["error"] == "offline" and not _paths().has("signup") and Account.refresh_token == "refresh-2", "offline during a refresh is just 'offline': the session is kept, nothing is replaced")
	# a dead session is replaced, and the player is logged out
	Account.set_logged_in(PID, "Test_Knight")
	requests.clear()
	var replaced: Array = []
	Backend.session_replaced.connect(func() -> void: replaced.append(true))
	_answer_for("grant_type=refresh_token", [_ok({"error": "invalid_grant"}, 400)])
	_answer_for("/auth/v1/signup", [_tokens("access-9", "refresh-9", "ffffffff-eeee-4ddd-8ccc-bbbbbbbbbbbb")])
	result = await Backend.ensure_session()
	_check(result["ok"] and _paths() == ["token", "signup"] and replaced.size() == 1, "a refused credential is replaced by a new anonymous session (and the game is told)")
	_check(not Account.logged_in and Account.username == "Test_Knight" and Account.auth_user_id == "ffffffff-eeee-4ddd-8ccc-bbbbbbbbbbbb", "...the new session is NOT logged in: the player must log in again (the account itself lives on the server)")

# ---- 3. register, log in, log out ----------------------------------------------------------------------------------------

func _t_accounts() -> void:
	print("\n[3] REGISTER, LOG IN, LOG OUT")
	_reset_fake()
	_signed_in_session()
	Progress.store.data = SaveStore.default_data()
	_answer_for("rpc/register_account", [_ok({"ok": true, "player_id": PID, "username": "Sir_Kay"})])
	_answer_for("rpc/get_account", [_ok({"ok": true, "records": {"endless": {"best_level": 42, "best_seconds": 31.5}}})])
	var answer: Dictionary = await Backend.register_account("Sir_Kay", PASSWORD)
	_check(answer["ok"] and Account.logged_in and Account.username == "Sir_Kay" and Account.player_id == PID, "registering logs the install in to the new account")
	_check(requests[0]["path"].ends_with("rpc/register_account") and requests[0]["body"].keys().size() == 2 and requests[0]["body"]["p_username"] == "Sir_Kay" and requests[0]["body"]["p_password"] == PASSWORD, "the request carries exactly the username and the password")
	_check(_header(requests[0], "Authorization") == "Bearer access-x", "...as the app's session")
	_check(int(Progress.best(GameMode.Mode.ENDLESS)["best_level"]) == 42, "the server's records are brought onto the phone after registering (best level 42)")
	var disk := AccountStore.new(ACC).read()
	_check(not JSON.stringify(disk).contains(PASSWORD) and not JSON.stringify(Account.public_info()).contains(PASSWORD), "the password is stored nowhere (not in the account file, not in the public profile)")
	_check(not JSON.stringify(answer).contains(PASSWORD), "...and is not in what the call returns")
	# failures
	_signed_in_session()
	_answer_for("rpc/register_account", [_ok({"ok": false, "error": "username_taken"})])
	answer = await Backend.register_account("Sir_Kay", PASSWORD)
	_check(not answer["ok"] and answer["error"] == "username_taken" and not Account.logged_in, "a taken username leaves the player logged out")
	_signed_in_session()
	_answer_for("rpc/login", [_ok({"ok": false, "error": "locked", "wait_seconds": 600})])
	answer = await Backend.log_in("Sir_Kay", "Wrong-Password-1")
	_check(not answer["ok"] and answer["error"] == "locked" and int(answer["wait_seconds"]) == 600 and not Account.logged_in, "a locked login passes the wait time on and logs nothing in")
	_answer_for("rpc/login", [_down("timeout")])
	answer = await Backend.log_in("Sir_Kay", PASSWORD)
	_check(not answer["ok"] and answer["error"] == "timeout" and not Account.logged_in, "a timeout during login: 'timeout', still logged out")
	# log in
	_signed_in_session()
	_answer_for("rpc/login", [_ok({"ok": true, "player_id": PID, "username": "Sir_Kay"})])
	answer = await Backend.log_in("sir_kay", PASSWORD)
	_check(answer["ok"] and Account.logged_in and Account.username == "Sir_Kay" and requests[0]["body"]["p_username"] == "sir_kay", "a good login logs in with the username the SERVER returns (its capitalisation), not what was typed")
	_check(requests.back()["path"].contains("rpc/get_account"), "...and then fetches the account's records")
	# log out, online and offline
	_answer_for("rpc/logout", [_ok({"ok": true})])
	requests.clear()
	await Backend.log_out()
	_check(_paths() == ["logout"] and not Account.logged_in and Account.refresh_token == "" and Account.username == "" and Backend.access_token == "", "log out tells the server, then forgets the account AND the session")
	_logged_in()
	_answer_for("rpc/logout", [_down("offline")])
	await Backend.log_out()
	_check(not Account.logged_in and Account.refresh_token == "" and Account.auth_user_id == "", "offline: the phone still logs out locally (it can no longer act as the account)")
	# password change
	_logged_in()
	requests.clear()
	_answer_for("change_password", [_ok({"ok": true})])
	answer = await Backend.change_password("Old-Password-1", "New-Password-2")
	_check(answer["ok"] and requests[0]["body"] == {"p_old": "Old-Password-1", "p_new": "New-Password-2"} and not JSON.stringify(Account.public_info()).contains("Password"), "changing the password sends both passwords and keeps neither")

# ---- 4. errors, retries and passing server answers through --------------------------------------------------------------------

func _t_errors() -> void:
	print("\n[4] ERRORS")
	_check(Backend.is_retryable("offline") and Backend.is_retryable("timeout") and Backend.is_retryable("network") and Backend.is_retryable("http_503") and Backend.is_retryable("http_429"), "offline, timeout, network, 5xx and 429 are retryable")
	_check(not Backend.is_retryable("http_400") and not Backend.is_retryable("run_not_active") and not Backend.is_retryable("not_logged_in") and not Backend.is_retryable("wrong_credentials"), "client errors and server refusals are not retried")
	_check(HttpTransport.error_for_result(HTTPRequest.RESULT_TIMEOUT) == "timeout" and HttpTransport.error_for_result(HTTPRequest.RESULT_CANT_CONNECT) == "offline" and HttpTransport.error_for_result(HTTPRequest.RESULT_CANT_RESOLVE) == "offline" and HttpTransport.error_for_result(HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED) == "network", "network results map to offline / timeout / network")
	_reset_fake()
	_logged_in()
	_answer_for("leaderboard_page", [_down("offline")])
	var board: Dictionary = await Backend.leaderboard(GameMode.Mode.ENDLESS, 10, 20)
	_check(not board["ok"] and board["error"] == "offline" and not board.has("entries"), "offline: the leaderboard call fails cleanly with no entries (nothing invented)")
	var lb_body: Dictionary = requests[0]["body"]
	_check(lb_body.keys().size() == 3 and lb_body["p_mode"] == "endless" and int(lb_body["p_limit"]) == 10 and int(lb_body["p_offset"]) == 20, "the leaderboard request carries the mode, limit and offset only (no rank)")
	_answer_for("leaderboard_page", [_ok({"message": "boom"}, 503)])
	var down: Dictionary = await Backend.leaderboard(GameMode.Mode.ENDLESS)
	_check(not down["ok"] and down["error"] == "http_503", "a server error is reported as http_503")
	_answer_for("leaderboard_page", [_ok({"ok": true, "mode": "endless", "total": 1, "entries": [{"rank": 1, "name": "Alpha", "level": 5, "seconds": 20.0, "is_me": false}], "me": null})])
	var good: Dictionary = await Backend.leaderboard(GameMode.Mode.ENDLESS)
	_check(good["ok"] and good["entries"][0]["name"] == "Alpha", "a good answer is passed through unchanged")
	_answer_for("start_run", [_ok({"ok": false, "error": "not_logged_in"})])
	var refused: Dictionary = await Backend.call_server("start_run", {"p_mode": "endless"})
	_check(refused["error"] == "not_logged_in" and not Account.logged_in, "'not logged in' from the server also logs the account out on the phone")
	_logged_in()
	requests.clear()
	_answer_for("start_run", [_ok({"message": "JWT expired"}, 401), _ok({"ok": true, "run_id": RUN1})])
	_answer_for("grant_type=refresh_token", [_tokens("access-9", "refresh-9")])
	var retried: Dictionary = await Backend.call_server("start_run", {"p_mode": "endless"})
	_check(retried["ok"] and _paths() == ["start_run", "token", "start_run"] and _header(requests[2], "Authorization") == "Bearer access-9", "a 401 refreshes the session once and retries with the new token")

# ---- 5. reporting runs to the server -------------------------------------------------------------------------------------------

func _queue_on_disk() -> Array:
	var copy := SaveStore.new(Progress.store.path)
	copy.load_data()
	return copy.data["queue"]

func _reset_progress() -> void:
	Progress.store.data = SaveStore.default_data()
	Progress.store.save()
	Progress.run_active = false
	RunSync.server_run = ""
	RunSync._waiting.clear()
	RunSync._timer.stop()

func _t_sync() -> void:
	print("\n[5] RUN REPORTING")
	RunSync.enabled = true
	# A. logged-out players do not report
	_reset_fake()
	_signed_in_session()
	_reset_progress()
	Progress.begin_run(GameMode.Mode.ENDLESS)
	await _settle()
	GameManager.extraction_succeeded.emit(1, 5.0)
	await _settle()
	_check(RunSync.status == "signed_out" and requests.is_empty() and int(Progress.best(GameMode.Mode.ENDLESS)["best_level"]) == 1, "not logged in: nothing is sent, the status is 'signed_out' and the phone's own record still counts")
	# B. online run
	_reset_fake()
	_logged_in()
	_reset_progress()
	_answer_for("start_run", [_ok({"ok": true, "run_id": RUN1})])
	_answer_for("submit_level", [_ok({"ok": true, "new_best": true})])
	_answer_for("end_run", [_ok({"ok": true, "status": "failed"})])
	Progress.begin_run(GameMode.Mode.ENDLESS)
	await _settle()
	GameManager.extraction_succeeded.emit(1, 5.0)
	GameManager.extraction_succeeded.emit(2, 6.5)
	await _settle()
	_check(_paths() == ["start_run", "submit_level", "submit_level"], "a logged-in run asks the server for a run id, then reports each level (%s)" % str(_paths()))
	_check(requests[1]["body"].keys().size() == 3 and requests[1]["body"]["p_run"] == RUN1 and int(requests[1]["body"]["p_level"]) == 1 and is_equal_approx(float(requests[1]["body"]["p_seconds"]), 5.0), "...with the server's run id, the level and its time (no rank, no tap count)")
	_check(RunSync.status == "submitted" and Progress.store.data["queue"].is_empty(), "status is 'submitted' and nothing is left queued")
	Progress.end_run("failed")
	await _settle()
	_check(requests.back()["body"] == {"p_run": RUN1, "p_reason": "failed"}, "the end of the run is reported as failed")
	# C. the connection drops
	_reset_fake()
	_reset_progress()
	_answer_for("start_run", [_ok({"ok": true, "run_id": RUN1})])
	_answer_for("submit_level", [_down("offline")])
	Progress.begin_run(GameMode.Mode.ENDLESS)
	await _settle()
	GameManager.extraction_succeeded.emit(1, 5.0)
	await _settle()
	RunSync._timer.stop()
	_check(RunSync.status == "pending" and Progress.store.data["queue"].size() == 1, "offline during a level: it stays queued, status 'pending'")
	GameManager.extraction_succeeded.emit(2, 6.0)
	await _settle()
	RunSync._timer.stop()
	_check(Progress.store.data["queue"].size() == 2 and _queue_on_disk().size() == 2, "the queue is saved to disk (it survives the app being killed)")
	Progress.store.load_data()
	_check(Progress.store.data["queue"].size() == 2, "after a reload the queued events are still there")
	_answer_for("submit_level", [_ok({"ok": true, "new_best": true})])
	requests.clear()
	RunSync.flush()
	await _settle()
	var delivered: Array = requests.map(func(r: Dictionary) -> int: return int(r["body"]["p_level"]))
	_check(delivered == [1, 2] and Progress.store.data["queue"].is_empty(), "when the network returns they are delivered in order (levels %s) and the queue empties" % str(delivered))
	# D. the server refuses
	_reset_fake()
	_reset_progress()
	_answer_for("start_run", [_ok({"ok": true, "run_id": RUN2})])
	_answer_for("submit_level", [_ok({"ok": false, "error": "run_not_active", "status": "invalidated"})])
	Progress.begin_run(GameMode.Mode.RUTHLESS)
	await _settle()
	GameManager.extraction_succeeded.emit(1, 6.0)
	await _settle()
	GameManager.extraction_succeeded.emit(2, 6.0)
	await _settle()
	_check(RunSync.status == "rejected" and Progress.store.data["queue"].is_empty() and not RunSync._timer.time_left > 0.0, "a run the server refuses is dropped, not retried (status 'rejected', no retry scheduled)")
	_check(int(Progress.best(GameMode.Mode.RUTHLESS)["best_level"]) >= 1, "a server refusal never removes the local record")
	# E. the server says we are logged out mid-run
	_reset_fake()
	_logged_in()
	_reset_progress()
	_answer_for("start_run", [_ok({"ok": true, "run_id": RUN1})])
	_answer_for("submit_level", [_ok({"ok": false, "error": "not_logged_in"})])
	Progress.begin_run(GameMode.Mode.ENDLESS)
	await _settle()
	GameManager.extraction_succeeded.emit(1, 5.0)
	await _settle()
	_check(RunSync.status == "signed_out" and not Account.logged_in and Progress.store.data["queue"].is_empty(), "if the server says the session is logged out, the run is dropped, the status is 'signed_out' and the phone shows logged out")
	# F. offline at the start
	_reset_fake()
	_logged_in()
	_reset_progress()
	_answer_for("start_run", [_down("offline")])
	Progress.begin_run(GameMode.Mode.ENDLESS)
	await _settle()
	GameManager.extraction_succeeded.emit(1, 5.0)
	GameManager.extraction_succeeded.emit(2, 5.0)
	await _settle()
	_check(RunSync.status == "offline" and _paths() == ["start_run"] and int(Progress.best(GameMode.Mode.ENDLESS)["best_level"]) == 2 and Progress.store.data["queue"].is_empty(), "offline at the start: a local-only run, nothing sent later, the phone's record still counts")
	# G. Ruthless invalidation
	_reset_fake()
	_logged_in()
	_reset_progress()
	_answer_for("start_run", [_ok({"ok": true, "run_id": RUN1})])
	_answer_for("submit_level", [_ok({"ok": true, "new_best": true})])
	_answer_for("end_run", [_ok({"ok": true, "status": "invalidated"})])
	Progress.begin_run(GameMode.Mode.RUTHLESS)
	await _settle()
	GameManager.extraction_succeeded.emit(1, 6.0)
	await _settle()
	Progress.invalidate_run("background")
	Progress.end_run("invalidated")
	await _settle()
	_check(_paths() == ["start_run", "submit_level", "end_run"] and requests.back()["body"]["p_reason"] == "invalidated" and requests[0]["body"] == {"p_mode": "ruthless"}, "a Ruthless run that left the foreground reports its level, then 'invalidated'")
	# H. a level finished before the run id arrived
	_reset_fake()
	_logged_in()
	_reset_progress()
	_answer_for("start_run", [_ok({"ok": true, "run_id": RUN1})])
	_answer_for("submit_level", [_ok({"ok": true, "new_best": true})])
	Progress.begin_run(GameMode.Mode.ENDLESS)
	GameManager.extraction_succeeded.emit(1, 5.0)
	await _settle()
	await _settle()
	_check(_paths() == ["start_run", "submit_level"] and requests[1]["body"]["p_run"] == RUN1, "a level finished before the server run id arrived is sent once it does")
	# I. the level cap
	_reset_fake()
	_logged_in()
	_reset_progress()
	_answer_for("start_run", [_ok({"ok": true, "run_id": RUN1})])
	Progress.begin_run(GameMode.Mode.ENDLESS)
	await _settle()
	Progress.run_levels.clear()
	for level in range(1, 9999):
		Progress.run_levels.append({"level": level, "seconds": 5.0})
	GameManager.extraction_succeeded.emit(9999, 5.0)
	GameManager.extraction_succeeded.emit(10000, 5.0)
	_check(Progress.highest_completed_level() == 9999 and int(Progress.best(GameMode.Mode.ENDLESS)["best_level"]) == 9999, "level 9999 is recorded and level 10000 never is (it does not exist)")
	# J. a damaged queue
	var damaged := {"queue": [{"kind": "level", "run": RUN1, "level": 3, "seconds": 4.0}, {"kind": "hack", "run": RUN1}, {"kind": "level", "run": "short"}, 7, {"kind": "end", "run": RUN2, "reason": "failed"}]}
	var file := FileAccess.open(Progress.store.path, FileAccess.WRITE)
	file.store_string(JSON.stringify(damaged))
	file.close()
	Progress.store.load_data()
	_check(Progress.store.data["queue"].size() == 2, "a damaged save keeps only well-formed queue entries (2 of 5)")
	_reset_progress()
	RunSync.enabled = false
