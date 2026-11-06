# THE WORTHY ONE – Milestone 1.25 Report: Harder Levels and a Brighter Background

Written for: the project owner. Based on two issues found while hand-testing the game. **Desktop (Godot, headless and one desktop render) only. No phone test, no human playtest, no new APK.** Version stays 0.1.9 (code 7), package `com.theworthyone.game`.

## 1. Where this sits among the latest reports

| Report | Status |
|---|---|
| `PHYSICAL_TEST_REPORT.md` (to 1.18) and `MILESTONE_1_19_REPORT.md` | Done. Audio crash fixed and verified on the phone. |
| `MILESTONES_1_20_TO_1_24_REPORT.md` | 1.20–1.23 written (no defects in 1.20–1.22; two export-hygiene fixes in 1.23). **1.24 (Release Candidate) section still unwritten**: the RC was built, installed and passed the desktop regression, but its phone smoke test was interrupted and not finished. |
| **This report (1.25)** | Gameplay balance and visual change made after the user's hand-testing. Not an RC change. |

Consequence: the RC built in 1.24 **does not contain** the 1.25 changes. A new APK is needed before the user can feel them.

## 2. Reported issues

1. The background looks dull.
2. Taps do not feel harder from one level to the next.

## 3. Issue 2: difficulty (cause confirmed, fixed)

**Cause:** every curve ramped over 12–14 levels (`1 - exp(-(level-1)/ramp)`), so level 5 was only about 15 % harder than level 1 (6 taps/s: 3.8 s at level 1, 4.5 s at level 5).

**Change** (`resources/difficulty/difficulty_config.gd`, defaults only; level 1 unchanged):

| Parameter | Before | After |
|---|---|---|
| Longest allowed gap between taps, level 1 → very high | 400 → 300 ms | 400 → 280 ms |
| Peak gain per tap | 6 → 4.5 % | 6 → 3.8 % |
| Resistance at the end of the bar | 0 → 0.35 | 0 → 0.5 |
| Slip-back decay | 5 → 14 %/s | 5 → 16 %/s |
| Grace before decay | 0.5 → 0.25 s | 0.5 → 0.2 s |
| Ramp (levels) | 12–14 | 6–7 |

Simulated time to extract for a perfectly steady tapper:

| Level | 5 taps/s | 6 taps/s | 7 taps/s |
|---|---|---|---|
| 1 | 6.4 s | 3.8 s | 2.7 s |
| 2 | 7.4 s | 4.3 s | 3.0 s |
| 3 | 8.4 s | 4.7 s | 3.3 s |
| 4 | 9.6 s | 5.2 s | 3.4 s |
| 5 | 10.8 s | 5.7 s | 3.7 s |

At 4 taps/s the time grows from 16 s (level 1) to about 50 s (level 5): slow tapping stops working. Fast tapping (7/s) stays achievable.

**First attempt rejected:** ramps of 5–6 with end values 3.2 gain / 0.6 resistance made the default harder than the "demanding" preset (a preset-order test failed and level 5 at 4 taps/s was 100 s). I softened it. Order at level 10, 5 taps/s: forgiving 8.2 s < default 18.2 s < demanding 22.0 s.

**Tests edited:** 7 assertions in `tests/run_tests.gd` that pinned the old numbers (end values, ramp, level 5/10/20 gaps, step size, level-10 decay/grace) now pin the new ones. Same properties checked (monotonic, gradual, never past the floor).

## 4. Issue 1: background (changed; judged by one desktop render)

`scripts/gameplay/forest_environment.gd`, colour and parameter edits only (no new nodes, lights or passes):
- Sky top (0.17,0.30,0.36) → (0.16,0.38,0.55); horizon (0.74,0.72,0.54) → (0.98,0.84,0.52); ground horizon greener.
- Saturation 1.0 → 1.22, contrast 1.14 → 1.16, ambient 0.95 → 1.05.
- Fog colour warmer/brighter, fog density 0.017 → 0.012 (trunks no longer merge into one green).
- Sun colour slightly warmer; two bark tones warmer/greener.

Evidence: desktop renders `build/shots/bg_after.png` (first pass) and `bg_after2.png` (final). The final shows a glowing golden-green distance and separable trunks. **No "before" image was kept, and whether it is no longer "dull" is the user's judgement, not mine.** Colours on the phone's screen may differ from the laptop's.

## 5. Focused tests (desktop, headless)

| Suite | Result |
|---|---|
| Difficulty logic (`run_tests.gd`) | ALL PASSED (0 failures) |
| Startup | 16 checks, 0 failed |
| Progression (real level loop, levels -5..1000) | 35 checks, 0 failed |
| Speed | 50 checks, 0 failed |
| Rhythm | 63 checks, 0 failed |
| Integration | 194 checks, 0 failed |
| Failure | 117 checks, 0 failed |
| **Experience** | **Intermittent: 6 runs, 2 clean; the other 4 each had 1–2 failures** |

Experience failures seen: "the discs spring back after the tap" (a 0.7 s wall-clock wait, 3 times), "biggest rise per 60 Hz frame … dt=0.0010", "biggest single-frame move 4.42 px" (once together). They differ from run to run and are timing-sensitive checks of tap-disc and sword animation. **I did not run the old code to prove they were already flaky, so I cannot say my change did not worsen them.** The sword-motion checks run at level 1, whose numbers I did not change, and the sky and fog edits do not touch animation, which makes a regression unlikely but is not proof.

Not run: audio and menu suites (nothing in them touched), layout and fx suites.

## 6. Unresolved and unverified

- **Not played by a human on the phone.** The new difficulty is a model result (simulation and headless taps). Whether levels 2–5 now feel right, and whether level 5 is too hard, is unknown. The values are plain defaults in one file and easy to retune.
- **Background not seen on the phone**; the user's own look is the real test.
- **Experience suite flakiness** (section 5) is open.
- **Performance still unresolved (deferred, not fixed):** about 45–46 FPS in play, 309–315 MB PSS, phone about 42 °C. The saturation/contrast/fog edits use the existing post pass and should be cheap, but they have **not been measured**.
- From earlier reports and still true: no release keystore, APK only (no AAB), no in-game credits screen, audio never heard by a human, OpenGL fallback and other devices untested, notification shade does not pause the game.

## 7. APK

Unchanged: the 1.24 release candidate and earlier backups in `build/android/` do not contain these changes. Nothing was exported, installed or published.

## 8. Exact next step

Build a debug APK with the 1.25 changes (version unchanged unless the user approves a bump) so the user can play levels 1–5 and judge difficulty and background. Then finish the 1.24 Release Candidate section. Retune only from what the user reports.
