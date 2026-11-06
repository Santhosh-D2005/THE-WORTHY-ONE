class_name GameMode
extends RefCounted
## The two ways to play. ENDLESS: no ceiling, a failed extraction ends the run, the best is kept. RUTHLESS: the same, but leaving the
## foreground (Home, app switch, screen lock) ends the run at once and an unfinished run can never be resumed. Each mode has its own
## record and its own Hall of Fame; they never share data.

enum Mode { ENDLESS, RUTHLESS }

const ENDLESS_DIFFICULTY := "res://resources/difficulty/default_difficulty.tres"
const RUTHLESS_DIFFICULTY := "res://resources/difficulty/ruthless_difficulty.tres"

## The key used in the save file and in the online API ("endless" / "ruthless").
static func key(mode: Mode) -> String:
	return "ruthless" if mode == Mode.RUTHLESS else "endless"

static func from_key(text: String) -> Mode:
	return Mode.RUTHLESS if text == "ruthless" else Mode.ENDLESS

static func title(mode: Mode) -> String:
	return "RUTHLESS" if mode == Mode.RUTHLESS else "ENDLESS"

static func difficulty_path(mode: Mode) -> String:
	return RUTHLESS_DIFFICULTY if mode == Mode.RUTHLESS else ENDLESS_DIFFICULTY

## Does leaving the foreground end the run?
static func ends_run_on_background(mode: Mode) -> bool:
	return mode == Mode.RUTHLESS
