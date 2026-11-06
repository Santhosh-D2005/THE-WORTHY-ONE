extends Node
## Saves one frame of the main menu:  godot --path . res://tools/menu_shot.tscn -- out.png [window_width window_height]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(540, 960)
	if args.size() >= 3:
		size = Vector2i(int(args[1]), int(args[2]))
	get_window().size = size
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() < t + 3500:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(args[0])
	get_tree().quit()
