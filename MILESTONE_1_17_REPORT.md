# THE WORTHY ONE – Milestone 1.17 Report: Menu, UI and Icon Review

**Status: PASS WITH FIXES.** Two small presentation defects were found and fixed. Version stays 0.1.9 (code 7), package `com.theworthyone.game`. No gameplay script, mechanic, package ID, version or export setting was changed. The core game was not played or tested.

## What was verified, and how

| Kind of check | Done? |
|---|---|
| Automated focused tests (desktop, simulated input) | Yes |
| Desktop screenshot review (360×800, the phone's 9:20 shape) | Yes |
| Physical phone: install, launch, main-menu screenshot, Android Back | Yes (menu only) |
| Physical phone: pause menu, failure screen, completion card, touch feel | **No** (they need the game running; out of scope) |
| Launcher icon / themed icon seen on the phone | **No** |

The phone was awake and not locked for every step (checked before each capture). I never opened the lock screen, the home screen or the app drawer, because they may show personal content. I did not press PLAY.

## 1. Screens reviewed

Main menu, pause menu, focus-loss "tap to resume" overlay, failure screen and the extraction completion card. The desktop screenshots were taken with the existing tools (`tools/menu_shot`, `tools/ui_shots`); the failure screen and card were displayed by the tool calling the UI directly, not by playing the game.

- **Main menu:** title, tagline, PLAY and QUIT readable, no overlap or clipping, consistent button styling. Also checked on the physical phone (see section 6).
- **Pause menu:** PAUSED heading and divider aligned, RESUME clearly primary, MAIN MENU secondary, no clipping.
- **Failure screen:** heading, subtitle, statistics inside their panel, TRY AGAIN wider than MAIN MENU, no stray colours, no overlap.
- **Completion card:** wording and extraction time unchanged and readable; no clipping or overflow.

## 2. Icon assets and APK configuration

- `assets/branding/`: `icon_192.png` (192×192), `icon_512.png` (512×512), `icon_adaptive_foreground_432.png`, `icon_adaptive_background_432.png`, `icon_adaptive_monochrome_432.png` (all 432×432). The foreground artwork occupies pixels 125–307 × 101–340 and the monochrome artwork 138–294 × 101–327, both inside Android's central adaptive safe zone (72–360).
- `project.godot`: `config/icon` is `res://assets/branding/icon_512.png`; start scene is `res://scenes/ui/main_menu.tscn`.
- `export_presets.cfg`: the four `launcher_icons/*` fields (main 192, adaptive foreground, background, monochrome) point at those files.
- **In the exported APK:** 24 launcher files (`icon.webp`, `icon_foreground.webp`, `icon_background.webp`, `icon_monochrome.webp`, six densities each) and the main-menu scene are present. They are byte-identical to the 1.16 build, as expected, since no icon was changed.
- I did **not** assume Android themed icons are enabled on the phone, and I did **not** view the launcher or a themed icon on the phone.
- No icon defect was found, so the icon was not redesigned.

## 3. Defects found and fixes

1. **Completion card, "N SWORDS EXTRACTED" line:** over the bright sky it measured about 3.6:1 contrast (30 px, 72 % opacity), low for small text. Fix: full parchment at 32 px (`scripts/ui/hud.gd`). Re-measured at about 4.4:1. The measurement is approximate (text and background luminance sampled from a screenshot), not a formal audit.
2. **Focus-loss "PAUSED / TAP TO RESUME" overlay:** the text was centred and lay across the sword and stump. Fix: it now sits at the pause menu's heading position, above the stump (`scripts/ui/hud.gd`).

Remaining borderline item, left as is: the "LEVEL n COMPLETE" line (larger gold text) measures about 3.4:1, which passes the 3:1 threshold for large text but is not high. It needs a look on the phone.

## 4. Focused tests (desktop)

| Suite | Result |
|---|---|
| UI tests | 106 checks, 0 failed |
| Menu tests | 55 checks, 0 failed |
| Pause tests | 42 checks, 0 failed |
| Layout tests | 256 checks, 0 failed |

The gameplay suites (unit, rhythm, speed, timer, extraction, experience, fx) were not run. No test was changed or weakened.

## 5. Screenshots reviewed

Yes. Desktop: `build/shots/r17_strip.png` (menu, card, pause menu, overlay, failure screen), `r17b_pair.png` (overlay and card after the first fix), `r17c_card_zoom.png` (card after the final fix). Physical phone: `build/shots/r17_phone_menu.png`.

## 6. Physical device

A vivo V2129 was connected and authorized, and was actually used:
- Installed the new APK (`adb install -r -d`). The installed package reports version 0.1.9, code 7.
- Launched the app: it opens directly on the main menu.
- Reviewed the phone screenshot (720×1600): title, tagline, stump with faint cracks, PLAY and QUIT all render as designed, nothing clipped or overlapping.
- Pressed Android Back on the menu: the app process ended (as designed).
- No debug files were left in the app's data (only `shader_cache` and `vulkan`).

Not verified on the phone: real touch feel and touch-target comfort, the pause menu, failure screen and completion card, the overlay fix, the launcher icon and the themed icon.

## 7. New APK

Generated: `D:\photos\gamic\THE WORTHY ONE\build\android\TheWorthyOne-debug.apk`, **36,400,247 bytes**. Exported to a temporary file first and swapped in afterwards. The size is exactly the same as the 1.16 APK, which I checked is a coincidence: the compiled `hud.gdc` inside the new package differs from the 1.16 one.

Previous builds kept: `TheWorthyOne-debug-1.16.apk` (36,400,247 bytes), `TheWorthyOne-debug-1.15.apk` (36,383,103 bytes), `TheWorthyOne-debug-before-1.15.apk` (36,090,625 bytes).

## 8. Remaining issues and manual checks

- Look at the pause menu, failure screen, completion card and the "tap to resume" overlay on the phone (this needs the game running).
- Judge the card's "LEVEL n COMPLETE" contrast by eye on the phone.
- Check the launcher icon, and the themed icon if Android themed icons are turned on.
- Feel the PLAY and QUIT touch targets with a real finger.
