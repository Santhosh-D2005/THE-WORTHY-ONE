class_name ForestDisc
extends Control
## A round, text-free tap target that looks like a slice of the forest (see shaders/control_disc.gdshader).
## It is only a visual: it ignores the mouse, and gameplay taps are read from the whole screen half by
## InputController, so its size never limits where the player can tap.
##
## Performance (measured on the phone, Milestone 1.7): running the wood shader live every frame cost about 5-9 FPS
## on the Adreno 610, which sits right at the 60 FPS cliff. The shader is therefore rendered ONCE into a small
## texture (a SubViewport that updates a single time) and the disc afterwards is one textured quad.
##
## set_press() is the pressed animation (the disc shrinks a few percent and darkens); set_glow() is the quiet warm
## ring in the groove that marks the side to tap next. Both only touch cheap properties (scale, modulate, one arc).

const SHADER_PATH := "res://shaders/control_disc.gdshader"
const PRESS_SCALE := 0.06    ## the disc shrinks by this fraction at full press
const PRESS_DARKEN := 0.22   ## the face is this much darker at full press
const BAKE_SIZE := 256       ## pixels of the pre-rendered texture
const GROOVE_RADIUS := 0.735 ## groove radius as a fraction of the disc radius (matches the shader)
const BAKE_GAMMA := 1.3     ## tone match to the live shader (a viewport texture is encoded slightly differently)
const WARM := Color(0.95, 0.78, 0.45)

var _seed: Vector2 = Vector2.ZERO
var _face: TextureRect
var _ring: Control
var _press: float = -1.0
var _glow: float = -1.0
var _ring_alpha: float = 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(func() -> void:
		pivot_offset = size * 0.5
		if _ring != null:
			_ring.queue_redraw())

## `seed_offset` differs per disc so the two look like two different cut slices.
func configure(seed_offset: Vector2) -> void:
	_seed = seed_offset

func _ready() -> void:
	var bake := SubViewport.new()
	bake.size = Vector2i(BAKE_SIZE, BAKE_SIZE)
	bake.transparent_bg = true
	bake.disable_3d = true
	bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	bake.gui_disable_input = true
	var paint := ColorRect.new()
	paint.color = Color.WHITE
	paint.size = Vector2(BAKE_SIZE, BAKE_SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	mat.set_shader_parameter("noise_tex", MaterialFactory.shared_noise())
	mat.set_shader_parameter("seed_offset", _seed)
	mat.set_shader_parameter("out_gamma", BAKE_GAMMA)
	paint.material = mat
	bake.add_child(paint)
	add_child(bake)

	_face = TextureRect.new()
	_face.texture = bake.get_texture()
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_SCALE
	_face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_face)

	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.draw.connect(_draw_ring)
	_ring.visible = false
	add_child(_ring)

func _draw_ring() -> void:
	var half := _ring.size.x * 0.5
	_ring.draw_arc(_ring.size * 0.5, half * GROOVE_RADIUS, 0.0, TAU, 72, Color(WARM, _ring_alpha), maxf(half * 0.045, 2.0), true)

func set_press(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if absf(value - _press) < 0.004:
		return
	_press = value
	var s := 1.0 - PRESS_SCALE * value
	scale = Vector2(s, s)
	var d := 1.0 - PRESS_DARKEN * value
	if _face != null:
		_face.modulate = Color(d, d, d, 1.0)
	_update_ring()

func set_glow(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if absf(value - _glow) < 0.004:
		return
	_glow = value
	_update_ring()

func _update_ring() -> void:
	if _ring == null:
		return
	var rim := clampf(maxf(_press, 0.0) * 0.55 + maxf(_glow, 0.0), 0.0, 1.0)
	_ring_alpha = rim * 0.75
	_ring.visible = _ring_alpha > 0.01
	if _ring.visible:
		_ring.queue_redraw()

func press_amount() -> float:
	return maxf(_press, 0.0)
