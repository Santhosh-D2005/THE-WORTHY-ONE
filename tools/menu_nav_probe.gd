extends SceneTree
## Probe: does MAIN MENU (from pause, and from the failure screen) really reach the main menu scene? Run (needs a window):
##   godot --path . -s res://tools/menu_nav_probe.gd
func _initialize() -> void:
	_run()

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _run() -> void:
	change_scene_to_file("res://scenes/main/main.tscn")
	await _wait(8.0)
	print("PROBE game scene: ", current_scene.name if current_scene else "none")
	current_scene.call("_quit_from_menu")
	await _wait(3.0)
	print("PROBE after pause -> MAIN MENU: ", current_scene.name if current_scene else "none", " | ", current_scene.scene_file_path if current_scene else "")
	change_scene_to_file("res://scenes/main/main.tscn")
	await _wait(8.0)
	root.get_node("GameManager").call("set_state", 4)  # State.FAILED
	current_scene.call("_open_main_menu")
	await _wait(3.0)
	print("PROBE after failure -> MAIN MENU: ", current_scene.name if current_scene else "none", " | ", current_scene.scene_file_path if current_scene else "")
	quit()
