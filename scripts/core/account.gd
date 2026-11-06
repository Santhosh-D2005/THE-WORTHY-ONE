extends Node
## Autoload "Account": who is playing on this device.
##
## The player logs in with a username and password (the server checks them; see Backend and server/schema.sql). This node remembers only
## what is safe to remember: the username, the server player id, and the credential of the app's anonymous session (a refresh token), all in
## one encrypted file (see AccountStore for what that protects and what it does not). THE PASSWORD IS NEVER STORED, LOGGED OR KEPT IN
## MEMORY BEYOND THE LOGIN CALL.
##
## Not logged in is a normal state: the game plays fine, records stay on the phone, and nothing is sent to the Hall of Fame. Uninstalling
## the app or clearing its data removes this file: the player simply logs in again (the server keeps their online records).

signal changed

const FILE_PATH := "user://account.dat"
## The desktop test runs use their own file so they never touch a real account.
const TEST_FILE_PATH := "user://account_headless.dat"

var username: String = ""
var player_id: String = ""
var logged_in: bool = false
## True once the player chose "play offline for now" on the first-launch screen: the login prompt is not shown again by itself.
var login_skipped: bool = false
## The app's anonymous Supabase session: its user id and refresh token. Losing them only means logging in again.
var auth_user_id: String = ""
var refresh_token: String = ""
var created_unix: int = 0
## False if the file could not be written (the state then only lives until the app closes).
var persisted: bool = false

var store: AccountStore

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var headless := DisplayServer.get_name() == "headless"
	store = AccountStore.new(TEST_FILE_PATH if headless else FILE_PATH)
	load_data()
	# The desktop suites open the main menu all the time; the first-launch login screen has its own tests and would otherwise block them.
	if headless and not OS.get_cmdline_user_args().has("--fresh-account"):
		login_skipped = true

func load_data() -> void:
	var data := store.read()
	username = str(data.get("username", ""))
	player_id = str(data.get("player_id", ""))
	logged_in = bool(data.get("logged_in", false)) and username != "" and player_id != ""
	login_skipped = bool(data.get("login_skipped", false))
	auth_user_id = str(data.get("auth_user_id", ""))
	refresh_token = str(data.get("refresh_token", ""))
	created_unix = int(data.get("created_unix", 0))
	persisted = not data.is_empty()
	if created_unix == 0:
		created_unix = int(Time.get_unix_time_from_system())

## Show the login screen by itself? Only on a fresh install that has neither logged in nor chosen to play offline.
func needs_login_prompt() -> bool:
	return not logged_in and not login_skipped

func set_logged_in(server_player_id: String, server_username: String) -> void:
	player_id = server_player_id
	username = server_username
	logged_in = true
	login_skipped = false
	_save()
	changed.emit()

## The server says this session is no longer logged in (for example the app's anonymous session was replaced).
func mark_logged_out() -> void:
	if not logged_in:
		return
	logged_in = false
	_save()
	changed.emit()

## Log out on this device: forget the account AND the app's session, so nothing on the phone can act as this account any more.
func clear_login() -> void:
	logged_in = false
	username = ""
	player_id = ""
	auth_user_id = ""
	refresh_token = ""
	_save()
	changed.emit()

func skip_login() -> void:
	login_skipped = true
	_save()
	changed.emit()

## Keep the anonymous session's credential (the server rotates it on every refresh, so it is saved every time). A DIFFERENT user id means a
## brand-new session, which is not logged in to any account yet.
func store_session(user_id: String, refresh: String) -> void:
	if auth_user_id != "" and user_id != "" and user_id != auth_user_id:
		logged_in = false
	auth_user_id = user_id
	refresh_token = refresh
	_save()
	changed.emit()

## What may be shown on screen. Never includes the session credential.
func public_info() -> Dictionary:
	return {"username": username, "player_id": player_id, "logged_in": logged_in, "created_unix": created_unix}

## Test hook: start over on a given file.
func reset_for_test(file_path: String) -> void:
	store = AccountStore.new(file_path)
	store.delete()
	username = ""
	player_id = ""
	logged_in = false
	login_skipped = false
	auth_user_id = ""
	refresh_token = ""
	created_unix = int(Time.get_unix_time_from_system())
	persisted = false
	changed.emit()

func _save() -> bool:
	persisted = store.write({
		"version": 2, "username": username, "player_id": player_id, "logged_in": logged_in, "login_skipped": login_skipped,
		"auth_user_id": auth_user_id, "refresh_token": refresh_token, "created_unix": created_unix,
	})
	return persisted
