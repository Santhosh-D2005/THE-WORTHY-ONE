class_name GameplayConfig
extends Resource
## Gameplay settings that are not difficulty (see DifficultyConfig for gain / decay / grace).
## Edit resources/configuration/default_gameplay.tres, or the "Gameplay Config" property of the
## Main node, to tune these without touching any script.

## After TRY AGAIN, gameplay taps are ignored for this long. It protects against the extra
## taps of a double-press starting the next attempt by accident. 0 disables the lock.
@export_range(0.0, 3.0, 0.05) var retry_input_lock_seconds: float = 0.4

## Minimum tapping speed. When false every accepted alternating tap awards progress (the old behaviour).
@export var rhythm_enabled: bool = true
## 0 = the allowed tap interval follows the level (DifficultyConfig). A value > 0 forces that many
## milliseconds for every level (designer / test override; independent of level difficulty).
@export_range(0, 2000, 10) var max_tap_interval_override_msec: int = 0

## When true, QUIT in the pause menu needs a second press ("CONFIRM QUIT?") while a run is in
## progress (the session timer has started). Off today; intended for a future Ruthless mode,
## where abandoning a run must not be one accidental tap.
@export var confirm_quit_during_run: bool = false
