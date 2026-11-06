extends Node
## Start-up asset tests (Milestone 1.4): the baked meshes / textures must be IDENTICAL to what the
## procedural builders produce, and the quality settings must parse and apply.
##
## Run (needs a window):  godot --path . res://tests/startup_tests.tscn
## Exit code: 0 = all passed, 1 = failures.

var _checks := 0
var _failures := 0

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)

func _ready() -> void:
	get_window().size = Vector2i(540, 960)
	await get_tree().process_frame
	_t_quality_settings()
	await _t_baked_equals_procedural()
	await _t_environment_follows_quality()
	print("\n==== %d checks, %d failed ====" % [_checks, _failures])
	print("RESULT: ", "ALL PASSED" if _failures == 0 else "FAILURES")
	get_tree().quit(1 if _failures > 0 else 0)

func _t_quality_settings() -> void:
	print("\n[1] QUALITY SETTINGS")
	var desktop := RenderQuality.from_arguments([], false)
	var phone := RenderQuality.from_arguments([], true)
	_check(desktop.name == "original" and desktop.scale_3d == 1.0 and desktop.shadows_enabled and desktop.fog_enabled and desktop.bark_normal_maps,
		"desktop default is the unchanged original look")
	_check(phone.name == "balanced" and phone.fsr_upscaling and is_equal_approx(phone.scale_3d, 0.6) and phone.anisotropy == 4 and phone.msaa == 0 and not phone.fxaa,
		"a phone defaults to balanced: 0.6 scale, FSR upscaling, 4x anisotropy, no MSAA/FXAA (the measured choice)")
	_check(is_equal_approx(phone.fsr_sharpness, 0.05) and is_equal_approx(phone.mipmap_bias, 0.0), "balanced uses FSR sharpness 0.05 and no texture bias (1.6, measured)")
	_check(desktop.anisotropy == 2 and not desktop.fsr_upscaling, "the original preset keeps bilinear scaling and 2x anisotropy")
	var q := RenderQuality.from_arguments(["--quality=original", "--rq=scale_3d=0.7,fog=0,shadow_size=1024,fog_scatter=0.1"], true)
	_check(q.name == "original" and is_equal_approx(q.scale_3d, 0.7) and not q.fog_enabled and q.shadow_map_size == 1024 and is_equal_approx(q.fog_sun_scatter, 0.1),
		"--quality and --rq overrides parse")
	_check(RenderQuality.from_arguments(["--rq=scale_3d=9"], false).scale_3d == 1.0 and RenderQuality.from_arguments(["--rq=scale_3d=0.01"], false).scale_3d == 0.25,
		"out-of-range values are clamped")
	_check(RenderQuality.from_arguments(["--quality=nonsense"], false).name == "original", "an unknown preset falls back to original")
	_check(not RenderQuality.new().set_value("bogus", "1"), "an unknown key is rejected")

func _arrays_close(x: Variant, y: Variant, tolerance: float) -> bool:
	if x == null or y == null:
		return x == y
	if x.size() != y.size():
		return false
	if tolerance == 0.0:
		return x == y
	for i in x.size():
		var d: float = 0.0
		match typeof(x[i]):
			TYPE_VECTOR3: d = (x[i] - y[i]).length()
			TYPE_VECTOR2: d = (x[i] - y[i]).length()
			TYPE_COLOR: d = absf(x[i].r - y[i].r) + absf(x[i].g - y[i].g) + absf(x[i].b - y[i].b)
			_: d = absf(float(x[i]) - float(y[i]))
		if d > tolerance:
			return false
	return true

## Same mesh data. Positions must match to 0.1 mm; normals/tangents/colours/UVs are stored in a
## compressed form by the engine, so they get a small tolerance. Indices must match exactly.
func _mesh_arrays_equal(a: ArrayMesh, b: ArrayMesh) -> bool:
	if a.get_surface_count() != b.get_surface_count():
		return false
	for s in a.get_surface_count():
		var x := a.surface_get_arrays(s)
		var y := b.surface_get_arrays(s)
		if not _arrays_close(x[Mesh.ARRAY_VERTEX], y[Mesh.ARRAY_VERTEX], 0.0001): return false
		if not _arrays_close(x[Mesh.ARRAY_INDEX], y[Mesh.ARRAY_INDEX], 0.0): return false
		if not _arrays_close(x[Mesh.ARRAY_NORMAL], y[Mesh.ARRAY_NORMAL], 0.02): return false
		if not _arrays_close(x[Mesh.ARRAY_COLOR], y[Mesh.ARRAY_COLOR], 0.02): return false
		if not _arrays_close(x[Mesh.ARRAY_TEX_UV], y[Mesh.ARRAY_TEX_UV], 0.001): return false
		if x[Mesh.ARRAY_TANGENT] != null and not _arrays_close(x[Mesh.ARRAY_TANGENT], y[Mesh.ARRAY_TANGENT], 0.02): return false
	return true

func _base_level(image: Image) -> PackedByteArray:
	var copy := image.duplicate() as Image
	copy.clear_mipmaps()
	return copy.get_data()

func _t_baked_equals_procedural() -> void:
	print("\n[2] BAKED ASSETS EQUAL THE PROCEDURAL ONES")
	var checked := {"mesh": 0, "texture": 0}
	var all_same := true
	var bad := ""
	for key in ["terrain_v1_90_56_45_06_5"]:
		AssetCache.disabled = false
		var baked := AssetCache.mesh(key, func() -> ArrayMesh: return null)
		AssetCache.disabled = true
		var built := OrganicMesh.build_terrain(90.0, 56, 4.5, 0.6, 5)
		AssetCache.disabled = false
		checked["mesh"] += 1
		if baked == null or not _mesh_arrays_equal(baked, built):
			all_same = false
			bad = key
	_check(all_same, "terrain: baked vertices/indices equal a fresh build %s" % bad)

	# A stump trunk (the largest mesh) and one background tree.
	var shape := OrganicMesh.TrunkShape.new()
	shape.radius_top = 1.25
	shape.radius_base = 1.5
	shape.height = 1.0
	shape.irregularity = 0.06
	shape.furrow_depth = 0.07
	shape.moss_amount = 0.55
	shape.seed_value = 12
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var roots: Array[float] = []
	for i in 6:
		roots.append(TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / 6 + 0.4)
	for angle in roots:
		shape.add_root(angle, rng.randf_range(0.16, 0.26), rng.randf_range(0.25, 0.42))
	var built_trunk := OrganicMesh.build_trunk(shape, 112, 14)
	AssetCache.disabled = false
	var baked_trunk := AssetCache.meshes("stump_trunk_v1", 2, func() -> Array[ArrayMesh]: return [])
	_check(baked_trunk.size() == 2 and _mesh_arrays_equal(baked_trunk[0], built_trunk[0]) and _mesh_arrays_equal(baked_trunk[1], built_trunk[1]),
		"stump trunk + cut face: baked equals a fresh build")

	# Noise textures: pixel-identical (waits for the asynchronous generator).
	AssetCache.disabled = false
	var baked_tex: Texture2D = MaterialFactory.shared_noise()
	AssetCache.disabled = true
	var fresh: NoiseTexture2D = MaterialFactory._build_noise_texture(0.02, 11, Color.BLACK, Color.WHITE, false, 1.0, 256)
	AssetCache.disabled = false
	var waited := 0
	while fresh.get_image() == null and waited < 300:
		await get_tree().process_frame
		waited += 1
	_check(baked_tex != null and fresh.get_image() != null and _base_level(baked_tex.get_image()) == _base_level(fresh.get_image()),
		"shared noise texture: baked pixels equal a fresh build")

	var before_loaded := AssetCache.loaded_count
	var before_built := AssetCache.built_count
	var forest := ForestEnvironment.new()
	add_child(forest)
	var stump := StumpBuilder.new()
	add_child(stump)
	_check(AssetCache.built_count == before_built and AssetCache.loaded_count - before_loaded >= 60,
		"building the scene used only baked files (%d loaded, %d built procedurally)" % [AssetCache.loaded_count - before_loaded, AssetCache.built_count - before_built])
	forest.queue_free()
	stump.queue_free()
	await get_tree().process_frame

func _t_environment_follows_quality() -> void:
	print("\n[3] THE SCENE FOLLOWS THE QUALITY SETTINGS")
	var original := RenderQuality.current()
	var q := RenderQuality.from_arguments(["--quality=original", "--rq=shadows=0,fog=0,adjustment=0,shadow_blur=0.5,scale_3d=0.5"], false)
	RenderQuality.set_current(q)
	var forest := ForestEnvironment.new()
	add_child(forest)
	await get_tree().process_frame
	var sun: DirectionalLight3D = forest.get_node("Sun")
	var env: Environment = (forest.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(not sun.shadow_enabled and is_equal_approx(sun.shadow_blur, 0.5), "sun shadow switch and blur follow the settings")
	_check(not env.fog_enabled and not env.adjustment_enabled, "fog and grading follow the settings")
	_check(is_equal_approx(get_viewport().scaling_3d_scale, 0.5), "3D render scale is applied to the viewport")
	forest.queue_free()
	RenderQuality.set_current(original)
	original.apply_to_viewport(get_viewport())
	original.apply_shadow_globals()
	await get_tree().process_frame
	var plain := ForestEnvironment.new()
	add_child(plain)
	await get_tree().process_frame
	_check((plain.get_node("Sun") as DirectionalLight3D).shadow_enabled and ((plain.get_node("WorldEnvironment") as WorldEnvironment).environment.fog_enabled),
		"the original quality keeps shadows and fog on (default look unchanged)")
	plain.queue_free()
