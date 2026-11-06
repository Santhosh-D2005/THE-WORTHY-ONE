class_name FoliageBuilder
extends RefCounted
## Foreground and mid-ground undergrowth for the clearing (Milestone 1.9): fern clumps and low leafy shrubs.
## Everything is ONE multimesh per kind (one draw call each), shadows off, so it costs almost nothing on the phone.
## The foliage is placed at the sides and in the near corners of the frame so it frames the stump and adds depth, and stays
## out of the middle of the picture and below the tap discs' line of sight.

## One fern frond: a flat strip that arches outward and droops at the tip, with leaflets suggested by a notched outline.
## Vertex colours run from a dark root to a lighter, slightly yellower tip.
static func make_fern_mesh(fronds: int = 9, seed_value: int = 5) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 4  # (1.9.2: fewer segments; overdraw, not vertex count, is what costs on the phone)
	for f in fronds:
		var yaw := TAU * (float(f) + rng.randf_range(-0.25, 0.25)) / float(fronds)
		var length := rng.randf_range(0.75, 1.15)
		var rise := rng.randf_range(0.55, 0.9)      # how steeply it leaves the root
		var droop := rng.randf_range(0.5, 0.95)     # how much the tip falls back
		var width := rng.randf_range(0.17, 0.24)
		var outward := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-sin(yaw), 0.0, cos(yaw))
		var previous_center := Vector3.ZERO
		var previous_half := 0.0
		for i in range(1, segments + 1):
			var t := float(i) / float(segments)
			var center := outward * (length * t) + Vector3.UP * (rise * length * (t - droop * t * t))
			# A leaf-shaped outline: widest at about 40 %, notched in a saw-tooth to read as leaflets.
			var notch := 0.78 if i % 2 == 1 else 1.0
			var half := width * sin(clampf(t * 0.9 + 0.1, 0.0, 1.0) * PI) * notch
			var c0 := Color(0.06, 0.10, 0.04).lerp(Color(0.20, 0.31, 0.10), clampf((t - 0.1) / 0.9, 0.0, 1.0))
			var c_prev := Color(0.06, 0.10, 0.04).lerp(Color(0.20, 0.31, 0.10), clampf((float(i - 1) / float(segments) - 0.1) / 0.9, 0.0, 1.0))
			var a := previous_center - side * previous_half
			var b := previous_center + side * previous_half
			var c := center - side * half
			var d := center + side * half
			var normal := (b - a).cross(c - a).normalized()
			if normal.y < 0.0:
				normal = -normal
			_tri(surface, a, c, b, c_prev, c0, c_prev, normal)
			_tri(surface, b, c, d, c_prev, c0, c0, normal)
			previous_center = center
			previous_half = half
	return surface.commit()

static func _tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, normal: Vector3) -> void:
	for pair in [[a, ca], [b, cb], [c, cc]]:
		surface.set_color(pair[1])
		surface.set_normal(normal)
		surface.add_vertex(pair[0])

## A multimesh of `count` ferns scattered inside the given rectangles (x range, z range pairs), skipping the clear middle.
static func make_fern_field(placements: Array[Rect2], count: int, seed_value: int, min_scale: float, max_scale: float) -> MultiMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = make_fern_mesh(7, seed_value)
	multi.instance_count = count
	for i in count:
		var area := placements[i % placements.size()]
		var point := Vector3(rng.randf_range(area.position.x, area.end.x), 0.0, rng.randf_range(area.position.y, area.end.y))
		var s := rng.randf_range(min_scale, max_scale)
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.08, 0.08)))
		multi.set_instance_transform(i, Transform3D(basis.scaled(Vector3(s, s * rng.randf_range(0.8, 1.1), s)), point))
	return multi
