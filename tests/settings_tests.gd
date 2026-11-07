extends Node
## Settings tests: the sound and optimisation options (the Settings autoload) and the SETTINGS panel as the main menu shows it.
## Run headless:   godot --headless --path . res://tests/settings_tests.tscn
## Exit code 0 = all passed. The test file (user://settings_headless.cfg) is separate from the player's real settings and is removed
## at the end; the defaults are restored before the run finishes.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _checks := 0
var _failures := 0

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
	_t_values()
	_t_buses()
	_t_quality_and_fps()
	_t_save_and_load()
	await _t_panel()
	await _t_pause_menu()
	await _t_credits()
	await _t_delete_flow()
	await _t_pause_button()
	await _t_menu_button_order()
	await _t_touch_leaves_scene()
	Settings.reset_to_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.default_path()))
	print("\n%d checks, %d failure(s)" % [_checks, _failures])
	print("ALL SETTINGS TESTS PASSED" if _failures == 0 else "SETTINGS TESTS FAILED")
	get_tree().quit(1 if _failures > 0 else 0)

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

# ---- Values -------------------------------------------------------------------------------------------

func _t_values() -> void:
	print("Settings values")
	Settings.reset_to_defaults()
	Settings.set_sound_volume(1.27)
	_check(is_equal_approx(Settings.sound_volume, 1.0), "sound volume is clamped to the top (1.27 -> 100%)")
	Settings.set_sound_volume(-0.2)
	_check(is_equal_approx(Settings.sound_volume, 0.0), "sound volume is clamped to silence (-0.2 -> 0%)")
	Settings.set_sfx_volume(0.46)
	_check(is_equal_approx(Settings.sfx_volume, 0.5), "SFX volume snaps to 10 % steps (0.46 -> 50%)")
	Settings.set_sfx_volume(Settings.sfx_volume + Settings.STEP)
	_check(is_equal_approx(Settings.sfx_volume, 0.6), "one + step adds 10 %")
	_check(Settings.percent_text(0.6) == "60%" and Settings.percent_text(1.0) == "100%", "percent labels read 60% and 100%")
	_check(Settings.fps_text(0) == "UNLIMITED" and Settings.fps_text(60) == "60 FPS", "frame-rate labels read UNLIMITED and 60 FPS")
	Settings.reset_to_defaults()
	_check(is_equal_approx(Settings.sound_volume, 1.0) and is_equal_approx(Settings.sfx_volume, 1.0) and Settings.quality == "" and Settings.fps_cap == 0, "reset restores full volume, automatic quality and unlimited frame rate")

# ---- Buses ----------------------------------------------------------------------------------------------

func _t_buses() -> void:
	print("Audio buses")
	var sfx := AudioServer.get_bus_index("SFX")
	var master := AudioServer.get_bus_index("Master")
	_check(sfx >= 0 and master >= 0, "the SFX bus exists next to Master")
	_check(sfx >= 0 and AudioServer.get_bus_send(sfx) == "Master", "the SFX bus sends to Master")
	Settings.set_sound_volume(0.0)
	_check(AudioServer.is_bus_mute(master), "SOUND at 0 mutes the Master bus")
	Settings.set_sound_volume(0.5)
	_check(not AudioServer.is_bus_mute(master) and is_equal_approx(AudioServer.get_bus_volume_db(master), linear_to_db(0.5)), "SOUND at 50% unmutes Master at -6 dB")
	Settings.set_sfx_volume(0.0)
	_check(AudioServer.is_bus_mute(sfx), "SFX at 0 mutes the SFX bus only")
	_check(not AudioServer.is_bus_mute(master), "muting SFX leaves Master on")
	Settings.reset_to_defaults()
	_check(not AudioServer.is_bus_mute(sfx) and not AudioServer.is_bus_mute(master), "defaults unmute both buses")

# ---- Optimisation -------------------------------------------------------------------------------------------

func _t_quality_and_fps() -> void:
	print("Optimisation")
	Settings.reset_to_defaults()
	var seen: Array[String] = []
	for i in Settings.QUALITY_CHOICES.size():
		seen.append(Settings.quality)
		Settings.cycle_quality()
	_check(seen == ["", "high", "balanced", "low"] and Settings.quality == "", "quality cycles through AUTO, HIGH, BALANCED, LOW and back to AUTO")
	Settings.quality = "low"
	Settings.apply_quality()
	_check(RenderQuality.current().name == "low", "choosing LOW makes RenderQuality use the low preset for the next scene")
	Settings.quality = "high"
	Settings.apply_quality()
	_check(RenderQuality.current().name == "high", "choosing HIGH makes RenderQuality use the high preset")
	Settings.reset_to_defaults()
	Settings.cycle_fps_cap()
	_check(Settings.fps_cap == 60 and Engine.max_fps == 60, "frame rate 60 is applied to the engine")
	Settings.cycle_fps_cap()
	_check(Settings.fps_cap == 30 and Engine.max_fps == 30, "frame rate 30 is applied to the engine")
	Settings.cycle_fps_cap()
	_check(Settings.fps_cap == 0 and Engine.max_fps == 0, "unlimited is applied to the engine (0)")
	Settings.reset_to_defaults()

# ---- Saving -----------------------------------------------------------------------------------------------

func _t_save_and_load() -> void:
	print("Saving")
	Settings.reset_to_defaults()
	Settings.set_sound_volume(0.3)
	Settings.set_sfx_volume(0.7)
	Settings.quality = "balanced"
	Settings.fps_cap = 30
	_check(Settings.save_settings(), "the settings file is written")
	Settings.sound_volume = 1.0
	Settings.sfx_volume = 1.0
	Settings.quality = ""
	Settings.fps_cap = 0
	Settings.load_settings()
	_check(is_equal_approx(Settings.sound_volume, 0.3) and is_equal_approx(Settings.sfx_volume, 0.7), "volumes come back after a restart")
	_check(Settings.quality == "balanced" and Settings.fps_cap == 30, "quality and frame rate come back after a restart")
	# A damaged value in the file is ignored, never trusted.
	var config := ConfigFile.new()
	config.load(Settings.default_path())
	config.set_value(Settings.SECTION, "quality", "ultra-extreme")
	config.set_value(Settings.SECTION, "fps_cap", 1000)
	config.save(Settings.default_path())
	Settings.load_settings()
	_check(Settings.quality == "" and Settings.fps_cap == 0, "unknown saved quality and frame rate fall back to the defaults")
	Settings.reset_to_defaults()

# ---- The panel, in the main menu --------------------------------------------------------------------------

func _t_panel() -> void:
	print("Settings panel")
	var menu := (load(MENU_SCENE) as PackedScene).instantiate() as MainMenu
	menu.scene_changer = func(_path: String) -> void: pass
	menu.app_quitter = func() -> void: pass
	add_child(menu)
	await _frames(2)
	var guard := Time.get_ticks_msec() + 6000
	while not menu.buttons_ready and Time.get_ticks_msec() < guard:
		await get_tree().process_frame
	var button := menu.settings_button()
	_check(button != null and button.text == "SETTINGS", "the main menu has a SETTINGS button")
	_check(button != null and button.is_visible_in_tree(), "the SETTINGS button is shown on the menu")
	var screen := menu.settings_screen()
	_check(not screen.is_showing, "the settings panel starts closed")
	button.pressed.emit()
	_check(screen.is_showing and menu.overlay_open(), "SETTINGS opens the panel and the menu behind it goes inert")
	guard = Time.get_ticks_msec() + 3000
	while not screen.buttons_ready and Time.get_ticks_msec() < guard:
		await get_tree().process_frame
	var sfx_up: Button = screen.find_child("SfxRowUp", true, false) as Button
	var sfx_before := Settings.sfx_volume
	if sfx_up != null:
		sfx_up.pressed.emit()
	_check(sfx_up != null and is_equal_approx(Settings.sfx_volume, minf(sfx_before + Settings.STEP, 1.0)), "the SFX + button raises the SFX volume by one step")
	var quality_button := screen.find_child("QualityRowButton", true, false) as Button
	var quality_before := Settings.quality
	if quality_button != null:
		quality_button.pressed.emit()
	_check(quality_button != null and Settings.quality != quality_before, "the QUALITY button changes the quality choice")
	var fps_button := screen.find_child("FpsRowButton", true, false) as Button
	if fps_button != null:
		fps_button.pressed.emit()
	_check(fps_button != null and Settings.fps_cap == 60, "the FRAME RATE button steps to 60 FPS")
	var caption := screen.find_child("Caption", true, false) as Label
	_check(caption != null and caption.text.contains("next run"), "the panel says graphics changes apply on the next run")
	screen.close_button.pressed.emit()
	_check(not screen.is_showing and not menu.overlay_open(), "CLOSE returns to the menu")
	Settings.reset_to_defaults()
	menu.queue_free()
	await _frames(2)

# ---- The panel, from the pause menu -----------------------------------------------------------------------

func _t_pause_menu() -> void:
	print("Settings from the pause menu")
	var pause := PauseMenu.new()
	add_child(pause)
	await _frames(2)
	pause.show_menu()
	await get_tree().create_timer(0.45).timeout  # the pause menu ignores presses for a moment after it opens
	var button := pause.settings_button()
	_check(button != null and button.text == "SETTINGS", "the pause menu has a SETTINGS button between RESUME and MAIN MENU")
	_check(not pause.back_belongs_to_settings(), "with only the pause menu open, Back is the pause menu's own (resume)")
	button.pressed.emit()
	_check(pause.settings_screen().is_showing, "SETTINGS from the pause menu opens the panel")
	_check(pause.back_belongs_to_settings(), "while the panel is open, Back belongs to the panel (the game stays paused)")
	var guard := Time.get_ticks_msec() + 3000
	while not pause.settings_screen().buttons_ready and Time.get_ticks_msec() < guard:
		await get_tree().process_frame
	pause.settings_screen().close()
	_check(pause.back_belongs_to_settings(), "the same frame the panel closes, a second Back is still absorbed (no resume)")
	await _frames(2)
	_check(not pause.back_belongs_to_settings(), "on the following frames Back is the pause menu's own again")
	pause.hide_menu()
	pause.queue_free()
	await _frames(2)

# ---- Credits ------------------------------------------------------------------------------------------------

func _t_credits() -> void:
	print("Credits")
	var settings := SettingsScreen.new()
	add_child(settings)
	await _frames(2)
	settings.open()
	var guard := Time.get_ticks_msec() + 3000
	while not settings.buttons_ready and Time.get_ticks_msec() < guard:
		await get_tree().process_frame
	settings.credits_button().pressed.emit()
	_check(settings.showing_credits() and settings.title_label.text == "CREDITS", "the CREDITS button shows the credits page in the same panel")
	_check(settings.find_child("Thanks", true, false) != null and settings.find_child("Body_GAME_DESIGN_CODE_AND_TESTING", true, false) != null, "the credits name the maker, the engine, the font and the sound licences")
	# Back: returns to the settings page and keeps the panel open, on the same press and after.
	settings.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)  # a real Back press reaches every node
	_check(not settings.showing_credits() and settings.is_showing, "Back from the credits returns to the settings, the panel stays open")
	await _frames(2)
	_check(settings.is_showing and not settings.showing_credits(), "the panel is still open on the following frames")
	# Escape does the same from the credits page.
	settings.credits_button().pressed.emit()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	settings._input(escape)
	_check(not settings.showing_credits() and settings.is_showing, "Escape from the credits returns to the settings")
	settings.close()
	settings.queue_free()
	await _frames(2)

# ---- Delete account: the confirmation step on the account screen (the server call itself is tested in backend_tests) ----------------

func _t_delete_flow() -> void:
	print("Delete account (screen)")
	Account.reset_for_test(Account.TEST_FILE_PATH)
	Account.set_logged_in("99999999-8888-4777-8666-555555555555", "Sir_Kay")
	var screen := AccountScreen.new()
	add_child(screen)
	await _frames(2)
	screen.open()
	var guard := Time.get_ticks_msec() + 3000
	while not screen.buttons_ready and Time.get_ticks_msec() < guard:
		await get_tree().process_frame
	var delete_button := screen.find_child("DeleteAccountButton", true, false) as Button
	_check(delete_button != null and delete_button.is_visible_in_tree(), "a logged-in player sees DELETE ACCOUNT")
	delete_button.pressed.emit()
	var confirm := screen.find_child("DeleteConfirm", true, false) as Control
	_check(confirm != null and confirm.visible and not delete_button.is_visible_in_tree(), "DELETE ACCOUNT opens the confirmation (the rest of the screen is hidden)")
	(screen.find_child("ConfirmDeleteButton", true, false) as Button).pressed.emit()
	_check((screen.find_child("DeleteMessage", true, false) as Label).text == "Type your password to confirm.", "DELETE FOREVER without a password does nothing and asks for it")
	_check(Account.logged_in, "...and the account is still there")
	(screen.find_child("CancelDeleteButton", true, false) as Button).pressed.emit()
	_check(not confirm.visible and delete_button.is_visible_in_tree(), "CANCEL returns to the account screen with nothing deleted")
	_check(Account.logged_in, "the account is still logged in after cancelling")
	screen.close()
	screen.queue_free()
	Account.reset_for_test(Account.TEST_FILE_PATH)
	await _frames(2)

# ---- The PAUSE button in the game ------------------------------------------------------------------------------------------------

func _t_pause_button() -> void:
	print("PAUSE button")
	var game := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(7.5).timeout  # the level 1 entrance
	var hud := game.get_node("Hud") as Hud
	var button := hud.pause_button()
	_check(button != null and button.text == "PAUSE" and button.is_visible_in_tree(), "the game has a PAUSE button on screen")
	var rect := button.get_global_rect()
	_check(rect.size.y >= 100.0 and rect.end.x <= hud.get_viewport().get_visible_rect().size.x, "the PAUSE button is big enough to tap and inside the screen")
	# A press on the button is not a game tap; a press elsewhere still is.
	var input := game.get_node("InputController") as InputController
	var taps := [0]
	input.tap_accepted.connect(func(_side: TapSide.Side) -> void: taps[0] += 1)
	var on_button := InputEventScreenTouch.new()
	on_button.pressed = true
	on_button.position = rect.get_center()
	input._input(on_button)
	_check(taps[0] == 0, "a press on PAUSE is not counted as a game tap")
	var elsewhere := InputEventScreenTouch.new()
	elsewhere.pressed = true
	elsewhere.position = Vector2(50, 900)
	input._input(elsewhere)
	_check(taps[0] == 1, "a press elsewhere is still a game tap")
	# PAUSE pauses the game and opens the pause menu (like the Back button).
	var pause_menu := game.get_node("PauseMenu") as PauseMenu
	button.pressed.emit()
	_check(GameManager.state == GameManager.State.PAUSED and pause_menu.is_showing, "PAUSE pauses the game and opens the pause menu")
	_check(not button.is_visible_in_tree(), "the PAUSE button hides while the game is paused")
	pause_menu.resume_requested.emit()
	await get_tree().process_frame
	_check(GameManager.state != GameManager.State.PAUSED and button.is_visible_in_tree(), "RESUME brings the game back and shows PAUSE again")
	# Back also pauses.
	game._on_back_requested()
	_check(GameManager.state == GameManager.State.PAUSED and pause_menu.is_showing, "the Back button pauses too")
	game.queue_free()
	GameManager.reset_run()
	get_tree().paused = false
	await get_tree().process_frame

# ---- MAIN MENU: the click plays BEFORE the scene changes (a crash on the phone) -----------------------------------------------------------

func _t_menu_button_order() -> void:
	print("MAIN MENU button order")
	# A sound asked of an audio node that is outside the tree is ignored, never played (it crashed Godot natively on Android).
	var lonely := GameAudio.new()
	lonely.play(&"ui_tap")
	_check(lonely.cue_count == 1 and lonely.get_child_count() == 0, "a GameAudio outside the scene tree ignores a sound request (no player is created)")
	lonely.free()
	var game := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(7.5).timeout
	var audio := game.get_node("Audio") as GameAudio
	var order: Array[String] = []
	game.scene_changer = func(_path: String) -> void: order.append("scene")
	audio.cue_requested.connect(func(cue: StringName, _i: float) -> void: order.append(String(cue)))
	# From the pause menu.
	game._on_back_requested()
	game.get_node("PauseMenu").quit_requested.emit()
	_check(order == ["ui_tap", "scene"], "pause menu, MAIN MENU: the click plays first, then the scene changes (%s)" % str(order))
	# From the failure screen.
	order.clear()
	GameManager.reset_run()
	get_tree().paused = false
	GameManager.set_state(GameManager.State.FAILED)
	game.get_node("FailureScreen").main_menu_requested.emit()
	_check(order == ["ui_tap", "scene"], "failure screen, MAIN MENU: the click plays first, then the scene changes (%s)" % str(order))
	game.queue_free()
	GameManager.reset_run()
	get_tree().paused = false
	await get_tree().process_frame

# ---- A real touch on MAIN MENU: the screen leaves the scene DURING the tap (the phone crash) -----------------------------------------------

## On the phone, MAIN MENU changed the scene at once; the input handler then called get_viewport() on a node that was already outside the
## tree (null) and the exported release build crashed natively. Here the scene change is replaced by "take the screen out of the tree",
## which is exactly what it did to the handler. Run the suite and look for "SCRIPT ERROR": there must be none.
func _t_touch_leaves_scene() -> void:
	print("Touch on MAIN MENU while the scene changes")
	var game := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(7.5).timeout
	# The failure screen.
	var failure := game.get_node("FailureScreen") as FailureScreen
	game.scene_changer = func(_path: String) -> void: game.remove_child(failure)
	GameManager.reset_run()
	get_tree().paused = false
	GameManager.set_state(GameManager.State.FAILED)
	failure.is_showing = true
	failure.visible = true
	failure.buttons_ready = true
	await get_tree().process_frame  # let the freshly shown screen be laid out, so its buttons have a position
	await get_tree().process_frame
	var point := (failure.find_child("MainMenuButton", true, false) as Button).get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.pressed = true
	press.position = point
	failure._input(press)
	var release := InputEventScreenTouch.new()
	release.pressed = false
	release.position = point
	failure._input(release)
	_check(not failure.is_inside_tree(), "a touch on the failure screen's MAIN MENU changed the scene (the screen left the tree during the tap) without an error")
	game.add_child(failure)  # put it back for the next part
	# The pause menu.
	GameManager.reset_run()
	GameManager.set_state(GameManager.State.READY)
	var pause := game.get_node("PauseMenu") as PauseMenu
	game._on_back_requested()
	await get_tree().create_timer(0.5).timeout  # the pause menu ignores presses for a moment after it opens
	game.scene_changer = func(_path: String) -> void: game.remove_child(pause)
	var pause_point := pause.quit_button().get_global_rect().get_center()
	press.position = pause_point
	release.position = pause_point
	pause._input(press)
	pause._input(release)
	_check(not pause.is_inside_tree(), "a touch on the pause menu's MAIN MENU changed the scene (the menu left the tree during the tap) without an error")
	game.queue_free()
	GameManager.reset_run()
	get_tree().paused = false
	await get_tree().process_frame

