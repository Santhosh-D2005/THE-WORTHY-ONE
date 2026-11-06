extends Node
## Rendered smoke test: plays through level 1 using the real tap path and saves screenshots.
## Run (needs a display):  godot --path . res://tests/playthrough.tscn -- <output_dir>

func _ready() -> void:
	var out_dir := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	var input: InputController = main.get_node("InputController")
	input.min_tap_interval_msec = 0
	var extraction: ExtractionManager = main.get_node("ExtractionManager")
	await get_tree().create_timer(1.0).timeout
	_shot(out_dir, "01_start")
	print("state after entrance: ", GameManager.state, " level ", GameManager.level)
	var side := TapSide.Side.LEFT
	for i in 7:
		input.handle_tap(side)
		side = TapSide.Side.RIGHT if side == TapSide.Side.LEFT else TapSide.Side.LEFT
		await get_tree().create_timer(0.12).timeout
	_shot(out_dir, "02_mid")
	print("progress mid: ", extraction.progress)
	# repeated same side must not add progress
	var before := extraction.progress
	input.handle_tap(TapSide.Side.LEFT); input.handle_tap(TapSide.Side.LEFT)
	await get_tree().create_timer(0.1).timeout
	print("same-side repeat added progress: ", extraction.progress > before + 8.5)
	# finish
	for i in 12:
		if GameManager.state != GameManager.State.PLAYING:
			break
		input.handle_tap(side)
		side = TapSide.Side.RIGHT if side == TapSide.Side.LEFT else TapSide.Side.LEFT
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(0.5).timeout
	_shot(out_dir, "03_extracting")
	print("state during success: ", GameManager.state)
	await get_tree().create_timer(3.0).timeout
	print("state after: ", GameManager.state, " level ", GameManager.level, " progress ", extraction.progress)
	_shot(out_dir, "04_level2")
	get_tree().quit()

func _shot(dir: String, name: String) -> void:
	get_viewport().get_texture().get_image().save_png(dir + "/" + name + ".png")
