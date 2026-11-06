extends Node
## Milestone 1.16 visual check:  godot --path . res://tools/ui_shots.tscn -- out_prefix [width height]
## Saves the real game scene with the completion card, the pause menu, the focus-loss pause and the failure screen showing.
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(540, 960)
	if args.size() >= 3:
		size = Vector2i(int(args[1]), int(args[2]))
	get_window().size = size
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	while GameManager.state != GameManager.State.READY:
		await get_tree().process_frame
	await _wait(1.2)
	var hud: Hud = main.get_node("Hud")
	hud.show_level_complete(3, 12.34, 3, 6.0)
	await _wait(1.3)
	_save(args[0] + "_card.png")
	await _wait(6.0)
	main._pause()
	main._open_pause_menu()
	await _wait(0.9)
	_save(args[0] + "_pause.png")
	main._pause_menu.hide_menu()
	hud.set_pause_overlay_suppressed(false)
	await _wait(0.3)
	_save(args[0] + "_pause_overlay.png")
	main._resume_from_menu()
	GameManager.resume_game()
	await _wait(0.3)
	main.get_node("InputController").handle_tap(TapSide.Side.LEFT)
	await _wait(0.2)
	main._on_progress_depleted()
	await _wait(3.0)
	get_tree().paused = false
	_save(args[0] + "_failure.png")
	get_tree().quit()

func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
