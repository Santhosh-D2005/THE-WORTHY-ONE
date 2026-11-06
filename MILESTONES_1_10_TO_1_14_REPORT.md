# THE WORTHY ONE – Milestones 1.10 to 1.14: Consolidated Report

Godot 4.7.2, Android portrait, target vivo V2129. Version stays **0.1.9 (code 7)**: nothing in the request gave a reason to change it.

**Read this first.** All five milestones are implemented and verified on the desktop. **The new build was NOT installed or run on the phone** (it was not connected; you chose to skip phone testing). **No Android FPS, memory or input-delay number exists for this build.** The cost of the new effects on the phone is unmeasured, and so is the ~30 FPS you reported (see section E). No person has played this build.

---

## A. Summary

| Milestone | What was built | State |
|---|---|---|
| 1.10 Sword micro-motion | A bounded, heavy, critically damped lean and tiny lift of the one rigid sword under valid taps; settles to exactly the embedded pose when tapping stops | Implemented, desktop-verified |
| 1.11 Inward forest compression | Background trunks drift toward the stump by up to 7 % of their x/z distance as strain rises (translation only, no deformation) | Implemented, desktop-verified |
| 1.12 Reversible cracks | Procedural cracks in the stump's cut-face shader: nine radial cracks that open one after another, fork at about 50 % and 70 %, and close again when progress falls | Implemented, desktop-verified, looked at in screenshots |
| 1.13 Amber glow | Restrained amber emission only inside the crack cores, scaled by progress, with a slow bounded ±6 % breathing | Implemented, desktop-verified, looked at in screenshots |
| 1.14 Coordinated extraction | One shared controller drives compression, cracks and glow; cracks and glow are at maximum before the blade is released, then the forest unwinds and the glow closes first | Implemented, desktop-verified |

Simplified on purpose: the cracks are on the **cut face only** (not on the bark sides), and the glow is a material emission, not a light. I removed the placeholder's always-visible "drying cracks" from the cut-face shader, because the spec requires no visible cracks at 0 %.

Not done: anything on the phone; no human playtest; no release build.

## B. Architecture

**Files modified or added**

- `scripts/gameplay/sword_controller.gd`: micro-motion, transform ownership fix.
- `scripts/gameplay/extraction_fx.gd` (new): the shared controller.
- `scripts/gameplay/forest_environment.gd`: `set_compression()`, trunk list.
- `scripts/gameplay/stump_builder.gd`: `set_cracks()` (two shader uniforms).
- `shaders/wood_top.gdshader`: cracks and glow.
- `scripts/managers/level_manager.gd`: wiring only (creates the controller, forwards progress, completion, release, failure, retry).
- Tests: `tests/fx_tests.gd/.tscn` (new, 50 checks); adapted `tests/rhythm_tests.gd`, `tests/integration_tests.gd`, `tests/experience_tests.gd`, `tests/speed_tests.gd`.
- Tool: `tools/fx_shots.gd/.tscn` (screenshots at 0/25/50/75/100 %).
- Debug-build-only switches for measuring: `--no-fx`, `--no-compress`, `--no-cracks` (read via the existing `launch_args.txt`, ignored in release).

**Transform ownership (sword).** While playing, `SwordController._process` is the only writer of the blade's `_visual` position and roll (z). The extraction tween owns `_visual.rotation:y` only. I found and removed a real conflict: the old code forced `_visual.rotation = ZERO` every frame, including during the extraction anticipation, which also tweens `rotation:y`. That per-frame overwrite is a plausible contributor to the earlier vibration, but I did not prove it was the cause. The root's height is still only a function of progress. The micro-offset is wiped on reset, entrance, and at the release; on failure it eases out together with the seating motion instead of snapping.

**Shared state.** `ExtractionFx` holds one number, `strain` (0..1), the extraction progress smoothed by a frame-rate-independent exponential follow. Compression = strain, cracks = strain, glow = `glow_for(strain)` × a gate. There are no per-effect timers. Modes: follow progress, `anticipate()` (push to 1 fast so cracks and glow are at maximum before the release), `release()` (strain falls, glow gate closes faster), `fade_out()` (failure), `reset()` (snap to baseline at a new level / retry). It is a child of the Stage so it pauses with the game, and it switches its own `_process` off when nothing changes. The existing speed-based progress formula, difficulty, timers and camera tension/exposure logic are untouched.

## C. Feature results

**1.10 Sword micro-motion**
- Behaviour: each valid tap sets an effort that fades over about 0.55 s; the blade leans a few millimetres (side ≤ 0.006 m, roll ≤ 0.009 rad, lift ≤ 0.005 m, scaled up with progress) through critically damped springs (no overshoot). The lean changes side at most once per 0.45 s, so it is a slow rocking, never a per-tap shake. (My first version flipped the side on every tap and tripped the rhythm test at 13.6 direction reversals/s; that is why it is time-based now.)
- Measured on the desktop (windowed, simulated taps, in phone render pixels): sideways travel of the pommel 1.55 px at 300 ms taps, 2.17 px at 200 ms, 3.06 px at 70 ms (an unrealistically fast 14 taps/s). Vertical direction reversals: 0 at all three speeds. Biggest single-frame move 0.78 px, biggest speed change 0.21 px.
- Acceptance: bounded (checked), settles to exactly zero (checked), no drift over repeated attempts (checked), pause/resume without a jump (checked: micro change < 0.004 m, strain change < 0.02), failure/retry restore the pose (checked), final extraction intact (checked), blade never scaled (checked).
- Limitation: amplitudes were chosen on the desktop. Whether it reads as "heavy and subtle" on the phone's 0.6-scale upscaled image is unverified; the 1.7 history shows sub-pixel edge crawl is a real risk there.

**1.11 Forest compression**
- Chosen technique: translate the 46 background trunks toward the stump (x and z × (1 − 0.07·strain)). No tree is scaled or rotated (checked in the test). One technique only, as asked.
- Acceptance: 0 at zero progress with every trunk exactly at its home position (checked); tracks progress both ways (checked: 25/50/75 % give 0.25/0.50/0.75); releases smoothly after the extraction (checked); reset on failure/retry (checked); pause freezes it (checked).
- Limitation: I verified the numbers and the "translation only" property, but I did **not** review a rendered frame of the compression by eye (my screenshots were of the cracks). Whether 7 % is perceptible, subtle or too much is a visual judgement still open. It is a single constant (`ForestEnvironment.COMPRESSION`).

**1.12 Reversible cracks**
- Implementation: analytic shader cracks on the cut face. Nine radial cracks with per-crack start and length, wandering lines, two fork generations from about 50 % and 70 %, a darkened wood halo; no geometry, no texture, no transparency layers; the code path is skipped when the amount is ~0.
- Acceptance: nothing at 0 % (checked, `crack_amount == 0`); fine cracks appear by 25 %, extend at 50 %, branch at 75 %, strongest at 100 % (judged from `build/shots/fx4_zoom.png`); the amount equals current strain, so it recedes when progress falls and returns to exactly 0 (checked); failure/retry reset (checked); no mesh or asset is modified.
- Limitation: judged only in desktop screenshots at 540×960. Hairline width at the phone's smaller render size may alias or look thinner.

**1.13 Amber glow**
- Implementation: emission = amber × crack core × glow level (0.29 at 25 %, 0.50 at 50 %, 0.73 at 75 %, 1.0 at 100 %, checked), brighter toward the slot, slow ±6 % breathing. No lights, no particles, no post-processing.
- Acceptance: only inside cracks (by construction, looked at in screenshots), tracks progress both ways (checked), zero at zero progress (checked), closes quickly after the release (checked: below 0.4 half a second after the release).
- Limitation: my first colour was too bright and yellow on the pale wood (looked neon); I reduced it and judged the final look by eye on the desktop only. Colour and brightness on the phone's screen are unverified.

**1.14 Polished extraction**
- Checked in the real extraction: at the moment of release cracks, glow and strain are all above 0.97 and the compression above 0.97; the micro-motion residue is under 0.5 mm so the pull does not jump; after the release the compression unwinds (about 0.2 half a second later) while the glow closes first; the completion card shows; the next level starts with no cracks, no glow, no compression, no micro offset and the camera back at its framing.
- Failure: cracks and glow are gone, the sword is exactly embedded, repeated 5 times with no scene-node growth (checked). Retry returns everything to the baseline and the controller switches itself off (checked).
- The completion card content (extraction time, swords extracted, no tap counts) was not changed.

## D. Testing

All on the desktop, with **simulated** input (`InputController.handle_tap`), never a person.

| Suite | Result |
|---|---|
| Unit | ALL PASSED |
| Integration | 194 checks, 0 failed |
| Failure | 116 checks, 0 failed |
| Layout | 256 checks, 0 failed |
| Timer | 25 checks, 0 failed |
| Startup | 16 checks, 0 failed |
| Pause | 41 checks, 0 failed (last run before the final micro-amplitude tuning, which does not touch pause) |
| Rhythm | 63 checks, 0 failed |
| Speed (speed-based extraction) | 50 checks, 0 failed (last run before the amplitude tuning; does not read it) |
| Experience (windowed) | 72 checks, 0 failed, 0 focus-loss pauses |
| **New** fx (1.10–1.14) | 50 checks, 0 failed |

**Existing tests changed (rules deliberately changed by 1.10, documented in the test source).** Several checks encoded the 1.7 rule "the blade has no tap offset or tilt of any kind", which 1.10 replaces. I adapted them to the new bounds rather than removing them: rhythm sideways limit 1.0 → 3.5 render px and reversals 2.0 → 3.5/s (still far below the old shake's 5–9 px and 13–29/s); experience sideways limit 0.5 → 3.5 px and the "clean visual" check now allows only the bounded micro-motion and still requires rigidity; "kick settles" now checks under 1 mm / 0.1° after 0.9 s (waiting longer let the single tap decay into a failure), and the experience check waits for exact zero; the zero-offset assertions after the taps stop are kept.

**Existing flaky or timing-fragile checks seen (and what I did).**
1. Speed test "0.35 s after stopping nothing is lost yet": it waited 0.35 s from the end of the tap loop, but the grace period counts from the last tap, which can be ~0.14 s earlier, so the total sat right on the 0.5 s limit. It failed on two runs in a row. I changed it to wait 0.35 s from the last tap (the test already recorded that time and did not use it); the assertion is unchanged.
2. Integration timer checks ("level timer continued from the frozen value") failed once with an absurd value (0.448 → 789.081) and passed on every later run; I did not find the cause and have not seen it again. Treat it as an unexplained intermittent failure.
3. Experience suite: earlier (before my changes) one card-fade check and one sword-motion smoothness check each failed once; this session's windowed runs were repeatedly invalidated by the OS taking window focus (3 runs in a row at one point), and the final run was clean. Frame-time-based checks can still be tripped by desktop hitches; I did not root-cause that.

**Defects found by my own tests during development (all fixed):** per-tap sideways flipping (vibration-like, 13.6 reversals/s); a variable name clash in the sword script; compression/crack timing assertions in my new tests.

**Not run:** any phone test; a human playtest; a release build; a long-session thermal run; a memory-growth measurement on the phone (only the desktop scene-node count over five failed attempts was checked).

## E. Performance

**There is no Android measurement for this build.** Everything below is about expectations and what was measured earlier.

- Last measured on the phone (Milestone 1.9.2, `PerfProbe`, **injected adb taps**, not a human): READY about 52–58 FPS, PLAYING about 50–53, EXTRACTING about 44–48, memory about 281–283 MB PSS in the three final runs.
- **You report about 30 FPS in real play. I could not reproduce or explain that gap.** The PerfProbe numbers above came from injected taps at the same screen positions; they do not include a real thumb, a warm phone after long play, background apps, or a different power mode. A comparable measurement while a person plays (with `--perf-log` on) is the way to establish the real baseline. Until then the earlier numbers should not be taken as representing real play.
- Expected cost of the new work (reasoning, not a measurement): compression is 46 position writes on frames where strain changes; the crack/glow shader runs only on the cut-face pixels and its branch is skipped when the amount is ~0, using no texture reads; no lights, particles, transparency or post-processing were added; the controller idles when nothing changes. The earlier lesson on this GPU is that a single changed light or an extra full-screen cost can lose 5–9 FPS at its 60 FPS cliff, so these costs must be measured, not assumed. The debug switches `--no-fx`, `--no-compress`, `--no-cracks` exist to isolate them on the phone.
- No desktop FPS numbers are given: desktop frame timing is not comparable with the phone.

## F. Android build

- APK (debug, exported with the existing configuration and signing): `D:\photos\gamic\THE WORTHY ONE\build\android\TheWorthyOne-debug.apk` (36,090,625 bytes).
- Version name 0.1.9, version code 7 (unchanged); package `com.theworthyone.game` (unchanged).
- **Not installed and not launched on the physical phone.** It is a debug build and is not release-ready.

## G. Remaining risks and next steps

1. **Phone performance of the new effects is unknown** (largest risk). Install the APK, measure READY/PLAYING/EXTRACTING with interleaved runs against the 1.9.2 build, using the `--no-fx` / `--no-cracks` / `--no-compress` switches to isolate any drop.
2. **The reported ~30 FPS is unexplained.** Measure while a person plays, before tuning anything.
3. **Visual judgement on the phone:** micro-motion amplitude (edge crawl risk at the 0.6 render scale), compression strength (7 %, not reviewed in a rendered frame), crack hairline width, glow brightness/colour.
4. Cracks exist only on the cut face; they are not on the bark sides.
5. Unexplained intermittent failure of the integration timer checks (once) and the usual desktop frame-hitch sensitivity of the windowed experience suite.
6. Difficulty and feel have never been human-played.

## H. Final decision

**READY FOR REVIEW**: for the code and desktop verification only. This is not a statement about the phone: Android performance of this build and the user-reported 30 FPS remain unverified and are the gate before accepting it as finished.
