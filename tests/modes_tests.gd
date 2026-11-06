extends Node
## Phase 2: Endless and Ruthless modes. (1) the save file, (2) the Progress rules (records, order, persistence, invalidation, relaunch),
## (3) the real game scene in both modes with simulated taps and simulated Android lifecycle notifications.
## Run headless:   godot --headless --path . res://tests/modes_tests.tscn
## DESKTOP, SIMULATED ONLY: lifecycle events are sent to the node with notification(); this proves the logic, NOT how a real phone
## behaves (that needs the physical test). Uses the headless save file (user://progress_headless.json), never a player's real save.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const TMP := "user://modes_test_save.json"

var _checks := 0
var _failures := 0
var main: Node
var input: InputController
var extraction: ExtractionManager
var timers: TimerManager
var _completed := false

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
	await _frames(3)
	_t_save_store()
	_t_progress_endless()
	_t_progress_ruthless()
	await _t_relaunch()
	await _t_scene_endless()
	await _t_scene_ruthless()
	_cleanup()
	print("\n==== %d checks, %d failed ====" % [_checks, _failures])
	print("RESULT: ALL PASSED" if _failures == 0 else "RESULT: FAILURES")
	get_tree().quit(0 if _failures == 0 else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(TMP + suffix):
			DirAccess.remove_absolute(TMP + suffix)

func _reset_progress() -> void:
	Progress.store.data = SaveStore.default_data()
	Progress.store.save()
	Progress.run_active = false
	Progress.run_valid = false
	Progress.run_levels = []
	Progress.abandoned_run_found = false

func _disk() -> SaveStore:
	var fresh := SaveStore.new(Progress.store.path)
	fresh.load_data()
	return fresh

# ---- 1. the save file --------------------------------------------------------------------------------------

func _t_save_store() -> void:
	print("\n[1] SAVE FILE")
	_cleanup()
	var s := SaveStore.new(TMP)
	s.load_data()
	_check(int(s.record("endless")["best_level"]) == 0 and int(s.record("ruthless")["best_level"]) == 0 and not s.recovered_from_damage, "no file: a clean default, no damage reported")
	_check(not bool(s.data["ruthless_run"]["active"]), "a clean default has no active Ruthless run")
	_check(s.submit_level("endless", 5, 20.0) and not s.submit_level("endless", 4, 1.0), "a higher level improves the record, a lower one does not")
	_check(not s.submit_level("endless", 5, 25.0) and s.submit_level("endless", 5, 19.5), "the same level only improves with a faster time (tie-break)")
	_check(not s.submit_level("endless", 0, 1.0) and not s.submit_level("endless", -3, 1.0) and not s.submit_level("endless", 6, -1.0), "level 0, negative levels and negative times are refused")
	_check(int(s.record("ruthless")["best_level"]) == 0, "an Endless submission never touches the Ruthless record")
	_check(s.save() and FileAccess.file_exists(TMP) and not FileAccess.file_exists(TMP + ".tmp") and not FileAccess.file_exists(TMP + ".bak"), "save writes the file and leaves no temp or backup file")
	var again := SaveStore.new(TMP)
	again.load_data()
	_check(int(again.record("endless")["best_level"]) == 5 and is_equal_approx(float(again.record("endless")["best_seconds"]), 19.5), "the record survives a reload (level 5, 19.5 s)")
	# Damage.
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var damaged := SaveStore.new(TMP)
	damaged.load_data()
	_check(int(damaged.record("endless")["best_level"]) == 0 and damaged.recovered_from_damage, "a damaged file gives a clean default and says so (no crash)")
	# Backup fallback: main file damaged, backup good.
	var good := FileAccess.open(TMP + ".bak", FileAccess.WRITE)
	good.store_string(JSON.stringify({"version": 1, "modes": {"endless": {"best_level": 9, "best_seconds": 3.0}}}))
	good.close()
	var from_backup := SaveStore.new(TMP)
	from_backup.load_data()
	_check(int(from_backup.record("endless")["best_level"]) == 9, "with the main file damaged the backup is used (level 9)")
	# Type safety and nonsense values.
	var junk := FileAccess.open(TMP, FileAccess.WRITE)
	junk.store_string(JSON.stringify({"modes": {"endless": {"best_level": -4, "best_seconds": "x", "runs": [1]}, "ruthless": 7}, "ruthless_run": "yes", "last_run": 3}))
	junk.close()
	var cleaned := SaveStore.new(TMP)
	cleaned.load_data()
	_check(int(cleaned.record("endless")["best_level"]) == 0 and int(cleaned.record("ruthless")["best_level"]) == 0 and not bool(cleaned.data["ruthless_run"]["active"]), "wrong types and negative numbers are cleaned, never crash")
	_cleanup()

# ---- 2. Progress rules: Endless ----------------------------------------------------------------------------

func _t_progress_endless() -> void:
	print("\n[2] PROGRESS: ENDLESS")
	_reset_progress()
	Progress.begin_run(GameMode.Mode.ENDLESS)
	_check(Progress.run_active and Progress.run_valid and Progress.run_mode == GameMode.Mode.ENDLESS and Progress.run_id.length() == 32, "a run starts (valid, Endless, 32-character run id)")
	var first_id := Progress.run_id
	_check(not bool(_disk().data["ruthless_run"]["active"]), "an Endless run writes no Ruthless 'active' flag")
	for level in range(1, 8):
		GameManager.extraction_succeeded.emit(level, 10.0 - level * 0.1)
	_check(Progress.highest_completed_level() == 7 and int(Progress.best(GameMode.Mode.ENDLESS)["best_level"]) == 7, "levels 1..7 completed: highest completed level 7, record 7")
	GameManager.extraction_succeeded.emit(9, 1.0)
	_check(Progress.highest_completed_level() == 7, "a level that skips ahead (9 after 7) is refused: levels count only in order")
	GameManager.extraction_succeeded.emit(7, 1.0)
	_check(Progress.highest_completed_level() == 7 and int(Progress.best(GameMode.Mode.ENDLESS)["extractions"]) == 7, "the same level reported twice counts once (7 extractions)")
	_check(int(_disk().record("endless")["best_level"]) == 7, "the record is already on disk before the run ends (a kill would not lose it)")
	var summary := Progress.end_run("failed")
	_check(summary["completed_level"] == 7 and summary["mode"] == "endless" and summary["reason"] == "failed", "the run summary says 7 completed levels, Endless, failed (the failed level 8 is not counted)")
	_check(Progress.end_run("failed").is_empty() and int(Progress.best(GameMode.Mode.ENDLESS)["runs"]) == 1, "ending a finished run again does nothing (1 run)")
	GameManager.extraction_succeeded.emit(8, 1.0)
	_check(int(Progress.best(GameMode.Mode.ENDLESS)["best_level"]) == 7, "nothing is recorded after the run has ended")
	# A worse second run does not lower the record, a better one raises it.
	Progress.begin_run(GameMode.Mode.ENDLESS)
	_check(Progress.run_id != first_id, "a new run gets a new run id")
	for level in range(1, 4):
		GameManager.extraction_succeeded.emit(level, 2.0)
	Progress.end_run("failed")
	_check(int(Progress.best(GameMode.Mode.ENDLESS)["best_level"]) == 7, "a worse run (3 levels) leaves the best at 7")
	Progress.begin_run(GameMode.Mode.ENDLESS)
	for level in range(1, 8):
		GameManager.extraction_succeeded.emit(level, 1.0)
	_check(is_equal_approx(float(Progress.best(GameMode.Mode.ENDLESS)["best_seconds"]), 1.0), "the same best level 7 in a faster time replaces the time (tie-break)")
	Progress.end_run("left")
	# No ceiling.
	Progress.begin_run(GameMode.Mode.ENDLESS)
	for level in range(1, 1501):
		GameManager.extraction_succeeded.emit(level, 5.0)
	_check(Progress.highest_completed_level() == 1500 and int(Progress.best(GameMode.Mode.ENDLESS)["best_level"]) == 1500, "there is no maximum level: 1500 levels completed and recorded")
	Progress.end_run("left")
	var reloaded := _disk()
	_check(int(reloaded.record("endless")["best_level"]) == 1500 and int(reloaded.record("endless")["runs"]) == 4, "after a reload from disk: best level 1500, 4 runs")
	_check(int(reloaded.record("ruthless")["best_level"]) == 0 and int(reloaded.record("ruthless")["runs"]) == 0, "...and the Ruthless record is untouched")

# ---- 2b. Progress rules: Ruthless --------------------------------------------------------------------------

func _t_progress_ruthless() -> void:
	print("\n[3] PROGRESS: RUTHLESS")
	_reset_progress()
	Progress.begin_run(GameMode.Mode.RUTHLESS)
	var disk := _disk()
	_check(bool(disk.data["ruthless_run"]["active"]) and str(disk.data["ruthless_run"]["run_id"]) == Progress.run_id, "a Ruthless run is written to disk as ACTIVE the moment it starts")
	for level in range(1, 4):
		GameManager.extraction_succeeded.emit(level, 4.0)
	_check(int(_disk().record("ruthless")["best_level"]) == 3 and int(_disk().record("endless")["best_level"]) == 0, "3 completed levels recorded in the Ruthless record only")
	var invalidated := []
	Progress.run_invalidated.connect(func(reason: String) -> void: invalidated.append(reason))
	_check(Progress.invalidate_run("background") and not Progress.run_valid and invalidated == ["background"], "leaving the foreground invalidates the run (signal sent once)")
	var after := _disk()
	_check(not bool(after.data["ruthless_run"]["active"]), "the invalidation is on disk immediately")
	_check(not Progress.invalidate_run("background") and invalidated.size() == 1, "invalidating twice does nothing")
	GameManager.extraction_succeeded.emit(4, 3.0)
	_check(Progress.highest_completed_level() == 3 and int(_disk().record("ruthless")["best_level"]) == 3, "an invalid run records nothing more (level 4 refused)")
	_check(int(_disk().record("ruthless")["best_level"]) == 3, "...but the 3 levels completed before leaving stay recorded")
	var summary := Progress.end_run("invalidated")
	_check(summary["valid"] == false and summary["completed_level"] == 3 and summary["reason"] == "invalidated", "the summary marks the run invalid with 3 completed levels")
	_check(not Progress.can_resume_ruthless_run() and not Progress.run_active, "there is no way to resume a Ruthless run")
	# Endless is never invalidated.
	Progress.begin_run(GameMode.Mode.ENDLESS)
	_check(not Progress.invalidate_run("background") and Progress.run_valid, "an Endless run is NOT invalidated by leaving the foreground")
	Progress.end_run("left")
	# The pause-menu path ("left") closes the Ruthless flag too.
	Progress.begin_run(GameMode.Mode.RUTHLESS)
	Progress.end_run("left")
	_check(not bool(_disk().data["ruthless_run"]["active"]), "ending a Ruthless run cleanly clears the active flag")

# ---- 3. relaunch after a kill ------------------------------------------------------------------------------

func _t_relaunch() -> void:
	print("\n[4] RELAUNCH AFTER THE APP WAS KILLED")
	_reset_progress()
	Progress.begin_run(GameMode.Mode.RUTHLESS)
	for level in range(1, 3):
		GameManager.extraction_succeeded.emit(level, 6.0)
	# The process dies here: no end_run, no invalidate. The disk says "active".
	_check(bool(_disk().data["ruthless_run"]["active"]), "(simulated kill) the disk still says a Ruthless run is active")
	var relaunched: Node = load("res://scripts/core/progress.gd").new()
	add_child(relaunched)
	await _frames(1)
	_check(relaunched.abandoned_run_found, "the next launch finds the unfinished Ruthless run")
	_check(not relaunched.run_active and not relaunched.can_resume_ruthless_run() and relaunched.run_levels.is_empty(), "...it is not resumable: no active run, no levels, no state to resume from")
	var disk := _disk()
	_check(not bool(disk.data["ruthless_run"]["active"]) and disk.data["last_run"]["reason"] == "abandoned", "...and it is closed on disk as abandoned")
	_check(int(disk.record("ruthless")["best_level"]) == 2, "the 2 levels completed before the kill are still in the Ruthless record")
	relaunched.acknowledge_abandoned_run()
	_check(not relaunched.abandoned_run_found, "the notice can be dismissed once")
	var second: Node = load("res://scripts/core/progress.gd").new()
	add_child(second)
	await _frames(1)
	_check(not second.abandoned_run_found, "a second launch does not report it again")
	relaunched.queue_free()
	second.queue_free()
	await _frames(2)

# ---- 4. the real scene: Endless ----------------------------------------------------------------------------

func _fresh(mode: GameMode.Mode) -> void:
	if main != null:
		main.queue_free()
		await get_tree().process_frame
	get_tree().paused = false
	_reset_progress()
	Progress.selected_mode = mode
	main = load(MAIN_SCENE).instantiate()
	add_child(main)
	input = main.get_node("InputController")
	extraction = main.get_node("ExtractionManager")
	timers = main.get_node("TimerManager")
	_completed = false
	extraction.extraction_completed.connect(func() -> void: _completed = true)
	while GameManager.state != GameManager.State.READY:
		await get_tree().process_frame
	await _wait(0.1)

func _tap_until_complete(interval_ms: float, max_seconds: float) -> void:
	_completed = false
	var side := TapSide.Side.LEFT
	var next := Time.get_ticks_msec()
	var deadline := next + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and not _completed and GameManager.state != GameManager.State.FAILED:
		if Time.get_ticks_msec() >= next:
			input.handle_tap(side)
			side = TapSide.Side.RIGHT if side == TapSide.Side.LEFT else TapSide.Side.LEFT
			next += int(interval_ms)
		await get_tree().process_frame

func _wait_ready_at(level: int) -> void:
	var guard := Time.get_ticks_msec() + 9000
	while not (GameManager.level == level and GameManager.state == GameManager.State.READY) and Time.get_ticks_msec() < guard:
		await get_tree().process_frame

func _t_scene_endless() -> void:
	print("\n[5] REAL SCENE: ENDLESS")
	await _fresh(GameMode.Mode.ENDLESS)
	var config: DifficultyConfig = load("res://resources/difficulty/default_difficulty.tres")
	_check(Progress.run_active and Progress.run_mode == GameMode.Mode.ENDLESS and is_equal_approx(extraction.gain_per_tap, config.peak_gain_for_level(1)), "the game starts an Endless run on the existing difficulty configuration")
	await _tap_until_complete(150.0, 25.0)
	await _wait_ready_at(2)
	await _tap_until_complete(150.0, 25.0)
	await _wait_ready_at(3)
	_check(Progress.highest_completed_level() == 2 and int(Progress.best(GameMode.Mode.ENDLESS)["best_level"]) == 2, "two real levels completed: 2 recorded")
	# Focus loss in Endless pauses (existing behaviour) and does not touch the run.
	main.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(GameManager.state == GameManager.State.PAUSED and Progress.run_valid and Progress.run_active, "Endless: leaving the foreground pauses the game and the run stays valid")
	GameManager.resume_game()
	input.handle_tap(TapSide.Side.LEFT)
	await _wait(0.1)
	main._on_progress_depleted()
	await _wait(1.8)
	var result: RunResult = GameManager.last_result
	_check(GameManager.state == GameManager.State.FAILED and result != null and result.completed_level == 2 and result.level_reached == 3 and result.mode == GameMode.Mode.ENDLESS and result.end_reason == RunResult.EndReason.FAILURE,
		"failing on level 3: the result says 2 completed (level 3 is not counted), Endless, a plain failure")
	_check(not Progress.run_active and int(_disk().record("endless")["best_level"]) == 2 and int(_disk().record("endless")["runs"]) == 1, "the run is closed and the record is on disk (best 2, 1 run)")
	var title: Label = main.get_node("FailureScreen").find_child("Title", true, false)
	_check(title.text == "THE SWORD REMAINS", "the normal failure screen keeps its wording")
	main._restart_run()
	await _wait(0.4)
	_check(Progress.run_active and Progress.run_valid and Progress.highest_completed_level() == 0 and GameManager.level == 1, "TRY AGAIN starts a new Endless run at level 1")
	_check(int(Progress.best(GameMode.Mode.ENDLESS)["best_level"]) == 2, "...and the best (2) is kept")

# ---- 5. the real scene: Ruthless ---------------------------------------------------------------------------

func _t_scene_ruthless() -> void:
	print("\n[6] REAL SCENE: RUTHLESS")
	await _fresh(GameMode.Mode.RUTHLESS)
	var ruthless: DifficultyConfig = load("res://resources/difficulty/ruthless_difficulty.tres")
	var normal: DifficultyConfig = load("res://resources/difficulty/default_difficulty.tres")
	_check(Progress.run_active and Progress.run_mode == GameMode.Mode.RUTHLESS and is_equal_approx(extraction.gain_per_tap, ruthless.peak_gain_for_level(1)) and not is_equal_approx(ruthless.peak_gain_for_level(1), normal.peak_gain_for_level(1)),
		"a Ruthless run uses the Ruthless difficulty (peak %.1f vs %.1f)" % [extraction.gain_per_tap, normal.peak_gain_for_level(1)])
	_check(bool(_disk().data["ruthless_run"]["active"]), "the run is marked active on disk from the first moment")
	await _tap_until_complete(150.0, 30.0)
	await _wait_ready_at(2)
	_check(Progress.run_valid and Progress.highest_completed_level() == 1 and GameManager.state == GameManager.State.READY, "ordinary transitions (entrance, extraction, level card, next level) do not invalidate the run")
	# The in-app pause menu (Back) is NOT leaving the foreground.
	main._on_back_requested()
	await _wait(0.2)
	_check(GameManager.state == GameManager.State.PAUSED and Progress.run_valid, "Back opens the pause menu and the run stays valid")
	main._on_back_requested()
	await _wait(0.2)
	_check(GameManager.state == GameManager.State.READY and Progress.run_valid, "Back again resumes the same run")
	# Home / app switch / screen lock.
	input.handle_tap(TapSide.Side.LEFT)
	await _wait(0.1)
	main.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await _frames(2)
	_check(not Progress.run_valid and not Progress.run_active, "Home / app switch / screen lock (application paused): the Ruthless run is invalid at once")
	_check(not bool(_disk().data["ruthless_run"]["active"]) and int(_disk().record("ruthless")["best_level"]) == 1, "...the invalidation is on disk and the 1 completed level stays recorded")
	_check(GameManager.state == GameManager.State.FAILED and GameManager.run_over and not get_tree().paused, "...the game is in the ended state, not paused, so it cannot be resumed")
	var result: RunResult = GameManager.last_result
	_check(result != null and result.end_reason == RunResult.EndReason.INVALIDATED and result.completed_level == 1 and result.mode == GameMode.Mode.RUTHLESS, "...with a run-ended result: INVALIDATED, 1 completed level, Ruthless")
	var screen: FailureScreen = main.get_node("FailureScreen")
	await _wait(0.2)
	_check(screen.is_showing and screen.find_child("Title", true, false).text == "RUN ENDED" and screen.find_child("TryAgainButton", true, false).text == "NEW ATTEMPT", "the run-ended screen waits for the player (RUN ENDED / NEW ATTEMPT)")
	var before := extraction.progress
	input.handle_tap(TapSide.Side.LEFT)
	input.handle_tap(TapSide.Side.RIGHT)
	await _wait(0.1)
	_check(GameManager.state == GameManager.State.FAILED and is_equal_approx(extraction.progress, before), "taps on the ended run do nothing")
	main.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	GameManager.resume_game()
	_check(GameManager.state == GameManager.State.FAILED, "resume_game cannot bring the invalid run back")
	await _wait(0.7)
	main._restart_run()
	await _wait(0.4)
	_check(GameManager.level == 1 and Progress.run_active and Progress.run_valid and Progress.highest_completed_level() == 0 and GameManager.state == GameManager.State.READY, "NEW ATTEMPT starts a fresh valid Ruthless run at level 1")
	_check(bool(_disk().data["ruthless_run"]["active"]) and not screen.is_showing, "...the new run is active on disk and the old run-ended screen is gone")
	# Window-focus loss while the pause menu is open also invalidates.
	main._on_back_requested()
	await _wait(0.2)
	main.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await _frames(2)
	_check(not Progress.run_valid and GameManager.state == GameManager.State.FAILED and not get_tree().paused, "losing focus while the pause menu is open also ends the run (menu closed, not paused)")
	# A real failure in Ruthless is a normal failure.
	main._restart_run()
	await _wait(0.4)
	input.handle_tap(TapSide.Side.LEFT)
	await _wait(0.1)
	main._on_progress_depleted()
	await _wait(1.8)
	var failed: RunResult = GameManager.last_result
	_check(failed.end_reason == RunResult.EndReason.FAILURE and failed.mode == GameMode.Mode.RUTHLESS and failed.completed_level == 0 and not Progress.run_active, "a Ruthless failure is a normal failure (0 completed, run closed)")
	_check(not bool(_disk().data["ruthless_run"]["active"]), "...and leaves no active flag behind")
	_check(int(_disk().record("endless")["best_level"]) == 0, "none of the Ruthless play touched the Endless record")
	main.queue_free()
	await _frames(2)
