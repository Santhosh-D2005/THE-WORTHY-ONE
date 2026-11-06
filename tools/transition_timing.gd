extends Node
func _ready() -> void:
	get_window().size = Vector2i(540, 960)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	var input: InputController = main.get_node("InputController")
	var sword: SwordController = main.get_node("Stage/Sword")
	while GameManager.state != GameManager.State.READY:
		await get_tree().process_frame
	var t0 := 0
	var stamp := func(label: String) -> void:
		print("  +%.2fs %s" % [float(Time.get_ticks_msec() - t0) / 1000.0, label])
	sword.freed.connect(func() -> void: stamp.call("freed"))
	sword.planted.connect(func() -> void: stamp.call("planted"))
	GameManager.state_changed.connect(func(s: GameManager.State) -> void: stamp.call("state " + str(GameManager.State.keys()[s])))
	GameManager.level_changed.connect(func(l: int) -> void: stamp.call("level_changed %d" % l))
	var left := true
	while GameManager.state != GameManager.State.EXTRACTING:
		input.handle_tap(TapSide.Side.LEFT if left else TapSide.Side.RIGHT)
		left = not left
		var t := Time.get_ticks_msec()
		while Time.get_ticks_msec() < t + 45:
			await get_tree().process_frame
	t0 = Time.get_ticks_msec()
	await get_tree().create_timer(4.0).timeout
	get_tree().quit()
