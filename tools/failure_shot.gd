extends SceneTree
## Saves the failure screen as it appears in the real game:  godot --path . -s res://tools/failure_shot.gd -- out.png
func _initialize() -> void:
	_run()

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "failure.png"
	root.size = Vector2i(540, 960)
	change_scene_to_file("res://scenes/main/main.tscn")
	await _wait(8.0)
	root.get_node("GameManager").call("set_state", 1)  # State.PLAYING
	current_scene.call("_on_progress_depleted")
	await _wait(6.0)
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
