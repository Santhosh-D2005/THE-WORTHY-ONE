class_name AssetCache
extends RefCounted
## Pre-generated ("baked") copies of the procedural meshes and noise textures.
##
## The game used to generate every trunk, the terrain and ten noise textures on each launch, which on
## a mid-range phone dominated start-up time. tools/bake_assets.gd now writes the SAME output to
## res://assets/baked/ once; at run time the baked file is loaded when it exists, otherwise the
## procedural builder runs exactly as before (so the game and the tests work without baked files and
## the baked files can be regenerated at any time).
##
## Rule: a cache key must change whenever the inputs of its builder change - keys are written by the
## callers next to the parameters they describe, and the bake tool is re-run after editing them.

const DIRECTORY := "res://assets/baked/"

## True only inside tools/bake_assets.gd: always rebuild and record the results to be saved.
static var baking: bool = false
## True to ignore baked files (tests that exercise the procedural path, measurements).
static var disabled: bool = "--no-baked" in RenderQuality.launch_arguments()  # also: --no-baked on the command line
static var _recorded_meshes: Dictionary = {}
static var _recorded_textures: Dictionary = {}
## How many requests were served from disk / built procedurally (for the report and tests).
static var loaded_count: int = 0
static var built_count: int = 0

## `builder` returns an Array[ArrayMesh]; `count` is how many meshes it returns.
static func meshes(key: String, count: int, builder: Callable) -> Array[ArrayMesh]:
	if not baking and not disabled:
		var loaded := _try_load_meshes(key, count)
		if not loaded.is_empty():
			loaded_count += 1
			return loaded
	built_count += 1
	var built: Array[ArrayMesh] = builder.call()
	if baking:
		_recorded_meshes[key] = built
	return built

static func mesh(key: String, builder: Callable) -> ArrayMesh:
	var wrapped := func() -> Array[ArrayMesh]:
		var result: Array[ArrayMesh] = [builder.call()]
		return result
	return meshes(key, 1, wrapped)[0]

static func _try_load_meshes(key: String, count: int) -> Array[ArrayMesh]:
	var result: Array[ArrayMesh] = []
	for i in count:
		var path := "%s%s_%d.res" % [DIRECTORY, key, i]
		if not ResourceLoader.exists(path):
			return []
		var loaded := load(path)
		if not loaded is ArrayMesh:
			return []
		result.append(loaded)
	return result

## Noise texture: baked as an ImageTexture holding the already-generated pixels.
static func texture(key: String, builder: Callable) -> Texture2D:
	if not baking and not disabled:
		var path := "%s%s.res" % [DIRECTORY, key]
		if ResourceLoader.exists(path):
			var loaded := load(path)
			if loaded is Texture2D:
				loaded_count += 1
				if not RenderQuality.current().texture_mipmaps and loaded is ImageTexture:
					var plain: Image = (loaded as ImageTexture).get_image()
					plain.clear_mipmaps()
					return ImageTexture.create_from_image(plain)
				return loaded
	built_count += 1
	var built: Texture2D = builder.call()
	if baking:
		_recorded_textures[key] = built
	return built

## Used by the bake tool: write everything recorded so far. Textures must have finished generating.
static func save_recorded() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var report := {"meshes": 0, "textures": 0, "bytes": 0}
	for key in _recorded_meshes:
		var list: Array = _recorded_meshes[key]
		for i in list.size():
			var path := "%s%s_%d.res" % [DIRECTORY, key, i]
			ResourceSaver.save(list[i], path, ResourceSaver.FLAG_COMPRESS)
			report["meshes"] += 1
			report["bytes"] += FileAccess.get_file_as_bytes(path).size()
	for key in _recorded_textures:
		var source: Texture2D = _recorded_textures[key]
		var image := source.get_image()
		if image == null:
			push_error("AssetCache: texture '%s' has no image yet" % key)
			continue
		image.generate_mipmaps()  # smoother distant detail; the runtime can strip them (RenderQuality.texture_mipmaps)
		var baked := ImageTexture.create_from_image(image)
		var path := "%s%s.res" % [DIRECTORY, key]
		ResourceSaver.save(baked, path, ResourceSaver.FLAG_COMPRESS)
		report["textures"] += 1
		report["bytes"] += FileAccess.get_file_as_bytes(path).size()
	return report

static func recorded_textures() -> Dictionary:
	return _recorded_textures
