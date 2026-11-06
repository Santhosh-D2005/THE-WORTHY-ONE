extends SceneTree
## Writes server/floor_expected.json: the physical per-level floor (a steady 130 ms tapper) from the game's own difficulty configs.
## The server's min_level_seconds() must agree with it (server/test_schema.mjs compares them).   godot --headless -s res://tools/server_floor_dump.gd
func _init() -> void:
	var out := {}
	for mode: String in ["endless", "ruthless"]:
		var config: DifficultyConfig = load("res://resources/difficulty/ruthless_difficulty.tres" if mode == "ruthless" else "res://resources/difficulty/default_difficulty.tres")
		var rows := {}
		for level: int in [1, 2, 3, 5, 10, 20, 30, 50, 75, 99, 100, 101, 500, 9999]:
			rows[str(level)] = config.simulate_extraction_seconds(level, 130.0)
		out[mode] = rows
	var file := FileAccess.open("res://server/floor_expected.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "  "))
	file.close()
	print("wrote server/floor_expected.json")
	quit()
