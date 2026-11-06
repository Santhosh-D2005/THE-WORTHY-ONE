# THE WORTHY ONE – Milestone 1.16 Report: Unified UI Polish

Version stays **0.1.9 (code 7)**, package `com.theworthyone.game` (unchanged). No gameplay rule, timer, difficulty, progress formula, failure condition or input logic was changed.

**Read this first.** Everything was checked on the **desktop**: automated layout/behaviour tests, and my own look at desktop screenshots. **The new APK was exported but NOT installed or run on the phone.** Nothing here has been seen on the physical screen, and no person has used it.

## 1. Summary of changes

- One shared styling helper, `UiStyle`, now defines the palette, the type scale, the button look, panels, dividers, scrims, the vignette and the font for every screen. The HUD, main menu, pause menu and failure screen all build from it (before, the same colours and the label/button builders were copy-pasted in four files).
- Pause menu restyled: clear PAUSED heading with an amber divider, RESUME as the primary button, **MAIN MENU** as the secondary button (it was labelled QUIT, but since 1.15 it returns to the main menu, so the label now says so), darkened clearing with a soft vignette.
- Failure screen polished: the statistics now sit in one quiet panel, a calm line "THE WOOD HOLDS FAST" sits under the heading, TRY AGAIN is wider than MAIN MENU. No red, no flashing.
- Completion card: wording unchanged; the extraction time is now the headline figure (larger type) and the swords-extracted line is slightly larger and clearer.
- HUD: moved onto the shared palette/label/scrim helpers with no layout change; the "tap to resume" overlay (shown after losing app focus) now uses the same heading and hint typography as the pause menu.
- Monochrome (themed) launcher icon layer added.

## 2. Files and scenes

Created: `scripts/ui/ui_style.gd`, `tests/ui_tests.gd/.tscn` (106 checks), `tools/ui_shots.gd/.tscn` (screenshots of the card, pause menu, focus-loss pause, failure screen), `assets/branding/icon_adaptive_monochrome_432.png`.

Modified: `scripts/ui/pause_menu.gd` (restyled; same signals, accessors and node names), `scripts/ui/failure_screen.gd` (style helpers, panel, subtitle), `scripts/ui/hud.gd` (shared helpers, pause overlay, card type sizes), `scripts/ui/main_menu.gd` (moved onto the shared helpers; same look), `export_presets.cfg` (monochrome icon path only), `tests/pause_tests.gd` (three label strings; see section 5).

Not touched: `scenes/main/main.tscn`, the failure-screen and menu scene files, all gameplay scripts.

## 3. Improvements to each screen

- **Pause menu:** heading 72 px amber, divider, RESUME 150 px primary, MAIN MENU 120 px secondary (48 dp touch targets), confirmation text "LEAVE THIS RUN?" when that option is on. Pause/resume behaviour, the 350 ms press guard and the touch handling are unchanged.
- **Failure screen:** same heading, divider and stats as before, plus the statistics panel, the subtitle, and a wider primary button. Safe-area shifting now covers the new subtitle and panel. Retry and MAIN MENU logic untouched.
- **Completion card:** content preserved exactly (THE SWORD YIELDS / LEVEL n COMPLETE / EXTRACTION TIME MM:SS.cc / n SWORD(S) EXTRACTED; no tap counts). Its fade, line-draw and hold animation were not changed.
- **HUD:** reviewed and **deliberately left visually as it was**: it already used the same Cinzel font, amber for the level and parchment for the timers, with dark top and bottom scrims for readability. The only change was moving it onto the shared helpers. The progress bar and the tap discs were not touched.

## 4. Icon status

A monochrome layer was feasible and was added: a single-colour sword-in-stump silhouette (432 px, inside the adaptive safe zone), wired into the export preset. **Verified in the exported APK:** `res/mipmap-*/icon_monochrome.webp` is different from the previous build at every density, and the adaptive icon descriptor (`mipmap-anydpi-v26/icon.xml`) changed. The colour icon and the foreground layer are byte-identical to the previous build, so the existing adaptive icon was not disturbed. I did **not** inspect the descriptor's contents, and I have **not** seen a themed icon on a phone (it only shows when the user turns on Android 13 themed icons).

## 5. Focused tests run (all desktop, simulated input)

| Check | Result |
|---|---|
| New UI test: scene loading; one shared font on all four screens; shared button styling; pause menu, failure screen, completion card and HUD layout at 540×960, 540×1200, 360×800, 720×1600, 800×1000; touch targets ≥ 48 dp; card content and no tap counts; HUD minimum text size | 106 checks, 0 failed |
| Pause tests (pause / resume / Back / confirmation navigation) | 42 checks, 0 failed |
| Failure tests (failure, retry, MAIN MENU) | 117 checks, 0 failed |
| Layout tests (HUD and failure-screen layout) | 256 checks, 0 failed |
| Menu tests (main menu, from 1.15, after moving it onto the shared helpers) | 55 checks, 0 failed |
| Startup tests | 16 checks, 0 failed |
| Asset import / project load | `--import` clean, no script errors |
| APK export | succeeded |

The only existing test text I changed: three pause-test strings that expected the button to say "QUIT" / "CONFIRM QUIT?". They now use the menu's own constants (`MAIN MENU`, `LEAVE THIS RUN?`); every assertion about behaviour is unchanged.

The core gameplay suites (unit, rhythm, speed, timer, extraction, experience, fx) were **not** re-run, as requested, because no gameplay code changed. Note that the windowed experience suite, which also checks the card during a real extraction, was therefore not re-run; the card's content and layout are covered by the new UI test, not by playing a full extraction.

**Honest limits of the automated checks.** They measure layout rectangles, font sizes, colours and text, not how the screens look. Two of my new checks are weak by nature (the "no red" check only inspects button text colours; the "shared font" check compares font resources). Whether the screens look good is a visual judgement.

**Visual inspection (desktop screenshots, mine, not the phone):** `build/shots/u1_strip.png` (card, pause menu, focus-loss pause, failure screen side by side) and `build/shots/icon_mono_preview.png`. I viewed the screens once, saw one problem (the "TOTAL EXTRACTIONS" caption sat too close to the panel edge on the failure screen) and fixed it by trimming that caption and adding padding; I then re-took the screenshot (`build/shots/u2_failure.png`, crop in `u2_failure_crop.png`) and the caption now has clear padding inside the panel. That re-take was on the desktop at 540×960 only.

## 6. Limitations

- Nothing was viewed or tested on the phone: touch behaviour, real-size legibility, the themed icon, and the performance of the screens are all unverified. The panel, vignette and scrims are cheap, but their cost on this phone was not measured.
- The completion card still has no backing panel of its own: it relies on the HUD's existing top scrim for contrast. I judged that sufficient in the desktop screenshot but did not measure contrast.
- The failure screen's new subtitle ("THE WOOD HOLDS FAST") is new copy; remove it if you prefer none.
- The pause menu's second button is now MAIN MENU, which abandons the current run; with `confirm_quit_during_run` off (the default) there is no confirmation.
- No Settings screen (unchanged from 1.15: there is nothing real to set yet).

## 7. APK

- Path: `D:\photos\gamic\THE WORTHY ONE\build\android\TheWorthyOne-debug.apk`
- Size 36,400,247 bytes. Debug build, signed with the existing debug configuration.
- Version name 0.1.9, version code 7 (from the unchanged export preset); package `com.theworthyone.game`.
- Export succeeded. I exported to a temporary file first, checked the package contents, then swapped it in.
- Previous builds kept: `TheWorthyOne-debug-1.15.apk` (36,383,103 bytes) and `TheWorthyOne-debug-before-1.15.apk` (36,090,625 bytes).
- **Not installed or launched on the physical phone.**

## 8. Final classification

**READY FOR VISUAL REVIEW**, for the desktop screenshots and automated checks only. The screens still need to be looked at on the actual phone before the look is treated as approved.
