class_name DifficultyManager
extends Node
## Translates a level number into concrete tuning values using a DifficultyConfig curve.
##
## PLAYTEST PRESETS: start the game with the argument  --difficulty-preset=<name>  to load
## res://resources/difficulty/presets/<name>.tres instead of the default configuration.
## On Android put the argument in the export preset's "Command Line > Extra Args".
## Unknown names fall back to the default with a warning. Non-default presets are shown as a
## small label on the HUD (print() output does NOT reach logcat on every Android device, so
## it cannot be relied on).

signal difficulty_changed(level: int, gain: float, decay: float, grace: float)
## The longest allowed gap between alternating taps (ms) for the level that was just applied.
signal rhythm_changed(max_interval_msec: float)
## The speed-response curve for the level that was just applied: optimal interval, minimum useful interval (ms), exponent.
signal speed_changed(optimal_msec: float, useful_msec: float, exponent: float)
## The extraction resistance (0..0.9) for the level that was just applied.
signal resistance_changed(resistance: float)

const PRESET_DIRECTORY := "res://resources/difficulty/presets/"
const PRESET_ARGUMENT := "--difficulty-preset="

@export var config: DifficultyConfig

## "default" unless a preset was loaded.
var preset_name: String = "default"

func _ready() -> void:
	var requested := requested_preset_from_arguments(OS.get_cmdline_args() + OS.get_cmdline_user_args())
	if requested != "":
		use_preset(requested)
	print("[difficulty] preset: %s | level 1: peak %.1f%%/tap, useful below %.0f ms, gap %.0f ms, grace %.2fs, decay %.2f%%/s" % [
		preset_name, config.peak_gain_for_level(1), config.min_useful_interval_for_level(1), config.max_interval_for_level(1),
		config.grace_for_level(1), config.decay_for_level(1)])

func apply_for_level(level: int) -> void:
	difficulty_changed.emit(
		level,
		config.peak_gain_for_level(level),
		config.decay_for_level(level),
		config.grace_for_level(level),
	)
	rhythm_changed.emit(config.max_interval_for_level(level))
	speed_changed.emit(config.optimal_interval_msec, config.min_useful_interval_for_level(level), config.gain_curve_exponent)
	resistance_changed.emit(config.resistance_for_level(level))

## Load a preset by name. Returns false (and keeps the current config) if it is not valid.
func use_preset(name: String) -> bool:
	if not is_valid_preset_name(name):
		push_warning("DifficultyManager: invalid preset name '%s'" % name)
		return false
	var path := PRESET_DIRECTORY + name + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("DifficultyManager: no preset '%s' (%s); using '%s'" % [name, path, preset_name])
		return false
	var loaded := load(path)
	if not loaded is DifficultyConfig:
		push_warning("DifficultyManager: '%s' is not a DifficultyConfig" % path)
		return false
	config = loaded
	preset_name = name
	return true

static func is_valid_preset_name(name: String) -> bool:
	if name.is_empty() or name.length() > 40:
		return false
	for i in name.length():
		var c := name.unicode_at(i)
		var ok := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95  # a-z 0-9 _
		if not ok:
			return false
	return true

static func requested_preset_from_arguments(arguments: Array) -> String:
	for argument in arguments:
		var text := str(argument)
		if text.begins_with(PRESET_ARGUMENT):
			return text.substr(PRESET_ARGUMENT.length())
	return ""
