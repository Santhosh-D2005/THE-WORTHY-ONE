extends Node
## LIVE check of account deletion against the real server (writes, then removes, one throwaway account):
##   godot --headless --path . res://tools/live_delete_check.tscn
## Also removes the leftover test account Hallcheck_945700 from the earlier submission check (its password follows the same pattern).
## Steps: register a throwaway account -> wrong password is refused and nothing is deleted -> right password deletes -> logging in as it fails
## -> the username can be registered again (it is free) -> delete that one too. Leaves no test account behind.

func _ready() -> void:
	var stamp := str(int(Time.get_unix_time_from_system()) % 1000000)
	var username := "Delcheck_" + stamp
	var password := "Worthy-delete-" + stamp + "-2026"
	var ok := true
	ok = _step("anonymous session", (await Backend.ensure_session()).get("ok", false), "") and ok
	var registered := await Backend.register_account(username, password)
	ok = _step("register throwaway account " + username, registered.get("ok", false), registered) and ok
	var wrong := await Backend.delete_account("Not-The-Password-1")
	ok = _step("wrong password is refused", wrong.get("error", "") == "wrong_credentials" and Account.logged_in, wrong) and ok
	var deleted := await Backend.delete_account(password)
	ok = _step("right password deletes the account", deleted.get("ok", false) and not Account.logged_in, deleted) and ok
	var login := await Backend.log_in(username, password)
	ok = _step("the deleted account can no longer log in", not login.get("ok", false), login) and ok
	var again := await Backend.register_account(username, password)
	ok = _step("the username is free again", again.get("ok", false), again) and ok
	var cleanup := await Backend.delete_account(password)
	ok = _step("delete the re-registered account (cleanup)", cleanup.get("ok", false), cleanup) and ok
	# Remove the earlier submission-check test account (password pattern from tools/live_submission_check.gd).
	var old_login := await Backend.log_in("Hallcheck_945700", "Worthy-check-945700-2026")
	if old_login.get("ok", false):
		var old_deleted := await Backend.delete_account("Worthy-check-945700-2026")
		ok = _step("remove the earlier test account Hallcheck_945700", old_deleted.get("ok", false), old_deleted) and ok
	else:
		print("  INFO  Hallcheck_945700 not found or already removed: ", old_login.get("error", ""))
	Account.clear_login()
	print("LIVE DELETE CHECK ", "PASSED" if ok else "FAILED")
	get_tree().quit(0 if ok else 1)

func _step(label: String, passed: bool, detail: Variant) -> bool:
	print("  %s  %s%s" % ["PASS" if passed else "FAIL", label, "" if passed else "  -> " + str(detail)])
	return passed
