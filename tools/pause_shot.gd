extends SceneTree
## Saves the in-game view with the PAUSE button:  godot --path . -s res://tools/pause_shot.gd -- out.png
func _initialize() -> void:
	_run()

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "pause.png"
	root.size = Vector2i(540, 960)
	change_scene_to_file("res://scenes/main/main.tscn")
	await _wait(8.0)
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
