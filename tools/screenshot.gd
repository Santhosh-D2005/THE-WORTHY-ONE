extends Node
## Saves one frame of the real game scene:  godot --path . res://tools/screenshot.tscn -- out.png [--quality=balanced]
func _ready() -> void:
	get_window().size = Vector2i(540, 960)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() < t + 9000:
		await get_tree().process_frame
	# If the OS took the window focus the game pauses itself; the picture must show the scene, not the pause overlay.
	get_tree().paused = false
	main.get_node("Hud").set_pause_overlay_suppressed(true)
	var settle := Time.get_ticks_msec()
	while Time.get_ticks_msec() < settle + 2000:  # a game paused by lost focus needs a moment to finish dropping the sword in
		await get_tree().process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
