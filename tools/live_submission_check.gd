extends Node
## LIVE check of the Hall of Fame path against the real server (run deliberately, it WRITES one test account and one test run):
##   godot --headless --path . res://tools/live_submission_check.tscn
## Steps, through the game's own Backend code: new anonymous session -> register a test account -> start an ENDLESS run -> submit level 1
## -> end the run -> read the endless leaderboard and look for the run. Prints PASS/FAIL per step. The test account is named Hallcheck_<time>.

func _ready() -> void:
	var stamp := str(int(Time.get_unix_time_from_system()) % 1000000)
	var username := "Hallcheck_" + stamp
	var password := "Worthy-check-" + stamp + "-2026"
	var ok := true
	var session := await Backend.ensure_session()
	ok = _step("anonymous session", session.get("ok", false), session) and ok
	var registered := await Backend.register_account(username, password)
	ok = _step("register account " + username, registered.get("ok", false), registered) and ok
	var start := await Backend.call_server("start_run", {"p_mode": "endless"})
	var run := str(start.get("run", start.get("run_id", "")))
	ok = _step("start endless run", start.get("ok", false) and run != "", start) and ok
	await get_tree().create_timer(7.0).timeout  # the server checks the reported time against the real time elapsed since the run started
	var level := await Backend.call_server("submit_level", {"p_run": run, "p_level": 1, "p_seconds": 5.0})
	ok = _step("submit level 1 (5.0 s)", level.get("ok", false), level) and ok
	var ended := await Backend.call_server("end_run", {"p_run": run, "p_reason": "completed"})
	ok = _step("end run as completed", ended.get("ok", false), ended) and ok
	var board := await Backend.leaderboard(GameMode.Mode.ENDLESS, 25, 0)
	var listed := false
	var me: Variant = board.get("me")
	if board.get("ok", false) and me is Dictionary:
		listed = int(me.get("level", 0)) >= 1
	ok = _step("leaderboard shows our place for level >= 1", listed, {"me": me, "total": board.get("total", 0)}) and ok
	Account.clear_login()  # leave this machine's game logged out of the test account
	print("LIVE CHECK ", "PASSED" if ok else "FAILED", " (test account: ", username, ")")
	get_tree().quit(0 if ok else 1)

func _step(label: String, passed: bool, detail: Variant) -> bool:
	print("  %s  %s%s" % ["PASS" if passed else "FAIL", label, "" if passed else "  -> " + str(detail)])
	return passed
