extends Node
## Renders the real game scene at LEVEL 9999 on the desktop and saves gameplay frames:
##   godot --path . res://tools/finale_shot.tscn -- <output folder>        (needs a window: not --headless)
## Frames: ready (progress 0), mid pull (55 %), about to break free (94 %). Also a level-1 frame for comparison.
func _ready() -> void:
	get_window().size = Vector2i(1080, 1920)
	var out_dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await _seconds(7.0)  # the level 1 entrance finishes
	get_tree().paused = false
	main.get_node("Hud").set_pause_overlay_suppressed(true)
	_save(out_dir + "/finale_compare_level1.png")
	var extraction: ExtractionManager = main.get_node("ExtractionManager")
	extraction.set_process(false)  # hold the progress we set by hand
	extraction.set_active(false)
	GameManager.level = GameManager.MAX_LEVEL
	GameManager.level_changed.emit(GameManager.MAX_LEVEL)
	main._finale.apply(true)
	GameManager.set_state(GameManager.State.PLAYING)
	# The pictures must not give away which level this is: hide the big "LEVEL <number>" heading.
	var hidden := 0
	for label in main.get_node("Hud").find_children("*", "Label", true, false):
		if (label as Label).text.begins_with("LEVEL ") and (label as Label).text.substr(6).is_valid_int():
			(label as Label).visible = false
			hidden += 1
	print("hid ", hidden, " level-number label(s)")
	await _seconds(3.5)
	_save(out_dir + "/finale_1_ready.png")
	extraction.progress = 55.0
	extraction.progress_changed.emit(55.0)
	await _seconds(2.0)
	_save(out_dir + "/finale_2_pull.png")
	extraction.progress = 94.0
	extraction.progress_changed.emit(94.0)
	await _seconds(2.5)
	_save(out_dir + "/finale_3_breaking_free.png")
	get_tree().quit()

func _seconds(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
