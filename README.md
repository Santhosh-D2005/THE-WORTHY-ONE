# THE WORTHY ONE

One sword. One tree. One challenge. (Godot 4.7, GDScript, Mobile renderer, portrait 1080x1920)

## Run
- Editor: open this folder in Godot 4.7.x and press F5 (main scene: `scenes/main/main.tscn`).
- Desktop testing: click the left / right half of the window alternately (mouse fallback).
- Android: touch the left / right half of the screen alternately.

## Tests
```
godot --headless --path . -s res://tests/run_tests.gd        # logic tests (exit code 1 on failure)
godot --path . res://tests/playthrough.tscn -- <out_dir>     # rendered smoke test + screenshots
godot --path . res://tests/integration_tests.tscn           # 191 simulated-input gameplay checks (opens a 540x960 window, ~110 s; do not click other windows; exit 0 pass / 1 fail / 2 invalid run)
godot --path . res://tests/failure_tests.tscn               # 102 failure-system checks (opens a 540x960 window, ~2 min, same exit codes)
godot --path . res://tests/layout_tests.tscn [-- <dir>]      # 256 layout checks at 7 window sizes + screenshots (~80 s)
```

## Tuning
Gameplay numbers live in `resources/difficulty/default_difficulty.tres` (level-1 values, asymptote
values, curve speed). `InputController.min_tap_interval_msec` controls double-tap debounce.

## Structure
- `scripts/core/game_manager.gd` - autoload: state machine + level counter
- `scripts/managers/` - ExtractionManager, DifficultyManager, TimerManager, LevelManager (orchestrator)
- `scripts/gameplay/` - InputController, SwordController, StumpBuilder, ForestEnvironment, camera
- `scripts/systems/material_factory.gd` - all placeholder materials in one place
- `scripts/ui/hud.gd` - gameplay HUD

## Placeholder assets (still procedural, none are final art)
| Item | Now | Replace with |
|---|---|---|
| Stump, roots, background trunks | Generated meshes (`OrganicMesh`, `StumpBuilder`): furrowed irregular bark, buttress + ground roots, cut face | Sculpted / photoscanned Blender models; keep cut face at y = `STUMP_TOP_Y` |
| Sword | Generated faceted blade + primitive guard/grip (`SwordController`) | Modelled sword, origin at the blade tip |
| Bark / wood / floor / moss materials | Noise textures + `wood_top.gdshader`, `forest_floor.gdshader` | Real PBR texture sets |
| Grass | Instanced bent blades | Authored vegetation cards |
| Canopy / dappled light | Invisible shadow-only blobs along the sun ray | Real canopy geometry or baked light cookies |
| Audio | None yet | Forest ambience, wood creak, metal scrape, tap, tension loop, release, failure, UI |
| Font | Cinzel (SIL OFL, `assets/fonts/`) - final | - |

## Not implemented yet (later phases)
Menus and screens, Endless / Ruthless modes, save data and records, audio, failure screen,
leaderboard (interface + local mock), settings, Android export preset.

## Android and playtesting
- `docs/ANDROID_EXPORT.md` - export settings, requirements, install/run commands, known risks
- `docs/PLAYTEST_PRESETS.md` - difficulty presets (`--difficulty-preset=<name>`) with level-1 numbers
- Export preset: `export_presets.cfg` ("Android"). Output: `build/android/TheWorthyOne-debug.apk`
