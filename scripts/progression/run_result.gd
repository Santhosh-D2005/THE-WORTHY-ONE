class_name RunResult
extends RefCounted
## Facts about one finished run, captured at the moment it ended.
##
## Deliberately contains ONLY values the game really measured. There are no lifetime totals,
## personal bests or rankings here: those need the (not yet built) save system, and showing
## invented numbers would be wrong. When SaveManager exists it should consume this object.

enum EndReason { FAILURE, INVALIDATED, COMPLETED }

var end_reason: EndReason = EndReason.FAILURE
## Which mode the run was played in (Endless unless the player chose Ruthless).
var mode: GameMode.Mode = GameMode.Mode.ENDLESS
## The highest level the player actually COMPLETED in this run (level_reached - 1 after a failure; the failed level never counts).
var completed_level: int = 0
## The level the player was on when the run ended (the level they failed to finish).
var level_reached: int = 1
## Final session time, frozen at the instant of failure.
var session_seconds: float = 0.0
## Time spent on the unfinished level before it failed.
var final_level_seconds: float = 0.0
## Swords successfully extracted during THIS run (not a lifetime count).
var extractions: int = 0

func to_dictionary() -> Dictionary:
	return {
		"end_reason": end_reason,
		"mode": GameMode.key(mode),
		"completed_level": completed_level,
		"level_reached": level_reached,
		"session_seconds": session_seconds,
		"final_level_seconds": final_level_seconds,
		"extractions": extractions,
	}

## m:ss.cc, matching the HUD timers.
static func format_time(seconds: float) -> String:
	var whole_minutes := int(seconds) / 60
	var remainder := seconds - whole_minutes * 60
	return "%d:%05.2f" % [whole_minutes, remainder]
