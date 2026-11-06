extends Node
## MANUAL live check against the real Supabase project (not part of the automated suites). READ-ONLY plus one anonymous app session:
## it never registers an account and never submits a level.   godot --headless --path . res://tools/live_smoke.tscn
func _ready() -> void:
	await get_tree().process_frame
	Account.reset_for_test("user://live_smoke_account.dat")
	var session: Dictionary = await Backend.ensure_session()
	print("anonymous session: ", session)
	var account: Dictionary = await Backend.call_server("get_account")
	print("get_account while not logged in (expect not_logged_in): ", account.get("error"))
	var board: Dictionary = await Backend.leaderboard(GameMode.Mode.ENDLESS, 5, 0)
	print("endless board ok: ", board.get("ok"), " total: ", board.get("total"))
	var rules: Dictionary = await Backend.call_server("username_error", {"raw": "Admin"})
	print("server username rule for 'Admin': ", rules)
	var run: Dictionary = await Backend.call_server("start_run", {"p_mode": "endless"})
	print("start_run while not logged in (expect not_logged_in): ", run.get("error"))
	DirAccess.remove_absolute("user://live_smoke_account.dat")
	get_tree().quit()
