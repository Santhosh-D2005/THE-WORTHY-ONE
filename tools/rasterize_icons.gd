extends Node
## Renders the icon SVG sources in assets/branding/src/ to the PNG sizes the project uses (see tools/make_icon.py).
##   godot --headless --path . res://tools/rasterize_icons.tscn
const SRC := "res://assets/branding/src/"
const OUT := "res://assets/branding/"
## source -> [output name, pixel size]
const JOBS := [
	["icon_full.svg", "icon_512.png", 512], ["icon_full.svg", "icon_192.png", 192],
	["adaptive_background.svg", "icon_adaptive_background_432.png", 432],
	["adaptive_foreground.svg", "icon_adaptive_foreground_432.png", 432],
	["adaptive_monochrome.svg", "icon_adaptive_monochrome_432.png", 432],
]

func _ready() -> void:
	var failures := 0
	for job in JOBS:
		var text := FileAccess.get_file_as_string(SRC + job[0])
		var image := Image.new()
		var err := image.load_svg_from_string(text, float(job[2]) / 432.0)
		if err != OK:
			printerr("could not render ", job[0], " (error ", err, ")")
			failures += 1
			continue
		var path := ProjectSettings.globalize_path(OUT + job[1])
		image.save_png(path)
		print("rendered ", job[1], " ", image.get_width(), "x", image.get_height())
	get_tree().quit(failures)
