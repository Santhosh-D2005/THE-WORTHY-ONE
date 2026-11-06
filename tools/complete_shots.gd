extends Node
## Captures the level-complete sequence:  godot --path . res://tools/complete_shots.tscn -- <out_dir> <level>
func _ready() -> void:
	get_window().size = Vector2i(540, 960)
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var level := int(args[1]) if args.size() > 1 else 1
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	var input: InputController = main.get_node("InputController")
	main.get_node("Hud").set_pause_overlay_suppressed(true)
	while GameManager.state != GameManager.State.READY:
		if GameManager.state == GameManager.State.PAUSED:
			GameManager.resume_game()  # the OS took the window focus: carry on
		await get_tree().process_frame
	if level > 1:
		GameManager.level = level
		main.get_node("DifficultyManager").apply_for_level(level)
		main.get_node("Hud")._on_level_changed(level)
	var left := true
	while GameManager.state != GameManager.State.EXTRACTING:
		if GameManager.state == GameManager.State.PAUSED:
			GameManager.resume_game()
		input.handle_tap(TapSide.Side.LEFT if left else TapSide.Side.RIGHT)
		left = not left
		var t := Time.get_ticks_msec()
		while Time.get_ticks_msec() < t + 45:
			await get_tree().process_frame
	var shots: Array = []
	var started := Time.get_ticks_msec()
	for stamp in [0.10, 0.20, 0.30, 0.45, 0.7, 1.0, 1.4, 1.8]:
		while Time.get_ticks_msec() - started < int(stamp * 1000.0):
			await get_tree().process_frame
		shots.append([int(stamp * 100.0), get_viewport().get_texture().get_image()])  # saved at the end: PNG encoding is slow
	for shot in shots:
		(shot[1] as Image).save_png("%s/L%d_%03d.png" % [out_dir, level, shot[0]])
	get_tree().quit()
