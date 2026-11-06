class_name UiStyle
extends RefCounted
## Milestone 1.16: the one place that defines how every screen of THE WORTHY ONE looks: palette, typography scale, button states, panels,
## dividers, scrims and screen transitions. The HUD, main menu, pause menu and failure screen all build from these helpers, so a change here
## changes the whole game consistently. Pure static helpers: no state, no nodes of its own, no dependencies beyond the Cinzel font.
##
## Palette: deep forest green and near-black grounds, muted parchment text, restrained amber-gold accents (GOLD for borders and lines, GOLD_BRIGHT for
## headings and the primary action). Nothing neon, no outlines, one soft drop shadow on text.

# ---- Palette ---------------------------------------------------------------------------------
const GOLD := Color(0.78, 0.65, 0.36)
const GOLD_DIM := Color(0.78, 0.65, 0.36, 0.7)
const GOLD_BRIGHT := Color(0.95, 0.84, 0.55)
const PARCHMENT := Color(0.93, 0.90, 0.82)
const PARCHMENT_DIM := Color(0.93, 0.90, 0.82, 0.72)
const CAPTION := Color(0.86, 0.74, 0.46, 0.95)
const PANEL := Color(0.03, 0.04, 0.03, 0.62)
const PANEL_DEEP := Color(0.02, 0.04, 0.03, 0.78)
const NEAR_BLACK := Color(0.0, 0.01, 0.0)
const FONT_PATH := "res://assets/fonts/Cinzel.ttf"

# ---- Type scale (base-viewport px; the viewport is 1080 wide) --------------------------------
const SIZE_DISPLAY := 112   # main-menu title
const SIZE_HEADING := 72    # PAUSED / THE SWORD REMAINS
const SIZE_SUBHEADING := 40
const SIZE_BODY := 32
const SIZE_CAPTION := 27
const SIZE_BUTTON_PRIMARY := 52
const SIZE_BUTTON := 38

# ---- Spacing and sizes -----------------------------------------------------------------------
const MARGIN := 64.0
const BUTTON_HEIGHT_PRIMARY := 150.0
const BUTTON_HEIGHT := 120.0       # 48 dp on the 720 px wide target phone (about 270 ppi)
const CORNER_RADIUS := 30
const DIVIDER_HALF_WIDTH := 170.0

static var _font: FontVariation = null

## The shared Cinzel font with slightly open letter spacing (a fallback font keeps the UI working if the file is missing).
static func font() -> FontVariation:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
		_font.spacing_glyph = 3
	return _font

static func label(text: String, font_size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = text
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.add_theme_font_override("font", font())
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.88))
	node.add_theme_constant_override("shadow_offset_x", 2)
	node.add_theme_constant_override("shadow_offset_y", 3)
	return node

static func button_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(CORNER_RADIUS)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 16
	return style

## One button look for the whole game. Primary: amber border, bright amber text. Secondary: dim border, parchment text.
static func button(text: String, primary: bool, node_name: String, font_size: int = -1) -> Button:
	var node := Button.new()
	node.name = node_name
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.custom_minimum_size = Vector2(0, BUTTON_HEIGHT_PRIMARY if primary else BUTTON_HEIGHT)
	node.add_theme_font_override("font", font())
	node.add_theme_font_size_override("font_size", font_size if font_size > 0 else (SIZE_BUTTON_PRIMARY if primary else SIZE_BUTTON))
	node.add_theme_color_override("font_color", GOLD_BRIGHT if primary else PARCHMENT)
	node.add_theme_color_override("font_hover_color", Color.WHITE)
	node.add_theme_color_override("font_pressed_color", Color.WHITE)
	node.add_theme_color_override("font_disabled_color", Color(0.93, 0.90, 0.82, 0.6))
	node.add_theme_stylebox_override("normal", button_style(Color(0.03, 0.06, 0.04, 0.66) if primary else Color(0.03, 0.04, 0.03, 0.5), GOLD if primary else GOLD_DIM, 3 if primary else 2))
	node.add_theme_stylebox_override("hover", button_style(Color(0.16, 0.13, 0.07, 0.74), GOLD_BRIGHT, 3))
	node.add_theme_stylebox_override("pressed", button_style(Color(0.30, 0.24, 0.11, 0.85), GOLD_BRIGHT, 3))
	node.add_theme_stylebox_override("disabled", button_style(Color(0.03, 0.04, 0.03, 0.45), Color(0.78, 0.65, 0.36, 0.35), 2))
	return node

## A quiet translucent panel with a thin amber hairline (behind statistics and cards).
static func panel_style(fill: Color = PANEL_DEEP, border: Color = Color(0.78, 0.65, 0.36, 0.38)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 12
	return style

static func panel(node_name: String) -> Panel:
	var node := Panel.new()
	node.name = node_name
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel", panel_style())
	return node

## The thin amber line under a heading.
static func divider(node_name: String = "Divider") -> ColorRect:
	var node := ColorRect.new()
	node.name = node_name
	node.color = GOLD_DIM
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.anchor_left = 0.5
	node.anchor_right = 0.5
	node.offset_left = -DIVIDER_HALF_WIDTH
	node.offset_right = DIVIDER_HALF_WIDTH
	return node

## A dark vertical gradient strip (top: strongest at the top edge; bottom: strongest at the bottom edge). One tiny texture.
static func scrim(node_name: String, at_top: bool, height: float, strength: float) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0.01, 0, strength if at_top else 0.0))
	gradient.set_color(1, Color(0, 0.01, 0, 0.0 if at_top else strength))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 64
	var rect := TextureRect.new()
	rect.name = node_name
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_left = 0.0
	rect.anchor_right = 1.0
	if at_top:
		rect.anchor_top = 0.0
		rect.anchor_bottom = 0.0
		rect.offset_bottom = height
	else:
		rect.anchor_top = 1.0
		rect.anchor_bottom = 1.0
		rect.offset_top = -height
	return rect

## A soft dark vignette over the whole screen: the centre stays clear, the edges darken.
static func vignette(node_name: String = "Vignette", strength: float = 0.8) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.0))
	gradient.set_color(1, Color(0, 0, 0, strength))
	gradient.set_offset(0, 0.35)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 1.0)
	texture.width = 256
	texture.height = 256
	var rect := TextureRect.new()
	rect.name = node_name
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect

## The shared screen transition: a short sine ease of a node's opacity.
static func fade(owner_node: Node, target: CanvasItem, to_alpha: float, seconds: float) -> Tween:
	var tween := owner_node.create_tween()
	tween.tween_property(target, "modulate:a", to_alpha, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if to_alpha > target.modulate.a else Tween.EASE_IN)
	return tween
