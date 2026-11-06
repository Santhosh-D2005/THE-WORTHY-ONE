extends Node
## Screen-adaptability tests (Milestone 1.3): renders the real game at several portrait window
## sizes / aspect ratios and measures where the UI and the 3D focus (stump + sword) land.
##
## Run (needs a window; sizes are applied with Window.size):
##   godot --path . res://tests/layout_tests.tscn [-- <screenshot_dir>]
## Exit code: 0 = all passed, 1 = failures.
##
## This checks LAYOUT GEOMETRY on a desktop window. It is not a test on real phones: real
## devices add notches, rounded corners, gesture bars and different pixel densities.

const MAIN_SCENE := "res://scenes/main/main.tscn"

## [width, height, note]
const SIZES := [
	[540, 960, "9:16 (design size, half)"],
	[720, 1280, "9:16"],
	[1080, 1920, "9:16 (design size, full)"],
	[540, 1170, "19.5:9 tall phone"],
	[540, 1200, "20:9 taller phone"],
	[540, 1296, "21.6:9 very tall"],
	[768, 1024, "3:4 tablet (wider than 9:16)"],
]

var _checks: int = 0
var _failures: int = 0
var _failed_labels: Array[String] = []
var main: Node
var hud: Hud
var screen: FailureScreen
var camera: GameplayCamera
var sword: SwordController
var _baseline: Dictionary = {}  # normalised positions measured at the first (9:16) size

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.use_accumulated_input = false
	get_window().always_on_top = true
	print("screen size: ", DisplayServer.screen_get_size(), "  usable: ", DisplayServer.screen_get_usable_rect())
	await _frames(3)
	main = load(MAIN_SCENE).instantiate()
	add_child(main)
	hud = main.get_node("Hud")
	screen = main.get_node("FailureScreen")
	camera = main.get_node("Stage/Camera3D")
	sword = main.get_node("Stage/Sword")
	await _wait_state(GameManager.State.READY, 5.0)

	for entry in SIZES:
		await _check_size(entry[0], entry[1], entry[2])

	print("\n==== %d checks, %d failed ====" % [_checks, _failures])
	for label in _failed_labels:
		print("  FAILED: ", label)
	print("RESULT: ", "ALL PASSED" if _failures == 0 else "FAILURES")
	get_tree().quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		_failed_labels.append(label)
		print("  FAIL  ", label)

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func _wait_state(state: GameManager.State, timeout: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while GameManager.state != state and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func _save(file_name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	get_viewport().get_texture().get_image().save_png(args[0] + "/" + file_name)

# ---- geometry helpers ------------------------------------------------------------------------

func _visible_rect() -> Rect2:
	return get_viewport().get_visible_rect()

func _inside(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 0.5 and inner.position.y >= outer.position.y - 0.5 \
		and inner.end.x <= outer.end.x + 0.5 and inner.end.y <= outer.end.y + 0.5

func _text_fits(label: Label) -> bool:
	# The label's rect must be at least as large as the text it shows (no clipping/overflow).
	var needed := label.get_minimum_size()
	return needed.x <= label.size.x + 1.0 and needed.y <= label.size.y + 1.0

func _to_screen(world_point: Vector3) -> Vector2:
	return camera.unproject_position(world_point)

## HUD elements that must stay readable / tappable, as rects in viewport coordinates.
## The progress bar draws its captions above its own rect, so its visual rect is taller.
func _hud_rects() -> Dictionary:
	var bar_rect: Rect2 = hud._bar.get_global_rect()
	bar_rect = Rect2(bar_rect.position - Vector2(0, 46), bar_rect.size + Vector2(0, 46))
	return {
		"level": hud._level_label.get_global_rect(),
		"level_timer": hud._level_time_label.get_global_rect(),
		"session_timer": hud._session_time_label.get_global_rect(),
		"bar": bar_rect,
		"hint": hud._hint.get_global_rect(),
		"zone_left": hud._zone_left.get_global_rect(),
		"zone_right": hud._zone_right.get_global_rect(),
	}

func _check_size(width: int, height: int, note: String) -> void:
	var tag := "%dx%d" % [width, height]
	print("\n[%s] %s" % [tag, note])
	get_window().size = Vector2i(width, height)
	await _frames(6)
	var actual := get_window().size
	print("   requested %dx%d, window is %dx%d, viewport %s" % [width, height, actual.x, actual.y, _visible_rect().size])
	if actual != Vector2i(width, height):
		print("   NOTE: the OS limited the window size; layout (aspect ratio) is still what is checked")
	var aspect_ok := absf(float(actual.x) / float(actual.y) - float(width) / float(height)) < 0.01
	_check(aspect_ok, "window has the requested aspect ratio (%.4f)" % (float(width) / float(height)))
	var visible := _visible_rect()

	# ---------- gameplay HUD (state READY) ----------
	await _wait_state(GameManager.State.READY, 3.0)
	await _wait(0.4)
	var rects := _hud_rects()
	var keys: Array = rects.keys()
	for key in keys:
		_check(_inside(rects[key], visible), "HUD '%s' lies inside the screen" % key)
	var overlap_found := ""
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (rects[keys[i]] as Rect2).intersects(rects[keys[j]]):
				overlap_found += "%s/%s " % [keys[i], keys[j]]
	_check(overlap_found == "", "no two HUD elements overlap%s" % ((" (overlaps: " + overlap_found + ")") if overlap_found != "" else ""))
	_check(_text_fits(hud._level_label) and _text_fits(hud._level_time_label) and _text_fits(hud._session_time_label) and _text_fits(hud._hint),
		"HUD texts fit inside their boxes (no clipping)")
	var zl: Rect2 = rects["zone_left"]
	var zr: Rect2 = rects["zone_right"]
	_check(zl.end.x <= visible.size.x * 0.5 and zr.position.x >= visible.size.x * 0.5, "tap panels stay in their own screen halves")
	# 1.7: the tap controls are round discs (260 base px = 173 px on a 720-wide phone), no longer wide panels.
	_check(zl.size.x >= 240.0 and zr.size.x >= 240.0 and absf(zl.size.x - zl.size.y) < 1.0 and absf(zr.size.x - zr.size.y) < 1.0,
		"round tap controls are at least 240 base px across and perfectly round (%dx%d base px)" % [int(zl.size.x), int(zl.size.y)])
	_check(absf((zl.size.x) - (zr.size.x)) < 2.0, "tap panels are symmetric")

	# 3D focus: stump top rim and sword at rest / at 100% must be on screen and not covered by HUD.
	var covers := ["level", "level_timer", "session_timer", "bar", "hint", "zone_left", "zone_right"]
	var rest_y: float = sword._rest_position.y
	var pommel_offset := SwordController.BLADE_LENGTH + 0.08 + SwordController.GRIP_LENGTH + 0.155
	var focus_points := {
		"stump top centre": Vector3(0, 1.0, 0),
		"stump top left rim": Vector3(-1.25, 1.0, 0),
		"stump top right rim": Vector3(1.25, 1.0, 0),
		"stump top front rim": Vector3(0, 1.0, 1.25),
		"stump top back rim": Vector3(0, 1.0, -1.25),
		"sword pommel at 0%": Vector3(0, rest_y + pommel_offset, 0),
		"sword guard at 0%": Vector3(0, rest_y + SwordController.BLADE_LENGTH, 0),
	}
	var focus_ok := true
	var focus_detail := ""
	for name in focus_points:
		var point := _to_screen(focus_points[name])
		if not visible.has_point(point):
			focus_ok = false
			focus_detail += "%s off-screen at %s; " % [name, point]
		for key in covers:
			if (rects[key] as Rect2).has_point(point):
				focus_ok = false
				focus_detail += "%s is covered by HUD '%s'; " % [name, key]
	_check(focus_ok, "stump top and resting sword are visible and not covered by any HUD element %s" % focus_detail)
	var top_clearance := _to_screen(Vector3(0, rest_y + pommel_offset + sword.full_lift, 0)).y - (rects["session_timer"] as Rect2).end.y
	_check(top_clearance > -80.0, "sword pommel at 100% progress stays within 80 px of the timers (clearance %d px)" % int(top_clearance))
	var held_y := _to_screen(Vector3(0, rest_y + pommel_offset + sword.full_lift + 0.55, 0)).y
	_check(held_y > 0.0, "the held-up sword in the success animation still shows its pommel on screen (y=%d)" % int(held_y))
	var stump_screen_x := _to_screen(Vector3(0, 1.0, 0)).x
	_check(absf(stump_screen_x - visible.size.x * 0.5) < 3.0, "stump is horizontally centred")
	var rim_left := _to_screen(Vector3(-1.25, 1.0, 0)).x
	var rim_right := _to_screen(Vector3(1.25, 1.0, 0)).x
	var stump_fraction := (rim_right - rim_left) / visible.size.x
	_check(stump_fraction > 0.35 and stump_fraction < 0.8, "stump occupies a meaningful share of the width (%.0f%%)" % (stump_fraction * 100.0))
	_save("layout_%s_hud.png" % tag)

	# ---------- playtest preset label (only appears for non-default presets) ----------
	_check(hud.get_preset_label() == null, "the default build shows no preset label")
	hud.show_preset_label("grace_long")
	await _frames(2)
	var preset_rect: Rect2 = hud.get_preset_label().get_global_rect()
	var preset_clear := _inside(preset_rect, visible) and _text_fits(hud.get_preset_label())
	for key in rects:
		if preset_rect.intersects(rects[key]):
			preset_clear = false
	_check(preset_clear, "the playtest-preset label fits on screen and overlaps no other HUD element")
	hud.get_preset_label().queue_free()
	hud._safe_nodes = hud._safe_nodes.filter(func(entry: Array) -> bool: return entry[0] != hud.get_preset_label())
	hud._fade_group = hud._fade_group.filter(func(item: CanvasItem) -> bool: return item != hud.get_preset_label())
	hud._preset_label = null
	await _frames(2)

	# ---------- composition is consistent across aspect ratios ----------
	var aspect := visible.size.x / visible.size.y
	var norm_centre := _to_screen(Vector3(0, 1.0, 0)) / visible.size
	var norm_pommel := _to_screen(Vector3(0, rest_y + pommel_offset, 0)) / visible.size
	var norm_rim := (_to_screen(Vector3(1.25, 1.0, 0)).x - _to_screen(Vector3(-1.25, 1.0, 0)).x) / visible.size.x
	if _baseline.is_empty():
		_baseline = {"centre": norm_centre, "pommel": norm_pommel, "rim": norm_rim}
	var design_aspect := 1080.0 / 1920.0
	if absf(aspect - design_aspect) < 0.002:
		_check(norm_centre.distance_to(_baseline["centre"]) < 0.003 and norm_pommel.distance_to(_baseline["pommel"]) < 0.003
			and absf(norm_rim - _baseline["rim"]) < 0.003,
			"9:16 at every resolution gives the identical composition (stump, sword, width)")
	elif aspect < design_aspect:
		_check(absf(norm_rim - _baseline["rim"]) < 0.003 and absf(norm_centre.x - _baseline["centre"].x) < 0.003,
			"taller than 9:16: the stump keeps its width on screen (%.1f%%)" % (norm_rim * 100.0))
		_check(camera.keep_aspect == Camera3D.KEEP_WIDTH, "taller screens keep the horizontal field of view")
	else:
		_check(camera.keep_aspect == Camera3D.KEEP_HEIGHT, "wider screens keep the vertical field of view")
		_check(absf(norm_centre.y - _baseline["centre"].y) < 0.003 and absf(norm_pommel.y - _baseline["pommel"].y) < 0.003,
			"wider than 9:16: vertical composition (stump and sword height) is unchanged")

	# ---------- safe-area insets (simulated camera cut-out and gesture bar) ----------
	var before := _hud_rects()
	SafeArea.test_insets = Vector4(0.0, 110.0, 0.0, 70.0)
	hud.refresh_safe_area()
	await _frames(2)
	var after := _hud_rects()
	var shifted_ok := true
	for key in ["level", "level_timer", "session_timer"]:
		if not is_equal_approx((after[key] as Rect2).position.y - (before[key] as Rect2).position.y, 110.0):
			shifted_ok = false
	for key in ["bar", "hint", "zone_left", "zone_right"]:
		if not is_equal_approx((after[key] as Rect2).position.y - (before[key] as Rect2).position.y, -70.0):
			shifted_ok = false
	_check(shifted_ok, "with a 110 px top inset and 70 px bottom inset the HUD moves down / up by exactly those amounts")
	var inset_inside := true
	var inset_overlap := false
	var inset_keys: Array = after.keys()
	for i in inset_keys.size():
		if not _inside(after[inset_keys[i]], visible):
			inset_inside = false
		for j in range(i + 1, inset_keys.size()):
			if (after[inset_keys[i]] as Rect2).intersects(after[inset_keys[j]]):
				inset_overlap = true
	_check(inset_inside and not inset_overlap, "with insets the HUD is still fully on screen and non-overlapping")
	_check((after["session_timer"] as Rect2).position.y >= 110.0 and (after["zone_left"] as Rect2).end.y <= visible.size.y - 70.0,
		"HUD stays inside the safe area (below the cut-out, above the gesture bar)")
	_save("layout_%s_hud_insets.png" % tag)
	SafeArea.test_insets = null
	hud.refresh_safe_area()
	await _frames(2)
	var restored := _hud_rects()
	var restored_ok := true
	for key in restored:
		if not (restored[key] as Rect2).is_equal_approx(before[key]):
			restored_ok = false
	_check(restored_ok, "removing the insets restores the original layout exactly")

	# ---------- failure screen ----------
	hud._level_label.text = "LEVEL 1"
	var result := RunResult.new()
	result.level_reached = 12
	result.session_seconds = 754.32
	result.extractions = 11
	_tap_to_start_and_fail()
	var failed := await _wait_failed()
	_check(failed, "a real failure was triggered at this size")
	await _wait_for_screen()
	await _wait(1.2)
	var title: Label = screen.find_child("Title", true, false)
	var divider: Control = screen.find_child("Divider", true, false)
	var stats: Control = screen.find_child("Stats", true, false)
	var buttons: Control = screen.find_child("Buttons", true, false)
	var try_button: Button = screen.find_child("TryAgainButton", true, false)
	var menu_button: Button = screen.find_child("MainMenuButton", true, false)
	var fs_rects := {
		"title": title.get_global_rect(),
		"divider": divider.get_global_rect(),
		"stats": stats.get_global_rect(),
		"try_again": try_button.get_global_rect(),
		"main_menu": menu_button.get_global_rect(),
	}
	for key in fs_rects:
		_check(_inside(fs_rects[key], visible), "failure screen '%s' lies inside the screen" % key)
	var fs_overlap := ""
	var fs_keys: Array = fs_rects.keys()
	for i in fs_keys.size():
		for j in range(i + 1, fs_keys.size()):
			if (fs_rects[fs_keys[i]] as Rect2).intersects(fs_rects[fs_keys[j]]):
				fs_overlap += "%s/%s " % [fs_keys[i], fs_keys[j]]
	_check(fs_overlap == "", "failure screen elements do not overlap%s" % ((" (" + fs_overlap + ")") if fs_overlap != "" else ""))
	var texts_fit := _text_fits(title)
	for column in stats.get_children():
		for child in column.get_children():
			if child is Label and not _text_fits(child):
				texts_fit = false
	_check(texts_fit, "failure screen texts fit (no clipping)")
	_check(try_button.size.y >= 100.0 and menu_button.size.y >= 100.0 and try_button.size.x >= 300.0, "buttons are large touch targets (%dx%d base px)" % [int(try_button.size.x), int(try_button.size.y)])
	var focus_covered := false
	for name in ["stump top centre", "sword pommel at 0%", "sword guard at 0%"]:
		var point := _to_screen(focus_points[name])
		for key in ["title", "stats", "try_again", "main_menu"]:
			if (fs_rects[key] as Rect2).has_point(point):
				focus_covered = true
	_check(not focus_covered, "the failure screen leaves the stump top and sword visible")
	_save("layout_%s_failure.png" % tag)
	SafeArea.test_insets = Vector4(0.0, 110.0, 0.0, 70.0)
	screen.refresh_safe_area()
	await _frames(2)
	var title_after := title.get_global_rect()
	var buttons_after := try_button.get_global_rect()
	_check(is_equal_approx(title_after.position.y - (fs_rects["title"] as Rect2).position.y, 110.0)
		and is_equal_approx(buttons_after.position.y - (fs_rects["try_again"] as Rect2).position.y, -70.0)
		and _inside(title_after, visible) and _inside(buttons_after, visible) and _inside(menu_button.get_global_rect(), visible),
		"failure screen respects the insets (title +110 px, buttons -70 px, all on screen)")
	_save("layout_%s_failure_insets.png" % tag)
	SafeArea.test_insets = null
	screen.refresh_safe_area()

	# Reset for the next size.
	if main != null:
		main.queue_free()
		await get_tree().process_frame
	get_tree().paused = false
	main = load(MAIN_SCENE).instantiate()
	add_child(main)
	hud = main.get_node("Hud")
	screen = main.get_node("FailureScreen")
	camera = main.get_node("Stage/Camera3D")
	sword = main.get_node("Stage/Sword")
	await _wait_state(GameManager.State.READY, 5.0)

func _tap_to_start_and_fail() -> void:
	var event := InputEventScreenTouch.new()
	event.pressed = true
	event.position = get_viewport().get_screen_transform() * Vector2(_visible_rect().size.x * 0.25, 1000.0)
	Input.parse_input_event(event)

func _wait_failed() -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while GameManager.state != GameManager.State.FAILED and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return GameManager.state == GameManager.State.FAILED

func _wait_for_screen() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while not screen.is_showing and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
