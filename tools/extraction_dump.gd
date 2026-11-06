extends Node
## Prints the sword / camera / light values frame by frame through one extraction:  godot --path . res://tools/extraction_dump.tscn -- <level>
func _ready() -> void:
	get_window().size = Vector2i(540, 960)
	var level := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 1
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	var input: InputController = main.get_node("InputController")
	var sword: SwordController = main.get_node("Stage/Sword")
	var camera: GameplayCamera = main.get_node("Stage/Camera3D")
	var forest: ForestEnvironment = main.get_node("Stage/Forest")
	while GameManager.state != GameManager.State.READY:
		await get_tree().process_frame
	if level > 1:
		GameManager.level = level
		main.get_node("DifficultyManager").apply_for_level(level)
	var left := true
	while GameManager.state != GameManager.State.EXTRACTING:
		input.handle_tap(TapSide.Side.LEFT if left else TapSide.Side.RIGHT)
		left = not left
		var t := Time.get_ticks_msec()
		while Time.get_ticks_msec() < t + 45:
			await get_tree().process_frame
	var started := Time.get_ticks_msec()
	var total := SwordController.extraction_total_seconds(LevelManager.reward_intensity(level))
	while float(Time.get_ticks_msec() - started) / 1000.0 < total + 0.2:
		await get_tree().process_frame
		print("t=%.3f y=%.3f z=%.3f rot=%.3f dolly=%.3f tension=%.2f sun=%.2f slot=%s" % [float(Time.get_ticks_msec() - started) / 1000.0, sword.position.y, sword.position.z, sword._visual.rotation.y, camera.dolly_amount(), camera.tension(), forest.sun_energy(), sword.slot_visible()])
	get_tree().quit()
