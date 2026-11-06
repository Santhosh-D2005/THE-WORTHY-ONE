extends Node
## Milestones 1.12/1.13 visual check:  godot --path . res://tools/fx_shots.tscn -- out_prefix
## Saves the real scene at strain 0, 25, 50, 75 and 100 % (cracks + glow + compression), using the real ExtractionFx.
func _ready() -> void:
	get_window().size = Vector2i(540, 960)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() < t + 6000:
		await get_tree().process_frame
	get_tree().paused = false
	main.get_node("Hud").set_pause_overlay_suppressed(true)
	var fx: ExtractionFx = main.get_node("Stage/ExtractionFx")
	var prefix: String = OS.get_cmdline_user_args()[0]
	for pct in [0, 25, 50, 75, 100]:
		fx.reset()
		fx.set_progress(float(pct))
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() < start + 1500:
			await get_tree().process_frame
		get_tree().paused = false
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, pct])
	get_tree().quit()
