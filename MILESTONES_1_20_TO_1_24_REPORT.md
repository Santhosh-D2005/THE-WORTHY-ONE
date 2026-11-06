# THE WORTHY ONE – Milestones 1.20 to 1.24: Release-Readiness Report (in progress)

Version 0.1.9 (code 7), package `com.theworthyone.game`: unchanged. Performance investigation is deferred, NOT resolved: the earlier observations (about 45-46 FPS during gameplay, 309-315 MB PSS, phone around 42 °C) stay open. Automated ADB taps are not human playtesting; audio has not been verified by ear.

## 1.20 Content and Progression Audit: no defects confirmed

- There is no fixed level list; every level comes from the DifficultyConfig curves.
- New `tests/progression_tests.gd` (35 checks, 0 failed, headless, simulated input):
  - levels -5..1000: all values finite and in range; difficulty never gets easier (gain, useful interval, gap, resistance, decay, grace, extraction time); a steady 6-7 taps/s player can finish every level (slowest 7.8 s at 6 taps/s); no jump above 1 s between neighbouring levels; converged from level 100 (curves are exponential saturations, not exactly flat); levels 0 and below behave like level 1;
  - real loop: levels 1-3 complete in order, each extraction counted once, level_changed once per advance, per-level tuning, timers reset; failure on level 4 keeps its result; a second failure signal changes nothing; TRY AGAIN restores level 1 / 0 extractions / no stale result / level-1 tuning, and a retried run counts 1 extraction;
  - entering the game from stale FAILED / EXTRACTING / PLAYING state starts a clean level 1;
  - 4 open/close cycles of the game scene add no connections to the GameManager signals.
- Fixes: none needed. One of my own test assumptions (curves exactly constant at high levels) was wrong and was corrected; it was not a game defect.
- APK change: none.

## 1.21 Release Stability: no defect demonstrated that needs a fix (real phone; game confirmed in front before every tap/screenshot)

- Home on the menu: Android's audio player for the game goes `paused` in the background and `started` on return; same process, no crash.
- Home during the game: returns paused ("PAUSED / TAP TO RESUME"); a tap resumes the live game.
- Resource lifecycle: five menu -> PLAY -> Back -> MAIN MENU cycles: PSS 313, 316, 312, 315, 314, 315 MB (no growth), same process, 0 new crashes (5 historical).
- Earlier: QUIT and Back on the menu exit cleanly; audio-player cleanup covered by the audio tests; autoload signal connections do not pile up (progression test).
- **Unresolved low-severity risk:** pulling the notification shade moves Android window focus to the shade, but the game does not pause (Godot's Android layer reports only activity pause, not window-focus loss). During an extraction the progress would keep decaying while the shade covers the screen. Player-initiated; not fixable without engine-level changes.
- Not tested: killing the app in the background, phone calls, low-memory kill, rotation (portrait-locked).
- Changes / APK change: none.

## 1.22 UI and Compatibility: no defect confirmed, no change (layout, contrast and touch targets were audited at 5 screen shapes in 1.16/1.17 and re-checked on the phone screenshots)

- Camera cutout (read from Android): waterdrop notch x 275-445, y 0-46 px; the HUD level label and the completion-card title start well below it (no overlap in the phone screenshots).
- Rounded display corners (radius 85 px): the tap discs (left edge about 93 px) and the extraction bar are clear of them.
- System bars: immersive mode, status bar hidden; no system-bar overlap seen. The bottom discs end about 67 px above the screen edge.
- Installed package requests **no permissions**.
- Compatibility: arm64-v8a only; minSdk 24 / targetSdk 36; renderer `mobile` (Vulkan) with the engine's OpenGL ES fallback enabled (`fallback_to_opengl3 = true`).
- **Unverified:** only one device (vivo V2129, Adreno, Vulkan) was available. The OpenGL fallback path (no Vulkan), 32-bit-only phones (not supported), other aspect ratios on real hardware, tablets/foldables, and Android versions other than 13 were not tested.
- Changes / APK change: none.

## 1.23 Release Build Preparation: two release-hygiene defects fixed; signing still needs the user

Audited: package identity (`com.theworthyone.game`, name THE WORTHY ONE, **0.1.9 / code 7 unchanged**), icons (all four launcher layers configured and packaged, see 1.17), permissions (**none requested**), debug-only features (launch args and `--perf-log` are read only when `OS.is_debug_build()`; the perf probe is inert without its flag), reproducibility, APK contents, signing.

- **Reproducible:** two fresh debug exports of the same project are identical in all 334 entries (signatures included), 37,098,813 bytes each.
- **Defect 1 (fixed):** 33+ development-only files shipped in the APK (compiled `tools/*` scripts and their scenes). Nothing at run time uses them. Fix: `tools/*` added to the export `exclude_filter`.
- **Defect 2 (fixed):** the SIL Open Font Licence file for the Cinzel font was **not** in the APK (Godot exports only resource types), although the licence must accompany the font. Fix: `include_filter="assets/fonts/OFL-Cinzel.txt"`.
- Verified after the change: 38 dev entries removed, the licence file present, **no game script, scene or audio entry changed**; APK 37,062,630 bytes (was 37,098,813). Only `export_presets.cfg` changed (backup: `build/export_presets_before_1_23.cfg`). Previous APK kept as `TheWorthyOne-debug-1.19.apk`.
- **Not configured / needs the user (not done on purpose):**
  - **No release keystore.** A release signing identity is the owner's decision; I did not create one. Debug builds use the Android debug keystore.
  - **Output is an APK, not an AAB.** Google Play requires an AAB, which needs a Gradle build template; not set up.
  - **No in-game credits / licences screen.** The Godot engine (MIT) and the Cinzel font (OFL) require their notices to be distributed; the font licence now ships inside the APK, but there is no screen showing the engine's notice. Adding one is a feature, so it is left for a decision.
- APK change: yes (smaller, licence added).
