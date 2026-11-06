extends Node
## Milestone 1.15 focused tests: the main menu scene (layout, touch targets, PLAY / QUIT / Back, double-press protection, safe area,
## scene hand-over and cleanup). Run headless:   godot --headless --path . res://tests/menu_tests.tscn
## SIMULATED INPUT ONLY (events handed to the menu's own input handler / Button signals): not a physical touchscreen.
## Exit code 0 = all passed.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const GAME_SCENE := "res://scenes/main/main.tscn"

var _checks := 0
var _failures := 0
var menu: MainMenu
var changes: Array[String] = []
var quits: int = 0
var plays: int = 0

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(540, 960)
	await _frames(3)
	await _t_structure_and_input_gate()
	await _t_layout()
	await _t_safe_area()
	await _t_play_once()
	await _t_quit_and_back()
	await _t_handover_and_cleanup()
	print("\n==== %d checks, %d failed ====" % [_checks, _failures])
	print("RESULT: ALL PASSED" if _failures == 0 else "RESULT: FAILURES")
	get_tree().quit(0 if _failures == 0 else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func _open_menu() -> void:
	if menu != null and is_instance_valid(menu):
		menu.queue_free()
		await get_tree().process_frame
	SafeArea.test_insets = null
	changes.clear()
	quits = 0
	plays = 0
	menu = load(MENU_SCENE).instantiate()
	add_child(menu)
	menu.scene_changer = func(path: String) -> void: changes.append(path)
	menu.app_quitter = func() -> void: quits += 1
	menu.play_pressed.connect(func() -> void: plays += 1)
	await _frames(2)

func _wait_ready() -> void:
	var guard := Time.get_ticks_msec() + 3000
	while not menu.buttons_ready and Time.get_ticks_msec() < guard:
		await get_tree().process_frame

## A finger press + release at the centre of a button (the path a phone takes).
func _touch(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = point
	menu._input(down)
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = point
	menu._input(up)

# ---- 1. structure and the early-press gate ------------------------------------------------------

func _t_structure_and_input_gate() -> void:
	print("\n[1] STRUCTURE AND INPUT GATE")
	await _open_menu()
	_check(menu.play_button() != null and menu.quit_button() != null and menu.play_button().text == "PLAY" and menu.quit_button().text == "QUIT", "exactly the two real actions exist: PLAY and QUIT (no placeholder buttons)")
	var buttons := 0
	for node in menu.find_children("*", "Button", true, false):
		if (node as Button).is_visible_in_tree():  # the guest notice keeps its own (hidden) buttons; account_tests covers them
			buttons += 1
	var names: Array[String] = []
	for node in menu.find_children("*", "Button", true, false):
		if (node as Button).is_visible_in_tree():
			names.append((node as Button).text)
	names.sort()
	_check(buttons == 5 and names == ["ACCOUNT", "HALL OF FAME", "MODES", "PLAY", "QUIT"], "the menu shows exactly its five real actions (Phase 6/7: %s), no placeholder buttons" % str(names))
	_check(menu.title_labels()[0].text == "THE" and menu.title_labels()[1].text == "WORTHY ONE", "the title reads THE WORTHY ONE")
	_check(menu.get_node("Stage/Sword") != null and menu.get_node("Stage/Stump") != null and menu.get_node("Stage/Forest") != null, "the backdrop is the game's own forest, stump and sword")
	_check((menu.get_node("Stage/Stump") as StumpBuilder).crack_amount() > 0.0 and (menu.get_node("Stage/Stump") as StumpBuilder).crack_glow() > 0.0, "the stump holds its faint amber crack glow")
	_check(not menu.buttons_ready, "right after opening the menu is not interactive yet")
	_touch(menu.play_button())
	menu.play_button().pressed.emit()
	await _frames(2)
	_check(plays == 0 and changes.is_empty(), "a press during the fade-in does nothing (a stray tap at app start cannot launch a game)")
	await _wait_ready()
	_check(menu.buttons_ready, "after the short fade-in the menu is interactive")

# ---- 2. layout on several portrait / odd screen shapes ---------------------------------------------

func _t_layout() -> void:
	print("\n[2] LAYOUT")
	for size in [Vector2i(540, 960), Vector2i(540, 1200), Vector2i(360, 800), Vector2i(720, 1600), Vector2i(800, 1000)]:
		get_window().size = size
		await _open_menu()
		await _frames(3)
		var view := menu.get_viewport().get_visible_rect()
		var tag := "%dx%d" % [size.x, size.y]
		var all_inside := true
		var rects := {}
		for node in [menu.play_button(), menu.quit_button(), menu.get_node("Ui/Root/TitleThe"), menu.get_node("Ui/Root/TitleMain"), menu.get_node("Ui/Root/Divider"), menu.get_node("Ui/Root/Subtitle")]:
			var rect: Rect2 = node.get_global_rect()
			rects[node.name] = rect
			if rect.position.x < view.position.x - 0.5 or rect.end.x > view.end.x + 0.5 or rect.position.y < view.position.y - 0.5 or rect.end.y > view.end.y + 0.5:
				all_inside = false
		_check(all_inside, "%s: every title and button rectangle is inside the screen" % tag)
		# Text must not be wider than its box (no clipping or spill).
		var text_fits := true
		for label in menu.title_labels():
			var need: float = label.get_minimum_size().x
			if need > view.size.x * 0.96:
				text_fits = false
		_check(text_fits, "%s: the title and subtitle text fit the screen width" % tag)
		_check(rects["TitleThe"].end.y <= rects["TitleMain"].position.y + 40.0 and rects["TitleMain"].end.y <= rects["Subtitle"].position.y + 0.5, "%s: the title lines do not collide" % tag)
		_check(rects["Subtitle"].end.y < rects["PlayButton"].position.y, "%s: the title block and PLAY do not overlap" % tag)
		_check(rects["PlayButton"].end.y <= rects["QuitButton"].position.y, "%s: PLAY sits clear above QUIT" % tag)
		# Touch targets: the view is 1080 base px wide whatever the screen, so physical size follows the WIDTH. On the 720 px wide target phone
		# (about 270 ppi) 48 dp = 81 screen px = 121 base px, so every button must be at least 120 base px high.
		_check(rects["PlayButton"].size.y >= 120.0 and rects["QuitButton"].size.y >= 120.0, "%s: touch targets of at least 48 dp (PLAY %.0f, QUIT %.0f base px high; 120 needed)" % [tag, rects["PlayButton"].size.y, rects["QuitButton"].size.y])
		_check(rects["PlayButton"].size.y > rects["QuitButton"].size.y and rects["PlayButton"].size.x > rects["QuitButton"].size.x, "%s: PLAY is the largest, clearest control" % tag)
	get_window().size = Vector2i(540, 960)

# ---- 3. safe area -----------------------------------------------------------------------------------

func _t_safe_area() -> void:
	print("\n[3] SAFE AREA")
	await _open_menu()
	await _frames(2)
	var title_top: float = menu.get_node("Ui/Root/TitleThe").get_global_rect().position.y
	var play_bottom: float = menu.play_button().get_global_rect().end.y
	var quit_bottom: float = menu.quit_button().get_global_rect().end.y
	SafeArea.test_insets = Vector4(0.0, 90.0, 0.0, 120.0)
	menu.refresh_safe_area()
	await _frames(2)
	var shifted_top: float = menu.get_node("Ui/Root/TitleThe").get_global_rect().position.y
	_check(is_equal_approx(shifted_top - title_top, 90.0), "a 90 px camera cut-out moves the title down by exactly 90 px")
	_check(is_equal_approx(play_bottom - menu.play_button().get_global_rect().end.y, 120.0) and is_equal_approx(quit_bottom - menu.quit_button().get_global_rect().end.y, 120.0), "a 120 px gesture bar moves PLAY and QUIT up by exactly 120 px")
	SafeArea.test_insets = null

# ---- 4. PLAY starts exactly one game ----------------------------------------------------------------

func _t_play_once() -> void:
	print("\n[4] PLAY")
	await _open_menu()
	await _wait_ready()
	_touch(menu.play_button())
	menu.play_button().pressed.emit()  # the mouse path as well: a touch device can deliver both
	_touch(menu.play_button())
	menu.play_button().pressed.emit()
	await _wait(0.8)
	_check(plays == 1, "four rapid presses (touch + mouse, doubled) emit exactly one play request (%d)" % plays)
	_check(changes == [GAME_SCENE], "...and ask for the game scene exactly once: %s" % [changes])
	_check(ResourceLoader.exists(GAME_SCENE), "the target game scene exists")
	menu.quit_button().pressed.emit()
	_touch(menu.quit_button())
	menu.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait(0.5)
	_check(quits == 0, "once PLAY has been pressed, QUIT and Back do nothing (no second action)")

# ---- 5. QUIT and Back -------------------------------------------------------------------------------------

func _t_quit_and_back() -> void:
	print("\n[5] QUIT AND BACK")
	await _open_menu()
	await _wait_ready()
	_touch(menu.quit_button())
	menu.quit_button().pressed.emit()
	await _wait(0.7)
	_check(quits == 1 and changes.is_empty() and plays == 0, "QUIT (touch + mouse) leaves the app once and starts no game")
	await _open_menu()
	await _wait_ready()
	menu.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	menu.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait(0.7)
	_check(quits == 1 and changes.is_empty(), "Android Back on the menu leaves the app (once, even if pressed twice)")
	await _open_menu()
	menu.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait(0.8)
	_check(quits == 0, "Back during the fade-in is ignored")

# ---- 6. hand-over to the game, and cleanup ----------------------------------------------------------------

func _t_handover_and_cleanup() -> void:
	print("\n[6] HAND-OVER AND CLEANUP")
	# Arriving from a paused game: the menu must run.
	get_tree().paused = true
	await _open_menu()
	_check(not get_tree().paused, "the menu un-pauses the tree (arriving from the game's pause menu)")
	# A game started from the menu begins a fresh run even if a previous run left state behind.
	GameManager.level = 7
	var game: Node = load(GAME_SCENE).instantiate()
	add_child(game)
	var guard := Time.get_ticks_msec() + 8000
	while GameManager.state != GameManager.State.READY and Time.get_ticks_msec() < guard:
		await get_tree().process_frame
	_check(GameManager.level == 1 and GameManager.state == GameManager.State.READY and not GameManager.run_over, "a game started after the menu begins a fresh run at level 1, READY")
	game.queue_free()
	await _frames(3)
	get_tree().paused = false
	# Repeated open / close does not grow the scene.
	await _open_menu()
	await _frames(3)
	var before := get_tree().get_node_count()
	for i in 4:
		await _open_menu()
		await _frames(2)
	menu.queue_free()
	await _frames(4)
	var after := get_tree().get_node_count()
	_check(after <= before, "opening and closing the menu 4 times does not grow the scene (%d -> %d nodes)" % [before, after])
