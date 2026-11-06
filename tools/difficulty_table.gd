extends SceneTree
## Prints the per-level difficulty table (levels 1-30):  godot --headless --path . -s res://tools/difficulty_table.gd
## "time at X taps/s" = seconds a player who alternates perfectly steadily at that speed needs (- = that speed makes no progress).
func _init() -> void:
	var c: DifficultyConfig = load("res://resources/difficulty/default_difficulty.tres")
	print("| Level | Peak gain %/tap | Useful below ms (taps/s) | Max gap ms | Resistance | Decay %/s | Grace s | 4 taps/s | 5 taps/s | 6 taps/s | 7 taps/s | Reward |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|")
	for l in range(1, 31):
		var cells: Array[String] = []
		for rate in [4.0, 5.0, 6.0, 7.0]:
			var t := c.simulate_extraction_seconds(l, 1000.0 / rate)
			cells.append("-" if t < 0.0 else "%.1f s" % t)
		var useful := c.min_useful_interval_for_level(l)
		print("| %d | %.2f | %.0f (%.1f) | %.0f | %.2f | %.1f | %.2f | %s | %s | %s | %s | %.1f |" % [l, c.peak_gain_for_level(l), useful, 1000.0 / useful, c.max_interval_for_level(l), c.resistance_for_level(l), c.decay_for_level(l), c.grace_for_level(l), cells[0], cells[1], cells[2], cells[3], clampf(float(l - 1) / 10.0, 0.0, 1.0)])
	quit()
