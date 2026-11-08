extends Node
## Autoload "Progress": the player's local progress and the rules that differ between Endless and Ruthless.
##
## It owns the save file, knows which mode the next run uses, records every completed level the moment it is completed (so a crash
## or a kill never loses an achievement), and enforces the Ruthless rule: a run that loses the foreground is invalid, is written as
## invalid immediately, and can never be resumed. It does not touch the gameplay itself.
##
## Only COMPLETED levels are ever recorded. The level a player failed (or was on when the run ended) never counts.

signal run_started(mode: GameMode.Mode, run_id: String)
signal level_recorded(mode: GameMode.Mode, level: int, seconds: float, new_best: bool)
signal run_ended(summary: Dictionary)
signal run_invalidated(reason: String)

const SAVE_PATH := "user://progress.json"
## Headless test runs (the desktop suites) use their own file, so tests never touch a player's real progress.
const TEST_SAVE_PATH := "user://progress_headless.json"

var store: SaveStore
## Which mode the next run uses. The mode screen sets it; ENDLESS is the default so plain PLAY behaves as before.
var selected_mode: GameMode.Mode = GameMode.Mode.ENDLESS

var run_active: bool = false
var run_valid: bool = false
var run_mode: GameMode.Mode = GameMode.Mode.ENDLESS
var run_id: String = ""
## [{level, seconds}] in order, for the levels completed in the current run (the evidence the server will check).
var run_levels: Array[Dictionary] = []
var run_started_unix: int = 0
## The level this run started at: 1, except an Endless run that continues where the player left off.
var run_start_level: int = 1
## Endless continues from the saved level. The headless test suites switch this off (they all expect a run to begin at level 1);
## the tests of the feature itself switch it back on.
var continue_endless: bool = true
## True if this launch found a Ruthless run that was still active (the app was killed mid-run). Shown once, then cleared.
var abandoned_run_found: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	store = SaveStore.new(default_path())
	store.load_data()
	continue_endless = DisplayServer.get_name() != "headless"
	_recover_abandoned_run()
	GameManager.extraction_succeeded.connect(_on_extraction_succeeded)

static func default_path() -> String:
	return TEST_SAVE_PATH if DisplayServer.get_name() == "headless" else SAVE_PATH

## A Ruthless run still marked active on disk means the process died. It is closed as abandoned; there is nothing to resume from.
func _recover_abandoned_run() -> void:
	var run: Dictionary = store.data["ruthless_run"]
	if not bool(run.get("active", false)):
		return
	abandoned_run_found = true
	store.data["last_run"] = {"mode": "ruthless", "reason": "abandoned", "completed_level": 0, "unix": int(Time.get_unix_time_from_system())}
	store.data["ruthless_run"] = {"active": false, "run_id": "", "started_unix": 0}
	store.save()

func acknowledge_abandoned_run() -> void:
	abandoned_run_found = false

## A Ruthless run can never be resumed: this is the rule in one place, and the save file has no state to resume from.
func can_resume_ruthless_run() -> bool:
	return false

# ---- Runs ------------------------------------------------------------------------------------------

## The level a new run in `mode` begins at: Endless continues where the player left off, Ruthless always starts at 1.
func start_level_for(mode: GameMode.Mode) -> int:
	if mode == GameMode.Mode.ENDLESS and continue_endless:
		return clampi(int(store.data.get("endless_level", 1)), 1, GameManager.MAX_LEVEL)
	return 1

## Start a new run in `mode`. A Ruthless run is written to disk as active BEFORE anything else happens.
func begin_run(mode: GameMode.Mode) -> String:
	if run_active:
		end_run("replaced")
	run_mode = mode
	run_id = _new_run_id()
	run_levels = []
	run_start_level = start_level_for(mode)
	run_active = true
	run_valid = true
	run_started_unix = int(Time.get_unix_time_from_system())
	if mode == GameMode.Mode.RUTHLESS:
		store.data["ruthless_run"] = {"active": true, "run_id": run_id, "started_unix": run_started_unix}
		store.save()
	run_started.emit(mode, run_id)
	return run_id

func _on_extraction_succeeded(level: int, seconds: float) -> void:
	if not run_active or not run_valid:
		return  # an invalid or finished run records nothing
	if level != run_start_level + run_levels.size() or level > GameManager.MAX_LEVEL:
		return  # levels are only accepted in order, from the run's first level up to the last level, 9999
	run_levels.append({"level": level, "seconds": seconds})
	var key := GameMode.key(run_mode)
	var rec := store.record(key)
	rec["extractions"] = int(rec["extractions"]) + 1
	var improved := store.submit_level(key, level, seconds)
	if run_mode == GameMode.Mode.ENDLESS:
		store.data["endless_level"] = level + 1 if level < GameManager.MAX_LEVEL else 1  # the next run continues from here
	store.save()
	level_recorded.emit(run_mode, level, seconds, improved)

## The player left the foreground during a Ruthless run (or the same rule is triggered by a test). Written to disk at once.
## Returns true if a valid Ruthless run was ended by this call.
func invalidate_run(reason: String) -> bool:
	if not run_active or not run_valid or not GameMode.ends_run_on_background(run_mode):
		return false
	run_valid = false
	store.data["ruthless_run"] = {"active": false, "run_id": "", "started_unix": 0}
	store.save()
	run_invalidated.emit(reason)
	return true

## Close the current run: "failed", "invalidated", "left" (back to the menu) or "replaced". Returns the summary.
func end_run(reason: String) -> Dictionary:
	if not run_active:
		return {}
	var key := GameMode.key(run_mode)
	var rec := store.record(key)
	rec["runs"] = int(rec["runs"]) + 1
	var last_seconds: float = 0.0
	if not run_levels.is_empty():
		last_seconds = float(run_levels[-1]["seconds"])
	var summary := {
		"mode": key, "reason": reason, "run_id": run_id, "completed_level": highest_completed_level(),
		"seconds": last_seconds, "valid": run_valid, "unix": int(Time.get_unix_time_from_system()),
	}
	store.data["last_run"] = {"mode": key, "reason": reason, "completed_level": summary["completed_level"], "unix": summary["unix"]}
	if run_mode == GameMode.Mode.RUTHLESS:
		store.data["ruthless_run"] = {"active": false, "run_id": "", "started_unix": 0}
	run_active = false
	store.save()
	run_ended.emit(summary)
	return summary

## Levels completed in the current (or last) run. The level being attempted is never counted.
func highest_completed_level() -> int:
	return run_start_level - 1 + run_levels.size()

## After logging in, the server's records (the authority for the Hall of Fame) are brought onto this phone if they are better than the
## local ones. A reinstall plus a login therefore restores the player's best levels.
func apply_server_records(records: Dictionary) -> void:
	var improved := false
	for key in ["endless", "ruthless"]:
		var raw: Variant = records.get(key)
		if raw is Dictionary:
			var level := int(raw.get("best_level", 0))
			if level >= 1 and level <= GameManager.MAX_LEVEL and store.submit_level(key, level, float(raw.get("best_seconds", 0.0))):
				improved = true
	if improved:
		store.save()

func best(mode: GameMode.Mode) -> Dictionary:
	return store.record(GameMode.key(mode)).duplicate()

func _new_run_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
