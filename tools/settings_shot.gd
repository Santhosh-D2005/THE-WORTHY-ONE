extends Node
## Saves two frames for a visual check of the settings work:  godot --path . res://tools/settings_shot.tscn -- menu.png settings.png
## (1) the main menu with its SETTINGS button, (2) the SETTINGS panel opened from it.
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	get_window().size = Vector2i(540, 960)
	var menu: MainMenu = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await _wait(3.5)
	if menu.login_open():
		menu.login_screen().close()  # a fresh test profile shows the account prompt first; it is not part of this check
		await _wait(0.8)
	get_viewport().get_texture().get_image().save_png(args[0])
	menu.settings_button().pressed.emit()
	await _wait(1.2)
	get_viewport().get_texture().get_image().save_png(args[1])
	if args.size() > 2:
		menu.settings_screen().credits_button().pressed.emit()
		await _wait(1.2)
		get_viewport().get_texture().get_image().save_png(args[2])
	get_tree().quit()

func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
