class_name MaterialFactory
extends RefCounted
## Procedural PLACEHOLDER materials built from native Godot noise textures.
## When real Blender/PBR assets exist, replace the calls to these functions (or the
## materials they return) - no gameplay script depends on how materials are made.

static var _shared_noise: Texture2D

## Generic grey noise (0..1), shared by shaders.
static func shared_noise() -> Texture2D:
	if _shared_noise == null:
		_shared_noise = _noise_texture(0.02, 11, Color.BLACK, Color.WHITE, false, 1.0, 256)
	return _shared_noise

## Served from the baked copy (AssetCache) when one exists; the key spells out every input.
static func _noise_texture(frequency: float, seed_value: int, dark: Color, light: Color,
		normal_map: bool = false, bump: float = 1.0, size: int = 512) -> Texture2D:
	var key := "noise_v1_f%s_s%d_%s_b%s_%d" % [str(frequency), seed_value,
		"normal" if normal_map else dark.to_html() + light.to_html(), str(bump), size]
	key = key.replace(".", "p")
	return AssetCache.texture(key, func() -> Texture2D: return _build_noise_texture(
		frequency, seed_value, dark, light, normal_map, bump, size))

static func _build_noise_texture(frequency: float, seed_value: int, dark: Color, light: Color,
		normal_map: bool, bump: float, size: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.seed = seed_value
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, dark)
	ramp.set_color(1, light)
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = size
	texture.height = size
	texture.seamless = true
	texture.as_normal_map = normal_map
	texture.bump_strength = bump
	if not normal_map:
		texture.color_ramp = ramp
	return texture

## Bark. Expects meshes with vertex colors (furrow shading / moss) and tangents.
static func bark(tint: Color = Color.WHITE, seed_value: int = 3, normal_strength: float = 1.6) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.vertex_color_use_as_albedo = true
	# 1.9: a wider tonal range (deep furrows, lit ridges) so the bark reads as relief instead of a flat tan surface.
	material.albedo_texture = _noise_texture(0.03, seed_value, Color(0.20, 0.15, 0.11), Color(0.50, 0.42, 0.34), false, 1.0, 512)
	if RenderQuality.current().bark_normal_maps:
		material.normal_enabled = true
		material.normal_texture = _noise_texture(0.03, seed_value, Color.BLACK, Color.WHITE, true, 18.0, 512)
		material.normal_scale = normal_strength
	material.roughness = 0.94
	# Strongly stretched vertically so detail reads as long bark fibres.
	material.uv1_scale = Vector3(14.0, 0.45, 1.0)
	return material

static func wood_top(radius: float = 1.25) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/wood_top.gdshader")
	material.set_shader_parameter("noise_tex", shared_noise())
	material.set_shader_parameter("stump_radius", radius)
	return material

static func ground() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/forest_floor.gdshader")
	material.set_shader_parameter("noise_tex", shared_noise())
	return material

static func moss() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _noise_texture(0.05, 31, Color(0.08, 0.15, 0.05), Color(0.22, 0.34, 0.12), false, 1.0, 256)
	material.normal_enabled = true
	material.normal_texture = _noise_texture(0.08, 32, Color.BLACK, Color.WHITE, true, 8.0, 256)
	material.roughness = 1.0
	material.uv1_scale = Vector3(2, 2, 1)
	return material

## Grass: vertex colors give a dark root to light tip gradient. Double sided.
static func grass() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.85, 0.95, 0.7)
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP  # soft light wrap reads as translucency
	return material

static func steel() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# 1.9: a cooler, more metallic steel. It reflects the warm haze at the horizon and the dark green of the forest, with a
	# crisp highlight along each bevel; the lower roughness keeps the sun glint tight (no glow, no bloom).
	material.albedo_color = Color(0.88, 0.91, 0.94)
	material.metallic = 0.70
	material.metallic_specular = 0.9
	material.roughness = 0.24
	return material

## Fern fronds and low leaves: vertex colours give the dark-root to light-tip gradient, a gentle wind sway (and a stronger
## one when a sword is freed) is done in the vertex shader. One shared material for all foliage.
static func fern() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/fern.gdshader")
	return material

static func dark_steel() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.30, 0.32, 0.34)  # 1.6: darker fuller / grip bands give the blade more depth
	material.metallic = 0.9
	material.roughness = 0.5
	return material

static func aged_gold() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.80, 0.60, 0.26)
	material.metallic = 0.9
	material.roughness = 0.34
	return material

static func leather() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.13, 0.09, 0.07)
	material.roughness = 0.82
	return material
