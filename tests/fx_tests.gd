extends Node
## Milestones 1.10-1.14 focused tests: sword micro-motion, forest compression, reversible cracks, amber glow and the coordinated
## extraction / failure / retry / pause behaviour. Run headless:   godot --headless --path . res://tests/fx_tests.tscn
## SIMULATED INPUT ONLY (InputController.handle_tap). Exit code 0 = all passed.

const MAIN_SCENE := "res://scenes/main/main.tscn"

var _checks := 0
var _failures := 0
var main: Node
var input: InputController
var extraction: ExtractionManager
var sword: SwordController
var forest: ForestEnvironment
var stump: StumpBuilder
var fx: ExtractionFx
var camera: GameplayCamera
var hud: Hud
var _completed := false
var _failed := false

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
	await _t_baseline_and_staging()
	await _t_reversibility()
	await _t_micro_motion()
	await _t_pause()
	await _t_extraction_sequence()
	await _t_failure_retry_repeat()
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

func _fresh() -> void:
	if main != null:
		main.queue_free()
		await get_tree().process_frame
	get_tree().paused = false
	main = load(MAIN_SCENE).instantiate()
	add_child(main)
	input = main.get_node("InputController")
	extraction = main.get_node("ExtractionManager")
	sword = main.get_node("Stage/Sword")
	forest = main.get_node("Stage/Forest")
	stump = main.get_node("Stage/Stump")
	fx = main.get_node("Stage/ExtractionFx")
	camera = main.get_node("Stage/Camera3D")
	hud = main.get_node("Hud")
	_completed = false
	_failed = false
	extraction.extraction_completed.connect(func() -> void: _completed = true)
	GameManager.run_failed.connect(func(_r: RunResult) -> void: _failed = true)
	while GameManager.state != GameManager.State.READY:
		await get_tree().process_frame
	await _wait(0.1)

## Alternating taps every `interval_ms` for `seconds` (or until complete / failed). Returns the number of taps sent.
func _tap_for(seconds: float, interval_ms: float) -> int:
	var side := TapSide.Side.LEFT
	var next := Time.get_ticks_msec()
	var end := next + int(seconds * 1000.0)
	var sent := 0
	while Time.get_ticks_msec() < end and not _completed and not _failed:
		if Time.get_ticks_msec() >= next:
			input.handle_tap(side)
			side = TapSide.Side.RIGHT if side == TapSide.Side.LEFT else TapSide.Side.LEFT
			sent += 1
			next += int(interval_ms)
		await get_tree().process_frame
	return sent

func _trees_home() -> bool:
	for i in forest._trees.size():
		if forest._trees[i].position != forest._tree_homes[i]:
			return false
	return true

func _clean_baseline() -> bool:
	return fx.strain == 0.0 and stump.crack_amount() == 0.0 and stump.crack_glow() == 0.0 and forest.compression() == 0.0 and _trees_home()

# ---- 1. baseline and the visual staging --------------------------------------------------------

func _t_baseline_and_staging() -> void:
	print("\n[1] BASELINE AND STAGING")
	await _fresh()
	_check(_clean_baseline(), "at zero progress: no cracks, no glow, no compression, every trunk at home")
	_check(sword.micro_offset() == Vector3.ZERO and sword._visual.scale == Vector3.ONE, "the sword has no micro offset and no scale")
	_check(ExtractionFx.glow_for(0.0) == 0.0, "glow is exactly 0 at 0 %")
	var g25 := ExtractionFx.glow_for(0.25)
	var g50 := ExtractionFx.glow_for(0.5)
	var g75 := ExtractionFx.glow_for(0.75)
	var g100 := ExtractionFx.glow_for(1.0)
	print("   glow at 25/50/75/100 %%: %.2f %.2f %.2f %.2f" % [g25, g50, g75, g100])
	_check(g25 > 0.1 and g25 < 0.4 and g25 < g50 and g50 < g75 and g75 < g100 and absf(g100 - 1.0) < 0.001, "glow is restrained at 25 % and rises monotonically to its maximum at 100 %")
	fx.set_progress(100.0)
	await _wait(1.6)
	_check(fx.strain > 0.99 and forest.compression() > 0.99, "at 100 % the strain and the compression are at their maximum")
	var scales_ok := true
	var moved_inward := true
	for i in forest._trees.size():
		var tree := forest._trees[i]
		if tree.scale != Vector3.ONE or tree.rotation != Vector3.ZERO:
			scales_ok = false
		var home := forest._tree_homes[i]
		if absf(tree.position.x) > absf(home.x) + 0.0001 or absf(tree.position.z) > absf(home.z) + 0.0001 or tree.position.y != home.y:
			moved_inward = false
	_check(scales_ok, "no trunk is scaled or rotated (no deformation)")
	_check(moved_inward, "every trunk only moved toward the stump (x and z shrink by at most %.0f %%, y untouched)" % (ForestEnvironment.COMPRESSION * 100.0))
	_check(stump.crack_amount() > 0.99 and stump.crack_glow() > 0.99, "at 100 %: cracks and glow at their maximum")
	_check(sword.position.x == 0.0 and stump.position == Vector3.ZERO, "the sword and the stump did not move")

# ---- 2. everything follows the current progress, both ways -------------------------------------

func _t_reversibility() -> void:
	print("\n[2] REVERSIBLE WITH PROGRESS")
	await _fresh()
	var cracks: Array[float] = []
	var glows: Array[float] = []
	var compress: Array[float] = []
	for pct in [25.0, 50.0, 75.0]:
		fx.set_progress(pct)
		await _wait(1.0)
		cracks.append(stump.crack_amount())
		glows.append(stump.crack_glow())
		compress.append(forest.compression())
	print("   cracks %s glow %s compression %s" % [cracks, glows, compress])
	_check(cracks[0] < cracks[1] and cracks[1] < cracks[2] and glows[0] < glows[1] and glows[1] < glows[2] and compress[0] < compress[1] and compress[1] < compress[2], "cracks, glow and compression all grow with progress")
	_check(absf(cracks[1] - 0.5) < 0.01 and absf(compress[2] - 0.75) < 0.01, "each follows the current progress value (50 %% -> %.2f, 75 %% -> %.2f)" % [cracks[1], compress[2]])
	fx.set_progress(50.0)
	await _wait(1.0)
	_check(absf(stump.crack_amount() - cracks[1]) < 0.005 and absf(stump.crack_glow() - glows[1]) < 0.01, "back at 50 %: the cracks and the glow are what they were at 50 % on the way up")
	fx.set_progress(10.0)
	await _wait(1.0)
	_check(stump.crack_amount() < cracks[0] and stump.crack_glow() < glows[0], "falling to 10 %: both recede below their 25 % state")
	fx.set_progress(0.0)
	await _wait(1.2)
	_check(_clean_baseline(), "back at zero progress: no cracks, no glow, no compression, every trunk exactly home")
	_check(not fx.is_processing(), "the shared controller switches itself off once nothing is changing")

# ---- 3. sword micro-motion ----------------------------------------------------------------------

func _t_micro_motion() -> void:
	print("\n[3] SWORD MICRO-MOTION")
	await _fresh()
	extraction.configure(1.0, 0.0, 5.0)  # slow, steady rise so the level does not complete
	var worst := Vector3.ZERO
	var rigid := true
	var flips := 0
	var last_sign := 0
	var end := Time.get_ticks_msec() + 4000
	var side := TapSide.Side.LEFT
	var next := Time.get_ticks_msec()
	while Time.get_ticks_msec() < end:
		if Time.get_ticks_msec() >= next:
			input.handle_tap(side)
			side = TapSide.Side.RIGHT if side == TapSide.Side.LEFT else TapSide.Side.LEFT
			next += 140
		await get_tree().process_frame
		var m := sword.micro_offset()
		worst = Vector3(maxf(worst.x, absf(m.x)), maxf(worst.y, absf(m.y)), maxf(worst.z, absf(m.z)))
		if sword._visual.scale != Vector3.ONE or sword.position.x != 0.0:
			rigid = false
		var sg := signi(int(round(m.x * 100000.0)))
		if sg != 0:
			if last_sign != 0 and sg != last_sign:
				flips += 1
			last_sign = sg
	print("   worst micro offset: sideways %.4f m, lift %.4f m, roll %.4f rad; %d sideways direction flips in 4 s" % [worst.x, worst.y, worst.z, flips])
	_check(worst.x <= SwordController.MICRO_SIDE + 0.0001 and worst.y <= SwordController.MICRO_UP + 0.0001 and worst.z <= SwordController.MICRO_ROLL + 0.0001, "the micro-motion stays inside its bounds")
	_check(worst.x > 0.0003 and worst.y > 0.0005, "the sword does respond to the taps (visible sideways and lift)")
	_check(rigid, "one rigid object: never scaled, its root never moved sideways")
	_check(flips < 4 * 8, "it is heavy and smooth: %d flips in 4 s of 7 taps/s (a vibration would be hundreds)" % flips)
	await _wait(1.8)
	_check(sword.micro_offset() == Vector3.ZERO and sword._visual.position == Vector3.ZERO and sword._visual.rotation == Vector3.ZERO, "tapping stopped: the sword settles to exactly the embedded pose (no residual drift)")
	var y_after := sword.position.y
	await _wait(0.5)
	_check(sword.position.y <= y_after + 0.0001 and sword._visual.position == Vector3.ZERO, "and stays there")

# ---- 4. pause -----------------------------------------------------------------------------------

func _t_pause() -> void:
	print("\n[4] PAUSE AND RESUME")
	await _fresh()
	extraction.configure(1.0, 0.0, 5.0)
	await _tap_for(0.7, 140)
	main._pause()
	await _frames(2)
	var strain := fx.strain
	var comp := forest.compression()
	var cracks := stump.crack_amount()
	var micro := sword.micro_offset()
	var visual_pos := sword._visual.position
	await _wait(1.0)
	_check(fx.strain == strain and forest.compression() == comp and stump.crack_amount() == cracks, "paused: strain, compression and cracks do not advance")
	_check(sword.micro_offset() == micro and sword._visual.position == visual_pos, "paused: the sword's micro-motion is frozen exactly")
	main._timers.resume()
	GameManager.resume_game()
	await _frames(2)
	var jump := (sword.micro_offset() - micro).length()
	_check(jump < 0.004 and absf(fx.strain - strain) < 0.02, "resume: no jump (micro change %.4f, strain change %.3f)" % [jump, absf(fx.strain - strain)])

# ---- 5. a real extraction ------------------------------------------------------------------------

func _t_extraction_sequence() -> void:
	print("\n[5] EXTRACTION SEQUENCE")
	await _fresh()
	var at_release := {"strain": -1.0, "cracks": -1.0, "glow": -1.0, "comp": -1.0, "visual": Vector3.ONE}
	sword.freed.connect(func() -> void:
		at_release["strain"] = fx.strain
		at_release["cracks"] = stump.crack_amount()
		at_release["glow"] = stump.crack_glow()
		at_release["comp"] = forest.compression()
		at_release["visual"] = sword._visual.position)
	await _tap_for(30.0, 150)
	_check(_completed, "the level completes with the unchanged speed-based rule")
	var guard := Time.get_ticks_msec() + 2000
	while at_release["strain"] < 0.0 and Time.get_ticks_msec() < guard:
		await get_tree().process_frame
	_check(at_release["cracks"] > 0.97 and at_release["glow"] > 0.97 and at_release["strain"] > 0.97, "cracks (%.2f), glow (%.2f) and strain (%.2f) are at their maximum BEFORE the blade is released" % [at_release["cracks"], at_release["glow"], at_release["strain"]])
	_check(at_release["comp"] > 0.97, "the forest is fully compressed at the release (%.2f)" % at_release["comp"])
	_check((at_release["visual"] as Vector3).length() < 0.0005, "the micro-motion is gone before the release, so no jump at the pull")
	await _wait(0.5)
	var c_mid := forest.compression()
	var g_mid := stump.crack_glow()
	_check(c_mid < at_release["comp"] - 0.2 and c_mid > 0.02, "after the release the compression unwinds smoothly (%.2f)" % c_mid)
	_check(g_mid < 0.4, "...and the glow closes first (%.2f)" % g_mid)
	_check(hud.is_level_complete_visible(), "the completion card is showing")
	await _wait(3.5)
	_check(GameManager.level == 2 and GameManager.state == GameManager.State.READY, "the next level begins")
	_check(_clean_baseline() and sword.micro_offset() == Vector3.ZERO, "nothing leaks into the next level: no cracks, no glow, no compression, no micro offset")
	_check(camera.dolly_amount() < 0.02, "the camera is back at its framing")

# ---- 6. failure, retry and repetition -------------------------------------------------------------

func _t_failure_retry_repeat() -> void:
	print("\n[6] FAILURE, RETRY, REPEATED ATTEMPTS")
	await _fresh()
	var nodes_before := get_tree().get_node_count()
	for attempt in 5:
		_failed = false
		await _tap_for(0.8, 140)  # build some progress
		_check(fx.strain > 0.0 and stump.crack_amount() > 0.0, "attempt %d: the effects are active while progress builds" % (attempt + 1))
		if GameManager.state == GameManager.State.PLAYING:
			main._on_progress_depleted()  # the same gate the game uses when progress hits zero
		var guard := Time.get_ticks_msec() + 6000
		while GameManager.state != GameManager.State.FAILED and Time.get_ticks_msec() < guard:
			await get_tree().process_frame
		await _wait(1.3)
		_check(GameManager.state == GameManager.State.FAILED and stump.crack_amount() < 0.005 and stump.crack_glow() < 0.01 and sword.position == sword._rest_position and sword._visual.position == Vector3.ZERO,
			"attempt %d: after the failure the sword is embedded and the cracks and glow are gone" % (attempt + 1))
		main._restart_run()
		await _wait(0.6)
		_check(GameManager.state == GameManager.State.READY and _clean_baseline() and sword.micro_offset() == Vector3.ZERO and not fx.is_processing(),
			"attempt %d: after TRY AGAIN everything is back at the baseline" % (attempt + 1))
	await _frames(5)
	var nodes_after := get_tree().get_node_count()
	_check(nodes_after <= nodes_before + 2, "five attempts do not grow the scene (%d -> %d nodes)" % [nodes_before, nodes_after])
