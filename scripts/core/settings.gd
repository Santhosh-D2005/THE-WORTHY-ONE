extends Node
## Autoload "Settings": the player's options, saved in user://settings.cfg and applied at once.
##
## SOUND  (sound_volume)  the level of the whole game's sound, including the forest ambience. It drives the Master bus.
## SFX    (sfx_volume)    the level of the effects (taps, bells, the blade, UI clicks). It drives the SFX bus, which feeds Master.
## Both run from 0 (silent) to 1 (full) in steps of 10 %. At 0 the bus is muted.
##
## OPTIMISATION
##   quality   "" (automatic: the platform default from RenderQuality), "high", "balanced" or "low". It selects a RenderQuality preset
##             for the scene that is built next (the forest reads RenderQuality.current() when it is built), so it takes effect the next
##             time a run starts.
##   fps_cap   0 (unlimited), 60 or 30 frames per second. Applied to the engine at once; lower values save battery and heat.
##
## Nothing here changes gameplay or the save progress file.

signal changed

const SAVE_PATH := "user://settings.cfg"
## Headless test runs use their own file, so tests never change a player's real settings.
const TEST_SAVE_PATH := "user://settings_headless.cfg"
const SECTION := "settings"
const STEP := 0.1
const QUALITY_CHOICES: Array[String] = ["", "high", "balanced", "low"]
const FPS_CHOICES: Array[int] = [0, 60, 30]
const MASTER_BUS := &"Master"
const SFX_BUS := &"SFX"

var sound_volume: float = 1.0
var sfx_volume: float = 1.0
var quality: String = ""
var fps_cap: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	load_settings()
	apply_all()

static func default_path() -> String:
	return TEST_SAVE_PATH if DisplayServer.get_name() == "headless" else SAVE_PATH

## The SFX bus is created on first use (no bus-layout file to maintain) and sends to Master. Missing buses are never fatal:
## a cue then simply plays on Master.
static func ensure_buses() -> void:
	if AudioServer.get_bus_index(SFX_BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, SFX_BUS)
		AudioServer.set_bus_send(AudioServer.get_bus_index(SFX_BUS), MASTER_BUS)

# ---- Setters (clamped, snapped to the 10 % steps, saved and applied) -------------------------------

func set_sound_volume(value: float) -> void:
	sound_volume = _snap_volume(value)
	apply_audio()
	_save_and_announce()

func set_sfx_volume(value: float) -> void:
	sfx_volume = _snap_volume(value)
	apply_audio()
	_save_and_announce()

## Choose the next quality in QUALITY_CHOICES (wraps around).
func cycle_quality() -> void:
	quality = _next_choice(QUALITY_CHOICES, quality)
	apply_quality()
	_save_and_announce()

## Choose the next frame-rate cap in FPS_CHOICES (wraps around).
func cycle_fps_cap() -> void:
	fps_cap = _next_choice(FPS_CHOICES, fps_cap)
	apply_frame_cap()
	_save_and_announce()

## Back to the defaults: full volume, automatic quality, unlimited frame rate.
func reset_to_defaults() -> void:
	sound_volume = 1.0
	sfx_volume = 1.0
	quality = ""
	fps_cap = 0
	apply_all()
	_save_and_announce()

# ---- Applying ------------------------------------------------------------------------------------------

func apply_all() -> void:
	apply_audio()
	apply_quality()
	apply_frame_cap()

func apply_audio() -> void:
	_apply_bus(MASTER_BUS, sound_volume)
	_apply_bus(SFX_BUS, sfx_volume)

func _apply_bus(bus_name: StringName, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, volume <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001)))

## Quality: an explicit choice replaces the platform default. "" keeps RenderQuality's own automatic choice.
func apply_quality() -> void:
	if quality != "":
		RenderQuality.set_current(RenderQuality.preset(quality))

func apply_frame_cap() -> void:
	Engine.max_fps = fps_cap

# ---- Labels for the screen --------------------------------------------------------------------------------

static func percent_text(volume: float) -> String:
	return "%d%%" % roundi(volume * 100.0)

static func quality_text(value: String) -> String:
	match value:
		"high": return "HIGH"
		"balanced": return "BALANCED"
		"low": return "LOW"
		_:
			return "AUTO (%s)" % ("BALANCED" if OS.has_feature("mobile") else "HIGH")

static func fps_text(cap: int) -> String:
	return "UNLIMITED" if cap <= 0 else "%d FPS" % cap

# ---- Saving -----------------------------------------------------------------------------------------------

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(default_path()) != OK:
		return  # no file yet (or unreadable): the defaults stand
	sound_volume = _snap_volume(float(config.get_value(SECTION, "sound_volume", sound_volume)))
	sfx_volume = _snap_volume(float(config.get_value(SECTION, "sfx_volume", sfx_volume)))
	var saved_quality := str(config.get_value(SECTION, "quality", quality))
	quality = saved_quality if saved_quality in QUALITY_CHOICES else ""
	var saved_fps := int(config.get_value(SECTION, "fps_cap", fps_cap))
	fps_cap = saved_fps if saved_fps in FPS_CHOICES else 0

func save_settings() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION, "sound_volume", sound_volume)
	config.set_value(SECTION, "sfx_volume", sfx_volume)
	config.set_value(SECTION, "quality", quality)
	config.set_value(SECTION, "fps_cap", fps_cap)
	return config.save(default_path()) == OK

func _save_and_announce() -> void:
	save_settings()
	changed.emit()

# ---- Helpers ------------------------------------------------------------------------------------------------

static func _snap_volume(value: float) -> float:
	return clampf(snappedf(value, STEP), 0.0, 1.0)

static func _next_choice(choices: Array, current: Variant) -> Variant:
	var index := choices.find(current)
	return choices[(index + 1) % choices.size()] if index >= 0 else choices[0]
