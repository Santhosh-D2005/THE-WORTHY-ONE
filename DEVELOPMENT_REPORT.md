# THE WORTHY ONE - Development Report

Report date: 2026-10-31. This version supersedes the earlier report and reflects the project after
Milestone 1.1 (gameplay validation). Detailed validation results are in `MILESTONE_1_1_TEST_REPORT.md`.
Every test claim below was actually executed; anything not executed is marked as such.

Status legend:
- **[DONE+TESTED]** Fully implemented and tested
- **[DONE, UNTESTED]** Implemented but not tested
- **[PARTIAL]** Partially implemented
- **[NOT DONE]** Not implemented

"Tested" always means **simulated** unless it says otherwise. **No physical Android device has been used for any test.**

---

## 1. PROJECT STATUS

**Current phase:** Phase 1 (foundation) and Phase 2 (core gameplay) are complete for a single playable loop and
have been through an automated validation pass (Milestone 1.1). A first visual pass and a first HUD styling pass
(Phase 4 items) were done early. Phase 3 is only partly done (difficulty curve and timers exist; modes, saving and records do not).
Phases 5 and 6 (online, Android export and device testing) are not started.

**Godot version:** 4.7.2 stable (.NET build, `Godot_v4.7.2-stable_mono_win64`). The project is pure GDScript; the .NET editor binary
is simply what is installed. `project.godot` features: `4.7`, `Mobile`.

**Display / renderer:** Mobile renderer, 1080x1920 portrait base, stretch `canvas_items`, aspect `expand`, portrait orientation.
Mouse-from-touch and touch-from-mouse emulation are both off.

**Main scene:** `res://scenes/main/main.tscn` (the only scene).

**Project structure (files that exist):**
```
project.godot                      README.md
DEVELOPMENT_REPORT.md              MILESTONE_1_1_TEST_REPORT.md
assets/fonts/        Cinzel.ttf, OFL-Cinzel.txt
resources/difficulty/ difficulty_config.gd, default_difficulty.tres
scenes/main/         main.tscn
scripts/core/        game_manager.gd                      (autoload "GameManager")
scripts/gameplay/    input_controller.gd, tap_side.gd, sword_controller.gd, stump_builder.gd,
                     forest_environment.gd, gameplay_camera.gd
scripts/managers/    extraction_manager.gd, difficulty_manager.gd, timer_manager.gd, level_manager.gd
scripts/systems/     material_factory.gd, organic_mesh.gd
scripts/ui/          hud.gd
shaders/             wood_top.gdshader, forest_floor.gdshader
tests/               run_tests.gd, integration_tests.gd/.tscn, playthrough.gd/.tscn
```
Empty folders reserved for later phases: `assets/{models,textures,materials,audio}`, `scenes/{gameplay,environment,ui}`,
`scripts/progression`, `resources/configuration`, `docs`. About 2,500 lines of GDScript including tests.
There is only one scene; most of the 3D world and the HUD are built in code at runtime (see Known Issues).

---

## 2. IMPLEMENTED FEATURES

| Feature | How it works | Files | Status |
|---|---|---|---|
| State machine + level counter | Autoload with states READY / PLAYING / EXTRACTING / PAUSED and signals `state_changed`, `level_changed`, `extraction_succeeded`. Also serves as the game-state manager (no separate script). | `scripts/core/game_manager.gd` | [DONE+TESTED] via integration suite |
| Alternating-tap input | Screen split at half the visible width; a tap counts only if opposite to the last accepted tap; 25 ms debounce measured from the last accepted tap; handles `InputEventScreenTouch` and left mouse button, ignores everything else. | `input_controller.gd`, `tap_side.gd` | Logic and event pipeline [DONE+TESTED] (simulated); physical touch [DONE, UNTESTED] |
| Extraction progress | Single owner of progress, clamped 0-100, gain per valid tap, grace period then decay, completes exactly once. | `extraction_manager.gd` | [DONE+TESTED] |
| Difficulty curve | `DifficultyConfig` resource blends level-1 values to asymptote values with `1 - exp(-(level-1)/ramp_levels)`; level 1 = 8% gain, 5%/s decay, 0.5 s grace. Tuned in `default_difficulty.tres`. | `resources/difficulty/*`, `difficulty_manager.gd` | Curve and per-level application [DONE+TESTED]; balance with real players [NOT TESTED] |
| Level and session timers | Monotonic clock; both start on the first valid tap; level timer stops at extraction and resets; session timer persists; pause freezes both. | `timer_manager.gd` | [DONE+TESTED] |
| Level loop | `LevelManager` wires everything by signals and runs READY -> PLAYING -> EXTRACTING -> next level; handles pause and resume. | `level_manager.gd` | [DONE+TESTED]; real device lifecycle [UNTESTED] |
| Sword behaviour | Height is a direct function of progress (smoothed); per-tap kick; tremble while slipping; extraction animation (pull, spin, carry off); entrance animation (drop-in with `planted` signal); re-entrancy guard on animations. | `sword_controller.gd` | [DONE+TESTED] numerically; "feel" not judged by a player |
| Camera + impact shake | Fixed portrait camera, keep-width FOV, shake on `planted`. | `gameplay_camera.gd` | [DONE+TESTED] visually only |
| Procedural stump, forest, lighting | See section 4. | `stump_builder.gd`, `forest_environment.gd`, `organic_mesh.gd`, `material_factory.gd`, 2 shaders | [DONE+TESTED] by screenshot review |
| HUD | Level, level timer, session timer, progress bar, two tap panels with next-side pulse and flash, hint, success banner, pause overlay; Cinzel font, contrast scrims. All controls ignore the mouse. | `hud.gd` | [DONE+TESTED] by screenshots; pause overlay shown during pause tests but not visually inspected |
| Test tooling | Unit tests, 191-check integration suite, rendered playthrough with screenshots. | `tests/*` | Working |

---

## 3. GAMEPLAY FUNCTIONALITY

| Item | Status | Detail |
|---|---|---|
| Touch controls | **[DONE, UNTESTED]** on a device | `InputEventScreenTouch` handled and tested **only as simulated events** (press accepted, release/drag ignored, multi-touch, boundary, off-screen). Never run on a touchscreen. |
| Mouse fallback | **[DONE+TESTED]** (simulated events) | Left click accepted; right/middle/wheel/motion ignored. Events were synthetic, not from real mouse hardware. |
| Alternating tap validation | **[DONE+TESTED]** | Same-side rejection, alternation, 25 ms debounce anchored to accepted taps (bug fixed), zone boundary at x=540 verified at 0/1/538/539 (left) and 540/541/542/1079 (right). |
| Extraction progress | **[DONE+TESTED]** | +8 per valid tap, invalid taps change nothing, clamped to 0..100 (observed min 0.0, max 100.0), extraction fires exactly once even with 45 taps or direct calls after completion. |
| Progress decay | **[DONE+TESTED]** | No decay inside 0.5 s grace; measured loss 6.57 vs expected 6.57 at 1.81 s; settles at exactly 0. |
| Sword movement | **[DONE+TESTED]** | Height matches progress within 4 mm at six samples; kick identical on every valid tap; decay motion monotonic with max per-frame step 0.0008 and tremble under 1 cm. Judged numerically, not by a player. |
| Extraction animation | **[DONE+TESTED]** | Sword reaches the held pose, returns to exact rest position, flags cleared, `planted` emitted once; no duplicate tweens. Visual smoothness judged from still frames and numbers, not video. |
| Level progression | **[DONE+TESTED]** for levels 1-6 | Six consecutive extractions via simulated touches; level, progress, difficulty values, timers and sword pose verified at each start. Levels above 6 are covered only by curve-math tests. |
| Level timer | **[DONE+TESTED]** | Starts on first valid tap, stops at extraction (stable to 0.5 ms), resets each level, matches wall clock within 0.12 s. |
| Session timer | **[DONE+TESTED]** | Starts on first valid tap, persists across levels, includes the success animation time (by design), frozen by pause. |
| Pause / resume | **[DONE+TESTED]** as *simulated* notifications only | Focus-out, repeated notifications, resume by tap, pause before first tap and during the success animation all pass. That Android actually delivers these notifications is **untested**. |
| Game modes (Endless / Ruthless) | **[NOT DONE]** | One implicit endless-style loop with no saving and no fail condition. |
| Fail condition / run failure | **[NOT DONE]** | The player cannot lose. |
| Save data / personal records | **[NOT DONE]** | Nothing persists; no personal best on the HUD. |
| Difficulty "timing precision / recovery" | **[NOT DONE]** | Only gain, decay and grace scale with level. |

---

## 4. VISUAL IMPLEMENTATION

All 3D visuals are **procedural placeholders generated in code**. None is a finished realistic asset.

| Area | Honest quality assessment | Actual vs placeholder |
|---|---|---|
| Tree stump | Convincing silhouette at gameplay distance: irregular furrowed bark, buttress and ground roots, freshly cut top with rings, cracks and a sword slot, moss, contact shadow. Close up, bark looks fur-like, roots are smooth tubes, moss looks like blobs. | Placeholder (generated mesh + noise materials) |
| Sword | Faceted blade with fuller, swept gold guard, wrapped grip, pommel; plausible proportions. Guard and grip are simple primitives; metal relies on sky reflection only so it does not look like real steel. | Placeholder |
| Forest | Irregular trunks in two depth layers, undulating floor shader, bent grass blades. No canopy, no leaf-litter objects, no ferns; trunks repeat two materials. | Placeholder |
| Materials / textures | `NoiseTexture2D` + `FastNoiseLite` albedo and normal maps and two custom shaders. No scanned/PBR texture sets. Normal-map tangent handedness was not verified. | Placeholder |
| Lighting | One shadowed warm sun, sky ambient and reflection, ACES tonemap, light fog; dappled shadows from invisible shadow-only blobs. Moody and coherent. No sun shafts or GI. | Real settings, placeholder canopy |
| Camera | Portrait, stump and sword central with headroom for the pull. Static apart from impact shake. | Adequate for this stage |
| UI | Cinzel font, scrims, rounded translucent panels, custom progress bar. Clean and minimal; only the gameplay screen exists. | Font is a **real asset**; the UI itself is a first pass |

Real (non-placeholder) assets in the project: **the Cinzel font only** (SIL OFL, licence file included).

---

## 5. TECHNICAL VALIDATION

Executed on the current files:
- `godot --headless --import`: no errors or warnings.
- `godot --headless --path . --quit-after 120` (loads and runs the main scene): no errors or warnings (dummy renderer, so rendering is not validated by this run).
- `tests/run_tests.gd` (unit): ALL PASSED (21 checks).
- `tests/integration_tests.tscn` (windowed): 191/191 passed in 3 consecutive runs after the harness was hardened; see section 6 for the full run history.

| Check | Result |
|---|---|
| GDScript parse errors | None reported by Godot |
| Scene loading errors | None observed |
| Missing resources | None observed (font, shaders, `.tres` all load) |
| Broken node references | None observed at runtime. `level_manager.gd` uses hard-coded `$` paths into `main.tscn`, which is fragile if the scene is restructured |
| Runtime errors | None in the runs above. Two `push_warning` lines appear in the integration log on purpose (the duplicate-animation guard being exercised) |
| Performance | **Not measured on any mobile device.** Incidental data point: in a 540x960 window on an Intel UHD desktop GPU, about 220 frames were rendered in 1.5 s while sampling (roughly 140 fps average, with occasional hitches up to ~50 ms). That says nothing reliable about phones |

Performance concerns (from reading the scene, unverified): about 46 separate background trunk meshes plus roots, ~26 moss meshes and ~22
shadow-only blobs, probably 100+ draw calls; a heavy procedural build at startup (stump normals, 46 trunks, terrain, four noise textures),
load time not measured; real-time soft shadows from one light; grass is one `MultiMesh` draw call.

---

## 6. TESTING RESULTS (tests actually executed)

**A. Unit tests** - `godot --headless -s tests/run_tests.gd` - **21 checks, all pass**: ExtractionManager (7), DifficultyConfig (6), InputController (3), TimerManager (5).

**B. Integration suite** - `tests/integration_tests.tscn`, windowed 540x960, real `main.tscn`, events fed through `Input.parse_input_event()`:
**191 checks: Input 35, Extraction 14, Sword 21, Level transitions 95, Timers/pause 26.**
- Final result: **191 passed, 0 failed, 0 inconclusive in 3 of 3 runs** after the harness was hardened (about 107 s each).
- Run history: it found 2 real bugs (both fixed, section 8). After those fixes, 8 runs gave 6 outright passes and 2 runs with one unrelated failure each
  (machine latency; real OS window-focus loss pausing the game). The harness was then hardened (focus-loss detection and recovery, latency-aware
  "same instant" tests) and the next 3 runs passed. In total 9 of the last 11 runs passed outright; the other 2 were traced to the test environment.
- Lifecycle events are simulated with engine notifications; they do not prove Android delivers them.

**C. Rendered playthrough** - `tests/playthrough.tscn` - ran many times during the visual and fix work; used for screenshot review of start, mid-pull, success and level 2.

**D. Visual review** - screenshots reviewed by me at 540x960 only.

**Not executed:** any physical Android touch or lifecycle test; Android export; any device performance or memory profiling; other aspect ratios or screen sizes;
play beyond level 6; slow or irregular or very fast real tapping; long sessions; a human playtest of balance and feel; audio (none exists).

---

## 7. KNOWN ISSUES AND LIMITATIONS

Functional:
1. No game modes, saving, records, fail state, menus, settings, audio or leaderboard. The player cannot lose, so Ruthless cannot be built yet.
2. Pause also triggers on desktop window focus loss (by design), so clicking another window pauses the game; the next tap only resumes.
3. Two fingers landing within 25 ms count as one tap even on opposite sides (by design). Whether 25 ms suits real hardware is unknown.
4. The session timer includes the success animation, so it exceeds the sum of level times (by design).
5. The resume tap is swallowed and resets alternation (by design).
6. `LevelManager._start_level_sequence(first_level)` has an unused parameter and `_on_state_changed` ignores its argument (cosmetic).

Visual / UX:
7. The pre-start hint still reads "TAP LEFT - RIGHT - LEFT - RIGHT" (an intended wording change did not apply) and is low contrast over the stump base.
8. The tap panels and progress bar overlap the lower stump and roots (translucent, but they cover part of the scene).
9. The sword is nearly edge-on for part of its spin in the success animation; the banner overlaps the rising sword.
10. Bark is fur-like up close, moss blobby, roots smooth, two background bark materials repeat; the metal does not look like real steel.

Technical / process:
11. Nearly the whole scene and HUD are generated in `_ready()`, so they cannot be edited in the Godot editor, and startup cost grows with detail.
12. Hard-coded node paths in `LevelManager`.
13. No version control: not a git repository.
14. The integration suite needs an interactive window and is sensitive to focus theft (detected and reported, exit code 2 if it invalidates a run).
15. Two assertions are loose on purpose ("timer value at pause is sane" allows 0.1 s; "resume tap added no progress" allows a decrease).
16. A Godot editor (a separate non-.NET build) is open on this project on this machine and rewrote `project.godot` into its own format earlier; contents are unchanged.

---

## 8. MODIFIED FILES

The project folder was empty at the start, so every file is new. Files marked "rewritten" were replaced during the visual pass at the same path.

| File | Purpose / history |
|---|---|
| `project.godot` | Portrait 1080x1920, Mobile renderer, stretch, `GameManager` autoload, emulation off |
| `scenes/main/main.tscn` | The only scene: managers, `Stage` (forest, stump, sword, camera), `Hud` |
| `scripts/core/game_manager.gd` | State machine and level counter |
| `scripts/gameplay/input_controller.gd` | Alternating-tap input. **Fixed in 1.1:** debounce anchored to accepted taps |
| `scripts/gameplay/tap_side.gd` | Shared left/right enum (works around a GDScript self-enum issue) |
| `scripts/gameplay/sword_controller.gd` | Sword model, motion and animations. Visual pass rewrote the model; **fixed in 1.1:** re-entrancy guard on animations |
| `scripts/gameplay/stump_builder.gd` | Stump, roots, moss, grass, contact shadow (rewritten in the visual pass) |
| `scripts/gameplay/forest_environment.gd` | Sky, fog, sun, terrain, trunks, canopy shadow casters (rewritten) |
| `scripts/gameplay/gameplay_camera.gd` | Portrait camera and shake (framing values tuned) |
| `scripts/managers/extraction_manager.gd` | Progress, decay, completion |
| `scripts/managers/difficulty_manager.gd` | Level to tuning values |
| `scripts/managers/timer_manager.gd` | Level and session timers |
| `scripts/managers/level_manager.gd` | Wiring, level loop, pause and resume |
| `scripts/systems/material_factory.gd` | Placeholder materials (rewritten) |
| `scripts/systems/organic_mesh.gd` | Procedural trunk, root tube and terrain meshes (new in the visual pass) |
| `scripts/ui/hud.gd` | Gameplay HUD (restyled in the visual pass) |
| `resources/difficulty/difficulty_config.gd`, `default_difficulty.tres` | Tunable difficulty curve |
| `shaders/wood_top.gdshader`, `shaders/forest_floor.gdshader` | Cut-face rings and cracks; world-space forest floor |
| `assets/fonts/Cinzel.ttf`, `OFL-Cinzel.txt` | Downloaded UI font and its licence |
| `tests/run_tests.gd` | Unit tests |
| `tests/integration_tests.gd`, `.tscn` | 191-check simulated-input integration suite (new in 1.1) |
| `tests/playthrough.gd`, `.tscn` | Rendered smoke test with screenshots |
| `README.md` | Run, test and tuning notes and the placeholder table |
| `DEVELOPMENT_REPORT.md`, `MILESTONE_1_1_TEST_REPORT.md` | This report and the Milestone 1.1 validation report |

**Deleted:** nothing was deleted from the project except first versions of `stump_builder.gd` and `forest_environment.gd`, which were removed and re-created at the same paths.
**Not changed since the visual pass** (apart from the two fixes above): all gameplay manager scripts, `main.tscn`, `project.godot`, and all visual and environment code.
This report was produced without changing any gameplay code.

---

## 9. NEXT DEVELOPMENT RECOMMENDATIONS (priority order)

1. **Test on a real Android device**: export preset, real touch and multi-touch, the 25 ms debounce under real fast tapping, safe areas and gesture zones near the bottom tap panels, backgrounding, frame rate. Nothing mobile-specific is verified.
2. **Define and build a fail condition, then Endless and Ruthless modes** and the run-failure screen. Decide the rule first (for example progress hitting zero after starting, or a per-level time limit).
3. **SaveManager and personal records** (versioned save, corrupt-data handling), then show personal best on the HUD.
4. **Menus and screens** (splash, main menu, mode select, pause, records, settings) as separate scenes under `scenes/ui/`.
5. **Audio architecture** with placeholder sounds first (tap, creak, tension, release, failure, UI) and separate music/SFX volume. Audio is a core pillar and is entirely absent.
6. **Performance pass**: profile draw calls and load time, merge or instance background trunks, consider baking generated meshes, add a low-quality setting.
7. **Replace placeholder art** with sculpted or scanned stump, sword and trunks and real PBR textures; the README table lists the integration points.
8. **Tune feel with real play**: gain, decay and grace values, kick strength, animation timing, haptics.
9. **Housekeeping**: initialise git with a `.gitignore` (`.godot/`), move generated content toward editable scenes where practical, add multi-aspect-ratio tests, fix the hint text and HUD overlap, tighten the two loose test assertions.

---

## 10. OVERALL ASSESSMENT

Target: 9.5/10 indie mobile game. The scores below are subjective estimates of the **current milestone**, not guarantees.

| Criterion | Estimate | Reason |
|---|---|---|
| Gameplay responsiveness | 6/10 | Logic is sound and now well tested in simulation; never felt on a phone; no haptics or audio feedback |
| Visual quality | 5/10 | Moody, coherent composition, but clearly procedural; far from premium cinematic realism |
| Animation quality | 4/10 | Functional and verified tweens; success sequence is basic |
| Audio quality | 0/10 | Not implemented |
| Difficulty balance | 3/10 | Reasonable curve on paper and verified over six levels; no human playtest |
| Replayability | 1/10 | No modes, records, failure or goals beyond an endless loop that cannot be lost |
| UI clarity | 6/10 | Readable and minimal; only one screen exists |
| Performance | unknown | Not measured on any mobile hardware |
| Stability | 6/10 | 191 simulated checks pass repeatedly, no runtime errors seen; real device and lifecycle untested |

**Overall: roughly 3-4 / 10 as a product**, unchanged in headline from the previous report even though confidence in the core loop is much higher.
What improved: the core loop is now backed by an automated suite that found and drove two fixes, which is a sound foundation to build on.
What has not changed: the gap to 9.5 is mostly in untouched areas (audio, modes, records, fail condition, menus, device validation) and in
replacing procedural placeholders with real assets. A claim of "complete" or "release-ready" would not be honest.
