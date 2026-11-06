extends Node
## Pre-generates the procedural meshes and noise textures into res://assets/baked/ (see AssetCache).
## Run from the project folder (needs a real renderer, so NOT --headless):
##   Godot --path . res://tools/bake_assets.tscn
## Re-run it after changing any procedural mesh / noise parameter or an AssetCache key.

func _ready() -> void:
	AssetCache.baking = true
	# Build exactly what the game builds. The nodes are never shown; _ready() does all the work.
	var forest := ForestEnvironment.new()
	forest.name = "Forest"
	add_child(forest)
	var stump := StumpBuilder.new()
	stump.name = "Stump"
	add_child(stump)
	print("[bake] procedural build finished; waiting for noise textures ...")
	_finish.call_deferred()

func _finish() -> void:
	var textures := AssetCache.recorded_textures()
	var waited := 0
	while waited < 600:
		var pending := 0
		for key in textures:
			if (textures[key] as Texture2D).get_image() == null:
				pending += 1
		if pending == 0:
			break
		await get_tree().process_frame
		waited += 1
	var report := AssetCache.save_recorded()
	print("[bake] saved %d meshes and %d textures (%.1f MB on disk)" % [
		report["meshes"], report["textures"], report["bytes"] / 1048576.0])
	get_tree().quit(0)
