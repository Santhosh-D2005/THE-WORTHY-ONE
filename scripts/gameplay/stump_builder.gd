class_name StumpBuilder
extends Node3D
## Builds the procedural tree stump: furrowed irregular bark, buttress roots, ground roots,
## a freshly cut top face, moss and grass. Still procedural placeholder art (see README).
## To use a Blender model later: replace _build_trunk()/_build_ground_roots() with an instanced
## model; only STUMP_TOP_Y (height of the cut surface) must match the sword scene.

const STUMP_RADIUS_TOP := 1.25
const STUMP_RADIUS_BASE := 1.5
const STUMP_HEIGHT := 1.0
## World-space Y of the cut surface. The sword is positioned relative to this.
const STUMP_TOP_Y := STUMP_HEIGHT

const ROOT_COUNT := 6

var _rng := RandomNumberGenerator.new()
var _root_angles: Array[float] = []

func _ready() -> void:
	_rng.seed = 7  # fixed: the stump looks identical every run
	for i in ROOT_COUNT:
		_root_angles.append(TAU * (float(i) + _rng.randf_range(-0.25, 0.25)) / ROOT_COUNT + 0.4)
	var t := PerfProbe.begin()
	_build_trunk()
	PerfProbe.end("stump_trunk", t)
	t = PerfProbe.begin()
	_build_ground_roots()
	_build_moss()
	_build_grass()
	_build_contact_shadow()
	PerfProbe.end("stump_rest", t)

func _build_trunk() -> void:
	var shape := OrganicMesh.TrunkShape.new()
	shape.radius_top = STUMP_RADIUS_TOP
	shape.radius_base = STUMP_RADIUS_BASE
	shape.height = STUMP_HEIGHT
	shape.irregularity = 0.06
	shape.furrow_depth = 0.07
	shape.moss_amount = 0.55
	shape.seed_value = 12
	for angle in _root_angles:
		shape.add_root(angle, _rng.randf_range(0.16, 0.26), _rng.randf_range(0.25, 0.42))
	var meshes := AssetCache.meshes("stump_trunk_v1", 2, func() -> Array[ArrayMesh]: return OrganicMesh.build_trunk(shape, 112, 14))

	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	trunk.mesh = meshes[0]
	trunk.material_override = MaterialFactory.bark(Color.WHITE, 3, 2.1)  # 1.6: slightly stronger bark relief (was 1.6)
	add_child(trunk)

	var cut_face := MeshInstance3D.new()
	cut_face.name = "CutFace"
	cut_face.mesh = meshes[1]
	_cut_material = MaterialFactory.wood_top(STUMP_RADIUS_TOP)
	cut_face.material_override = _cut_material
	add_child(cut_face)

## MILESTONES 1.12/1.13: the cracks and the amber glow in them live entirely in the cut-face material (two shader uniforms): no
## geometry, no extra node, no light. `amount` 0..1 is how far the wood has split; `glow` 0..1 how bright the amber is.
var _cut_material: ShaderMaterial
var _crack_amount := 0.0
var _crack_glow := 0.0

func set_cracks(amount: float, glow: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	glow = clampf(glow, 0.0, 1.0)
	if _cut_material == null or (amount == _crack_amount and glow == _crack_glow):
		return
	_crack_amount = amount
	_crack_glow = glow
	_cut_material.set_shader_parameter("crack_amount", amount)
	_cut_material.set_shader_parameter("crack_glow", glow)

func crack_amount() -> float:
	return _crack_amount

func crack_glow() -> float:
	return _crack_glow

## Roots that leave the buttress flare and creep along (then under) the forest floor.
func _build_ground_roots() -> void:
	var bark := MaterialFactory.bark(Color(0.55, 0.53, 0.5), 5, 1.2)
	for i in _root_angles.size():
		var angle: float = _root_angles[i]
		var length := _rng.randf_range(1.2, 2.2)
		var wander := _rng.randf_range(-0.5, 0.5)
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		var steps := 12
		for s in steps + 1:
			var f := float(s) / float(steps)
			var swing := angle + sin(f * 3.0 + float(i)) * 0.18 * wander + f * wander * 0.35
			var distance := 1.15 + f * length
			var y := lerpf(0.2, -0.06, smoothstep(0.0, 1.0, f))
			points.append(Vector3(cos(swing) * distance, y, sin(swing) * distance))
			radii.append(lerpf(0.2, 0.03, pow(f, 0.7)))
		var root := MeshInstance3D.new()
		root.name = "GroundRoot%d" % i
		var seed_value := 40 + i
		root.mesh = AssetCache.mesh("stump_root_v1_%d" % i, func() -> ArrayMesh: return OrganicMesh.build_tube(points, radii, 9, seed_value))
		root.material_override = bark
		add_child(root)

func _build_moss() -> void:
	# Irregular overlapping cushions, biased to the damp base, the roots and a patch on the rim.
	var material := MaterialFactory.moss()
	var cushions := 26
	for i in cushions:
		var angle: float
		if i % 3 == 0:
			angle = _root_angles[_rng.randi() % _root_angles.size()] + _rng.randf_range(-0.3, 0.3)
		else:
			angle = _rng.randf_range(0.0, TAU)
		var on_rim := i % 7 == 0
		var radius := _rng.randf_range(1.0, 1.18) if on_rim else _rng.randf_range(1.2, 2.2)
		var y := STUMP_TOP_Y - 0.05 if on_rim else _rng.randf_range(0.0, 0.18)
		var mesh := SphereMesh.new()
		var size := _rng.randf_range(0.04, 0.10)
		mesh.radius = size
		mesh.height = size * 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		var instance := MeshInstance3D.new()
		instance.name = "Moss%d" % i
		instance.mesh = mesh
		instance.material_override = material
		instance.scale = Vector3(_rng.randf_range(1.3, 2.2), _rng.randf_range(0.35, 0.55), _rng.randf_range(1.3, 2.2))
		instance.rotation.y = _rng.randf() * TAU
		instance.position = Vector3(cos(angle) * radius, y, sin(angle) * radius)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)

func _build_grass() -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = _make_blade_mesh()
	var transforms: Array[Transform3D] = []
	var attempts := 0
	while transforms.size() < 260 and attempts < 2000:
		attempts += 1
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(1.7, 5.0)
		var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if point.z > 2.6:
			continue  # keep blades out of the lens / behind the tap zones
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf() * TAU, _rng.randf_range(-0.2, 0.2)))
		basis = basis.scaled(Vector3(1.0, _rng.randf_range(0.6, 1.35), 1.0))
		transforms.append(Transform3D(basis, point))
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Grass"
	instance.multimesh = multi
	instance.material_override = MaterialFactory.grass()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

## A bent, tapering blade (4 rows) with a dark-root to light-tip vertex gradient.
func _make_blade_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var rows := 4
	var blade_height := 0.34
	for row in rows + 1:
		var f := float(row) / float(rows)
		var half_width := lerpf(0.022, 0.002, pow(f, 1.2))
		var bend := f * f * 0.12
		var y := f * blade_height
		vertices.append(Vector3(-half_width, y, bend))
		vertices.append(Vector3(half_width, y, bend))
		normals.append(Vector3(0, 0.3, 1).normalized())
		normals.append(Vector3(0, 0.3, 1).normalized())
		var tone := lerpf(0.35, 1.0, f)
		var color := Color(0.30 * tone, 0.42 * tone, 0.14 * tone, 1.0)
		colors.append(color)
		colors.append(color)
	for row in rows:
		var a := row * 2
		indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Soft dark gradient under the stump: cheap ambient occlusion that grounds it in the floor.
func _build_contact_shadow() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.7))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(6.5, 6.5)
	var instance := MeshInstance3D.new()
	instance.name = "ContactShadow"
	instance.mesh = mesh
	instance.material_override = material
	instance.position.y = 0.015
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
