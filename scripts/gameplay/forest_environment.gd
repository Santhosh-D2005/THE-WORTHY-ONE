class_name ForestEnvironment
extends Node3D
## Builds lighting, sky, fog, terrain, background trunks and a fake canopy for dappled light.
## Exactly one real-time light (a directional sun) - mobile friendly.

const SUN_ROTATION_DEGREES := Vector3(-38.0, -32.0, 0.0)
const SUN_ENERGY := 2.1

var _sun: DirectionalLight3D
var _pulse_tween: Tween = null

func _ready() -> void:
	var quality := RenderQuality.current()
	quality.apply_shadow_globals()
	quality.apply_to_viewport(get_viewport())
	var t := PerfProbe.begin()
	_build_world_environment(quality)
	_build_sun(quality)
	PerfProbe.end("forest_env_light", t)
	t = PerfProbe.begin()
	_build_terrain()
	PerfProbe.end("forest_terrain", t)
	t = PerfProbe.begin()
	_build_background_trees()
	PerfProbe.end("forest_trees", t)
	t = PerfProbe.begin()
	_build_canopy_shadow_casters()
	PerfProbe.end("forest_canopy", t)
	t = PerfProbe.begin()
	if "--no-foliage" not in RenderQuality.launch_arguments():
		_build_undergrowth()
	PerfProbe.end("forest_undergrowth", t)

func _build_world_environment(quality: RenderQuality) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	# 1.9: a deeper blue-green canopy sky and a warm, sunlit haze at the horizon (natural, not saturated).
	sky_material.sky_top_color = Color(0.16, 0.38, 0.55)
	sky_material.sky_horizon_color = Color(0.98, 0.84, 0.52)
	sky_material.ground_horizon_color = Color(0.45, 0.52, 0.28)
	sky_material.ground_bottom_color = Color(0.06, 0.08, 0.05)
	sky_material.sun_angle_max = 18.0
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Soft, slightly cool fill from the sky; the warm sun provides the contrast.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.05  # 1.9: less flat fill, so shadows keep their depth
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	environment.adjustment_enabled = quality.adjustment_enabled
	environment.adjustment_contrast = 1.16  # 1.9: a touch more contrast; saturation is NOT raised (it stays natural)
	environment.adjustment_saturation = 1.22
	# Light atmospheric haze: depth without hiding the forest.
	environment.fog_enabled = quality.fog_enabled
	environment.fog_light_color = Color(0.70, 0.76, 0.50)  # 1.9: a warmer green haze: distant trunks fade into it
	environment.fog_density = 0.012
	var debug_args := RenderQuality.launch_arguments()  # debug builds only: --no-height-fog, --no-fog, --no-foliage (cost bisect)
	if "--no-height-fog" not in debug_args:
		environment.fog_height = 1.2      # 1.9: a knee-high ground mist that thickens toward the forest floor
		environment.fog_height_density = 0.035
	if "--no-fog" in debug_args:
		environment.fog_enabled = false
	environment.fog_sun_scatter = quality.fog_sun_scatter
	environment.fog_sky_affect = 0.45

	_environment = environment
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

func _build_sun(quality: RenderQuality) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.80, 0.48)  # low, warm, muted golden sunlight
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = quality.shadows_enabled
	sun.shadow_blur = quality.shadow_blur  # soft penumbra
	sun.directional_shadow_max_distance = 22.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL  # one cascade: cheapest
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.rotation_degrees = SUN_ROTATION_DEGREES
	add_child(sun)
	_sun = sun

## PERFORMANCE (measured on the Adreno 610, Milestone 1.9.2): changing the sun's light_energy while playing cost about 9 FPS
## (the phone sits at the 60 FPS cliff), so the "light" of the reward moment is now the tone-mapping EXPOSURE, a single uniform
## in the post pass. The look is the same: the whole clearing brightens or dims by a few percent.
var _environment: Environment
var _light_scale: float = 1.0:
	set(value):
		_light_scale = value
		if _environment != null:
			_environment.tonemap_exposure = value

## A restrained swell of the light when a sword comes free: +10 % (level 1) to +30 % (level 10+) for a moment, then back.
## No colour change, no bloom - just the clearing seeming to brighten.
func pulse_light(strength: float) -> void:
	if _environment == null:
		return
	strength = clampf(strength, 0.0, 1.0)
	if _pulse_tween != null:
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "_light_scale", 1.10 + 0.20 * strength, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(self, "_light_scale", 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## While the last part of the pull is under way the clearing dims by up to 6 % (0..1 = how tense the pull is). Does
## nothing while the release swell is running, and only touches the environment when the value really changed.
func set_tension(amount: float) -> void:
	if _environment == null:
		return
	if _pulse_tween != null and _pulse_tween.is_valid() and _pulse_tween.is_running():
		return
	var target := 1.0 - 0.06 * clampf(amount, 0.0, 1.0)
	if absf(target - _light_scale) > 0.002:
		_light_scale = target

## LEVEL 9999 ("the final sword"): a whole other world. A moving night sky (stars, aurora, a halo over the clearing), violet-gold mist, a cold
## golden sun, glowing highlights (the environment glow is on ONLY here), and the background trunks turn dark ebony with a gold rim.
## Everything it changes is remembered and put back exactly when it is switched off, so ordinary levels look as they always did.
const FINALE_SKY_SHADER := """
shader_type sky;
uniform vec3 top_color : source_color = vec3(0.02, 0.015, 0.10);
uniform vec3 mid_color : source_color = vec3(0.17, 0.05, 0.33);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.60, 0.20);
uniform vec3 aurora_a : source_color = vec3(0.20, 1.0, 0.72);
uniform vec3 aurora_b : source_color = vec3(0.95, 0.30, 0.85);

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int k = 0; k < 4; k++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; } return v; }

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = clamp(dir.y, -0.2, 1.0);
	vec3 col = mix(horizon_color, mid_color, smoothstep(0.0, 0.32, h));
	col = mix(col, top_color, smoothstep(0.22, 0.95, h));
	// stars: a hashed grid on the dome, each twinkling at its own pace
	vec2 uv = vec2(atan(dir.z, dir.x) * 1.2, dir.y * 2.4);
	vec2 cell = floor(uv * vec2(90.0, 48.0));
	float star = step(0.978, hash21(cell)) * (0.55 + 0.45 * sin(TIME * (1.5 + hash21(cell + 3.0) * 3.0) + hash21(cell) * 6.28));
	col += vec3(0.85, 0.9, 1.0) * star * smoothstep(0.12, 0.45, dir.y);
	// aurora: slow curtains of green and magenta
	float flow = TIME * 0.06;
	float band = fbm(vec2(dir.x * 2.6 + flow, dir.z * 2.6 - flow * 0.7) * 1.4);
	float curtain = smoothstep(0.38, 0.78, band) * smoothstep(0.10, 0.42, dir.y) * (1.0 - smoothstep(0.55, 0.95, dir.y));
	col += mix(aurora_a, aurora_b, fbm(dir.xz * 3.0 + TIME * 0.08)) * curtain * 0.95;
	// a great pulsing halo over the clearing
	float halo = pow(max(dot(dir, normalize(vec3(0.0, 0.50, -1.0))), 0.0), 38.0);
	col += vec3(1.0, 0.78, 0.40) * halo * (0.85 + 0.15 * sin(TIME * 1.3));
	COLOR = col;
}
"""

var _finale_on: bool = false
var _finale_saved: Dictionary = {}
var _finale_sky_material: ShaderMaterial = null
var _finale_bark: StandardMaterial3D = null
var _tree_materials: Array[Material] = []

func is_finale() -> bool:
	return _finale_on

func apply_finale(on: bool) -> void:
	if on == _finale_on or _environment == null:
		return
	_finale_on = on
	if on:
		_finale_saved = {
			"sky_material": _environment.sky.sky_material, "fog_light": _environment.fog_light_color, "fog_density": _environment.fog_density,
			"ambient": _environment.ambient_light_energy, "sat": _environment.adjustment_saturation, "con": _environment.adjustment_contrast,
			"glow": _environment.glow_enabled, "sun_color": _sun.light_color, "sun_energy": _sun.light_energy,
		}
		if _finale_sky_material == null:
			var shader := Shader.new()
			shader.code = FINALE_SKY_SHADER
			_finale_sky_material = ShaderMaterial.new()
			_finale_sky_material.shader = shader
			_finale_bark = MaterialFactory.bark(Color(0.09, 0.06, 0.15), 8, 2.2)
			_finale_bark.rim_enabled = true
			_finale_bark.rim = 0.45
			_finale_bark.rim_tint = 0.4
			_finale_bark.emission_enabled = true
			_finale_bark.emission = Color(0.9, 0.55, 0.15)
			_finale_bark.emission_energy_multiplier = 0.04
		_environment.sky.sky_material = _finale_sky_material
		_environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME  # the sky moves
		_environment.sky.radiance_size = Sky.RADIANCE_SIZE_32
		_environment.fog_light_color = Color(0.42, 0.26, 0.55)
		_environment.fog_density = 0.016
		_environment.ambient_light_energy = 0.75
		_environment.adjustment_saturation = 1.32
		_environment.adjustment_contrast = 1.2
		_environment.glow_enabled = true
		_environment.glow_intensity = 0.8
		_environment.glow_strength = 1.1
		_environment.glow_bloom = 0.12
		_environment.glow_hdr_threshold = 0.95
		_sun.light_color = Color(0.86, 0.80, 1.0)
		_sun.light_energy = 1.5
		_tree_materials.clear()
		for tree in _trees:
			_tree_materials.append(tree.material_override)
			tree.material_override = _finale_bark
	else:
		_environment.sky.sky_material = _finale_saved["sky_material"]
		_environment.sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
		_environment.fog_light_color = _finale_saved["fog_light"]
		_environment.fog_density = _finale_saved["fog_density"]
		_environment.ambient_light_energy = _finale_saved["ambient"]
		_environment.adjustment_saturation = _finale_saved["sat"]
		_environment.adjustment_contrast = _finale_saved["con"]
		_environment.glow_enabled = _finale_saved["glow"]
		_sun.light_color = _finale_saved["sun_color"]
		_sun.light_energy = _finale_saved["sun_energy"]
		for i in _trees.size():
			if i < _tree_materials.size():
				_trees[i].material_override = _tree_materials[i]

## The effective brightness of the sun (SUN_ENERGY times the current light scale).
func sun_energy() -> float:
	return SUN_ENERGY * _light_scale if _environment != null else 0.0

func _build_terrain() -> void:
	var instance := MeshInstance3D.new()
	instance.name = "Ground"
	instance.mesh = AssetCache.mesh("terrain_v1_90_56_45_06_5", func() -> ArrayMesh: return OrganicMesh.build_terrain(90.0, 56, 4.5, 0.6, 5))
	instance.material_override = MaterialFactory.ground()
	add_child(instance)

func _build_background_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	# 1.9: natural bark tones instead of two near-identical greys: warm brown, grey brown, mossy green-brown and dark wet bark
	# (the same two noise textures as before, so no extra texture memory). Nearer trunks use the darker tones.
	var materials: Array[StandardMaterial3D] = [
		MaterialFactory.bark(Color(0.72, 0.58, 0.44), 8, 1.0),
		MaterialFactory.bark(Color(0.44, 0.40, 0.34), 9, 1.0),
		MaterialFactory.bark(Color(0.40, 0.52, 0.30), 8, 1.0),
		MaterialFactory.bark(Color(0.54, 0.47, 0.39), 9, 1.0),
		MaterialFactory.bark(Color(0.30, 0.28, 0.25), 8, 1.0),
	]
	var near_choices := [1, 2, 4]
	var far_choices := [0, 3, 1, 2]
	var count := 46
	for i in count:
		var near_layer := i < 18
		var x := rng.randf_range(-9.0, 9.0) if near_layer else rng.randf_range(-24.0, 24.0)
		var z := -rng.randf_range(5.5, 11.0) if near_layer else -rng.randf_range(12.0, 40.0)
		if near_layer and absf(x) < 2.6:
			x += signf(x + 0.01) * 2.6  # keep the view behind the stump open
		var trunk_radius := rng.randf_range(0.3, 0.7) if near_layer else rng.randf_range(0.4, 1.0)

		var shape := OrganicMesh.TrunkShape.new()
		shape.radius_base = trunk_radius * 1.12
		shape.radius_top = trunk_radius * 0.78
		shape.height = 30.0
		shape.below_ground = 0.5
		shape.irregularity = 0.09
		shape.furrow_depth = trunk_radius * 0.14
		shape.furrow_frequency = 1.8
		shape.moss_amount = 0.35
		shape.rim_inset = 0.0
		shape.lean = Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03))
		shape.seed_value = 100 + i
		for r in rng.randi_range(2, 4):
			shape.add_root(rng.randf() * TAU, rng.randf_range(0.2, 0.3), trunk_radius * rng.randf_range(0.35, 0.7))
		var segments := 28 if near_layer else 18
		var meshes := AssetCache.meshes("bgtree_v1_%d" % i, 1, func() -> Array[ArrayMesh]: return OrganicMesh.build_trunk(shape, segments, 9, false))

		var instance := MeshInstance3D.new()
		instance.name = "BackgroundTree%d" % i
		instance.mesh = meshes[0]
		instance.material_override = materials[near_choices[i % 3] if near_layer else far_choices[i % 4]]
		instance.position = Vector3(x, 0.0, z)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_trees.append(instance)
		_tree_homes.append(instance.position)

## MILESTONE 1.11, inward forest compression (Option B): as the pull gets harder the background trunks drift toward the stump, in x
## and z, by up to COMPRESSION (7 %) of their distance. Each trunk is only TRANSLATED (never scaled or bent), so no tree deforms; the
## frame simply seems to close in. The sword and the stump do not move. It is a pure function of `amount` (0..1), so it is reversible
## and exactly neutral at 0. Cost: 46 position writes, and only on frames where the amount changed.
const COMPRESSION := 0.07
var _trees: Array[MeshInstance3D] = []
var _tree_homes: Array[Vector3] = []
var _compression_shown := 0.0

func set_compression(amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if amount == _compression_shown:
		return
	_compression_shown = amount
	var factor := 1.0 - COMPRESSION * amount
	for i in _trees.size():
		var home := _tree_homes[i]
		_trees[i].position = Vector3(home.x * factor, home.y, home.z * factor)

func compression() -> float:
	return _compression_shown

## Fern clumps at the sides of the clearing (two multimeshes, one draw call each, no shadows). They frame the stump, give the
## foreground depth and keep the middle of the picture and the area behind the stump open.
var _foliage_material: ShaderMaterial = null

func _build_undergrowth() -> void:
	_foliage_material = MaterialFactory.fern()
	var near: Array[Rect2] = [Rect2(-5.0, 0.2, 2.6, 2.4), Rect2(2.4, 0.2, 2.6, 2.4), Rect2(-6.5, -2.0, 3.2, 2.6), Rect2(3.3, -2.0, 3.2, 2.6)]
	var far: Array[Rect2] = [Rect2(-3.2, -4.5, 1.5, 2.2), Rect2(1.7, -4.5, 1.5, 2.2), Rect2(-8.0, -7.0, 5.0, 4.0), Rect2(3.0, -7.0, 5.0, 4.0)]
	# Far clumps use a hazier tint, because the cheap foliage shader has no per-pixel fog.
	var far_material := _foliage_material.duplicate() as ShaderMaterial
	far_material.set_shader_parameter("tint", Vector3(0.66, 0.76, 0.62))
	for entry in [["FernsNear", near, 14, 71, 0.5, 0.78, _foliage_material], ["FernsFar", far, 10, 72, 0.8, 1.3, far_material]]:
		var instance := MultiMeshInstance3D.new()
		instance.name = entry[0]
		instance.multimesh = FoliageBuilder.make_fern_field(entry[1], entry[2], entry[3], entry[4], entry[5])
		instance.material_override = entry[6]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)

## The undergrowth answers the moment a sword comes free: a brief, soft gust (the foliage leans and settles).
func gust(strength: float) -> void:
	if _foliage_material == null:
		return
	var tween := create_tween()
	_foliage_material.set_shader_parameter("gust", 0.0)
	tween.tween_property(_foliage_material, "shader_parameter/gust", 0.6 + 0.4 * clampf(strength, 0.0, 1.0), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_foliage_material, "shader_parameter/gust", 0.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Invisible leaf clusters overhead that only cast shadow. Each is placed along the sun ray so
## its shadow lands at a chosen spot on the clearing, giving dappled light without any
## extra lights or volumetrics.
func _build_canopy_shadow_casters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var sun_direction := (Basis.from_euler(Vector3(
		deg_to_rad(SUN_ROTATION_DEGREES.x), deg_to_rad(SUN_ROTATION_DEGREES.y), 0.0)) * Vector3.FORWARD).normalized()
	var canopy_height := 9.0
	var material := StandardMaterial3D.new()
	for i in 22:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(3.0, 9.0)
		var target := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		if target.z > 3.5:
			continue
		var travel := canopy_height / -sun_direction.y
		var mesh := SphereMesh.new()
		var size := rng.randf_range(0.5, 1.5)
		mesh.radius = size
		mesh.height = size * 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		var instance := MeshInstance3D.new()
		instance.name = "CanopyShadow%d" % i
		instance.mesh = mesh
		instance.material_override = material
		instance.position = target - sun_direction * travel
		instance.scale = Vector3(rng.randf_range(0.9, 1.6), 0.5, rng.randf_range(0.9, 1.6))
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(instance)
