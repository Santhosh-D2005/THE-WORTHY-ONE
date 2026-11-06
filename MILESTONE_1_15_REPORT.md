# THE WORTHY ONE – Milestone 1.15 Report: Main Menu and Visual Identity

Version stays **0.1.9 (code 7)**, package `com.theworthyone.game` (unchanged). Gameplay rules, difficulty, timers, failure conditions and the 1.10–1.14 effects were not changed.

**Read this first.** Everything below was checked on the **desktop** (automated tests and my own look at screenshots). **The new APK was exported but NOT installed or run on the phone.** No phone screenshot, FPS or touch test of the menu exists, and no person has used it.

## 1. Visual direction

A quiet, dark, ancient-forest opening shot that reuses the game itself: the real clearing (forest, fog, sun), the real stump and the real sword, framed so the stump sits between the title and the buttons. The cracks in the stump hold a faint, still amber glow (the 1.12/1.13 shader at a fixed low level) as the one gold accent in the scene. Palette: deep forest green and near-black, muted parchment text, amber-gold only for the "THE" line, the divider, the PLAY border and the crack glow. Typography is the game's existing Cinzel font (already used in the HUD, failure screen and pause menu). No bloom, no particles, no new post-processing, no extra lights.

Layout (top to bottom): small gold "THE", large parchment "WORTHY ONE", a thin gold divider, the subtitle "One sword. One tree. One challenge." (the project's own tagline), the 3D scene, a large PLAY button, a smaller QUIT button. Dark top and bottom gradients keep text readable over bark and sky.

## 2. Files and scenes

Created:
- `scenes/ui/main_menu.tscn`: the menu scene (3D backdrop nodes + the menu script).
- `scripts/ui/main_menu.gd`: menu logic and UI, built in code like the other screens (anchors, no hard-coded desktop coordinates).
- `assets/branding/icon_192.png`, `icon_512.png`, `icon_adaptive_foreground_432.png`, `icon_adaptive_background_432.png`: the new icon.
- `tests/menu_tests.gd/.tscn`: focused menu test (55 checks).
- `tools/menu_shot.gd/.tscn`: saves a menu screenshot at a chosen window size.
- `build/export_presets_before_1_15.cfg`: backup of the export presets before I changed them.

Modified:
- `project.godot`: start scene is now the main menu; project icon is `assets/branding/icon_512.png` (the old `icon.svg` file is untouched).
- `export_presets.cfg`: the three launcher-icon fields now point at the new icon files (version, code and package unchanged).
- `tests/pause_tests.gd`, `tests/failure_tests.gd`: adapted to the new rule (section 6).

Not touched: `scenes/main/main.tscn`, the gameplay scripts, the HUD.

## 3. Main menu features

- **Title** large and readable; the test checks the title text fits the screen width at five screen shapes.
- **Backdrop** is the game's own scene; one extra, very slow and tiny sideways camera drift (a single transform per frame). No expensive effects were added.
- **PLAY** is the largest control (620×150 base px, amber border). It starts the game scene; the gameplay scene is preloaded on a background thread while the menu is open so the switch is quick. A fresh run starts in the game's own startup (the existing `LevelManager`), so no duplicate managers or timers are created by the menu.
- **QUIT** leaves the app. **Android Back** on the menu also leaves the app (and Escape on the desktop), because the menu is the first screen. `config/quit_on_go_back` stays false.
- **Button feedback**: the existing hover/pressed colour styles, plus a short 0.08 s dip to 97 % on touch. Nothing bounces or loops.
- **Double-launch protection**: one guard covers touch, mouse, double taps and Back; after PLAY, QUIT and Back do nothing. Presses during the 0.55 s fade-in are ignored, so a stray tap while the app opens cannot start a game.
- **Fade** from black on opening and to black when leaving (0.9 s and 0.35 s).
- **Safe area**: the title block moves down by the top inset and the buttons move up by the bottom inset (same helper the failure screen uses).
- The menu un-pauses the tree on arrival, so coming from the game's pause menu never leaves it frozen.

## 4. Settings and navigation

**There is no Settings screen, on purpose.** The project has no audio files and no haptics code, and no real setting to expose; a volume or vibration toggle would do nothing. Graphics quality presets exist in code but changing them risks the phone's 60 FPS cliff, so I did not expose them. This is documented as a follow-up: add Settings when audio assets or haptics exist.

Navigation now works end to end:
- App start → main menu → PLAY → game.
- Game: Android Back opens the pause menu (unchanged); its QUIT now returns to the **main menu** (before: it ended the app, because no menu existed). The failure screen's MAIN MENU button, which used to be shown disabled, is now enabled and returns to the menu.
- Main menu → Back or QUIT → app closes.

## 5. Icon and logo status

The old icon was a labelled placeholder SVG and the Android launcher icon fields were empty. I drew one new direction: a sword embedded in a stump with amber cracks, on a dark forest green with a soft haze behind the blade, legible at 48 px (checked in a preview). I produced a 192 px legacy icon plus 432 px adaptive foreground and background layers (content inside the adaptive safe zone) and a 512 px project icon. Original `icon.svg` is preserved.

Verified in the exported APK (by comparing the package contents with the previous APK): the launcher files `res/mipmap-*/icon.webp`, `icon_foreground.webp` and `icon_background.webp` at every density, and the boot-splash image, are different from the previous build. The **monochrome** (themed-icon) layer was not made and is unchanged from the engine default. **I have not seen the icon on the phone's home screen**, so I do not claim how it looks there.

## 6. Focused tests (all desktop, simulated input)

| Check | Result |
|---|---|
| New menu test (structure, layout at 540×960, 540×1200, 360×800, 720×1600, 800×1000, touch targets, safe area, PLAY once, QUIT/Back, hand-over, cleanup) | 55 checks, 0 failed |
| Startup tests (project load, start scene) | 16 checks, 0 failed |
| Pause tests (QUIT / Back path changed by the menu) | 42 checks, 0 failed |
| Failure tests (MAIN MENU button now enabled) | 117 checks, 0 failed |
| Layout tests (HUD, failure screen) | 256 checks, 0 failed (run once before the final menu button-size tweak; the tweak touches only the menu) |
| Asset import / project load | Godot `--import` ran cleanly, no script errors |
| APK export | succeeded |

The core gameplay suites (unit, rhythm, speed, extraction, timer, experience, fx) were **not** re-run, as you asked, because no gameplay code changed.

**Existing checks I had to change, and why.** They encoded "no main menu exists yet", which this milestone deliberately makes false; I kept every assertion's intent:
- Pause tests: QUIT used to be counted through the app-quit hook; it now leaves via the scene change to the menu. The same hook counts both, so the "once", "no repeat on second press" and two-step confirmation checks are unchanged, and I added a check that the destination is the real menu scene.
- Failure tests: "no menu scene exists / MAIN MENU is dimmed and does nothing" now points the button at a scene path that does not exist, so the disabled behaviour is still tested; I added checks that the real scene exists and the button is enabled by default.

**One failed first run of my own new test** (touch targets): I had measured the target size as a share of view height, which is wrong on tall phones. Physical size follows the width, so I changed the check to 48 dp (120 base px) and **enlarged QUIT from 100 to 120 px** to meet it, rather than loosening the check.

**Visual inspection (desktop screenshots, not automated):** `build/shots/menu1.png` (540×960), `menu2.png` (360×800), `icon_preview.png`. The composition looked balanced and legible at both shapes.

## 7. Known limitations

- Not installed or run on the phone: real touch behaviour, fade timing, scene-switch time, FPS and memory of the menu, and the on-device icon are all unverified.
- The menu draws the full forest scene, so it costs about what the game's idle state costs; it was not measured on the phone. The scene switch loads the forest a second time (the preload covers the scene file, not the world building), so a short stall at PLAY is possible on the phone.
- No Settings screen (see section 4).
- No themed (monochrome) launcher icon.
- Screenshots were taken with the desktop renderer at small sizes; fonts and gradients may look slightly different on the phone's upscaled 3D image.
- The title uses the existing Cinzel font; I did not check its glyph coverage beyond the text used.

## 8. APK

- Path: `D:\photos\gamic\THE WORTHY ONE\build\android\TheWorthyOne-debug.apk`
- Size: 36,383,103 bytes. Debug build, signed with the existing debug configuration.
- Version name 0.1.9, version code 7 (from the unchanged export preset); package `com.theworthyone.game`.
- Export succeeded. I exported to a temporary file first, checked it contained the menu scene and the new icon files, then swapped it in.
- The previous APK is kept as `TheWorthyOne-debug-before-1.15.apk` (36,090,625 bytes).
- **Not installed or launched on the physical phone.**

## 9. Final classification

**READY FOR VISUAL REVIEW**, for the desktop screenshots and automated checks only. Reviewing the menu and the icon on the actual phone is still required before treating the look as approved.
