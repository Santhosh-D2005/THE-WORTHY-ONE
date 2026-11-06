# Milestone 1.6 report - rhythm mechanic, difficulty, controls, sword smoothness, clarity

Build: version 0.1.6 (code 4), debug APK, installed on the vivo V2129 (Android 13, Adreno 610, 720x1600, 60 Hz).
Labels used below: **[desktop]** = automated test or desktop measurement with simulated input; **[phone]** = run on the vivo with the installed 0.1.6 build (injected `adb input tap` touches, not a human finger; the game's own log read back through `PerfProbe`).
Backups: `..\THE WORTHY ONE_backup_1_3`, `..\THE WORTHY ONE_backup_1_4` (the 1.4 backup was also used to measure the old sword motion).

## 1. The tapping-speed mechanic

Every accepted tap (alternating side, not a duplicate) is classified by `TapRhythm.classify()` (`scripts/gameplay/tap_rhythm.gd`, a pure function):

| Tap | Kind | Effect |
|---|---|---|
| First tap of an attempt (also the first tap after a new level, retry or resume) | FIRST | starts the attempt and both timers, anchors the rhythm, **awards no progress**, no sword kick |
| Alternating tap, interval from the previous accepted tap <= limit | PROGRESS | awards one gain, resets the decay grace timer, kicks the sword |
| Alternating tap, interval > limit | TOO_SLOW | awards nothing, no kick, **does not reset the grace timer** (so slow tapping cannot hold the bar), but becomes the new anchor so the next quick tap counts |
| Same-side repeat / double registration (< 25 ms) | rejected | no effect on progress or on the timing anchor (the interval is measured from the last *accepted* tap) |

- Time source: `Time.get_ticks_usec()` (monotonic microseconds) in `InputController.handle_tap`; no frame counts anywhere.
- Duplicate or simultaneous events: the existing 25 ms debounce still applies (two taps in the same instant, or two fingers at once, give exactly one accepted tap; tested).
- Failure when nothing is earned: because the first tap awards nothing, progress can sit at 0 after an attempt began. If no progress tap arrives within *grace + the level's allowed interval* (0.9 s on level 1) the attempt fails exactly like a bar that decayed to zero (`ExtractionManager`, same `progress_depleted` signal and gate, still impossible before the first tap or while paused). Decay of a bar above zero is unchanged (5 %/s on level 1, same grace). **This stall rule is my own design decision**; without it a player could tap once and then wait forever at 0 %.
- Configurable independently of level difficulty (`GameplayConfig`): `rhythm_enabled` (false = old behaviour, every tap counts) and `max_tap_interval_override_msec` (> 0 forces one limit on every level). The per-level curve lives in `DifficultyConfig`.
- Feedback: panel flash is full for progress taps, medium for the first tap, faint for a too-slow tap, and a too-slow tap shows "TAP FASTER" briefly (restored on retry).
- Pause/resume: the tree is paused so the stall timer and decay are frozen; the tap that follows a resume is a FIRST tap, so the paused time is never counted as a slow gap.

## 2. Timing thresholds and justification

Initial values as you proposed: **400 ms** on level 1 (2.5 taps/s). Reasoning from the phone: injected taps ran at 200-230 ms intervals in the normal-tapping run and 69-160 ms in the rapid run, so 400 ms is comfortably achievable for any alternating rhythm and only punishes a clearly slow rhythm. The floor is **220 ms (4.5 taps/s)**; no preset goes below 200 ms (5 taps/s), enforced by a unit test. All values are data (`default_difficulty.tres` / script defaults), not constants.

## 3. Difficulty progression

`DifficultyConfig` blends each value from its level-1 value to a limit along `t = 1 - exp(-(level-1)/ramp)`; every parameter has its own start, end and ramp.

New this milestone: the **allowed tap interval**, 400 ms -> 220 ms, own ramp **8 levels** (`interval_ramp_levels`).
Unchanged (as required): decay (5 -> 14 %/s, ramp 12), grace (0.5 -> 0.25 s), gain per tap (8 -> 4.5 %, ramp 12). Unit tests pin level 1 and level 10 values of these three to the original formula, so decay is **not** more aggressive than in 1.5.

| Level | Max gap ms | Taps/s needed | Gain %/tap | Taps to extract* | Decay %/s | Grace s |
|---|---|---|---|---|---|---|
| 1 | 400 | 2.50 | 8.00 | 14 | 5.0 | 0.50 |
| 2 | 379 | 2.64 | 7.72 | 14 | 5.7 | 0.48 |
| 3 | 360 | 2.78 | 7.46 | 15 | 6.4 | 0.46 |
| 5 | 329 | 3.04 | 7.01 | 16 | 7.6 | 0.43 |
| 8 | 295 | 3.39 | 6.45 | 17 | 9.0 | 0.39 |
| 10 | 278 | 3.59 | 6.15 | 18 | 9.7 | 0.37 |
| 15 | 251 | 3.98 | 5.59 | 19 | 11.2 | 0.33 |
| 20 | 237 | 4.22 | 5.22 | 21 | 12.2 | 0.30 |
| 30 | 225 | 4.45 | 4.81 | 22 | 13.2 | 0.27 |
| 50 | 220 | 4.54 | 4.56 | 23 | 13.8 | 0.25 |

\* including the first tap that awards nothing. The biggest single-level tightening is 21 ms (level 1 -> 2); the sequence is monotonic (unit-tested to level 60).
Honest note: a first version used a 10-level ramp. On the phone, taps at ~200 ms took 13 / 13 / 14 taps on levels 1-3 and the limit (383 / 367 ms) never bound, i.e. levels still felt the same. I changed the ramp to 8 levels and the floor stayed 220 ms; the difficulty still depends on the player's own tapping speed, and a player who taps at 150 ms will not feel the interval limit until a very high level (the limit only constrains slower rhythms; the falling gain and rising decay still apply). If you want stronger early pressure the right lever is a lower `end_max_tap_interval_msec` / faster `interval_ramp_levels`, or more required progress per level; I did not change those without your feedback.
Presets: `forgiving` 460 -> 260 ms (ramp 12), `demanding` 360 -> 200 ms (ramp 6); others use the default curve.

## 4. Control size

The LEFT / RIGHT panels went from 485 x 340 to **425 x 300 base px (-12.4 % wide, -11.8 % tall)**, each centred in its screen half, bottom edge unchanged (thumb reach). On the phone that is **about 283 x 199 px (was about 322 x 225)**, measured on the device screenshot (`build/shots/dev16_ready.png` vs the 1.5 pause screenshot).
Touch accuracy is unaffected by design: `InputController` still reads the *whole left/right half of the screen*; the panels are only the visual target. Tested: a tap in the far top-left corner and in the bottom-right margin still register as LEFT / RIGHT. Panels stay in their halves, symmetric, level, inside the safe area (layout suite 256/256 unchanged).

## 5. Rapid-tap sword pixelation: investigation

Cause found by reading and then measuring, not assumed: each valid tap set a kick of up to 3.2 cm, drawn as a **14 Hz sideways shake** (`sin(time * 90)`), plus a **rotation about the blade tip** (a 2 m lever to the pommel), re-triggered by every tap. Rapid tapping kept the sword vibrating.
Measurement [desktop, `tools/sword_motion.tscn`, pommel position in phone render pixels (432 px wide), 3 s per speed, same method on the 1.4 code and the new code]:

| Taps | Before: sideways range / direction reversals per s / vertical jerk | After |
|---|---|---|
| 2.5/s (400 ms) | 5.35 px / 12.7 / 1.23 px | 0.00 px / 0.0 / 0.46 px |
| 4.5/s (220 ms) | 5.78 px / 20.7 / 1.24 px | 0.00 px / 0.0 / 0.50 px |
| 8.3/s (120 ms) | 7.09 px / 28.7 / 1.30 px | 0.00 px / 0.0 / 0.53 px |
| 14.3/s (70 ms) | 8.77 px / 28.7 / 1.13 px | 0.00 px / 0.0 / 0.47 px |

So on an un-antialiased 0.6-scale upscaled image the pommel swung 5-9 render pixels about 14 times a second, which reads as crawling, blocky edges. FSR itself, the 0.6 scale and the sword mesh were not the cause (they are unchanged and the sword is now stable).
Fix (`SwordController`): the tap kick is now a small **vertical** thump (<= 1 cm, about 1 render pixel) passed through a short exponential low-pass (45 /s, frame-rate independent). Rapid taps merge into one smooth pulse; motion no longer grows with the number of taps; TOO_SLOW taps produce no motion at all. The slip tremble (only while decaying) keeps its frequency but its tilt coupling is reduced (0.9 -> 0.35). The sword height remains a pure function of progress (tested after rapid tapping). Cost: none measurable (section 7).
Tested [desktop, `rhythm_tests` section 10]: slow (800 ms), normal (220 ms) and very rapid (70 ms) tapping each give 0.00 px sideways movement, 0 reversals/s, thump <= 0.0037. On the phone I could only capture screenshots during rapid tapping (two frames, `build/shots/dev16_rapid_crop.png`): they caught the extraction animation and show a clean blade apart from the normal stair-stepping of the 0.6 render scale; a still screenshot cannot prove the absence of vibration, so that claim rests on the desktop measurement. A human eye on the phone is still needed.

## 6. Visual clarity (all measured for cost on the phone)

Changes kept:
- **FSR sharpness 0.2 -> 0.05** (sharper edges): free, 58.3 FPS vs 58.3 control.
- **Cut-face ring contrast** (`wood_top` shader 0.75/0.25 -> 0.9/0.1): rings stay legible at the low render scale. Free (shader maths).
- **Bark relief** on the main stump (normal scale 1.6 -> 2.1) and **grading contrast** 1.08 -> 1.12.
- **Darker fuller / grip bands** (dark steel 0.38 -> 0.30) for more depth in the blade.
- Kept from 1.5: scale 0.60, FSR 1.0, 4x anisotropy, existing shadow configuration, no MSAA/FXAA (not re-enabled; the 1.5 benchmark of -14 to -17 FPS stands).
Rejected after measuring: **texture LOD bias -0.5** looked crisper but cost FPS (54.4 alone, 55.0-55.7 combined; -0.25: 55.8 vs 58.3 control), so `mipmap_bias` stays 0 (the knob remains available: `--rq=mip_bias=`).
Evidence: desktop comparison images `build/shots/cl_compare.png` (sharpness / bias), `build/shots/mat_compare.png` (before/after materials) and a phone screenshot of the final build (`build/shots/dev16_ready.png`), where bark relief and rings are visibly crisper than the 1.5 screenshots. No neon, bloom or particles were added; the direction (natural colours, steel and wood) is unchanged. These are subjective improvements judged from screenshots; no side-by-side human preference test was done.

## 7. Performance, before vs after [phone, same session, protocol as 1.5]

| | 1.5 final (from the 1.5 report) | 1.6 final run 1 | 1.6 final run 2 | 1.6 control (1.5 sharpness) |
|---|---|---|---|---|
| All-frames avg FPS | 57.9 / 58.5 | 57.9 | 58.8 | 57.5 |
| Idle / active / extraction FPS | 58.5 / 56.7 / 56.0 and 59.1 / 58.3 / 56.4 | 58.3 / 58.1 / 55.9 | 59.0 / 57.5 / 55.4 | 57.8 / 57.7 / 56.5 |
| Median / P95 / P99 | 16.7 / 19.4 / 27.7 and 16.7 / 18.2 / 27.9 ms | 16.7 / 20.0 / 27.5 | 16.7 / 18.1 / 25.5 | 16.7 / 20.8 / 27.4 |
| Worst steady-state frame | 82 / 94 ms | 142 ms (one idle hitch) | 89 ms | 92 ms |
| PSS memory | 268 MB | 285 MB | 285 MB | 282 MB |

Frame rate is unchanged within run-to-run noise (+-1 FPS). Memory is about 15 MB higher than the 1.5 runs (282-285 vs 268); the control run is also at 282, so it is not the sharpness setting, and I did not isolate it (candidates: the new PauseMenu / rhythm code are tiny; the difference may be measurement state). Startup was not changed this milestone and was not re-measured. Extraction is still the weakest state (~56 FPS).

## 8. Tests [desktop, simulated input; one clean run of everything]

| Suite | Result |
|---|---|
| Unit (`run_tests.gd`) | all pass: **106 checks** (58 before + 48 new: rule boundaries, ExtractionManager stall/slow behaviour, real-clock InputController checks, difficulty curve/independence/presets) |
| Integration | 193 / 193 |
| Failure | 116 / 116 |
| Layout | 256 / 256 |
| Timer lifecycle | 25 / 25 |
| Startup / quality settings | 16 / 16 |
| Pause menu / Back | 41 / 41 |
| **New: rhythm** (`tests/rhythm_tests.gd`) | **62 / 62**: first tap awards nothing; first valid pair awards one gain; slow tap awards nothing, no kick, no decay reset, re-anchors; steady 0.55 s tapping never gets progress and fails; same-side repeats ignored and do not disturb timing; 30 rapid taps with every event duplicated give exactly (accepted - 1) gains; two fingers at once -> one tap; interval tightens on levels 1-3 and follows the override; pause freezes progress and the zero-progress stall timer, resume gives a FIRST tap and no "TAP FASTER"; retry restores hint and FIRST; rule switch off; panel size and whole-half touch area; sword motion at slow / normal / very rapid speeds |

**Existing checks I changed on purpose (the first-tap rule is exactly the behaviour you asked to change), 12 in total, none weakened:** integration - "after N valid taps progress = 8N" now expects 8(N-1) (first tap awards 0); "valid tap sets the full kick" now first asserts the first tap gives no kick, then a valid tap does; "slipping state clears after the next valid tap" now first asserts that a slow tap does not clear it; the kick-settle wait went from 0.2 to 0.4 s (the low-pass tail) and a priming tap was added before the "same kick for every tap" loop (the longer wait made the next tap legitimately TOO_SLOW). Failure - a single tap now fails after grace + interval (0.91 s measured, was 2.1 s), the run-result time floor went from 1.5 s to 0.75 s, and three "first tap starts a new extraction" checks now use a first tap plus one quick tap. The first full run after the change showed these 11 failures, which is how I found them; one more appeared after my own settle-wait edit and was fixed (see above). A parallel earlier run during the session had false failures from a test window losing OS focus; the final run was clean.

## 9. Physical-device results [phone, 0.1.6 installed; injected touches, not a finger]

Taps were run by a loop on the phone itself (host-side adb calls were too slow to time taps); an `input tap` costs ~81 ms. Results come from the game's own `PerfProbe` log (kind, interval, progress after each tap).
- **Slow tapping (~0.6 s gaps):** tap 1 = FIRST (0 progress); tap 2 at 600 ms = TOO_SLOW (interval 600.5 ms, progress 0.0); FAILED 0.88 s after the first tap (0.9 s predicted). No progress ever awarded.
- **Normal tapping (~0.2 s gaps, 80 taps):** 42 PROGRESS taps, mean interval 205 ms (max 233), 0 TOO_SLOW; **3 level extractions** completed (progress 8, 16, ... 96, 100; levels 2 and 3 started with a FIRST tap, gains 7.7 then 7.5 per tap), and one failure when the taps ended. Note levels 1, 2, 3 took 13, 13, 14 progress taps with the older 10-level interval curve (see section 3); the 8-level curve was built after this run, and on the phone I only re-checked rapid tapping, pause/resume and performance afterwards.
- **Rapid tapping (back-to-back, ~80-110 ms gaps):** 26 follow-up taps all PROGRESS (69-160 ms), 2 extractions, no failure; screenshots show no blocky artefacts beyond the 0.6-scale pixels.
- **Pause / resume (real Back key):** 6 taps in rhythm (progress 40.0), Back -> PAUSED (menu screenshot `dev16_paused.png` taken), 8.5 s later RESUME -> PLAYING; the first tap after resume was FIRST with progress 31.5 (the bar decayed for the ~1.6 s it took my script to tap after resuming, not for the paused time), then PROGRESS taps (+8.0 each).
- **Failure and retry:** failure screen shown (THE SWORD REMAINS, session 0:00.88); TRY AGAIN restarted at READY; the first tap after the retry was FIRST with progress 0.0.
- **Control size:** panels about 283 x 199 px on the 720 x 1600 screen, balanced left/right (device screenshot).
- **Level transitions:** 3 in the normal run on the older curve; the final 8-level curve was only exercised by the first two levels of later runs.
Not tested on the phone: a human finger / thumb accuracy with the smaller panels, whether 400 ms (and the tightening curve) feels right, the "TAP FASTER" hint in play, Android gesture-navigation Back, other devices.

## 10. Remaining issues

- **Feel is untested by a person.** All device taps were machine-timed; whether 400 ms -> 220 ms, the stall failure after 0.9 s, and the smaller panels feel right needs your hands.
- Levels still depend on how fast the player already taps: with natural 150-200 ms tapping the interval limit only bites late; use the lever in section 3 if you want it earlier.
- The new stall rule (fail 0.9 s after the first tap if no valid pair follows) is strict at the very start of a run; make it softer (e.g. a longer start grace) if testers fail before they have settled.
- Rapid-tap smoothness is proven by a desktop measurement, not by an on-device video.
- Stair-stepping from the 0.6 render scale remains; MSAA/FXAA/higher scale still cost 14-17 FPS or fall off the 60 FPS cliff (1.5 data).
- QUIT still exits the app (no main menu); memory +15 MB vs 1.5 unexplained; extraction animation still ~56 FPS; startup not re-measured.
- `docs/PLAYTEST_PRESETS.md` now has a short interval table; its older level-1 table still describes the gain/decay/grace values only.
