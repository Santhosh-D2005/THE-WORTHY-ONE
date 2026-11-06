class_name CredentialRules
extends RefCounted
## Username and password rules. The SERVER repeats every rule (server/schema.sql) and is the authority; this class only gives the player
## an instant, friendly answer before anything is sent. The same fixture files are used by the server tests and the game's tests, so the
## two can never disagree. Nothing here ever stores or logs a password.

const USERNAME_MIN := 3
const USERNAME_MAX := 20
const PASSWORD_MIN := 8
const PASSWORD_MAX_BYTES := 72   ## bcrypt ignores anything past 72 bytes, so longer passwords are refused instead of silently cut

const RESERVED: Array[String] = ["admin", "moderator", "support", "system", "official", "staff", "developer", "gamemaster"]
const BLOCKED: Array[String] = ["fuck", "shit", "bitch", "cunt", "nigg", "asshole", "bastard", "slut", "whore", "rape", "nazi", "hitler", "dick", "pussy", "cock"]
const COMMON_PASSWORDS: Array[String] = ["password", "password1", "password123", "12345678", "123456789", "1234567890", "qwertyui", "qwerty123", "iloveyou", "abcdefgh", "theworthyone", "worthyone", "11111111", "00000000"]

const MESSAGES := {
	"too_short": "A username needs at least 3 characters.",
	"too_long": "A username can have at most 20 characters.",
	"bad_start": "A username must start with a letter.",
	"bad_character": "Use only letters, numbers and the underscore (_).",
	"reserved": "That username is reserved.",
	"not_allowed": "That username is not allowed.",
	"pw_too_short": "A password needs at least 8 characters.",
	"pw_too_long": "That password is too long (72 bytes at most).",
	"pw_same_as_username": "The password cannot be your username.",
	"pw_too_common": "That password is too easy to guess. Choose another.",
	"pw_mismatch": "The two passwords are not the same.",
	"username_taken": "That username is already taken.",
	"wrong_credentials": "Wrong username or password.",
	"rate_limited": "Too many new accounts right now. Please try again in a while.",
	"already_logged_in": "You are already logged in.",
	"offline": "You are offline. Check your connection and try again.",
	"timeout": "The server took too long to answer. Try again.",
	"network": "The connection failed. Try again.",
}

## "" if the username is fine, else a code (the same codes as the server).
static func username_error(raw: String) -> String:
	var name := raw.strip_edges()
	if name.length() < USERNAME_MIN:
		return "too_short"
	if name.length() > USERNAME_MAX:
		return "too_long"
	if not _is_ascii_letter(name.unicode_at(0)):
		return "bad_start"
	for i in name.length():
		var c := name.unicode_at(i)
		if not (_is_ascii_letter(c) or (c >= 48 and c <= 57) or c == 95):
			return "bad_character"
	var squashed := _squash(name)
	for word in RESERVED:
		if squashed.contains(word):
			return "reserved"
	for word in BLOCKED:
		if squashed.contains(word):
			return "not_allowed"
	return ""

## "" if the password is acceptable, else a code.
static func password_error(password: String, username: String) -> String:
	if password.length() < PASSWORD_MIN:
		return "pw_too_short"
	if password.to_utf8_buffer().size() > PASSWORD_MAX_BYTES:
		return "pw_too_long"
	if password.to_lower() == username.strip_edges().to_lower():
		return "pw_same_as_username"
	if password.to_lower() in COMMON_PASSWORDS:
		return "pw_too_common"
	var first := password.unicode_at(0)
	var all_same := true
	for i in password.length():
		if password.unicode_at(i) != first:
			all_same = false
			break
	return "pw_too_common" if all_same else ""

## Text for the player for any rule code or server error code (a plain default for anything unknown).
static func message(code: String, extra: Dictionary = {}) -> String:
	if code == "locked":
		var minutes := maxi(int(ceil(float(extra.get("wait_seconds", 900)) / 60.0)), 1)
		return "Too many wrong attempts. Try again in %d minute%s." % [minutes, "" if minutes == 1 else "s"]
	return str(MESSAGES.get(code, "Something went wrong (%s). Please try again." % code))

static func _is_ascii_letter(c: int) -> bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

## Lower-case letters only, with the usual look-alike digits turned back into letters (so "H1tl3r" is caught).
static func _squash(name: String) -> String:
	var out := ""
	for i in name.length():
		var c := name[i].to_lower()
		match c:
			"0": c = "o"
			"1": c = "i"
			"3": c = "e"
			"4": c = "a"
			"5": c = "s"
			"7": c = "t"
		var code := c.unicode_at(0)
		if code >= 97 and code <= 122:
			out += c
	return out
