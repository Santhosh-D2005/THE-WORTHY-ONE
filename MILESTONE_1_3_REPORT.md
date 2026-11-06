# Milestone 1.3 - Preparing for the first physical Android test

Godot 4.7.2 stable. Date: 2026-10-31.
Scope: retry input protection, independent failure-timing configuration plus playtest presets, Android export preparation,
screen adaptability, tests. No Endless/Ruthless work. Existing gameplay systems were extended, not rewritten.

## READ THIS FIRST: what physical testing means in this report

This milestone **did** include testing on a physical phone, which earlier milestones could not do.

| Item | Status |
|---|---|
| **Device used** | vivo V2129, Android 13, arm64-v8a, Snapdragon 662 / Adreno 610 (Vulkan 1.1), 720x1600, 60 Hz, top cut-out 46 px. **One device only.** |
| APK installed and run on that device | **Yes** (debug APK, `adb install`, launched, ran through real gameplay) |
| Touch input on the device | **Injected by `adb shell input tap`.** These are real Android OS touch events delivered to the real screen, but **not a human finger**: no multi-touch, no two-thumb play, no human timing. |
| Screenshots | taken with `adb screencap` and reviewed |
| Performance numbers | measured on that one low-end device only |
| Human playtest, other devices, battery/thermal, long sessions | **Not done** |

Automated tests are all desktop tests (simulated input); the device results are listed separately in section 4.

---

## 1. Summary

| Task | Result |
|---|---|
| 1 Retry input protection | Done. Configurable lock (default 0.4 s). 14 desktop checks + 2 device experiments |
| 2 Failure timing configuration | Done. Gain / decay delay / decay rate independent; per-parameter curve speeds; 5 playtest presets; balance **unchanged** |
| 3 Android export | Done. Preset created; debug APK built, signed, **installed and run on the phone**. No release/AAB preparation |
| 4 Screen adaptability | Done. 7 sizes checked; two layout problems found and fixed; safe-area support added |
| 5 Testing | 58 unit + 191 integration + 116 failure + 256 layout checks, all passing. Existing tests preserved |
| **Most important finding** | **The game runs at ~30 FPS on this phone** (pixel/GPU-bound). Cold start is ~11-16 s. See section 4 |

---

## 2. Changes implemented

### Task 1 - Retry input protection
- `GameplayConfig` resource (`resources/configuration/gameplay_config.gd`, `default_gameplay.tres`): `retry_input_lock_seconds`, default **0.4 s** (range 0-3, 0 = off). Assigned to the Main node, editable in the inspector.
- `InputController` got `lock_for(seconds)`, `is_locked()`, `lock_remaining_seconds()`, `clear_lock()`. While locked, gameplay taps are rejected (they emit `tap_rejected`, do not touch alternation, do not start timers). Blocked taps never extend the lock; a shorter lock never shortens a running one.
- `LevelManager._restart_run()` engages the lock right after TRY AGAIN. The retry button itself is part of the failure screen, not gameplay input, so it is never affected. The lock is not applied at game start or on level transitions.

### Task 2 - Failure timing configuration
- Gain, decay delay (grace) and decay rate were already separate fields; they shared one curve speed. `DifficultyConfig` now has optional **per-parameter curve speeds** (`gain_ramp_levels`, `decay_ramp_levels`, `grace_ramp_levels`; 0 = follow `ramp_levels`), so each is fully independent (start, end, speed). **Default values are unchanged** (8 / 5 / 0.5 at level 1; 4.5 / 14 / 0.25 limit; ramp 12) and a unit test pins them.
- `DifficultyManager` can load a preset: `--difficulty-preset=<name>` (Android: export preset Command Line Extra Args). Unknown or malformed names fall back to the default with a warning. A small "PLAYTEST PRESET - NAME" label appears under the timers for non-default presets only.
- Presets (`resources/difficulty/presets/`): `forgiving`, `demanding` (change all three), `grace_long`, `decay_slow`, `gain_high` (each changes exactly one parameter). Numbers and suggested use are in `docs/PLAYTEST_PRESETS.md`.

### Task 3 - Android export preparation
- `export_presets.cfg` ("Android"): portrait build, arm64 only, package `com.theworthyone.game`, version 0.1.3 (code 1), no permissions, immersive mode, tests/docs/build excluded from the package.
- `icon.svg` placeholder launcher icon and `config/icon` in `project.godot`.
- `docs/ANDROID_EXPORT.md`: requirements actually present on this machine, export/install/run commands (all executed), presets, known risks.
- The built APK was inspected with `aapt2` (package, SDK levels, portrait `screenOrientation=1`, arm64, no permissions) and then installed and run.

### Task 4 - Screen adaptability
Measured on 540x960, 720x1280, 1080x1920, 540x1170 (19.5:9), 540x1200 (20:9), 540x1296 (21.6:9) and 768x1024 (3:4 tablet).
Problems found and fixed:
1. **Timer boxes overlapped by 2 px** at every size (invisible, but a real layout fault). Offsets nudged.
2. **Wider-than-9:16 screens (tablets) zoomed in and cropped:** Godot fixes the horizontal FOV by default, so the stump grew and its front rim slid under the progress bar. `GameplayCamera` now keeps the horizontal FOV for taller screens and the 9:16 design's vertical FOV for wider ones, so the composition is identical (verified) and extra forest appears at the sides. At exactly 9:16 nothing changes.
3. **Safe-area support (new `SafeArea` helper):** the HUD and failure screen now keep clear of the OS camera cut-out (top) and gesture bar (bottom). It is a no-op on desktop. On the test phone the 46 px cut-out inset was applied (the "LEVEL 1" label sits exactly where base position + inset predicts).
Taller phones (20:9 and up) needed no change: the stump keeps its width, UI sits at the edges.

---

## 3. Automated tests (desktop, simulated input)

| Suite | Checks | Result (final code) |
|---|---|---|
| Unit `tests/run_tests.gd` | 58 (was 31) | ALL PASSED |
| Integration `tests/integration_tests.tscn` (existing) | 191 | ALL PASSED, 0 inconclusive, 0 focus-loss pauses |
| Failure `tests/failure_tests.tscn` | 116 (was 102) | ALL PASSED |
| Layout `tests/layout_tests.tscn` (new) | 256 | ALL PASSED (36-37 checks at each of 7 sizes) |
| Project import / main scene load | - | No errors or warnings (apart from a harmless Godot message, see 6) |

New unit tests (27): default balance unchanged; changing only gain, only decay or only grace leaves the other two identical over levels 1-200; per-parameter curve speeds;
every preset loads, stays achievable (<= 5 taps/s to hold progress, level-1 lone tap >= 1 s), isolated presets change exactly one parameter,
ordering forgiving > default > demanding; preset-name validation and argument parsing (rejects `../x`, uppercase, spaces); `use_preset` fallback; the input lock
(locks, rejects, does not extend, expires, zero/shorter/clear cases).
New failure-suite section 14 (14 checks): the lock engages on retry (about 0.4 s remaining), spamming taps and clicks for the whole lock does not start the attempt, timers stay 0,
the lock expires on schedule (not extended), gameplay works right after, a full level completes and level transitions are not locked, the retry button works again next time, a configured 1.2 s lock
holds at 0.8 s, and a 0 s lock disables it.
**Existing tests were preserved. Two expectations in the failure suite were intentionally updated** because the behaviour they described changed on purpose:
the "triple press on TRY AGAIN" test now expects a clean READY state (previously the extra presses legitimately started the run), and one label was reworded ("a new extraction works once the retry lock has expired").
Layout checks per size: window aspect, every HUD element inside the screen, no two overlapping, text fits, tap panels symmetric and large (>= 300x250 base px), stump and resting sword visible and not covered by any HUD element,
sword pommel clearance at 100%, held-up sword still on screen, stump centred and its width share, composition identical across 9:16 resolutions (and constant width on taller / constant height on wider), safe-area insets shift the HUD by exactly the inset and restore exactly,
the preset label fits, the failure screen fits and avoids the sword/stump, and respects the insets.

---

## 4. Physical-device results (one phone, adb-injected touches)

| Test | Result |
|---|---|
| Install `adb install -r` | Success; package, version 0.1.3, arm64 confirmed by `dumpsys package` |
| Launch and render | Runs; full scene, fonts and HUD correct in portrait; cut-out cleared. Log shows a harmless .NET template message and Adreno gralloc noise, no crash |
| Idle 4 s, no tap | No failure (cannot fail before the first tap) |
| One tap and stop (default balance) | Failure screen after a session time of 2.06 s (predicted 2.1 s); screen content correct |
| Failure screen | Renders correctly, HUD fades out, stump and sword visible |
| TRY AGAIN (touch) | Starts a clean run |
| **Retry lock, test A** | 2nd tap issued **158 ms** after the retry tap (measured with device timestamps): run stayed READY, timers 0:00.00 |
| **Retry lock, control B** | Tap 0.9 s after retry: attempt started, timers ran, progress rose |
| Full extraction | 14 alternating taps: success animation, banner with time, next level: level 2, level timer reset, session timer continued, sword re-embedded |
| **Android lifecycle (HOME)** | Tap, HOME, 7 s away, return: process stayed alive, pause overlay shown, level timer frozen at 0:00.91 (a run would have failed after 2.1 s), resume by tap continued from 0.91 |
| Difficulty preset via export extra-args | `--difficulty-preset=forgiving` reached the app: label shown; a single tap survived **3.62 s** (predicted 3.66 s) |
| Safe area | 46 px cut-out inset applied (verified from screenshot geometry) |

### Performance and startup (the most important findings)
- **Frame rate: about 30 FPS.** SurfaceFlinger presented-frame timestamps over 127 frames: median 33.3 ms, p95 33.5 ms, max 50 ms (about 29.4 FPS idle, 29.9 FPS during play); vsync period is 16.7 ms. Far below the 60 FPS target.
- **Diagnosis:** the game thread was almost idle (<1% CPU); Godot's Vulkan render thread (`VkThread`) ran at 43-52% of a core. A throwaway diagnostic build at **60% 3D resolution** gave a median of 16.7 ms (60 FPS; average ~45 FPS during play with dips). So the game is **pixel/GPU-bound on the Adreno 610**, not limited by game logic. The diagnostic build was discarded and `project.godot` restored byte-identically.
- Likely contributors (not individually measured): real-time shadows with blur, depth fog, normal-mapped bark on ~46 trunks, the layered floor shader, 720x1600 native resolution.
- **Cold start is slow:** roughly **11-16 s** from launch to the first gameplay frame (polling screenshots about every 2.5 s, so +/- 2.5 s). Procedural meshes and noise textures are generated at startup on a weak CPU. During that time the Godot boot splash is shown, and taps are lost.
- Memory: about 344 MB total PSS (193 MB native heap, 46 MB graphics) in one sample.
- Other devices, thermals and battery: not measured.

---

## 5. Android export readiness

| Item | State |
|---|---|
| Debug APK builds, signs, installs, runs | **Verified on one phone** |
| Portrait lock, touch input, scaling, safe areas | Verified on that phone (adb touches) |
| Export toolchain on this machine (SDK, JDK 17, templates, debug keystore) | Present and working; SDK cmdline-tools missing but not needed for this export |
| Release signing / release keystore | **Not prepared** |
| Android App Bundle (.aab) / Gradle build / Google Play | **Not prepared** (needs Gradle build + release keystore) |
| Launcher icon | Placeholder |
| Vulkan requirement | APK requires Vulkan; no fallback tested |
| Back button behaviour | **Untested** (see section 6) |
| Performance / startup | **Not acceptable for a polished release yet** (section 4) |

Verdict: ready for **sideloaded debug playtesting**, not for store release.

---

## 6. Remaining physical-device tests (not done)

1. **Human finger play**: real two-thumb alternating at speed, accidental double-registration (is 25 ms debounce right?), palm touches, multi-touch, tap feel and latency.
2. **Android Back button / back gesture**: Godot's default `quit_on_go_back` closes the app on Back, which would end a run; the game's own pause-on-back code may be moot. My attempt to test it failed because the phone's screen had locked itself; I did not unlock it. Needs a deliberate decision and a test.
3. Other lifecycle cases: screen lock during play, incoming call, notification shade, app switcher, split-screen, being killed in the background (no saving exists), rotation/orientation settings.
4. Other devices: different GPUs (especially more capable ones, and one without Vulkan), other aspect ratios and gesture-navigation vs 3-button navigation (bottom safe area was 0 on this phone).
5. Performance work and re-measurement: optimise to 60 FPS on this class of device (e.g. render scale, shadow/fog/shader costs) and shorten the 11-16 s cold start.
6. Long sessions: thermals, battery, memory growth, frame-time drift.
7. Audio and haptics (none exist yet).
8. Release signing and an AAB build.

---

## 7. Known issues

1. **~30 FPS and ~11-16 s cold start on the test phone** (section 4). Highest priority.
2. Back button behaviour unknown (section 6).
3. `print()` output does not reach logcat on this phone, so on-device logging is unreliable; the HUD preset label exists for that reason.
4. A harmless `ERROR: EditorSettings not instantiated yet ... shutdown_adb_on_exit` is printed by Godot whenever it runs headless with an Android export preset present (import, test runs, export). The APK and tests are unaffected.
5. The cold-start numbers above come from relaunches after `force-stop`; I did not separately measure a first launch right after installing.
6. The session timer keeps running while the player idles in READY (by design: it only stops when a run ends), so a long wait before tapping inflates it.
7. MAIN MENU is still shown disabled (no main menu scene).
8. The launcher icon, art and materials are placeholders; no audio.
9. The retry lock means a deliberate very fast tap right after TRY AGAIN is ignored for 0.4 s; set `retry_input_lock_seconds` to 0 to disable.
10. Only the debug build was exported; export templates are the .NET (mono) ones, which add the .NET runtime to the APK (about 28 MB total).
11. During the final device test the phone's screen locked itself and a screenshot captured its lock screen, which showed the owner's private notifications. **I deleted that file without using it and did not try to unlock the phone.** The remaining captures are game-only.

---

## 8. Files

**New:**
- `resources/configuration/gameplay_config.gd`, `default_gameplay.tres`
- `resources/difficulty/presets/forgiving.tres`, `demanding.tres`, `grace_long.tres`, `decay_slow.tres`, `gain_high.tres`
- `scripts/systems/safe_area.gd`
- `export_presets.cfg`, `icon.svg`
- `docs/ANDROID_EXPORT.md`, `docs/PLAYTEST_PRESETS.md`
- `tests/layout_tests.gd`, `tests/layout_tests.tscn`
- `build/android/TheWorthyOne-debug.apk` (+ `.idsig`): build output, currently installed on the phone
- `MILESTONE_1_3_REPORT.md`

**Modified:**
- `resources/difficulty/difficulty_config.gd` - per-parameter curve speeds (defaults unchanged)
- `scripts/managers/difficulty_manager.gd` - preset loading and argument parsing
- `scripts/gameplay/input_controller.gd` - input lock
- `scripts/managers/level_manager.gd` - applies the lock after retry; gameplay config; preset label hook
- `scripts/ui/hud.gd` - safe-area offsets, timer-box overlap fix, preset label
- `scripts/ui/failure_screen.gd` - safe-area offsets
- `scripts/gameplay/gameplay_camera.gd` - aspect-ratio-aware framing (identical at 9:16)
- `scenes/main/main.tscn` - references the gameplay config
- `project.godot` - `config/icon`
- `tests/run_tests.gd` (+27 checks), `tests/failure_tests.gd` (+14 checks, 2 expectations updated), `README.md`

Deleted: nothing from the project. Throwaway diagnostic APKs and temporary project/export-setting edits were reverted (`project.godot` restored byte-identically; export preset restored).
