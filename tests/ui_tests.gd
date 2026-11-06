extends Node
## Milestone 1.16 focused UI tests (presentation only): the shared style, the pause menu, the failure screen, the completion card and the
## HUD, at several portrait screen shapes. Run headless:   godot --headless --path . res://tests/ui_tests.tscn
## Navigation and behaviour (pause / resume, retry, MAIN MENU) are covered by pause_tests and failure_tests; this file checks what the
## player SEES: layout, touch targets, typography and palette consistency, and the card's content.
## Exit code 0 = all passed. This is an automated measurement of layout rectangles, NOT a visual inspection and NOT a phone test.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const SIZES := [Vector2i(540, 960), Vector2i(540, 1200), Vector2i(360, 800), Vector2i(720, 1600), Vector2i(800, 1000)]

var _checks := 0
var _failures := 0
var main: Node
var hud: Hud
var pause_menu: PauseMenu
var screen: FailureScreen

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
	await _t_scene_and_style()
	await _t_pause_menu()
	await _t_failure_screen()
	await _t_completion_card()
	await _t_hud()
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

func _fresh(size: Vector2i = Vector2i(540, 960)) -> void:
	get_window().size = size
	if main != null:
		main.queue_free()
		await get_tree().process_frame
	get_tree().paused = false
	main = load(MAIN_SCENE).instantiate()
	add_child(main)
	hud = main.get_node("Hud")
	pause_menu = main.get_node("PauseMenu")
	screen = main.get_node("FailureScreen")
	while GameManager.state != GameManager.State.READY:
		await get_tree().process_frame
	await _frames(3)

func _inside(rect: Rect2, view: Rect2) -> bool:
	return rect.position.x >= view.position.x - 0.5 and rect.end.x <= view.end.x + 0.5 and rect.position.y >= view.position.y - 0.5 and rect.end.y <= view.end.y + 0.5

func _labels_under(node: Node) -> Array:
	return node.find_children("*", "Label", true, false)

# ---- 1. scene loading and the shared style --------------------------------------------------------

func _t_scene_and_style() -> void:
	print("\n[1] SCENES LOAD AND SHARE ONE STYLE")
	await _fresh()
	_check(hud != null and pause_menu != null and screen != null, "the HUD, pause menu and failure screen load with the game scene")
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await _frames(3)
	var shared_font := UiStyle.font()
	var mismatched := 0
	var total := 0
	for root in [hud, pause_menu, screen, menu]:
		for label in _labels_under(root):
			total += 1
			var font: Font = label.get_theme_font("font")
			if font != shared_font and font.get_class() == "FontVariation" and (font as FontVariation).base_font != shared_font.base_font:
				mismatched += 1
			elif font != shared_font and font.get_class() != "FontVariation":
				mismatched += 1
	_check(total > 20 and mismatched == 0, "all %d labels on the four screens use the shared Cinzel font (%d mismatched)" % [total, mismatched])
	# Buttons: the same style family everywhere (amber border on the primary, dim border on the secondary).
	var primary_style := (pause_menu.resume_button().get_theme_stylebox("normal") as StyleBoxFlat)
	var main_primary := ((menu as MainMenu).play_button().get_theme_stylebox("normal") as StyleBoxFlat)
	var retry := screen.find_child("TryAgainButton", true, false) as Button
	var retry_style := retry.get_theme_stylebox("normal") as StyleBoxFlat
	_check(primary_style.border_color == UiStyle.GOLD and main_primary.border_color == UiStyle.GOLD and retry_style.border_color == UiStyle.GOLD, "the primary button of the menu, pause menu and failure screen share one amber border")
	var secondary := (pause_menu.quit_button().get_theme_stylebox("normal") as StyleBoxFlat)
	_check(secondary.border_color == UiStyle.GOLD_DIM and secondary.corner_radius_top_left == UiStyle.CORNER_RADIUS and primary_style.corner_radius_top_left == UiStyle.CORNER_RADIUS, "secondary buttons use the dim border and every button uses the same corner radius")
	menu.queue_free()
	await _frames(2)

# ---- 2. pause menu ----------------------------------------------------------------------------------

func _t_pause_menu() -> void:
	print("\n[2] PAUSE MENU")
	for size in SIZES:
		await _fresh(size)
		main._pause()
		main._open_pause_menu()
		await _frames(3)
		var view := hud.get_viewport().get_visible_rect()
		var tag := "%dx%d" % [size.x, size.y]
		var title := pause_menu.get_node("Root/Title") as Label
		var resume := pause_menu.resume_button()
		var leave := pause_menu.quit_button()
		_check(title.text == "PAUSED" and _inside(title.get_global_rect(), view), "%s: a clear PAUSED heading, inside the screen" % tag)
		_check(_inside(resume.get_global_rect(), view) and _inside(leave.get_global_rect(), view), "%s: both buttons are inside the screen" % tag)
		_check(resume.get_global_rect().size.y >= 120.0 and leave.get_global_rect().size.y >= 120.0, "%s: touch targets of at least 48 dp (RESUME %.0f, MAIN MENU %.0f base px high)" % [tag, resume.get_global_rect().size.y, leave.get_global_rect().size.y])
		_check(resume.get_global_rect().size.y > leave.get_global_rect().size.y and resume.get_global_rect().end.y <= leave.get_global_rect().position.y, "%s: RESUME is the primary (larger) action, above MAIN MENU" % tag)
		_check(title.get_global_rect().end.y < resume.get_global_rect().position.y, "%s: the heading does not overlap the buttons" % tag)
		_check(leave.text == PauseMenu.LEAVE_TEXT and resume.text == "RESUME", "%s: the buttons say RESUME and MAIN MENU" % tag)
	await _fresh()

# ---- 3. failure screen ----------------------------------------------------------------------------

func _t_failure_screen() -> void:
	print("\n[3] FAILURE SCREEN")
	for size in SIZES:
		await _fresh(size)
		var result := RunResult.new()
		result.level_reached = 7
		result.extractions = 6
		result.session_seconds = 95.5
		screen.show_result(result)
		await _frames(3)
		var view := hud.get_viewport().get_visible_rect()
		var tag := "%dx%d" % [size.x, size.y]
		var title := screen.find_child("Title", true, false) as Label
		var sub := screen.find_child("Subtitle", true, false) as Label
		var panel := screen.find_child("StatsPanel", true, false) as Control
		var stats := screen.find_child("Stats", true, false) as Control
		var retry := screen.find_child("TryAgainButton", true, false) as Button
		var menu_button := screen.find_child("MainMenuButton", true, false) as Button
		var ok := true
		for node in [title, sub, panel, stats, retry, menu_button]:
			if not _inside(node.get_global_rect(), view):
				ok = false
		_check(ok, "%s: title, subtitle, statistics panel and both buttons are inside the screen" % tag)
		_check(title.text == "THE SWORD REMAINS" and title.get_global_rect().end.y <= sub.get_global_rect().position.y + 1.0, "%s: heading, then a quiet subtitle without overlap" % tag)
		_check(panel.get_global_rect().encloses(stats.get_global_rect()), "%s: the three statistics sit inside their panel" % tag)
		_check(sub.get_global_rect().end.y < panel.get_global_rect().position.y and panel.get_global_rect().end.y <= retry.get_global_rect().position.y, "%s: subtitle, statistics and buttons are stacked without overlap (the middle stays free for the stump)" % tag)
		_check(retry.get_global_rect().size.y >= 120.0 and menu_button.get_global_rect().size.y >= 120.0, "%s: touch targets of at least 48 dp (%.0f / %.0f)" % [tag, retry.get_global_rect().size.y, menu_button.get_global_rect().size.y])
		_check(retry.get_global_rect().size.x > menu_button.get_global_rect().size.x, "%s: TRY AGAIN is the wider, clearer action" % tag)
		_check(menu_button.get_theme_color("font_color") == UiStyle.PARCHMENT and retry.get_theme_color("font_color") == UiStyle.GOLD_BRIGHT, "%s: no red anywhere: amber and parchment text only" % tag)
		# The stored statistics are untouched by the restyle.
		_check((screen.find_child("LevelValue", true, false) as Label).text == "7" and (screen.find_child("ExtractionsValue", true, false) as Label).text == "6" and (screen.find_child("SessionValue", true, false) as Label).text == RunResult.format_time(95.5), "%s: the run statistics still show level reached, session time and extractions" % tag)
	await _fresh()

# ---- 4. completion card -----------------------------------------------------------------------------

func _t_completion_card() -> void:
	print("\n[4] COMPLETION CARD")
	await _fresh()
	hud.show_level_complete(3, 12.34, 3, 5.0)
	await _wait(0.8)
	_check(hud.is_level_complete_visible(), "the card is visible after an extraction")
	_check(hud._banner_title.text == "THE SWORD YIELDS" and hud._banner_sub.text == "LEVEL 3 COMPLETE", "the wording is unchanged: THE SWORD YIELDS / LEVEL 3 COMPLETE")
	_check(hud._banner_stats.text == "EXTRACTION TIME   00:12.34", "the extraction time is shown as MM:SS.cc (%s)" % hud._banner_stats.text)
	_check(hud._banner_note.text == "3 SWORDS EXTRACTED", "the swords-extracted line is unchanged (%s)" % hud._banner_note.text)
	var all_text := (hud._banner_title.text + hud._banner_sub.text + hud._banner_stats.text + hud._banner_note.text).to_lower()
	_check(not all_text.contains("tap"), "the card never shows tap counts")
	hud.show_level_complete(1, 3.0, 1, 5.0)
	_check(hud._banner_note.text == "1 SWORD EXTRACTED", "singular wording for one sword")
	_check(hud._banner_stats.get_theme_font_size("font_size") >= hud._banner_note.get_theme_font_size("font_size") + 6, "the extraction time is the card's headline figure (bigger than the note)")
	for size in SIZES:
		await _fresh(size)
		hud.show_level_complete(12, 123.45, 12, 5.0)
		await _frames(3)
		var view := hud.get_viewport().get_visible_rect()
		var inside := true
		var fits := true
		for label in [hud._banner_title, hud._banner_sub, hud._banner_stats, hud._banner_note]:
			if not _inside(label.get_global_rect(), view):
				inside = false
			if label.get_minimum_size().x > view.size.x * 0.96:
				fits = false
		_check(inside and fits, "%dx%d: the card's four lines are inside the screen and fit the width (even at 12 swords / 123 s)" % [size.x, size.y])
		var rects: Array[Rect2] = [hud._banner_title.get_global_rect(), hud._banner_sub.get_global_rect(), hud._banner_stats.get_global_rect(), hud._banner_note.get_global_rect()]
		var stacked := true
		for i in range(1, rects.size()):
			if rects[i].position.y < rects[i - 1].end.y - 4.0:
				stacked = false
		_check(stacked, "%dx%d: the card's lines are stacked without overlap" % [size.x, size.y])
	await _fresh()

# ---- 5. HUD ----------------------------------------------------------------------------------------

func _t_hud() -> void:
	print("\n[5] GAMEPLAY HUD")
	for size in SIZES:
		await _fresh(size)
		var view := hud.get_viewport().get_visible_rect()
		var tag := "%dx%d" % [size.x, size.y]
		var inside := true
		var smallest := 999
		for label in _labels_under(hud):
			if label.text == "" or not label.is_visible_in_tree():
				continue
			if not _inside(label.get_global_rect(), view):
				inside = false
			smallest = mini(smallest, label.get_theme_font_size("font_size"))
		_check(inside, "%s: every visible HUD label is inside the screen" % tag)
		_check(smallest >= 26, "%s: the smallest HUD text is %d base px (26 or more: about 17 px on the 720 px phone)" % [tag, smallest])
		_check(hud._level_label.get_theme_color("font_color") == UiStyle.GOLD_BRIGHT and hud._level_time_label.get_theme_color("font_color") == UiStyle.PARCHMENT, "%s: the HUD uses the shared amber / parchment palette" % tag)
	await _fresh()
