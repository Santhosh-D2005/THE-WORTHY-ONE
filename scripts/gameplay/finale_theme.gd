class_name FinaleTheme
extends Node3D
## LEVEL 9999 - "the final sword". Switches the whole scene to its other look: the forest (moving night sky, violet-gold mist, glow), the
## sword (gold, gems, runes, halo, aura: see SwordController.apply_finale) and the STUMP, which becomes a dark ebony altar with a gold rim,
## a ring of floating runes, crystal shards and a glowing rune circle on the ground, with golden embers drifting up and a warm light.
## Nothing here exists until level 9999 is reached (it is built the first time) and everything is undone when the theme is switched off.
## It never touches gameplay: no input, no timing, no difficulty.

const RUNE_COUNT := 12
const SHARD_COUNT := 7
const RUNE_HEIGHT := 3.7

const GROUND_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec3 color : source_color = vec3(1.0, 0.70, 0.25);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float line = 0.010;
	float rings = smoothstep(line, 0.0, abs(r - 0.94)) + smoothstep(line, 0.0, abs(r - 0.66)) + smoothstep(line, 0.0, abs(r - 0.40));
	float ticks = step(0.5, fract((a + TIME * 0.10) / 6.2832 * 56.0)) * smoothstep(0.035, 0.0, abs(r - 0.80));
	float star = smoothstep(0.012, 0.0, abs(abs(sin(a * 4.0 + TIME * 0.20)) * r - 0.18)) * step(0.40, r) * step(r, 0.94);
	float pulse = 0.78 + 0.22 * sin(TIME * 1.6 - r * 8.0);
	float v = clamp(rings + ticks * 0.8 + star * 0.9, 0.0, 1.0) * pulse;
	ALBEDO = color * v * 1.5;
	ALPHA = v * smoothstep(1.0, 0.92, r);
}
"""

var _forest: ForestEnvironment
var _stump: StumpBuilder
var _sword: SwordController
var _active: bool = false
var _built: bool = false
var _decor: Node3D
var _runes: Node3D
var _embers: GPUParticles3D
var _light: OmniLight3D
var _saved: Dictionary = {}
var _time: float = 0.0

func setup(forest: ForestEnvironment, stump: StumpBuilder, sword: SwordController) -> void:
	_forest = forest
	_stump = stump
	_sword = sword
	set_process(false)

func is_active() -> bool:
	return _active

func apply(on: bool) -> void:
	if on == _active:
		return
	_active = on
	if on and not _built:
		_build()
	if _forest != null:
		_forest.apply_finale(on)
	if _sword != null:
		_sword.apply_finale(on)
	_restyle_stump(on)
	if _built:
		_decor.visible = on
		_embers.emitting = on
		_light.visible = on
	set_process(on)

func _process(delta: float) -> void:
	_time += delta
	_runes.rotation.y += delta * 0.28
	for i in _runes.get_child_count():
		var rune := _runes.get_child(i) as Node3D
		rune.position.y = RUNE_HEIGHT + sin(_time * 1.1 + float(i) * 0.9) * 0.12
	_light.light_energy = 2.0 + sin(_time * 1.7) * 0.35

# ---- the stump ---------------------------------------------------------------------------------

func _restyle_stump(on: bool) -> void:
	if _stump == null:
		return
	if on:
		var ebony := MaterialFactory.bark(Color(0.07, 0.045, 0.11), 3, 2.6)
		ebony.rim_enabled = true
		ebony.rim = 0.55
		ebony.rim_tint = 0.5
		ebony.metallic = 0.2
		ebony.emission_enabled = true
		ebony.emission = Color(1.0, 0.55, 0.12)
		ebony.emission_energy_multiplier = 0.05
		for child in _stump.get_children():
			var part := child as MeshInstance3D
			if part == null:
				continue
			var kind := str(part.name).rstrip("0123456789")
			if kind == "Moss" or kind == "Grass":
				_saved[part] = {"visible": part.visible}
				part.visible = false
			elif kind == "Trunk" or kind == "GroundRoot":
				_saved[part] = {"material": part.material_override}
				part.material_override = ebony
		_stump.set_cracks(1.0, 1.0)
	else:
		for part: Node in _saved:
			var info: Dictionary = _saved[part]
			if info.has("visible"):
				(part as MeshInstance3D).visible = info["visible"]
			if info.has("material"):
				(part as MeshInstance3D).material_override = info["material"]
		_saved.clear()

func _gold(energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.78, 0.30)
	material.metallic = 1.0
	material.roughness = 0.22
	material.emission_enabled = true
	material.emission = Color(1.0, 0.62, 0.15)
	material.emission_energy_multiplier = energy
	return material

func _glow(color: Color, energy: float, alpha: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _piece(parent: Node3D, node_name: String, mesh: Mesh, position_value: Vector3, material: Material, rotation_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position_value
	instance.rotation = rotation_value
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _build() -> void:
	_built = true
	_decor = Node3D.new()
	_decor.name = "FinaleDecor"
	add_child(_decor)
	var top_y := StumpBuilder.STUMP_TOP_Y
	# Gold rims: round the cut face and round the foot of the stump.
	var rim := TorusMesh.new()
	rim.inner_radius = 1.20
	rim.outer_radius = 1.33
	rim.rings = 64
	rim.ring_segments = 10
	_piece(_decor, "RimTop", rim, Vector3(0.0, top_y + 0.01, 0.0), _gold(0.8))
	var foot := TorusMesh.new()
	foot.inner_radius = 1.46
	foot.outer_radius = 1.60
	foot.rings = 64
	foot.ring_segments = 10
	_piece(_decor, "RimFoot", foot, Vector3(0.0, 0.10, 0.0), _gold(0.6))
	# An inner ring of small glowing studs on the cut face.
	var stud := SphereMesh.new()
	stud.radius = 0.035
	stud.height = 0.07
	stud.radial_segments = 8
	stud.rings = 4
	for k in 24:
		var angle := TAU * float(k) / 24.0
		_piece(_decor, "Stud", stud, Vector3(cos(angle) * 1.12, top_y + 0.02, sin(angle) * 1.12), _glow(Color(1.0, 0.8, 0.4), 3.0))
	# The glowing rune circle on the ground.
	var disc := CylinderMesh.new()
	disc.top_radius = 3.5
	disc.bottom_radius = 3.5
	disc.height = 0.01
	disc.radial_segments = 64
	disc.rings = 1
	var shader := Shader.new()
	shader.code = GROUND_SHADER
	var ground := ShaderMaterial.new()
	ground.shader = shader
	_piece(_decor, "RuneCircle", disc, Vector3(0.0, 0.035, 0.0), ground)
	# Crystal shards in a half-ring BEHIND the altar (never between the camera and the sword), tall at the back, shorter at the sides.
	var shard_material := _glow(Color(0.55, 0.75, 1.0), 1.8, 0.8)
	for s in SHARD_COUNT:
		var spread := (float(s) / float(SHARD_COUNT - 1)) * 2.0 - 1.0   # -1 .. 1 across the back
		var angle := PI * 1.5 + spread * 1.15                              # round the far side (negative z)
		var shard := CylinderMesh.new()
		shard.top_radius = 0.0
		shard.bottom_radius = 0.17
		shard.height = 1.5 + (1.0 - absf(spread)) * 1.3
		shard.radial_segments = 6
		shard.rings = 1
		var radius := 3.3
		var piece := _piece(_decor, "Shard", shard, Vector3(cos(angle) * radius, shard.height * 0.5, sin(angle) * radius), shard_material)
		piece.rotation = Vector3(-sin(angle) * 0.10, angle, cos(angle) * 0.10)
	# A crown of small runes turning slowly high above the sword.
	_runes = Node3D.new()
	_runes.name = "Runes"
	_runes.position = Vector3(0.0, 0.0, -0.3)
	_decor.add_child(_runes)
	for i in RUNE_COUNT:
		var angle := TAU * float(i) / float(RUNE_COUNT)
		var rune := BoxMesh.new()
		rune.size = Vector3(0.10, 0.22 + float(i % 3) * 0.05, 0.03)
		var instance := _piece(_runes, "Rune%d" % i, rune, Vector3(cos(angle) * 1.45, RUNE_HEIGHT, sin(angle) * 1.45), _glow(Color(1.0, 0.80, 0.40), 3.2))
		instance.rotation.y = -angle + PI * 0.5
	# Golden embers drifting up through the clearing.
	_embers = GPUParticles3D.new()
	_embers.name = "Embers"
	_embers.amount = 150
	_embers.lifetime = 7.0
	_embers.preprocess = 6.0
	_embers.visibility_aabb = AABB(Vector3(-9.0, -1.0, -9.0), Vector3(18.0, 14.0, 18.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 5.5
	process.emission_ring_inner_radius = 0.6
	process.emission_ring_height = 0.2
	process.direction = Vector3.UP
	process.spread = 14.0
	process.initial_velocity_min = 0.35
	process.initial_velocity_max = 0.95
	process.gravity = Vector3(0.0, 0.12, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.8, 0.4, 0.0))
	fade.add_point(0.15, Color(1.0, 0.82, 0.45, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 0.55, 0.2, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	_embers.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.075, 0.075)
	var ember_material := StandardMaterial3D.new()
	ember_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ember_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ember_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_material.vertex_color_use_as_albedo = true
	ember_material.albedo_color = Color(1.0, 0.8, 0.4)
	var dot := Gradient.new()                       # a soft round spark, not a square
	dot.set_color(0, Color(1, 1, 1, 1))
	dot.set_color(1, Color(1, 1, 1, 0))
	var dot_texture := GradientTexture2D.new()
	dot_texture.gradient = dot
	dot_texture.fill = GradientTexture2D.FILL_RADIAL
	dot_texture.fill_from = Vector2(0.5, 0.5)
	dot_texture.fill_to = Vector2(0.5, 0.0)
	dot_texture.width = 32
	dot_texture.height = 32
	ember_material.albedo_texture = dot_texture
	quad.material = ember_material
	_embers.draw_pass_1 = quad
	_embers.emitting = false
	add_child(_embers)
	# A warm light over the altar.
	_light = OmniLight3D.new()
	_light.name = "FinaleLight"
	_light.position = Vector3(0.0, 2.6, 0.8)
	_light.light_color = Color(1.0, 0.80, 0.45)
	_light.light_energy = 2.0
	_light.omni_range = 8.0
	_light.shadow_enabled = false
	add_child(_light)
	_decor.visible = false
	_light.visible = false
