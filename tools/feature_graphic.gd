extends SceneTree
## Makes the Play Store feature graphic (1024 x 500):  godot --path . -s res://tools/feature_graphic.gd -- out.png   (needs a window, not --headless)
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "feature.png"
	var vp := SubViewport.new()
	vp.size = Vector2i(1024, 500)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.07, 0.04)
	bg.size = Vector2(1024, 500)
	vp.add_child(bg)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.16, 0.26, 0.12))
	grad.set_color(1, Color(0.02, 0.04, 0.03))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.28, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 512
	tex.height = 250
	var glow := TextureRect.new()
	glow.texture = tex
	glow.size = Vector2(1024, 500)
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	vp.add_child(glow)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/branding/icon_512.png")
	icon.size = Vector2(340, 340)
	icon.position = Vector2(70, 80)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vp.add_child(icon)
	var small := UiStyle.label("THE", 44, UiStyle.GOLD)
	small.position = Vector2(440, 105); small.size = Vector2(540, 60)
	vp.add_child(small)
	var title := UiStyle.label("WORTHY ONE", 62, UiStyle.PARCHMENT)
	title.position = Vector2(440, 160); title.size = Vector2(540, 90)
	vp.add_child(title)
	var line := ColorRect.new()
	line.color = UiStyle.GOLD_DIM
	line.position = Vector2(560, 275); line.size = Vector2(300, 3)
	vp.add_child(line)
	var tag := UiStyle.label("One sword. One tree. One challenge.", 22, UiStyle.GOLD_BRIGHT)
	tag.position = Vector2(440, 305); tag.size = Vector2(540, 50)
	vp.add_child(tag)
	for i in 8:
		await process_frame
	vp.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
