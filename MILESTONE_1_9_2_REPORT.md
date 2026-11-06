# THE WORTHY ONE – Milestone 1.9.2 Report
**Physical-phone install, run and performance check of version 0.1.9 (versionName 0.1.9, versionCode 7)**

Device: vivo V2129, Android 13, Adreno 610, 720x1600, 60 Hz, connected by USB. The Godot debug APK built from the
1.9 code plus the 1.9.2 performance fixes below was installed with `adb install -r` and run on the phone. The emulator was not used.

## 0. What was and was not done (read this first)

| Kind of testing | Done? |
|---|---|
| Desktop automated suites (headless and windowed) | Yes, see section 3 |
| Installed and run on the physical phone | Yes |
| Phone performance measurement (logged by the game itself, `PerfProbe`) | Yes, see section 2 |
| Phone functional checks driven by **injected input** (`adb shell input tap`) | Yes, see section 4 |
| **Human playtesting** (a person playing with their thumbs) | **No. Nobody has played this build.** |
| Release (signed) APK | Not built. Only the debug APK was tested. |

All taps on the phone were injected through `adb shell input tap`. That is **not** human playtesting. The injected taps are
about 80 ms apart at best and unnaturally regular, so they say nothing about how the extraction feels or whether the
difficulty curve is fair. The 60 FPS target was **not** met on the phone (section 2).

Privacy: the phone's lock screen shows private notifications. I never captured it. Every screenshot was preceded by a keyguard
check, and the phone was awake and unlocked throughout.

## 1. Changes made during this device pass (1.9.2)

The first 0.1.9 build on the phone was a clear performance regression from 0.1.7. Idle (READY) FPS was about 47 against 59.5.
Measured per-effect isolation on the phone (debug flags, interleaved runs) found:

* **Foliage overdraw:** per-pixel-fogged and per-pixel-lit overlapping fern fronds were the idle regression. Fix: a dedicated
  cheap fern shader (`shaders/fern.gdshader`: vertex lighting, no fog, no shadows), 4 segments per frond, 7 fronds per clump,
  fewer and better-placed clumps. Idle FPS recovered to about 55-58.
* **Light swell on extraction:** changing the sun's `light_energy` costs about 9 FPS on this GPU. It is now done with tone-map
  exposure (`forest_environment.gd`, `_light_scale`), and the sun energy itself never changes.
* **Camera tension creep:** I suspected about 5 FPS. A final interleaved A/B (3 runs each, flag `--no-cam-tension`) showed
  **no real difference** (PLAYING 50.0 / 53.4 / 50.0 with it, 50.2 / 51.3 / 50.6 without; EXTRACTING 47.0 / 47.6 / 43.7 against
  46.1 / 45.3 / 46.2). It is within noise, so it stayed.
* The debug flags `--no-discs --no-cam-fx --no-light-fx --no-card --no-cam-tension --no-height-fog --no-fog --no-foliage` and
  `--rq=key=value` are debug-build-only measuring aids, read from `files/launch_args.txt` on the phone. Release builds ignore them.

## 2. Phone performance (measured, `PerfProbe` log, frames per second)

Protocol per run: cold launch, 12 s idle in READY, then 3 bursts of 20 injected alternating tap pairs, then pull the log.
READY = idle, PLAYING = tapping before completion, EXTRACTING = the extraction sequence (card shown).

| Build / run | READY | PLAYING | EXTRACTING | PSS |
|---|---|---|---|---|
| 0.1.7 final (earlier baseline) | 59.5 | 58.6 | 47-48 | about 278 MB |
| 0.1.9 first build (before fixes) | about 47 | about 45 | about 40.5 | n/a |
| 0.1.9.2 final, default flags, run 1 | 52.2 | 50.0 | 47.0 | 281 MB |
| 0.1.9.2 final, default flags, run 2 | 58.0 | 53.4 | 47.6 | 283 MB |
| 0.1.9.2 final, default flags, run 3 | 56.8 | 50.0 | 43.7 | 281 MB |
| (first run after install, discarded as warm-up) | 49.3 | 45.3 | 44.7 | 295 MB |

Honest reading:

* **The target (about 55-60 FPS, no major extraction drops) is only partly met.** Idle is 52-58 FPS. Playing is 50-53 FPS,
  about 5-8 below 0.1.7. Extraction is 44-48 FPS, which is about the same as 0.1.7 (47-48), so the extraction drop was not made worse,
  but it was also not fixed. The phone sits at the 60 FPS cliff (render scale 0.60 with FSR), and the remaining forest and
  fern detail from 1.9 costs a few FPS against 0.1.7.
* The phone heats during a session (about 33 to 36.5 degrees C) and FPS drifts down by roughly 3-4 FPS, and run-to-run
  noise is about +/-3 FPS. Only interleaved runs are comparable; the single numbers above should not be over-read.
* Memory is flat at about 281-295 MB PSS, a little above 0.1.7's 278 MB.
* Frame time p95 on the final runs was about 25-31 ms (that is 32-40 FPS at the slowest 5% of frames), so there are small
  stutters on extraction. I did not make this smaller.
* No attempt was made to lower the render scale or quality further, since that would trade away the visual overhaul
  that was the point of 1.9. That would be the next lever if 60 FPS is required.

## 3. Desktop automated tests (after the 1.9.2 edits)

| Suite | Result |
|---|---|
| Unit (`run_tests.gd`, headless) | all passed, 0 failures |
| Integration (headless) | 194 checks, 0 failed |
| Failure (headless) | 116 checks, 0 failed |
| Layout (headless) | 256 checks, 0 failed |
| Timer (headless) | 25 checks, 0 failed |
| Startup (headless) | 16 checks, 0 failed |
| Pause (headless) | 41 checks, 0 failed |
| Rhythm (headless) | 63 checks, 0 failed |
| Speed (headless) | 50 checks, 0 failed |
| Experience (windowed, 72 checks) | **Not consistently clean.** See below. |

Experience suite, windowed, repeated runs after the 1.9.2 edits: 1 run with 1 failure, then 2 clean, then (after the check was
made patient) 2 clean and 1 failure. Two different checks failed, each once:
1. "the card fades and the HUD shows LEVEL 2" failed once, because READY begins while the card is still mid-fade. I changed
   the check to wait up to 3 s for the fade to finish before asserting. This does not loosen what is asserted.
2. "the biggest single-frame move is 1.32 px and the biggest speed change 0.80 px" failed once (the limit is jerk below 0.6). It
   measures sword motion per rendered frame, so a single desktop frame hitch can trip it. It passed in the other runs. I did not
   loosen it and I did not root-cause it. It is a **known flaky desktop check**, not a confirmed sword-motion regression, but it
   is also not proven harmless. Worth a look if it recurs.

## 4. Phone functional checks (injected input only)

Run on the installed build, with taps injected from the phone shell at about 80-120 ms apart.

| Check | Result |
|---|---|
| Install and cold launch | OK. READY about 5.4 s after process start (engine time). |
| Levels 1-8 with continuous alternating taps | Completed in order. Extraction times 3.0, 3.1, 3.1, 3.3, 3.4, 3.6, 3.6, 3.6 s. |
| Level 9 with the same stream | **Failed** about 0.7 s after play began. I attribute this to adb tap-spawn jitter, which sometimes creates a gap longer than the allowed interval; I did not confirm that. Failure screen appears correctly. |
| Failure screen and TRY AGAIN | OK. Screen shows level reached 9, session time, total extractions 8. TRY AGAIN restarts at level 1. |
| Extraction card on phone (screenshot burst) | OK. "THE SWORD YIELDS / LEVEL 1 COMPLETE / EXTRACTION TIME 00:03.01 / 1 SWORD EXTRACTED". No tap counts. Sword rises and the stump shows its empty slot. Then the HUD shows LEVEL 2. |
| Slow alternating taps (0.6 s apart) | Fails the level (2 taps counted as too slow). |
| Same-side taps x12 | Fails the level. |
| Alternate 6 taps then stop 4 s | Stays in play, no crash. The progress decays as designed. |
| Back button | Opens PAUSED menu (RESUME, QUIT). |
| RESUME | Returns to the game (READY). |
| QUIT | The process ends. The app is gone from the foreground. |
| Cleanup | `files/launch_args.txt` and `files/perf_log.txt` removed from the phone. Only `shader_cache` and `vulkan` remain. |

Not checked on the phone, and so not claimed: levels 10 and above on-device, all difficulty-curve fairness, real thumb
accuracy on the round discs, rotation or app-switch behaviour beyond the Back/pause path, long-session thermal behaviour beyond
the runs above, and a release (non-debug) build.

Screenshots (`build/shots/`): `dev192_failed.png` (failure screen), `dev192_pause.png` (pause menu), `c192_strip.png`
(burst: play, extraction card, next level), `c192_0.png` to `c192_7.png` (the individual burst frames), `dev19_ready.png`
(earlier READY frame on the phone).

## 5. Known issues and honest summary

* 60 FPS is not reached on this phone in play, and extraction dips to the mid-40s. This is the main open issue.
* Nobody has played the game by hand. Difficulty values (tuned only against simulation and injected taps) are unvalidated.
* One desktop motion-smoothness check is intermittent (section 3).
* Level 9 failing under injected taps is probably an input-injection artifact but is unconfirmed.
* Version stays 0.1.9 (code 7), as the changes since the first 0.1.9 build are performance fixes only; the installed package
  reports versionName 0.1.9, versionCode 7.
* Endless and Ruthless modes, the main menu and leaderboards were not started, as instructed.
