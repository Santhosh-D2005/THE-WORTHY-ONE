# Milestone 1.9 - Speed-based extraction and visual overhaul (version 0.1.9)

**Read this first - what was and was not tested.**
- **Desktop automated tests:** done, all pass (section 9).
- **Android injected-input tests:** **NOT done for 0.1.9.** You chose to skip phone testing again. The 0.1.9 APK was exported (`build/android/TheWorthyOne-debug.apk`, 22:10) but has **never been installed or run on the device**. There is no Android FPS, memory, crash or Back/pause result for this version.
- **Human playtest:** none. Whether the new rhythm feels like 5-6/10, and whether the forest looks better to a person, is **unjudged**.

The performance target (55-60 FPS on the vivo V2129) is therefore **unverified**, and the visual changes in section 6 may have cost frames (see section 8).

---

## 1. The new speed-based progress formula

There is no fixed number of taps any more. Each valid alternating tap adds an amount that depends on the **measured time since the previous alternating tap** (`scripts/managers/speed_gain.gd`, a pure function):

```
x      = clamp((useful - interval) / (useful - optimal), 0, 1)       # 1 at the optimal speed, 0 at the slowest useful speed
x      = clamp((x - 0.08) / (1 - 0.08), 0, 1)                         # dead zone: the slowest 8 % of the window earns nothing
shape  = x ^ exponent                                                 # exponent 1.4: faster is rewarded more than proportionally
cap    = min(1, interval / optimal)                                   # faster than optimal never raises progress per second
gain   = peak * shape * cap
tap's real gain = gain * (1 - resistance * progress / 100)            # resistance: the last stretch needs faster tapping
```

- `interval >= useful` (minimum useful speed) gives exactly 0.
- Same-side taps are rejected before this (no timing, no progress). The first tap of an attempt awards 0. Debounce (25 ms) and the input lock are unchanged.
- Progress is clamped to 100 and the sword is extracted the moment it reaches 100.
- The bar is continuous-looking (the display eases to the real value) while the label is a whole number (`floor`).

Configurable in `DifficultyConfig` (`default_difficulty.tres` or the inspector): **peak gain** (start/end/ramp), **optimal interval** (130 ms), **minimum useful speed** (a fraction, 0.85, of the level's maximum interval), **maximum acceptable interval** (start/end/ramp, 400 -> 300 ms), **gain curve exponent** (1.4), **resistance** (start/end/ramp, 0 -> 0.35), **decay and grace** (the approved 1.3 curves, unchanged), the **difficulty ramps**.

Worked example, level 1 (peak 6 %, optimal 130 ms, useful 340 ms): a steady 4 taps/s earns about 1.7 % per tap; 5 taps/s about 3.4 %, 6 taps/s about 4.6 % per tap. That is 16.3 s, 6.4 s and 3.8 s to extract.

## 2. Difficulty scaling (levels 1-30)

Difficulty rises through a **narrower window of useful speeds** (the useful interval shrinks 340 -> 266 ms), **more resistance** (0 -> 0.32), a **slightly smaller peak gain** (6.0 -> 4.7 %, "more effort"), and the unchanged decay/grace curves. It does **not** rise through any tap count. The last four columns are the time a perfectly steady tapper needs at that speed ("-" = that speed makes no progress).

| Level | Peak gain %/tap | Useful below ms (taps/s) | Max gap ms | Resistance | Decay %/s | Grace s | 4 taps/s | 5 taps/s | 6 taps/s | 7 taps/s | Reward |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 6.00 | 340 (2.9) | 400 | 0.00 | 5.0 | 0.50 | 16.3 s | 6.4 s | 3.8 s | 2.7 s | 0.0 |
| 2 | 5.90 | 334 (3.0) | 393 | 0.03 | 5.7 | 0.48 | 18.0 s | 6.8 s | 4.0 s | 2.7 s | 0.1 |
| 3 | 5.80 | 329 (3.0) | 387 | 0.05 | 6.4 | 0.46 | 20.0 s | 7.0 s | 4.2 s | 2.9 s | 0.2 |
| 4 | 5.71 | 324 (3.1) | 381 | 0.08 | 7.0 | 0.44 | 22.0 s | 7.4 s | 4.3 s | 3.0 s | 0.3 |
| 5 | 5.63 | 319 (3.1) | 375 | 0.10 | 7.6 | 0.43 | 24.3 s | 7.8 s | 4.5 s | 3.0 s | 0.4 |
| 6 | 5.55 | 314 (3.2) | 370 | 0.12 | 8.1 | 0.41 | 26.8 s | 8.2 s | 4.5 s | 3.1 s | 0.5 |
| 7 | 5.48 | 310 (3.2) | 365 | 0.14 | 8.5 | 0.40 | 29.8 s | 8.6 s | 4.7 s | 3.1 s | 0.6 |
| 8 | 5.41 | 307 (3.3) | 361 | 0.15 | 9.0 | 0.39 | 33.0 s | 9.0 s | 4.8 s | 3.3 s | 0.7 |
| 9 | 5.35 | 303 (3.3) | 356 | 0.17 | 9.4 | 0.38 | 36.5 s | 9.4 s | 5.0 s | 3.3 s | 0.8 |
| 10 | 5.29 | 300 (3.3) | 353 | 0.18 | 9.7 | 0.37 | 40.8 s | 9.6 s | 5.2 s | 3.4 s | 0.9 |
| 11 | 5.23 | 297 (3.4) | 349 | 0.20 | 10.1 | 0.36 | 45.3 s | 10.0 s | 5.3 s | 3.4 s | 1.0 |
| 12 | 5.18 | 294 (3.4) | 346 | 0.21 | 10.4 | 0.35 | 50.5 s | 10.4 s | 5.3 s | 3.6 s | 1.0 |
| 13 | 5.14 | 291 (3.4) | 342 | 0.22 | 10.7 | 0.34 | 56.3 s | 10.8 s | 5.5 s | 3.6 s | 1.0 |
| 14 | 5.09 | 289 (3.5) | 340 | 0.23 | 11.0 | 0.33 | 63.0 s | 11.2 s | 5.7 s | 3.7 s | 1.0 |
| 15 | 5.05 | 286 (3.5) | 337 | 0.24 | 11.2 | 0.33 | 70.5 s | 11.6 s | 5.8 s | 3.7 s | 1.0 |
| 16 | 5.01 | 284 (3.5) | 334 | 0.25 | 11.4 | 0.32 | 79.0 s | 12.0 s | 5.8 s | 3.9 s | 1.0 |
| 17 | 4.98 | 282 (3.5) | 332 | 0.26 | 11.6 | 0.32 | 89.0 s | 12.4 s | 6.0 s | 3.9 s | 1.0 |
| 18 | 4.95 | 280 (3.6) | 330 | 0.27 | 11.8 | 0.31 | 100.3 s | 12.6 s | 6.2 s | 3.9 s | 1.0 |
| 19 | 4.91 | 278 (3.6) | 328 | 0.27 | 12.0 | 0.31 | 113.5 s | 13.0 s | 6.2 s | 4.0 s | 1.0 |
| 20 | 4.89 | 277 (3.6) | 326 | 0.28 | 12.2 | 0.30 | 128.8 s | 13.4 s | 6.3 s | 4.0 s | 1.0 |
| 21 | 4.86 | 275 (3.6) | 324 | 0.28 | 12.3 | 0.30 | 146.5 s | 13.8 s | 6.3 s | 4.0 s | 1.0 |
| 22 | 4.83 | 274 (3.7) | 322 | 0.29 | 12.4 | 0.29 | 167.3 s | 14.0 s | 6.5 s | 4.0 s | 1.0 |
| 23 | 4.81 | 273 (3.7) | 321 | 0.29 | 12.6 | 0.29 | 192.0 s | 14.4 s | 6.5 s | 4.1 s | 1.0 |
| 24 | 4.79 | 271 (3.7) | 319 | 0.30 | 12.7 | 0.29 | 221.3 s | 14.6 s | 6.7 s | 4.1 s | 1.0 |
| 25 | 4.77 | 270 (3.7) | 318 | 0.30 | 12.8 | 0.28 | 256.5 s | 15.0 s | 6.7 s | 4.1 s | 1.0 |
| 26 | 4.75 | 269 (3.7) | 317 | 0.31 | 12.9 | 0.28 | 299.3 s | 15.2 s | 6.8 s | 4.1 s | 1.0 |
| 27 | 4.73 | 268 (3.7) | 316 | 0.31 | 13.0 | 0.28 | 351.8 s | 15.6 s | 6.8 s | 4.3 s | 1.0 |
| 28 | 4.72 | 267 (3.7) | 315 | 0.31 | 13.1 | 0.28 | 417.0 s | 15.8 s | 6.8 s | 4.3 s | 1.0 |
| 29 | 4.70 | 267 (3.8) | 314 | 0.32 | 13.1 | 0.27 | 499.3 s | 16.0 s | 7.0 s | 4.3 s | 1.0 |
| 30 | 4.69 | 266 (3.8) | 313 | 0.32 | 13.2 | 0.27 | 605.5 s | 16.4 s | 7.0 s | 4.3 s | 1.0 |

Reading it: at level 1 a normal 5 taps/s player extracts in about 6 s and a brisk 6 taps/s player in under 4 s; by level 10 a 4 taps/s player needs about 40 s (effectively the rhythm demand), while 5 taps/s still takes under 10 s; by level 30 only 5-7 taps/s is comfortable. **The 5-6/10 target is a design intent for the early game, not a measured result**: no player has tried it.

Presets (`forgiving`, `demanding`, `gain_high`, `grace_long`, `decay_slow`) were retargeted to the new parameters and still change only their own parameters (tested). The decay system was **not** modified.

## 3. Old versus new gameplay architecture

| | 0.1.8 (fixed tap count) | 0.1.9 (speed based) |
|---|---|---|
| What defines an extraction | A table: 15, 17, 20 ... taps. Gain per tap solved so that exactly N taps fill the bar | Nothing fixed. Progress per tap = f(measured interval) |
| Effect of tapping faster | The same number of taps, only done sooner | Each tap is also worth more, so progress per second grows faster than the tapping speed (up to the optimal speed) |
| Slow tapping | Positive progress per tap | Exactly 0 below the minimum useful speed |
| Difficulty | More taps, a shorter gap | A narrower useful speed window, resistance, a smaller peak gain |
| Completion card | Level, time, taps, session time | Level, **extraction time**, swords extracted |
| `DifficultyConfig` | `required_taps_table`, `taps_to_extract`, `gain_for_level` | removed; `peak_gain_for_level`, `min_useful_interval_for_level`, `gain_for_interval`, `simulate_extraction_seconds` |
| `ExtractionManager` | `register_valid_tap()` adds `gain_per_tap` | `register_valid_tap(interval_ms)`; `gain_per_tap` is now the peak gain; `configure_speed(...)` |

Dependencies inspected before the change: `DifficultyConfig` (table, solver), `DifficultyManager` (print, signals, new `speed_changed`), `ExtractionManager`, `LevelManager` (`_level_taps` is now debug only), `Hud` (card), `TapRhythm`/`InputController` (already measured the interval; unchanged), `PerfProbe` (still logs tap counts for debugging), the presets and eight test files. `TimerManager`, pause, failure/retry, the discs and the safe-area code were not touched.

## 4. Extraction-time measurement

The level timer (`TimerManager`) already started on the first valid (accepted) tap and was stopped in the same call that detects 100 %, using a monotonic microsecond clock, frozen while paused. 1.9 uses it as the primary statistic and formats it `MM:SS.cc` (for example `00:08.42`).

Verified (desktop, injected taps at exact intervals): at 125, 150, 170, 200 and 230 ms the reported extraction time equalled the measured wall time within 0.1 s and the model within 0.01 s (for example 6.41 s measured, 6.40 s predicted at 5 taps/s); also checked on levels 1-10.

## 5. Completion card

Now: `THE SWORD YIELDS` / `LEVEL N COMPLETE` / `EXTRACTION TIME   00:08.42` / `N SWORDS EXTRACTED` (`1 SWORD EXTRACTED` for one). Removed: tap count, required taps, taps per level, session time. A test checks that no text on the card contains "TAP".

**Personal best: not shown.** There is no reliable implementation (the code deliberately keeps no lifetime records), and the brief says to show it only if one exists. Internally taps are still measured for gameplay and debugging; they are never presented.

## 6. Visual environment changes (desktop-verified look, not measured on the phone)

Before/after on the same render settings as the phone ("balanced"): `build/shots/disc_baked3.png` (before, the 1.7/1.8 look) and `build/shots/v19_b_balanced.png` (after).

| Area | Change |
|---|---|
| Foreground / depth | New **fern undergrowth** (`foliage_builder.gd`, `fern.gdshader`): two multimeshes, 26 near and 26 far clumps at the sides and behind the stump, one draw call each, no shadows. They frame the stump and separate foreground from background. The middle of the picture stays open. |
| Foliage motion | A very gentle idle sway (vertex shader, tips only) and a short, soft gust of the undergrowth when a sword comes free (the environment's response). |
| Trunks | Five natural bark tones (warm brown, grey-brown, mossy green-brown, dark wet bark) instead of two near-identical greys; the nearer trunks use the darker ones. The same two noise textures are reused, so no extra texture memory. |
| Ground | A richer forest floor shader (same 3 texture reads): damp dark soil, brown litter, rust-brown dry leaves, moss, darker and damper near the stump. |
| Stump top | Thin dark late-wood lines at each growth ring and a gentle warm gradient across the cut. |
| Sword | Cooler, more metallic steel (metallic 0.70, roughness 0.24) with a tight sun glint on the bevels; no glow. |
| Atmosphere | Warm green haze fog, slightly denser, plus a knee-high ground mist that thickens toward the floor. |

## 7. Colour grading and lighting changes

- Sky: deeper blue-green canopy at the top (0.17, 0.30, 0.36), a warm sunlit haze at the horizon (0.74, 0.72, 0.54).
- Sun: warmer (1.0, 0.82, 0.55), same direction and energy; ambient fill lowered from 1.15 to 0.95 so shadows keep depth.
- Tone mapping stays ACES; contrast 1.12 -> 1.14; **saturation lowered to 1.0** (the brief says not to simply add saturation); no bloom, no glow, no neon, no filter.
- Whether this "looks realistic" is a judgement for a person; the desktop screenshots look natural to me, but that is not a playtest.

## 8. Performance

**No Android measurement for 0.1.9.** Last device figures (0.1.7 final): about 58 FPS overall and idle, 47-48 FPS during extraction, about 278 MB.

What I changed that could cost or help, all **unproven**:
- Possible cost: knee-high **height fog** (per-pixel, in the fog that was already enabled), foliage draw calls (2 more), the foliage vertex shader, a slightly more expensive ground shader (a few more ALU operations, same texture reads), 52 fern instances (~5 k triangles in total).
- Possible help for extraction frames: 1.8 already removed the FOV change and the random camera offsets; 1.9 keeps that.
- The game sat at the 60 FPS cliff on this phone (small GPU costs caused large FPS drops in 1.7), so a regression is a real possibility. The fastest way to find out is to run the existing device protocol (`/tmp`-style batch: warm run + two interleaved runs of 0.1.8 vs 0.1.9) once the phone is available, and use `--no-light-fx`, `--no-cam-fx`, `--no-card` to isolate the extraction cost. If the foliage or the fog turns out to be the cause, they can be disabled by quality preset.

## 9. Test results

Desktop automated (final code):

| Suite | Checks | Result |
|---|---|---|
| unit (`run_tests`) | all | ALL PASSED, 0 failures |
| integration | 194 | 0 failed |
| failure / retry | 116 | 0 failed |
| layout / safe area | 256 | 0 failed |
| timer | 25 | 0 failed |
| startup | 16 | 0 failed |
| pause / Back | 41 | 0 failed |
| rhythm | 63 | 0 failed |
| experience (progress, extraction, card, discs, motion) | 72 | 0 failed (windowed run, 0 focus-loss pauses) |
| **speed (new, `tests/speed_tests.gd`)** | 50 | 0 failed |

What the new speed suite covers (real `main.tscn`, scripted tapper at exact wall-clock intervals, headless): very fast (125 ms), fast (150, 170 ms), normal (200 ms) and steady (230 ms) tapping each extract, the time matches the model, and **extraction gets strictly faster with every step up in speed** (2.26, 3.00, 4.08, 6.41, 10.82 s); the tap counts differ (19 taps at 8/s versus 48 at 4.3/s: no fixed count); tapping at an impossible 60 ms is not faster than the optimal speed; 3 taps/s and 520 ms alternating make no progress; same-side taps give nothing; an irregular 150-260 ms rhythm extracts within the expected range; a lopsided 120/280 ms rhythm is slower than steady 200 ms; stopping midway holds for the grace period and then decays at 5 %/s; levels 1-10 at 150 ms each extract at the modelled time; level 10 cannot be finished at 4 taps/s in 12 s.

Notes for honesty:
- Existing checks that encoded the 1.7/1.8 rules (fixed tap counts, per-tap gain, the card text, FOV, the rotation sequence) were rewritten with the reason in comments. The unit and experience suites were rewritten for the speed model; the integration suite went from 202 (1.7) to 194 checks earlier in 1.8 and is unchanged here.
- The windowed experience suite reports `INVALID RUN` when the OS takes window focus; this happened on several runs on this PC and they were repeated until valid. Headless runs are used for logic suites and the speed suite because their frame timing is irrelevant there.
- Failure/retry, pause/resume and Back are covered by the (adapted) desktop suites with simulated input. **None was run on Android for 0.1.9.**
- **No human playtest** of 0.1.9.

## 10. Remaining issues

1. **Android not tested for 0.1.9**: FPS, memory, crashes, the new fog/foliage cost, transition stability.
2. **No human playtest**: the 5-6/10 early difficulty, whether 4 taps/s feels "steady", whether the extraction (release, card) is satisfying, and whether the new forest looks better, are all unjudged.
3. Decay is unchanged as instructed, but a faster, more rewarding tap makes a lapse costlier in progress at higher levels (a 1 s lapse costs 9.7 % at level 10 against a gain of about 17 % per second at 5 taps/s).
4. Higher levels (above about level 12) are only verified by the model and the desktop tests.
5. Audio cues still have no assets (silent).
6. No personal best (no reliable implementation exists).
7. The debug switches (`--no-cam-fx`, `--no-light-fx`, `--no-card`, `--no-discs`) remain; they act only in debug builds with a launch-args file.
8. The level timer measures from the first valid tap, so a very slow first stretch (3 taps/s) counts as part of the extraction time, as intended.

## 11. Screenshots (desktop captures, not the phone)

- Environment (phone quality settings): `build/shots/v19_b_balanced.png` (after); `build/shots/disc_baked3.png` (before).
- Completion sequence with the new look and card (`EXTRACTION TIME 00:02.75`, `1 SWORD EXTRACTED`; the tool sets the level directly, so the sword count reads 1): `build/shots/m19_L1_strip.png`, `build/shots/m19_L5_strip.png`, `build/shots/m19_L10_strip.png` (8 frames each, left to right, top to bottom).
- No 0.1.9 screenshot from the phone exists.
