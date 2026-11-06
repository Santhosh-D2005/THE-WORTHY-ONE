class_name Hud
extends CanvasLayer
## Gameplay HUD, built in code so layout stays adaptive (anchors) without scene churn.
## Purely presentational: it reads state and never changes gameplay.
## Every Control ignores the mouse so taps always reach InputController.

const GOLD := UiStyle.GOLD
const GOLD_DIM := UiStyle.GOLD_DIM
const GOLD_BRIGHT := UiStyle.GOLD_BRIGHT
const PARCHMENT := UiStyle.PARCHMENT
const PANEL := UiStyle.PANEL
const FONT_PATH := "res://assets/fonts/Cinzel.ttf"

var _font: FontVariation

var _level_label: Label
var _level_time_label: Label
var _session_time_label: Label
var _banner: Control
var _hint: Label
var _pause_overlay: ColorRect
var _pause_overlay_suppressed: bool = false
var _bar: Control
var _zone_left: ForestDisc
var _zone_right: ForestDisc
var _banner_title: Label
var _banner_sub: Label
var _banner_stats: Label
var _banner_note: Label
var _banner_line: ColorRect
var _banner_tween: Tween = null
var _complete_flash: float = 0.0  # bar glow when the extraction completes

var _extraction: ExtractionManager
var _timers: TimerManager
var _input: InputController
var _display_progress: float = 0.0
var _progress: float = 0.0
var _hint_tween: Tween = null
## The two round controls (Milestone 1.7): diameter in base px, distance of the circle's bottom from the screen bottom.
const DISC_DIAMETER := 260.0
const DISC_BOTTOM_MARGIN := 100.0
const HINT_TEXT := "ALTERNATE  YOUR  TAPS"
var _flash_left: float = 0.0
var _flash_right: float = 0.0
var _safe_nodes: Array = []  # [control, is_top, base_offset_top, base_offset_bottom]
var _preset_label: Label = null  # only exists for non-default playtest presets
var _fade_group: Array[CanvasItem] = []  # gameplay widgets that fade out on failure
var _ui_faded: bool = false

func setup(extraction: ExtractionManager, timers: TimerManager, input_controller: InputController) -> void:
	_extraction = extraction
	_timers = timers
	_input = input_controller
	_extraction.progress_changed.connect(func(value: float) -> void: _progress = value)
	_input.tap_accepted.connect(_on_tap_accepted)
	GameManager.level_changed.connect(_on_level_changed)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.extraction_succeeded.connect(func(_l: int, _t: float) -> void: _complete_flash = 1.0)
	_on_level_changed(GameManager.level)

func _ready() -> void:
	layer = 10
	_font = UiStyle.font()
	_build_scrims()
	_build_top_bar()
	_build_progress_bar()
	_build_tap_zones()
	_build_banner()
	_build_pause_overlay()
	for top_node in [_level_label, _level_time_label, _session_time_label, _banner]:
		_register_safe_area(top_node, true)
	for bottom_node in [_bar, _hint, _zone_left, _zone_right]:
		_register_safe_area(bottom_node, false)
	refresh_safe_area()
	get_viewport().size_changed.connect(refresh_safe_area)
	# Measurement switches (debug builds, via user://launch_args.txt): hide parts of the HUD to find what costs GPU time.
	var debug_args := RenderQuality.launch_arguments()
	if "--no-discs" in debug_args:
		_zone_left.visible = false
		_zone_right.visible = false
	# Everything except the banner and the pause overlay belongs to the gameplay HUD.
	for child in get_children():
		if child is CanvasItem and child != _banner and child != _pause_overlay:
			_fade_group.append(child)

# ---- Construction --------------------------------------------------------------------------

func _build_scrims() -> void:
	_add_scrim(true, 440, 0.62)
	_add_scrim(false, 760, 0.7)

func _add_scrim(at_top: bool, height: float, strength: float) -> void:
	add_child(UiStyle.scrim("TopScrim" if at_top else "BottomScrim", at_top, height, strength))

func _build_top_bar() -> void:
	_level_label = _make_label("LEVEL 1", 78, GOLD_BRIGHT)
	_level_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_level_label.offset_top = 90
	_level_label.offset_bottom = 190
	add_child(_level_label)

	_level_time_label = _make_label("LEVEL  0:00.00", 38, PARCHMENT)
	_level_time_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_level_time_label.offset_top = 200
	_level_time_label.offset_bottom = 260
	add_child(_level_time_label)

	_session_time_label = _make_label("SESSION  0:00.00", 32, Color(0.93, 0.90, 0.82, 0.72))
	_session_time_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_session_time_label.offset_top = 262
	_session_time_label.offset_bottom = 314
	add_child(_session_time_label)

func _build_progress_bar() -> void:
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.anchor_left = 0.12
	_bar.anchor_right = 0.88
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_top = -545
	_bar.offset_bottom = -505
	_bar.draw.connect(_draw_progress_bar)
	add_child(_bar)

func _build_tap_zones() -> void:
	_zone_left = _make_disc(0.25, Vector2(0.0, 0.0))
	_zone_right = _make_disc(0.75, Vector2(0.43, 0.29))

	_hint = _make_label(HINT_TEXT, 34, GOLD_DIM)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -490
	_hint.offset_bottom = -430
	add_child(_hint)

## A round forest disc centred in its screen half (0.25 = centre of the left half, 0.75 = of the right half).
func _make_disc(anchor_x: float, seed_offset: Vector2) -> ForestDisc:
	var disc := ForestDisc.new()
	disc.configure(seed_offset)
	disc.anchor_left = anchor_x
	disc.anchor_right = anchor_x
	disc.anchor_top = 1.0
	disc.anchor_bottom = 1.0
	disc.offset_left = -DISC_DIAMETER * 0.5
	disc.offset_right = DISC_DIAMETER * 0.5
	disc.offset_top = -(DISC_BOTTOM_MARGIN + DISC_DIAMETER)
	disc.offset_bottom = -DISC_BOTTOM_MARGIN
	disc.pivot_offset = Vector2(DISC_DIAMETER, DISC_DIAMETER) * 0.5
	add_child(disc)
	return disc

func _build_banner() -> void:
	_banner = Control.new()
	_banner.name = "LevelComplete"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.0
	_banner.anchor_bottom = 0.0
	_banner.offset_top = 70
	_banner.offset_bottom = 340
	_banner.modulate.a = 0.0
	add_child(_banner)
	# Headline, thin gold line, the completed level, the extraction time and the number of swords extracted this session.
	_banner_title = _make_label("THE SWORD YIELDS", 62, GOLD_BRIGHT)
	_banner_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_banner_title.offset_top = 0
	_banner_title.offset_bottom = 90
	_banner.add_child(_banner_title)
	_banner_line = ColorRect.new()
	_banner_line.color = Color(0.78, 0.65, 0.36, 0.85)  # (the amber hairline under the heading)
	_banner_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_line.anchor_left = 0.25
	_banner_line.anchor_right = 0.75
	_banner_line.offset_top = 100
	_banner_line.offset_bottom = 103
	_banner.add_child(_banner_line)
	_banner_sub = _make_label("LEVEL 1 COMPLETE", 40, GOLD)
	_banner_sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_banner_sub.offset_top = 114
	_banner_sub.offset_bottom = 172
	_banner.add_child(_banner_sub)
	_banner_stats = _make_label("", 40, PARCHMENT)  # 1.16: the extraction time is the card's headline figure (was 32)
	_banner_stats.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_banner_stats.offset_top = 176
	_banner_stats.offset_bottom = 238
	_banner.add_child(_banner_stats)
	_banner_note = _make_label("", 32, UiStyle.PARCHMENT)  # 1.17: was 30 px at 0.72 alpha (about 3.6:1 over the bright sky); now full parchment
	_banner_note.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_banner_note.offset_top = 244
	_banner_note.offset_bottom = 290
	_banner.add_child(_banner_note)

## The level-complete card (Milestone 1.9): THE SWORD YIELDS / LEVEL n COMPLETE / EXTRACTION TIME 00:08.42 / n SWORDS EXTRACTED.
## The primary statistic is the extraction time (first valid tap to 100 %). Tap counts are never shown.
## While it is up, the level and timer labels at the top fade out so the two never compete, and return after.
## `hold` is how long it stays fully visible. Purely presentational; nothing in gameplay waits for it.
func show_level_complete(level: int, seconds: float, extractions: int, hold: float) -> void:
	_banner_title.text = "THE SWORD YIELDS"
	_banner_sub.text = "LEVEL %d COMPLETE" % level
	_banner_stats.text = "EXTRACTION TIME   %s" % format_extraction_time(seconds)
	_banner_note.text = ("%d SWORD EXTRACTED" if extractions == 1 else "%d SWORDS EXTRACTED") % extractions
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner_line.pivot_offset = Vector2(_banner_line.size.x * 0.5, 0.0)
	_banner_line.scale = Vector2(0.0, 1.0)
	var top_labels: Array[Control] = [_level_label, _level_time_label, _session_time_label]
	if _preset_label != null:
		top_labels.append(_preset_label)
	_banner_tween = create_tween()
	_banner_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)  # the card freezes with the game when it is paused
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_banner_tween.parallel().tween_property(_banner_line, "scale:x", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for label in top_labels:
		_banner_tween.parallel().tween_property(label, "modulate:a", 0.0, 0.3)
	_banner_tween.tween_interval(maxf(hold, 0.2))
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	for label in top_labels:
		_banner_tween.parallel().tween_property(label, "modulate:a", 1.0, 0.5)

func is_level_complete_visible() -> bool:
	return _banner.modulate.a > 0.05

func _build_pause_overlay() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.color = Color(0.0, 0.01, 0.0, 0.72)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	_pause_overlay.add_child(UiStyle.vignette())
	# 1.16: the same heading and hint typography as the pause menu (PAUSED in bright amber, the hint in muted parchment).
	var heading := _make_label("PAUSED", UiStyle.SIZE_HEADING, GOLD_BRIGHT)
	heading.name = "PausedHeading"
	# 1.17: the heading sits where the pause menu's heading sits (above the stump), not across the sword.
	heading.anchor_left = 0.0
	heading.anchor_right = 1.0
	heading.anchor_top = 0.28
	heading.anchor_bottom = 0.28
	heading.offset_top = -60
	heading.offset_bottom = 60
	_pause_overlay.add_child(heading)
	var hint := _make_label("TAP TO RESUME", UiStyle.SIZE_SUBHEADING, UiStyle.PARCHMENT_DIM)
	hint.name = "ResumeHint"
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 0.28
	hint.anchor_bottom = 0.28
	hint.offset_top = 70
	hint.offset_bottom = 140
	_pause_overlay.add_child(hint)
	add_child(_pause_overlay)

func _make_label(text: String, font_size: int, color: Color) -> Label:
	return UiStyle.label(text, font_size, color)

# ---- Updates -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _timers == null:
		return
	_level_time_label.text = "LEVEL  " + _format_time(_timers.level_seconds())
	_session_time_label.text = "SESSION  " + _format_time(_timers.session_seconds())

	_display_progress = lerpf(_display_progress, _progress, 1.0 - exp(-20.0 * delta))
	if absf(_display_progress - _progress) < 0.05:
		_display_progress = _progress  # settle exactly, so the label equals floor(progress) instead of 61 for 62.00
	_bar.queue_redraw()

	_flash_left = move_toward(_flash_left, 0.0, delta * 4.0)   # a full press lasts about a quarter of a second
	_flash_right = move_toward(_flash_right, 0.0, delta * 4.0)
	# Gently pulse the zone the player should tap next.
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	var expected := _input.expected_side()
	# The flash decays from the tap strength (1 = progress, 0.6 = first tap, 0.2 = too slow): the disc sinks and
	# its groove catches warm light; the quiet pulse marks the side to tap next.
	_zone_left.set_press(_flash_left)
	_zone_right.set_press(_flash_right)
	_zone_left.set_glow(0.25 * pulse if expected == TapSide.Side.LEFT else 0.0)
	_zone_right.set_glow(0.25 * pulse if expected == TapSide.Side.RIGHT else 0.0)
	_complete_flash = move_toward(_complete_flash, 0.0, delta * 1.6)

func _draw_progress_bar() -> void:
	var size := _bar.size
	var track := Rect2(Vector2(0, size.y * 0.3), Vector2(size.x, size.y * 0.4))
	var fraction := clampf(_display_progress / 100.0, 0.0, 1.0)

	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Color(0.02, 0.03, 0.02, 0.8)
	track_style.border_color = GOLD_DIM
	track_style.set_border_width_all(2)
	track_style.set_corner_radius_all(int(track.size.y * 0.5))
	track_style.draw(_bar.get_canvas_item(), track)

	if fraction > 0.0:
		var fill_rect := Rect2(track.position + Vector2(3, 3), Vector2(maxf((track.size.x - 6.0) * fraction, track.size.y - 6.0), track.size.y - 6.0))
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = GOLD
		fill_style.set_corner_radius_all(int(fill_rect.size.y * 0.5))
		fill_style.draw(_bar.get_canvas_item(), fill_rect)
		# Soft highlight along the upper half of the fill, for a lit-metal look.
		var highlight := Rect2(fill_rect.position + Vector2(fill_rect.size.y * 0.4, 2), Vector2(maxf(fill_rect.size.x - fill_rect.size.y * 0.8, 0.0), fill_rect.size.y * 0.3))
		_bar.draw_rect(highlight, Color(1.0, 0.95, 0.75, 0.35))
		if _complete_flash > 0.0:  # the bar warms for a moment when the sword comes free
			fill_style.bg_color = Color(1.0, 0.9, 0.62, 0.55 * _complete_flash)
			fill_style.draw(_bar.get_canvas_item(), fill_rect)

	# Quarter marks.
	for quarter in [0.25, 0.5, 0.75]:
		var x: float = track.position.x + track.size.x * quarter
		_bar.draw_line(Vector2(x, track.position.y + track.size.y + 4), Vector2(x, track.position.y + track.size.y + 12), GOLD_DIM, 2.0)

	var text := "%d%%" % displayed_percent()
	_bar.draw_string(_font, Vector2(0, track.position.y - 14), "EXTRACTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, GOLD_DIM)
	_bar.draw_string(_font, Vector2(0, track.position.y - 14), text, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 30, GOLD_BRIGHT)

## What the label shows right now: the smoothed bar value as a whole number. The smoothing glides through
## every integer (0, 1, 2, 3 ...) instead of jumping with each tap.
func displayed_percent() -> int:
	return ProgressFormat.percent_for(100.0 if _progress >= 99.9999 else _display_progress)

## The extraction time as MM:SS.cc, for example 00:08.42.
static func format_extraction_time(seconds: float) -> String:
	var whole_minutes := int(seconds) / 60
	return "%02d:%05.2f" % [whole_minutes, seconds - whole_minutes * 60]

func _format_time(seconds: float) -> String:
	var whole_minutes := int(seconds) / 60
	var remainder := seconds - whole_minutes * 60
	return "%d:%05.2f" % [whole_minutes, remainder]

func _on_tap_accepted(side: TapSide.Side) -> void:
	# Zone feedback shows whether the tap counted: full flash = progress, medium = first tap (starts the
	# rhythm), faint = alternating but too slow (no progress).
	var strength := 1.0
	match _input.last_kind:
		TapKind.Kind.FIRST:
			strength = 0.6
		TapKind.Kind.TOO_SLOW:
			strength = 0.2
	if side == TapSide.Side.LEFT:
		_flash_left = strength
	else:
		_flash_right = strength
	if _hint_tween != null:
		_hint_tween.kill()
	if _input.last_kind == TapKind.Kind.TOO_SLOW:
		# Short, quiet reminder of the rule; fades by itself.
		_hint.text = "TAP FASTER"
		_hint.modulate.a = 0.9
		_hint_tween = create_tween()
		_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.8)
	elif _hint.modulate.a > 0.0:
		# Once the player has started, the instruction is no longer needed.
		_hint_tween = create_tween()
		_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.6)

func _on_level_changed(level: int) -> void:
	_level_label.text = "LEVEL %d" % level
	if _level_label.size.x > 0.0 and level > 1:
		# A brief settle so the new number is noticed (scale only; the layout box does not change).
		_level_label.pivot_offset = _level_label.size * 0.5
		_level_label.scale = Vector2(1.16, 1.16)
		create_tween().tween_property(_level_label, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_level_label.scale = Vector2.ONE

## The pause MENU replaces the "tap to resume" text while it is open.
func set_pause_overlay_suppressed(suppressed: bool) -> void:
	_pause_overlay_suppressed = suppressed
	_pause_overlay.visible = GameManager.state == GameManager.State.PAUSED and not suppressed

func _on_state_changed(state: GameManager.State) -> void:
	_pause_overlay.visible = state == GameManager.State.PAUSED and not _pause_overlay_suppressed
	# On failure the gameplay HUD steps aside so the failure screen is clean; it returns when a
	# new run starts (not on PAUSED, which can interrupt the failed state and return to it).
	if state == GameManager.State.FAILED:
		_set_gameplay_ui_visible(false)
	elif _ui_faded and state != GameManager.State.PAUSED:
		_set_gameplay_ui_visible(true)
	if state == GameManager.State.READY and _progress <= 0.0:
		if _hint_tween != null:
			_hint_tween.kill()
		_hint.text = HINT_TEXT
		_hint.modulate.a = 1.0

## Playtest aid: show which difficulty preset this build runs. Nothing is shown for "default".
func show_preset_label(preset_name: String) -> void:
	if preset_name == "default":
		return
	if _preset_label == null:
		_preset_label = _make_label("", 24, Color(0.93, 0.90, 0.82, 0.55))
		_preset_label.name = "PresetLabel"
		_preset_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_preset_label.offset_top = 322
		_preset_label.offset_bottom = 358
		add_child(_preset_label)
		_register_safe_area(_preset_label, true)
		_fade_group.append(_preset_label)
		refresh_safe_area()
	_preset_label.text = "PLAYTEST PRESET  ·  %s" % preset_name.replace("_", " ").to_upper()

func get_preset_label() -> Label:
	return _preset_label

func _register_safe_area(node: Control, is_top: bool) -> void:
	_safe_nodes.append([node, is_top, node.offset_top, node.offset_bottom])

## Keep clear of camera cut-outs (top) and the gesture bar (bottom). No-op where the OS reports none.
func refresh_safe_area() -> void:
	var insets := SafeArea.insets_in_viewport(get_viewport())
	for entry in _safe_nodes:
		var node: Control = entry[0]
		var shift: float = insets.y if entry[1] else -insets.w
		node.offset_top = entry[2] + shift
		node.offset_bottom = entry[3] + shift

func _set_gameplay_ui_visible(show_ui: bool) -> void:
	_ui_faded = not show_ui
	for item in _fade_group:
		var tween := create_tween()
		tween.tween_property(item, "modulate:a", 1.0 if show_ui else 0.0, 0.45 if not show_ui else 0.2)
