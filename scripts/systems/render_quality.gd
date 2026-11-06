class_name RenderQuality
extends RefCounted
## Configurable rendering quality. One small set of knobs, a few named presets, and a way to pick one:
##   --quality=<preset>            choose a preset (original / high / balanced / low)
##   --rq=key=value,key=value      override single knobs on top of it (used for A/B measurements)
## With no argument: desktop and tests use "original" (exactly the Milestone 1.3 look), Android uses "balanced".
## The values are applied by ForestEnvironment (sun, fog, post-processing), MaterialFactory (normal
## maps) and apply_to_viewport() (3D render scale). Nothing here changes gameplay.

const QUALITY_ARGUMENT := "--quality="
const OVERRIDE_ARGUMENT := "--rq="

## Resolution of the 3D scene relative to the screen. The HUD is always drawn at full resolution.
var scale_3d: float = 1.0
var shadows_enabled: bool = true
## Side length of the sun's shadow map in pixels.
var shadow_map_size: int = 4096
var shadow_blur: float = 1.8
## 0 = hard, 1 = very low ... 5 = ultra (RenderingServer.ShadowQuality).
var soft_shadow_quality: int = 2
var fog_enabled: bool = true
## Contrast / saturation grading. It costs a full-screen pass in some configurations.
var adjustment_enabled: bool = true
var bark_normal_maps: bool = true
## Strength of the sun-coloured glow in the fog (0.25 = original). 0 skips the per-pixel sun-direction term.
var fog_sun_scatter: float = 0.25
## Multisample anti-aliasing of the 3D scene: 0 = off, 2 or 4 samples (applied at the scaled 3D resolution).
var msaa: int = 0
## Cheap post-process edge smoothing (FXAA). Can be combined with msaa.
var fxaa: bool = false
## Anisotropic texture filtering: 1 (off), 2, 4, 8, 16 samples. Sharpens textures seen at a slant (bark, floor).
var anisotropy: int = 2
## Mipmaps on the baked noise textures (smoother distant detail, +33 % texture memory).
var texture_mipmaps: bool = true
## Upscaler used when scale_3d < 1: false = bilinear (cheapest), true = AMD FSR 1.0 (sharper, costs GPU time).
var fsr_upscaling: bool = false
## FSR sharpening (Viewport.fsr_sharpness): 0.0 = sharpest, each +1.0 halves it. Godot default 0.2.
var fsr_sharpness: float = 0.2
## Texture LOD bias (Viewport.texture_mipmap_bias): negative = sharper textures (more shimmer). 0 = default.
var mipmap_bias: float = 0.0

var name: String = "original"

static func preset(preset_name: String) -> RenderQuality:
	var q := RenderQuality.new()
	q.name = preset_name
	match preset_name:
		"original", "high":
			pass  # the Milestone 1.3 look
		"balanced":
			# Measured on an Adreno 610 phone (MILESTONE_1_4_REPORT.md): ~58 FPS idle instead of ~20.
			# Milestone 1.5: FSR 1.0 upscaling (sharper than bilinear at the same cost) and 4x anisotropic
			# filtering (free) on top of the 1.4 settings. 0.65-0.75 all measured ~42-45 FPS: 0.60 is the cliff.
			q.scale_3d = 0.6
			q.shadow_map_size = 1024
			q.soft_shadow_quality = 0
			q.fog_sun_scatter = 0.0
			q.fsr_upscaling = true
			q.anisotropy = 4
			q.fsr_sharpness = 0.05  # 1.6: crisper edges; measured free (58.3 vs 58.3 FPS, MILESTONE_1_6_REPORT.md)
			# A -0.5 texture LOD bias looked crisper but cost 2.5-4 FPS on the phone, so it stays off (0.0).
		"low":
			# Extra headroom on weaker or hot GPUs (measured: a solid 60 FPS on the test phone, but softer).
			q.scale_3d = 0.5
			q.shadow_map_size = 1024
			q.soft_shadow_quality = 0
			q.fog_sun_scatter = 0.0
			q.fsr_upscaling = true
			q.anisotropy = 4
		_:
			push_warning("RenderQuality: unknown preset '%s', using original" % preset_name)
			q.name = "original"
	return q

static var _current: RenderQuality = null

## Command-line arguments plus, in DEBUG builds only, the words in user://launch_args.txt. The file lets a
## developer change quality / enable the perf log on an installed phone build without re-exporting
## (the Android launcher activity does not forward intent extras):
##   adb shell "run-as com.theworthyone.game sh -c 'echo --perf-log --quality=low > files/launch_args.txt'"
static func launch_arguments() -> Array:
	var arguments: Array = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if OS.is_debug_build() and FileAccess.file_exists("user://launch_args.txt"):
		var text := FileAccess.get_file_as_string("user://launch_args.txt")
		for word in text.split(" ", false):
			arguments.append(word.strip_edges())
	return arguments

## The quality for this run (parsed once; tests can replace it with set_current()).
static func current() -> RenderQuality:
	if _current == null:
		_current = from_arguments(launch_arguments(), OS.has_feature("mobile"))
	return _current

static func set_current(quality: RenderQuality) -> void:
	_current = quality

static func from_arguments(arguments: Array, is_mobile: bool) -> RenderQuality:
	var chosen := "balanced" if is_mobile else "original"
	var overrides := ""
	for argument in arguments:
		var text := str(argument)
		if text.begins_with(QUALITY_ARGUMENT):
			chosen = text.substr(QUALITY_ARGUMENT.length())
		elif text.begins_with(OVERRIDE_ARGUMENT):
			overrides = text.substr(OVERRIDE_ARGUMENT.length())
	var q := preset(chosen)
	for pair in overrides.split(",", false):
		var kv := pair.split("=", false)
		if kv.size() == 2:
			q.set_value(kv[0], kv[1])
	return q

## Set one knob from text. Returns false for an unknown key.
func set_value(key: String, text: String) -> bool:
	match key:
		"scale_3d": scale_3d = clampf(text.to_float(), 0.25, 1.0)
		"shadows": shadows_enabled = text != "0"
		"shadow_size": shadow_map_size = clampi(text.to_int(), 256, 8192)
		"shadow_blur": shadow_blur = maxf(text.to_float(), 0.0)
		"soft_shadow": soft_shadow_quality = clampi(text.to_int(), 0, 5)
		"fog": fog_enabled = text != "0"
		"adjustment": adjustment_enabled = text != "0"
		"normal_maps": bark_normal_maps = text != "0"
		"fog_scatter": fog_sun_scatter = maxf(text.to_float(), 0.0)
		"msaa": msaa = 4 if text.to_int() >= 4 else (2 if text.to_int() >= 2 else 0)
		"fxaa": fxaa = text != "0"
		"aniso": anisotropy = clampi(text.to_int(), 1, 16)
		"mipmaps": texture_mipmaps = text != "0"
		"fsr": fsr_upscaling = text != "0"
		"fsr_sharp": fsr_sharpness = clampf(text.to_float(), 0.0, 2.0)
		"mip_bias": mipmap_bias = clampf(text.to_float(), -2.0, 2.0)
		_:
			push_warning("RenderQuality: unknown key '%s'" % key)
			return false
	return true

func apply_to_viewport(viewport: Viewport) -> void:
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fsr_upscaling and scale_3d < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = scale_3d
	viewport.fsr_sharpness = fsr_sharpness
	viewport.texture_mipmap_bias = mipmap_bias
	viewport.msaa_3d = Viewport.MSAA_4X if msaa >= 4 else (Viewport.MSAA_2X if msaa >= 2 else Viewport.MSAA_DISABLED)
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	var level := Viewport.ANISOTROPY_DISABLED
	if anisotropy >= 16: level = Viewport.ANISOTROPY_16X
	elif anisotropy >= 8: level = Viewport.ANISOTROPY_8X
	elif anisotropy >= 4: level = Viewport.ANISOTROPY_4X
	elif anisotropy >= 2: level = Viewport.ANISOTROPY_2X
	viewport.anisotropic_filtering_level = level

## Global shadow settings (shadow atlas size and filter quality). Call once at startup.
func apply_shadow_globals() -> void:
	RenderingServer.directional_shadow_atlas_set_size(shadow_map_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(soft_shadow_quality as RenderingServer.ShadowQuality)

func describe() -> String:
	return "%s (3D scale %.2f, shadows %s %d px blur %.1f filter %d, fog %s, grading %s, normal maps %s, msaa %d, fxaa %s, aniso %d, mipmaps %s, fsr %s)" % [
		name, scale_3d, "on" if shadows_enabled else "off", shadow_map_size, shadow_blur, soft_shadow_quality,
		"on" if fog_enabled else "off", "on" if adjustment_enabled else "off",
		"on" if bark_normal_maps else "off", msaa, "on" if fxaa else "off", anisotropy, "on" if texture_mipmaps else "off", "on" if fsr_upscaling else "off"]
