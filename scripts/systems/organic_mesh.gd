class_name OrganicMesh
extends RefCounted
## Procedural organic geometry: irregular tree trunks (furrowed bark, buttress roots, cut top face),
## ground-hugging root tubes and gently undulating terrain.
## All of it is generated at load time from a seed, so there are no binary assets to ship.
## It is still PROCEDURAL placeholder art - good silhouettes and lighting response, not a
## substitute for sculpted / scanned assets.

## Describes one trunk. Radius varies by angle and height so no two stumps look the same.
class TrunkShape:
	var radius_top: float = 1.25
	var radius_base: float = 1.5
	var height: float = 1.0
	var below_ground: float = 0.15
	var irregularity: float = 0.07      ## +/- fraction of radius
	var furrow_depth: float = 0.05      ## bark groove depth (world units)
	var furrow_frequency: float = 2.2   ## grooves around the circumference
	var rim_inset: float = 0.035        ## the bark lip rounds in slightly at the cut
	var moss_amount: float = 0.0        ## 0..1 vertex-color moss tint
	var lean: Vector2 = Vector2.ZERO    ## horizontal drift per unit height
	var seed_value: int = 1
	var roots: Array[Vector3] = []      ## (angle, angular width, strength)

	var _noise: FastNoiseLite

	func setup() -> void:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 1.0
		_noise.seed = seed_value

	func add_root(angle: float, width: float, strength: float) -> void:
		roots.append(Vector3(angle, width, strength))

	## Bark groove mask 0..1 (1 = deepest part of a furrow).
	func furrow(theta: float, y: float) -> float:
		var p := Vector3(cos(theta) * furrow_frequency, sin(theta) * furrow_frequency, y * 0.55)
		var primary := 1.0 - smoothstep(0.0, 0.32, absf(_noise.get_noise_3dv(p)))
		var secondary := 1.0 - smoothstep(0.0, 0.2, absf(_noise.get_noise_3dv(p * 2.3 + Vector3(9.0, 3.0, 1.0))))
		return clampf(primary * 0.85 + secondary * 0.35, 0.0, 1.0)

	func radius(theta: float, y: float) -> float:
		var height_fraction := clampf(y / height, 0.0, 1.0)
		var base_radius := lerpf(radius_base, radius_top, pow(height_fraction, 0.7))
		var wobble := _noise.get_noise_3dv(Vector3(cos(theta) * 1.3 + 40.0, sin(theta) * 1.3, y * 0.8)) * irregularity
		var r := base_radius * (1.0 + wobble)
		r -= furrow(theta, y) * furrow_depth * (0.55 + 0.45 * height_fraction)
		# Buttress roots: lobes that flare out at the base and melt into the trunk higher up.
		var flare := exp(-maxf(y, 0.0) * 3.6)
		for root in roots:
			var angle_gap := angle_difference(theta, root.x)
			r += exp(-(angle_gap * angle_gap) / (root.y * root.y)) * root.z * flare
		if y >= height - 0.0001:
			r -= rim_inset
		return r

	func position_at(theta: float, y: float) -> Vector3:
		var r := radius(theta, y)
		var drift := maxf(y, 0.0)
		return Vector3(cos(theta) * r + lean.x * drift, y, sin(theta) * r + lean.y * drift)

	func vertex_color(theta: float, y: float) -> Color:
		var groove := furrow(theta, y)
		var shade := lerpf(1.0, 0.42, groove)
		# Ambient occlusion fake: darker where the trunk meets the ground.
		shade *= lerpf(0.5, 1.0, smoothstep(-0.05, 0.45, y))
		var color := Color(shade, shade, shade * 0.97)
		if moss_amount > 0.0:
			var height_fraction := clampf(y / height, 0.0, 1.0)
			var moss_noise := _noise.get_noise_3dv(Vector3(cos(theta) * 1.1 + 70.0, sin(theta) * 1.1, y * 0.9))
			var moss := smoothstep(0.05, 0.5, moss_noise + (0.55 - height_fraction) * moss_amount)
			color = color.lerp(Color(0.34, 0.55, 0.22) * shade * 1.25, moss * 0.85)
		return color

## Builds [side_mesh, cut_face_mesh] for a trunk. Segment / ring counts control cost.
static func build_trunk(shape: TrunkShape, segments: int, rings: int, build_cap: bool = true) -> Array[ArrayMesh]:
	shape.setup()
	var heights: Array[float] = []
	for k in rings:
		heights.append(lerpf(-shape.below_ground, shape.height * 0.94, float(k) / float(rings - 1)))
	heights.append(shape.height * 0.985)
	heights.append(shape.height)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var tangents := PackedFloat32Array()
	var total_height := shape.height + shape.below_ground
	var ring_count := heights.size()

	for ring in ring_count:
		var y := heights[ring]
		for i in segments + 1:  # +1: duplicated seam column keeps UVs continuous
			var theta := TAU * float(i) / float(segments)
			var p := shape.position_at(theta, y)
			var e_theta := 0.5 * TAU / float(segments)
			var e_y := 0.015
			var d_theta := shape.position_at(theta + e_theta, y) - shape.position_at(theta - e_theta, y)
			var d_y := shape.position_at(theta, y + e_y) - shape.position_at(theta, y - e_y)
			var n := d_y.cross(d_theta).normalized()
			if n.dot(Vector3(cos(theta), 0.0, sin(theta))) < 0.0:
				n = -n
			vertices.append(p)
			normals.append(n)
			colors.append(shape.vertex_color(theta, y))
			var tangent := d_theta.normalized()
			tangents.append_array([tangent.x, tangent.y, tangent.z, 1.0])
			uvs.append(Vector2(float(i) / float(segments), (y + shape.below_ground) / total_height))

	var stride := segments + 1
	for ring in ring_count - 1:
		for i in segments:
			var a := ring * stride + i
			var b := a + 1
			var c := a + stride
			var d := c + 1
			_append_oriented(indices, vertices, normals, a, c, b)
			_append_oriented(indices, vertices, normals, b, c, d)

	var result: Array[ArrayMesh] = [_make_mesh(vertices, normals, colors, uvs, indices, tangents)]
	if build_cap:
		result.append(_build_cut_face(shape, segments))
	return result

static func _build_cut_face(shape: TrunkShape, segments: int) -> ArrayMesh:
	var cap_rings := 7
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in cap_rings + 1:
		var scale_factor := float(ring) / float(cap_rings)
		for i in segments + 1:
			var theta := TAU * float(i) / float(segments)
			var rim := shape.position_at(theta, shape.height)
			var p := Vector3(
				lerpf(shape.lean.x * shape.height, rim.x, scale_factor),
				shape.height,
				lerpf(shape.lean.y * shape.height, rim.z, scale_factor))
			vertices.append(p)
			normals.append(Vector3.UP)
			colors.append(Color.WHITE)
			uvs.append(Vector2(p.x, p.z))
	var stride := segments + 1
	for ring in cap_rings:
		for i in segments:
			var a := ring * stride + i
			var b := a + 1
			var c := a + stride
			var d := c + 1
			_append_oriented(indices, vertices, normals, a, c, b)
			_append_oriented(indices, vertices, normals, b, c, d)
	return _make_mesh(vertices, normals, colors, uvs, indices)

## Tapered, wobbling tube following `points` - used for roots creeping along the ground.
static func build_tube(points: PackedVector3Array, radii: PackedFloat32Array, sides: int, seed_value: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var count := points.size()
	for i in count:
		var previous := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, count - 1)]
		var tangent := (next - previous).normalized()
		var side_axis := tangent.cross(Vector3.UP)
		if side_axis.length() < 0.001:
			side_axis = Vector3.RIGHT
		side_axis = side_axis.normalized()
		var up_axis := side_axis.cross(tangent).normalized()
		for j in sides + 1:
			var phi := TAU * float(j) / float(sides)
			var direction := side_axis * cos(phi) + up_axis * sin(phi)
			var bump := 1.0 + noise.get_noise_3d(float(i) * 0.9, cos(phi) * 1.5, sin(phi) * 1.5) * 0.18
			vertices.append(points[i] + direction * radii[i] * bump)
			normals.append(direction)
			var shade := lerpf(0.6, 1.0, direction.y * 0.5 + 0.5)
			colors.append(Color(shade, shade, shade * 0.97))
			uvs.append(Vector2(float(j) / float(sides), float(i) * 0.35))
	var stride := sides + 1
	for i in count - 1:
		for j in sides:
			var a := i * stride + j
			var b := a + 1
			var c := a + stride
			var d := c + 1
			_append_oriented(indices, vertices, normals, a, c, b)
			_append_oriented(indices, vertices, normals, b, c, d)
	return _make_mesh(vertices, normals, colors, uvs, indices)

## Square terrain patch, flat near the origin and gently undulating further out.
static func build_terrain(size: float, cells: int, flat_radius: float, bumpiness: float, seed_value: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var stride := cells + 1
	var half := size * 0.5
	for z in stride:
		for x in stride:
			var px := -half + size * float(x) / float(cells)
			var pz := -half + size * float(z) / float(cells)
			var py := _terrain_height(noise, px, pz, flat_radius, bumpiness)
			vertices.append(Vector3(px, py, pz))
			var dx := _terrain_height(noise, px + 0.3, pz, flat_radius, bumpiness) - _terrain_height(noise, px - 0.3, pz, flat_radius, bumpiness)
			var dz := _terrain_height(noise, px, pz + 0.3, flat_radius, bumpiness) - _terrain_height(noise, px, pz - 0.3, flat_radius, bumpiness)
			normals.append(Vector3(-dx, 0.6, -dz).normalized())
			colors.append(Color.WHITE)
			uvs.append(Vector2(px, pz))
	for z in cells:
		for x in cells:
			var a := z * stride + x
			var b := a + 1
			var c := a + stride
			var d := c + 1
			_append_oriented(indices, vertices, normals, a, c, b)
			_append_oriented(indices, vertices, normals, b, c, d)
	return _make_mesh(vertices, normals, colors, uvs, indices)

static func _terrain_height(noise: FastNoiseLite, x: float, z: float, flat_radius: float, bumpiness: float) -> float:
	var blend := smoothstep(flat_radius, flat_radius + 6.0, Vector2(x, z).length())
	return noise.get_noise_2d(x, z) * bumpiness * blend

## Appends triangle (a, b, c) wound for Godot (front faces are CLOCKWISE), so the visible side
## is the one the vertex normals point toward.
static func _append_oriented(indices: PackedInt32Array, vertices: PackedVector3Array,
		normals: PackedVector3Array, a: int, b: int, c: int) -> void:
	var geometric := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
	var reference := normals[a] + normals[b] + normals[c]
	if geometric.dot(reference) > 0.0:
		indices.append_array([a, c, b])
	else:
		indices.append_array([a, b, c])

static func _make_mesh(vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array,
		tangents: PackedFloat32Array = PackedFloat32Array()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	if not tangents.is_empty():
		arrays[Mesh.ARRAY_TANGENT] = tangents
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
