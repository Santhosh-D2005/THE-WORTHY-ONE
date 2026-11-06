extends Node
## Autoload "Backend": the online service layer (Supabase). It gets the app an anonymous session, registers or logs in an ACCOUNT on top of
## it, and offers one call_server() used by everything else. It never touches game rules; it only talks to the server.
##
## HOW IDENTITY WORKS. Supabase gives each install an anonymous session (kept as a refresh token in Account). A player becomes "someone" only
## by registering or logging in: the server then binds that session to the account (username + bcrypt password hash, see server/schema.sql).
## Reinstalling gives a new anonymous session; logging in binds it to the same account again, so the online records come back. If the saved
## session ever stops working, a new anonymous session is created and the player must log in again (nothing is lost: the account lives on the
## server). THE PASSWORD ONLY EVER PASSES THROUGH register_account() / log_in() / change_password(): it is sent over TLS, never stored,
## never logged, never put in a signal or a return value.
##
## OFFLINE. Every call returns {"ok": false, "error": "offline"|"timeout"|"network"|"http_<status>"|<server code>}. Nothing is invented when
## the server cannot be reached. Server answers are returned as the server sent them ({"ok": true, ...} / {"ok": false, "error": "<code>"}).

signal session_replaced

const NETWORK_ERRORS: Array[String] = ["offline", "timeout", "network"]

## (method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary (a coroutine). Tests replace it.
var transport: Callable
var access_token: String = ""
var expires_at: int = 0

var _http: HttpTransport
var _busy: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HttpTransport.new()
	_http.name = "Http"
	add_child(_http)
	transport = _http.send

## True when no answer could be had because of the network or a server fault (so it is worth retrying later).
static func is_retryable(error: String) -> bool:
	return error in NETWORK_ERRORS or error == "http_429" or error.begins_with("http_5")

func has_valid_token() -> bool:
	return access_token != "" and int(Time.get_unix_time_from_system()) < expires_at - 60

## Make sure the app has a usable anonymous session. Returns {"ok": bool, "error": String}.
func ensure_session() -> Dictionary:
	while _busy:
		await get_tree().process_frame
	if has_valid_token():
		return {"ok": true, "error": ""}
	_busy = true
	var result := await _acquire_session()
	_busy = false
	return result

func _acquire_session() -> Dictionary:
	var reply: Dictionary
	if Account.refresh_token != "":
		reply = await _post("/auth/v1/token?grant_type=refresh_token", {"refresh_token": Account.refresh_token}, "")
		if not reply["ok"]:
			if is_retryable(reply["error"]):
				return {"ok": false, "error": reply["error"]}
			# The saved session is dead for good. Start a fresh anonymous one; the player has to log in again.
			Account.store_session("", "")
			Account.mark_logged_out()
			session_replaced.emit()
			reply = await _post("/auth/v1/signup", {}, "")
	else:
		reply = await _post("/auth/v1/signup", {}, "")
	if not reply["ok"]:
		return {"ok": false, "error": reply["error"]}
	_store_tokens(reply["data"])
	return {"ok": true, "error": ""}

func _store_tokens(data: Variant) -> void:
	if not data is Dictionary:
		return
	access_token = str(data.get("access_token", ""))
	var lifetime := int(data.get("expires_in", 3600))
	expires_at = int(data.get("expires_at", int(Time.get_unix_time_from_system()) + lifetime))
	var user: Variant = data.get("user", {})
	var user_id := str((user as Dictionary).get("id", "")) if user is Dictionary else ""
	Account.store_session(user_id if user_id != "" else Account.auth_user_id, str(data.get("refresh_token", Account.refresh_token)))

## Call a server function. Returns the server's JSON ({"ok": ...}) or {"ok": false, "error": ...} for transport problems.
## If the server says this session is not logged in, the account is marked logged out locally too.
func call_server(function_name: String, arguments: Dictionary = {}) -> Dictionary:
	var session := await ensure_session()
	if not session["ok"]:
		return {"ok": false, "error": session["error"]}
	var reply := await _post("/rest/v1/rpc/" + function_name, arguments, access_token)
	if reply["status"] == 401:  # the access token expired between the check and the call: refresh once and retry
		access_token = ""
		session = await ensure_session()
		if not session["ok"]:
			return {"ok": false, "error": session["error"]}
		reply = await _post("/rest/v1/rpc/" + function_name, arguments, access_token)
	if reply["ok"]:
		var data: Variant = reply["data"]
		var answer: Dictionary = data if data is Dictionary else {"ok": true, "value": data}
		if str(answer.get("error", "")) == "not_logged_in":
			Account.mark_logged_out()
		return answer
	var message := ""
	if reply["data"] is Dictionary:
		message = str((reply["data"] as Dictionary).get("message", ""))
	return {"ok": false, "error": reply["error"], "message": message}

# ---- accounts ----------------------------------------------------------------------------------

## Create an account and log this install in to it. The caller checks CredentialRules first; the server checks again.
func register_account(username: String, password: String) -> Dictionary:
	var answer := await call_server("register_account", {"p_username": username, "p_password": password})
	if answer.get("ok", false):
		Account.set_logged_in(str(answer["player_id"]), str(answer["username"]))
		await sync_records()
	return answer

## Log this install in to an existing account. Wrong password and unknown username give the same answer.
func log_in(username: String, password: String) -> Dictionary:
	var answer := await call_server("login", {"p_username": username, "p_password": password})
	if answer.get("ok", false):
		Account.set_logged_in(str(answer["player_id"]), str(answer["username"]))
		await sync_records()
	return answer

## Log out: tell the server (best effort), then forget the account AND this install's session either way, so the phone cannot act as the
## account any more. Logging in again restores everything from the server.
func log_out() -> Dictionary:
	var answer := {"ok": true}
	if Account.refresh_token != "":
		answer = await call_server("logout")
	Account.clear_login()
	access_token = ""
	expires_at = 0
	return answer

func change_password(old_password: String, new_password: String) -> Dictionary:
	return await call_server("change_password", {"p_old": old_password, "p_new": new_password})

## Bring the server's records onto this phone (the server is the authority for what counts online).
func sync_records() -> void:
	var answer := await call_server("get_account")
	if answer.get("ok", false) and answer.get("records") is Dictionary:
		Progress.apply_server_records(answer["records"])

func leaderboard(mode: GameMode.Mode, limit: int = 25, offset: int = 0) -> Dictionary:
	return await call_server("leaderboard_page", {"p_mode": GameMode.key(mode), "p_limit": limit, "p_offset": offset})

## One line of flavour text from the server's Edge Function (which holds the Gemini key; the game never sees it).
## Only a mode, a level and an end reason are sent. Returns {"ok": true, "text": ...} or {"ok": false, ...}.
func verdict(mode: GameMode.Mode, level: int, reason: String) -> Dictionary:
	var session := await ensure_session()
	if not session["ok"]:
		return {"ok": false, "error": session["error"]}
	var reply := await _post("/functions/v1/verdict", {"mode": GameMode.key(mode), "level": level, "reason": reason}, access_token)
	if reply["ok"] and reply["data"] is Dictionary:
		return reply["data"]
	return {"ok": false, "error": reply["error"]}

# ---- plumbing ----------------------------------------------------------------------------------

func _post(path: String, body: Dictionary, token: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, path, body, token)

func _request(method: int, path: String, body: Dictionary, token: String) -> Dictionary:
	var headers := PackedStringArray(["apikey: " + BackendConfig.PUBLISHABLE_KEY, "Content-Type: application/json", "Accept: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var payload := "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	var answer: Dictionary = await transport.call(method, BackendConfig.URL + path, headers, payload)
	var failure := str(answer.get("error", ""))
	if failure != "":
		return {"ok": false, "status": 0, "error": failure, "data": {}}
	var status := int(answer.get("status", 0))
	var parsed: Variant = JSON.parse_string(str(answer.get("body", "")))
	if status >= 200 and status < 300:
		return {"ok": true, "status": status, "error": "", "data": parsed}
	return {"ok": false, "status": status, "error": "http_%d" % status, "data": parsed if parsed != null else {}}
