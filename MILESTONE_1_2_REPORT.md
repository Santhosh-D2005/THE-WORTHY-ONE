# Milestone 1.2 - Failure System Report

Godot 4.7.2 stable. Date: 2026-10-31.
Scope: end the run when extraction progress reaches exactly 0% after the first valid tap, play a failure
animation, show the failure screen, and make TRY AGAIN restart cleanly. No Endless, Ruthless, leaderboard or other
future milestone work was done. Existing gameplay systems were extended, not rewritten.

## READ THIS FIRST: what was and was not tested

| Kind | Done? |
|---|---|
| Unit tests | Yes: **31 checks pass** (the original 21 untouched + 10 new) |
| Simulated-input integration tests of the failure system (real `main.tscn`, events via `Input.parse_input_event()`) | Yes: **102 checks pass** (3 consecutive clean runs on the final code) |
| Existing 191-check integration suite re-run with failure in the game | Yes: **191/191 pass** |
| **Physical Android touchscreen** | **NO. Not tested.** |
| **Real mouse hardware** | No (synthetic events only) |
| Failure screen on other aspect ratios / devices | No (540x960 window only) |
| Human judgement of how the failure *feels* | No (numbers and screenshots only) |

"Touch" below always means a **simulated** `InputEventScreenTouch`. The USB-debugging device test was not started in this task.

---

## 1. Implementation

### The failure rule
`ExtractionManager` (scripts/managers/extraction_manager.gd) got a new signal `progress_depleted`. It fires when decay brings
progress to exactly 0, **only if the attempt was started by a valid tap** (`_attempt_started`) and **at most once per attempt**
(`_depleted`); `reset()` re-arms it. Before the first valid tap progress is 0 and nothing decays, so it cannot fire.
The decay system itself (grace period, rate, clamping) is unchanged.

### The state machine: a dedicated FAILED state with a single gate
`GameManager` (scripts/core/game_manager.gd) gained:
- `State.FAILED`
- `begin_failure() -> bool`: the **only** way to fail. Succeeds exactly once per run and only while the state is `PLAYING`.
  It refuses in READY (before the first tap), EXTRACTING (success or entrance animation), PAUSED, FAILED, and after the run is over.
  On success it sets `run_over` and switches to FAILED, which disables input **synchronously** (the existing state handler).
- `run_over`, `run_extractions` (swords extracted this run, counted from `extraction_succeeded`), `last_result`, `run_failed(result)` signal, `publish_run_result()`.
- `reset_run()` now also clears the run counters and `run_over`.

### What happens on failure (`LevelManager._on_progress_depleted`)
1. `begin_failure()` gate (duplicates, wrong states, and pauses are rejected here).
2. Extraction set inactive (no further progress updates; no completion possible).
3. `RunResult` captured: level reached, extractions this run, `stop_level()` and `stop_session()` values. Timers are now frozen.
4. `GameManager.run_failed` emitted once.
5. `await sword.play_failure()`.
6. `FailureScreen.show_result(result)` (skipped if the run was reset meanwhile).

`_on_extraction_completed` now also refuses to run unless the state is `PLAYING`, so a failed run can never complete a level.

### Sword failure animation (`SwordController.play_failure`)
Deterministic, no randomness: the sword position eases (cubic ease-out) onto the embedded rest position, and the visual node does a small damped
"seating" spring (deepest dip 8 mm, largest offset 8.5 mm, dies out in under a second). Total ~0.8 s. The final pose is set to **exactly** the rest
position. It uses the existing `_tween_running` guard, so a failure animation can never overlap an extraction/entrance animation (tested).
Camera shake: none added. `restore_embedded()` returns the sword to the start pose for a retry. Honest note: because the sword has been sliding
down with the decaying progress, it is already within about 2 mm of the rest pose when failure triggers, so the animation is mostly a *settle*
(the wood gripping it) and not a long return trip.
**Wood creak sound: not added.** No audio assets exist and no audio system exists yet; the task said to use one only if an appropriate asset existed.

### Failure screen (`scenes/ui/failure_screen.tscn`, `scripts/ui/failure_screen.gd`)
Layer above the HUD. Dimmed forest with a vignette and bottom scrim; the middle of the screen is left clear so the stump and embedded sword stay visible.
"THE SWORD REMAINS" (Cinzel, antique gold), thin divider, three stats (LEVEL REACHED / SESSION TIME / TOTAL EXTRACTIONS), buttons TRY AGAIN and MAIN MENU.
The gameplay HUD fades out on failure and fades back in on a new run.
Design decisions:
- **Accident protection:** buttons ignore presses until 0.6 s after the 0.7 s fade-in finishes, so a player who is still frantically tapping cannot hit TRY AGAIN by accident.
- **Touch support:** the project disables mouse-from-touch emulation (needed so one tap is not counted twice), and Godot's `Button` only reacts to mouse events.
  The screen therefore handles `InputEventScreenTouch` itself (press and release on the same button). **Simulated only; not verified on a phone.**
- **Pause:** the screen steps aside while paused so the pause overlay is readable, and is inert while paused.
- **TOTAL EXTRACTIONS is the count for THIS run.** Lifetime totals need the save system that does not exist yet; no fake statistic is shown.
- **MAIN MENU:** there is no main menu scene yet. The button is **shown disabled and dimmed** (it does not pretend to work). When
  `res://scenes/ui/main_menu.tscn` exists it enables automatically and calls `LevelManager.scene_changer`. Tested with a stub menu scene.

### TRY AGAIN (`LevelManager._restart_run`)
Only acts in FAILED. Resets the run (level 1, 0 extractions, not over), both timers, level-1 difficulty, extraction progress/attempt flags,
alternation, restores the sword to the embedded pose without a re-entrance (the sword never left the stump), hides the screen, re-arms extraction,
and sets READY. Nothing persistent is touched (no lifetime records exist yet).

### Results structure (`scripts/progression/run_result.gd`)
`RunResult` holds only measured values (level reached, run session seconds, unfinished-level seconds, extractions this run, end reason). It has no lifetime or
best fields. It is ready for a future save system to consume.

---

## 2. Files

**New scripts / scenes:**
- `scripts/progression/run_result.gd` - results structure
- `scripts/ui/failure_screen.gd`, `scenes/ui/failure_screen.tscn` - failure screen
- `tests/failure_tests.gd`, `tests/failure_tests.tscn` - 102-check failure suite
- `tests/stub_main_menu.tscn` - stand-in menu scene used only to test the enabled MAIN MENU path
- `MILESTONE_1_2_REPORT.md`

**Modified:**
- `scripts/core/game_manager.gd` - FAILED state, `begin_failure()` gate, run counters, `run_failed`
- `scripts/managers/extraction_manager.gd` - `progress_depleted` signal and flags
- `scripts/gameplay/sword_controller.gd` - `play_failure()`, `restore_embedded()`, `failure_settled`
- `scripts/managers/level_manager.gd` - failure flow, retry, menu hook, completion guard
- `scripts/ui/hud.gd` - fades the gameplay HUD out/in around failure
- `scenes/main/main.tscn` - instances the FailureScreen
- `tests/run_tests.gd` - 10 new unit checks appended (existing 21 untouched)
- `README.md` - test command

Deleted: nothing. Not touched: input controller, timers, difficulty, camera, all environment and visual code, shaders, existing integration tests.

---

## 3. Tests executed

### A. Project validation
`godot --headless --import`: no errors or warnings. `godot --headless --quit-after 120` (loads main scene including the failure screen): no errors or warnings.

### B. Unit tests (`tests/run_tests.gd`): 31/31 pass
Original 21 unchanged and passing. New 10: idle at 0% never depletes; no depletion while above 0; fires exactly when progress reaches 0; at most once
per attempt; re-arms after `reset()`; an inactive manager never depletes; `RunResult` carries measured values, has no lifetime fields, and formats time like the HUD.

### C. Failure suite (`tests/failure_tests.tscn`): 102/102 pass, 3 consecutive clean runs (about 125 s each)
Simulated events through the real input pipeline; run windowed 540x960.

| Section | Checks | What it proves |
|---|---|---|
| 1 Waiting before the first tap | 6 | 3.5 s idle: still READY, progress 0, timers 0, no failure, input on; a stray `progress_depleted` in READY is ignored; the first tap afterwards works |
| 2 One valid tap, then stop | 8 | Fails 2.08-2.12 s after the tap (decay predicts 2.1 s); FAILED + `run_over`; progress exactly 0, never negative; exactly 1 event; result is level 1 / 0 extractions; input off; extraction stopped |
| 3 Exactly one failure / zero detection | 7 | Every frame sampled during the decay: alive for 220+ frames while progress > 0 (lowest 0.05%), failed on the first frame at exactly 0; 5 extra signals + `begin_failure()` produce no second failure; exactly 1 screen |
| 4 Input disabled / timers stopped | 5 | 12 rounds of taps and clicks, 30 direct `register_valid_tap()` calls and a forced completion signal: nothing accepted, no completion, still FAILED on level 1; timers equal the captured result and do not move for 1 s |
| 5 Sword animation | 7 | Completes in 0.75-0.83 s; only moves toward rest (monotonic, no pops, no overshoot); dip under 8 mm and offsets under 9 mm; final pose **exactly** the rest position; no tween left; a second failure / extraction / entrance animation started mid-animation is refused (tween count unchanged) |
| 6 Failure screen + spam | 13 | Taps and clicks hammered on the future TRY AGAIN spot during the whole animation change nothing; screen appears once; texts: title, LEVEL REACHED, SESSION TIME, TOTAL EXTRACTIONS match the result; button labels; presses before the interactive delay do nothing; HUD steps aside; stump and sword remain visible |
| 7 TRY AGAIN (mouse) + immediate restart | 16 | Real click: READY, level 1, 0 extractions, not over, progress 0 and level-1 gain, timers 0, sword at exact embedded pose, input on, alternation reset, screen hidden, HUD back; an immediate new extraction works and timers restart; second failure gives exactly 2 events and 2 screens in total; after another retry the player can wait 2.5 s without failing |
| 8 TRY AGAIN (touch) + negative cases | 5 | Press on the button but release elsewhere (and the reverse) does nothing; tapping the empty screen does nothing; proper press+release retries |
| 9 Double press | 2 | Three rapid presses reset the run exactly once; state stays consistent |
| 10 Fail on level 3, retry | 9 | Two real extractions then failure: result level 3 / 2 extractions; screen shows them; retry returns level 1, 0 extractions, level-1 difficulty, HUD "LEVEL 1", sword embedded, session timer 0 |
| 11 Depletion during other states | 9 | A depletion signal during the success animation, during the entrance, and while paused is ignored; the level still advances once; after resume the natural failure still happens exactly once |
| 12 Pause during/after failure | 8 | Pause mid-animation: no screen while paused; resume returns to FAILED, screen then appears once, sword ends at rest; pause with the screen up hides it, and a tap on the TRY AGAIN spot only resumes (does not press it); timers never move |
| 13 MAIN MENU | 7 | With no menu scene the button is dimmed/disabled and pressing it (mouse or touch) does nothing; with a menu scene present it enables and clicking or touching it requests that scene exactly once; the stored result is unchanged |

### D. Regression: existing integration suite
`tests/integration_tests.tscn` re-run after all changes: **191 checks, 0 failed, 0 inconclusive**. During that run the OS took window focus once; the suite detected it,
recovered, and still passed (see "Test environment" below).

### Run history, for honesty
The first run of the new failure suite had 5 failures out of 101 checks, all of them **mistakes in my tests, not game bugs** (see section 4).
After correcting them: 3 consecutive runs with 102/102.

---

## 4. Bugs and problems found

**No bug was found in the new game code during testing.** The first failure-suite run exposed these, all in the tests:
1. A scenario that tapped every 0.3 s outpaced the 0.5 s decay grace period, so progress climbed to 100% and the player *won*. Rewritten to sample every frame during a natural decay.
2. The test counted its own forced `extraction_completed` emit as a "completion". Fixed to count only real successes.
3. A comparison ignored an earlier legitimate tap in the recorder. Fixed.
4. After a retry, the 2nd and 3rd rapid presses of a triple-click are **legitimate gameplay taps** on the live game (the run has restarted), so the state is PLAYING, not READY.
   The test now accepts that. This is a design behaviour, listed in section 5.

Test environment: real OS window-focus loss pauses the game by design and can disturb a windowed test. The earlier-built detection and recovery handled one occurrence in the regression run.
The suite exits with code 2 if such a pause coincides with a failure.

---

## 5. Behaviours and decisions you may want to review

- **Double-pressing TRY AGAIN:** the first press restarts the run. A second quick press then lands on the live game and counts as the first gameplay tap
  (this also starts the timers). Harmless, and it also matches "immediately start another extraction", but a short post-retry input delay could be added if you prefer.
- **MAIN MENU is visibly disabled** until a main menu scene exists. That is the single deliberate exception to "all buttons function"; hiding a dead button seemed worse
  than showing it honestly disabled.
- **The failure animation is subtle** (a settle and seat), since the sword is already almost at rest. If you want a longer, more dramatic fall-back, the decay would have to
  slide it visibly faster or the animation would need an extra pre-slip.
- **Failure timing is purely the existing decay**: a single tap fails about 2.1 s later at level 1. That follows from the starting values (8% gain, 5%/s, 0.5 s grace) and may feel harsh or generous
  once played; tuning is in `default_difficulty.tres`.
- The session timer is frozen at the instant of failure, including time of the success animations earlier in the run.

---

## 6. Remaining limitations

- **No physical Android testing**, including whether the failure-screen buttons respond to a real finger. The touch handling relies on simulated events only.
- No audio at all (no creak, no failure sound). No lifetime records, personal bests, or save system, so no records can be "preserved" yet; the results structure is prepared only.
- No main menu scene.
- Failure screen checked visually only at 540x960; no tall-phone or tablet aspect ratios; safe areas and gesture-bar zones untested.
- Feel of the failure moment (pacing, emotional weight) not judged by a player.
- The failure suite takes about 2 minutes and needs an interactive window without focus theft.

## 7. Placeholders still in use

Unchanged from earlier milestones: the stump, roots, trunks, grass, sword model, all materials and textures are procedural placeholders; the sky/lighting canopy shadows are faked.
New in this milestone: the failure screen is a first-pass UI with no icons or final art (the Cinzel font is the only real asset), and there is no failure sound.

## 8. Verdict

Failure is now reliable at the level of simulated testing: it cannot happen before the first tap, fires exactly once, locks input, freezes the timers, returns the sword exactly
to its embedded pose, shows exactly one screen, and TRY AGAIN produces a clean fresh run, with 102 new and 191 existing checks passing. It is not yet validated on a phone, has no sound, and
has no main menu or records behind it. Nothing here claims physical-device validation.
