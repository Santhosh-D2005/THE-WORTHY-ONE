class_name AccountStore
extends RefCounted
## Where the guest credentials live: one small encrypted file inside the app's private storage (user://), written through a temp file.
##
## HONEST SECURITY NOTE. Godot has no access to the Android Keystore without a native plugin, so this is not hardware-backed. What it
## gives: the file sits in the app's private directory (other apps cannot read it on a normal phone), Android backup is switched off in
## the export (user_data_backup/allow=false), and the contents are encrypted with a key derived from the device id and the app name,
## so the file is not readable text and cannot simply be copied to another phone. It does NOT protect against a rooted device or someone
## who has the app's code and the phone. The server must therefore never treat the local secret as proof of anything but "the same
## install"; the login (username and password on the server) is what proves who a player is.

const SALT := "theworthyone.account.v1"

var path: String

func _init(file_path: String = "user://account.dat") -> void:
	path = file_path

func exists() -> bool:
	return FileAccess.file_exists(path)

static func key_for_device() -> String:
	var device := OS.get_unique_id()
	if device.is_empty():
		device = "no-device-id"
	return (SALT + "|" + device + "|com.theworthyone.game").sha256_text()

## Returns {} when the file is missing, unreadable (wrong device key, damaged) or not a dictionary.
func read() -> Dictionary:
	if not exists():
		return {}
	var file := FileAccess.open_encrypted_with_pass(path, FileAccess.READ, key_for_device())
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func write(data: Dictionary) -> bool:
	var temp := path + ".tmp"
	var file := FileAccess.open_encrypted_with_pass(temp, FileAccess.WRITE, key_for_device())
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp, path) == OK

func delete() -> void:
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
