# Milestone 1.1 - Gameplay Validation Report

Godot 4.7.2 stable. Date: 2026-10-31.
Scope: validate the first playable loop and fix what breaks. No redesign, no new features,
no changes to the visual environment.

## READ THIS FIRST: what kind of testing this was

| Kind | Done? |
|---|---|
| **Simulated input, real engine pipeline** (events built in code, fed through `Input.parse_input_event()` into the real `main.tscn`) | **Yes** - 191 checks |
| Unit tests of individual classes | Yes (existing 21 checks, re-run) |
| **Physical Android touchscreen** | **NO. Not tested at all.** |
| Android export / on-device lifecycle (home button, app switch, phone call, screen lock) | **NO** |
| Performance / frame rate on any mobile device | **NO** |

Everything below that says "touch" means a *simulated* `InputEventScreenTouch` created in code.
It proves the code path handles that event type correctly; it does **not** prove a real finger on a
real phone produces the events I assumed (coordinates, multi-touch ordering, timing, cancellation).

---

## 1. Summary

| | |
|---|---|
| Integration checks executed | **191** (`tests/integration_tests.gd`) |
| Result of the final code and final test suite | **191 passed, 0 failed, 0 inconclusive** in 3 consecutive full runs (about 107 s each) |
| Existing unit tests (`tests/run_tests.gd`) | 21 checks, all pass after the fixes |
| Project import (`--headless --import`) | no errors or warnings |
| Real bugs found | **2** (both minor), **both fixed** |
| Test-harness defects found and fixed | 4 (see section 5) |
| Intermittent failures | 2 seen in earlier runs; **root cause identified: real OS window-focus loss pausing the game** (see section 5). Suite now detects and recovers from it |

Per section (final run): Input 35 - Extraction 14 - Sword 21 - Level transitions 95 - Timers/pause 26.

Run history, so the pass rate is not overstated (windowed full-suite runs only; the first headless attempt is excluded):
- Harness still being corrected: 4 runs, with failures from harness defects and the genuine bugs.
- With the harness correct but before any game fix: 1 run, 2 failures = the two genuine bugs below.
- After the two game fixes, before the harness hardening: **8 runs, 6 passed 191/191, 2 failed with one unrelated check each**
  (one from machine latency, one from a real window-focus loss; see section 5).
- After hardening the harness: **3 runs, 3 passed 191/191** (one of them suffered a real focus-loss pause, which the suite detected and recovered from).
So the honest summary is: 9 of the last 11 runs passed outright, and the 2 failures were traced to the test environment, not the game.

---

## 2. Tests executed and results

All of these run against the real `main.tscn` with real managers. Input is simulated through
`Input.parse_input_event()` (window coordinates -> content-scale transform -> viewport ->
`InputController._input`). Lifecycle is simulated with
`get_tree().notification(NOTIFICATION_APPLICATION_FOCUS_OUT)` etc. (the same engine notification
Godot sends on focus loss; this does not prove Android delivers it).

### Objective 1 - Input validation (35 checks, all pass)
| Test | Result |
|---|---|
| Emulation settings: mouse-from-touch OFF, touch-from-mouse OFF (so one physical tap cannot become two events) | PASS |
| Left mouse click on left half -> LEFT; on right half -> RIGHT (alternates) | PASS |
| Mouse button *release* ignored | PASS |
| **Right click, middle click, wheel up/down, mouse motion, `InputEventScreenDrag`** produce no taps and no rejections, no progress | PASS |
| `InputEventScreenTouch` press accepted on left and right; release ignored | PASS |
| Same-side rejection for touches and for mouse clicks; progress unchanged by rejected taps; alternation resumes | PASS |
| Debounce: opposite-side tap <25 ms after an accepted tap is rejected; same tap 60 ms later accepted | PASS |
| Debounce window anchored to last *accepted* tap | PASS after fix (**failed before**, bug 1) |
| Multi-touch: two fingers same instant, opposite sides -> exactly 1 counts | PASS (reported as SKIP/inconclusive, never as pass, if the machine takes 25 ms or more to deliver the pair) |
| Multi-touch: two fingers same side -> exactly 1 counts | PASS (same latency rule) |
| Held finger + two more fingers alternating 60 ms apart -> all 3 accepted in order | PASS |
| Zone boundary (split = half of visible width = x 540): x=0,1,538,539 -> LEFT; 540,541,542,1079 -> RIGHT; x=-20 -> LEFT; x beyond right edge -> RIGHT | PASS (8 + 2 checks) |
| `Viewport.push_input(ScreenTouch)` reaches the controller | PASS |
| Touches during the entrance animation (input locked) are ignored entirely | PASS |

### Objective 2 - Extraction validation (14 checks, all pass)
Progress is +8.000 per valid tap for taps 1-3 (exact). Rejected taps / right click / release change nothing.
No decay at 0.35 s after the last tap (grace 0.5 s). Measured decay 1.81 s after the last tap:
expected loss 6.54, measured 6.61 (tolerance 0.6). Progress settles at exactly 0; the minimum value
ever emitted over the whole run is 0.0 and the maximum is exactly 100.0.
Spamming **45** alternating touches: `extraction_completed` fired **exactly once**, `extraction_succeeded`
exactly once, level advanced by exactly 1. Calling `register_valid_tap()` five more times directly
(bypassing input) cannot re-trigger it.

### Objective 3 - Sword animation (21 checks, all pass)
- Height tracks progress at six samples: sword y matches `rest + progress/100 x 0.9` within 4 mm.
- Tap feedback: every valid tap sets the identical full kick (4/4); a rejected tap gives none;
  after 0.3 s the kick, position offset and rotation return to exactly zero.
- Decay: over 91 frames the height never rose, the largest per-frame step was 0.00081, the largest
  tremble 0.005 (under 1 cm). Slipping state starts with decay and clears on the next valid tap.
- Extraction animation: sword rose to the held pose (peak above rest + lift + 0.5), state returned to READY,
  sword back at exactly the rest position with zero visual offset, animation flags cleared, `planted` emitted exactly once.
- No overlapping tweens: three overlapping `play_*` calls created **1** tween (**3 before the fix**, bug 2).

### Objective 4 - Level transitions (95 checks, all pass)
Six consecutive extractions, each driven by real touch events (about 28 taps/s). For every level 1-6, at the
start of the level: level counter correct; progress 0; **gain / decay / grace equal the difficulty curve for
that level** (level 1 = 8.00 / 5.00 / 0.50); level timer 0; sword at embedded rest pose with zero offsets;
alternation reset; input enabled. During each level: state EXTRACTING immediately on completion;
level timer frozen (stable to 0.5 ms for 0.4 s); `extraction_succeeded` reported the right level;
reported level time matched wall clock; session timer kept running through the animation.
End: level 7; session time (>= sum of level times); exactly 6 completions; progress stayed in 0-100;
configured gain never increases over levels 1-8.

### Objective 5 - Timers (26 checks, all pass)
- Idle: both timers 0 after 0.3 s.
- Invalid input (right click, middle click, releases, drag) does not start either timer; state stays READY.
- First valid tap starts both together (level 0.264 s, session 0.264 s at +0.3 s); state PLAYING.
- Level timer stops at extraction and resets next level; session timer continues (covered in objective 4).
- Pause (simulated focus loss): state PAUSED, tree paused, input disabled; **both timers frozen for 0.8 s of paused wall time**; progress frozen (no decay).
- Repeated focus-loss notifications (FOCUS_OUT, WM_WINDOW_FOCUS_OUT, APPLICATION_PAUSED) pause only once.
- Resume by real touch: state returns to PLAYING; the resume tap is **not** counted as a gameplay tap; level timer continued from the frozen value excluding the pause (final run: 0.423 s at pause -> 0.769 s about 0.35 s of real play later; had the 0.8 s pause been counted it would read about 1.2 s).
- Pause before the first tap: timers stay 0, first tap after resume starts them.
- Pause during the success animation: sword and level progression frozen; after resume the level advances exactly once and the sword ends exactly at rest.

### Existing tests / validation re-run after fixes
`godot --headless --import`: clean. `tests/run_tests.gd`: ALL PASSED (21). Integration suite: 191/191, three times.

---

## 3. Bugs discovered and fixes applied

### BUG 1 - Rejected same-side taps re-armed the debounce window  (severity: low)
`InputController.handle_tap()` updated its "last tap" timestamp *before* the same-side check. A same-side
tap that was rejected therefore restarted the debounce window and could cause the *next valid* opposite-side tap
to be rejected. Reproduction (debounce 100 ms): LEFT accepted at 0 ms, LEFT again at 120 ms (rejected, same side),
RIGHT at 180 ms -> rejected, even though it came 180 ms after the last accepted tap.
At the shipped 25 ms debounce the window is tiny, so real-world impact is small, but it is a logic error.
**Fix:** the timestamp is now set only when a tap is accepted. File: `scripts/gameplay/input_controller.gd`.
**Verified:** failing test now passes; unit tests (alternation, debounce) still pass.

### BUG 2 - Overlapping sword animations created duplicate tweens  (severity: low, latent)
`SwordController.play_extraction()` / `play_entrance()` had no re-entrancy guard. A second call while one was
running created a second tween fighting over the same properties. The current game flow never does this
(the level manager awaits each call), so it was not reachable in play, but it is a trap for later changes.
**Fix:** a `_tween_running` flag; a second call is ignored with a `push_warning`. The flag is cleared when each
tween finishes, so the normal extraction -> entrance sequence is unaffected (verified by 6 consecutive levels).
File: `scripts/gameplay/sword_controller.gd`.
**Verified:** three overlapping calls now create one tween. The test deliberately triggers the warning twice;
those two warnings in the log are expected.

### No other gameplay bugs were found
Alternation, extraction counting/clamping, decay, completion-once, level progression, difficulty application,
timer semantics, and pause/resume (as simulated) all behaved as specified.

---

## 4. Files

**Modified (gameplay code, 2 files):**
- `scripts/gameplay/input_controller.gd` - debounce anchored to accepted taps (bug 1).
- `scripts/gameplay/sword_controller.gd` - re-entrancy guard on `play_extraction` / `play_entrance` (bug 2).

**Created:**
- `tests/integration_tests.gd`, `tests/integration_tests.tscn` - the 191-check suite.
- `MILESTONE_1_1_TEST_REPORT.md` - this report.

**Edited (docs only):** `README.md` - added the integration-test command.

**Not touched:** all visual/environment code (`stump_builder`, `forest_environment`, `organic_mesh`,
`material_factory`, shaders, HUD, camera), `extraction_manager`, `difficulty_*`, `timer_manager`,
`level_manager`, `game_manager`, `main.tscn`, `project.godot`.

**How to run:**
```
godot --path . res://tests/integration_tests.tscn         # needs a window; ~110 s; exit 0 = pass, 1 = failures, 2 = invalid run (focus lost)
godot --headless --path . -s res://tests/run_tests.gd     # unit tests
```
**Do not click other windows while it runs.** The game deliberately pauses when its window loses focus, and the suite window is
only 540x960 and can lose focus to anything else on the desktop (see section 5). The integration suite forces a 540x960 window. It should be run **windowed**: in `--headless` the dummy window is
64x64, which makes the visible area 1920x1920 and cannot resolve the one-pixel zone boundary (this wrecked my first run).

---

## 5. Test-harness problems found along the way (not game bugs)

1. **Headless window is 64x64.** Boundary tests are meaningless there; suite is windowed and uses width-relative coordinates.
2. **`SceneTreeTimer` can fire up to a frame early** after a long frame, so a "45 ms" wait could be shorter than the 25 ms debounce
   and make valid taps look rejected. Waits now use `Time.get_ticks_msec()` wall-clock deadlines.
3. **A wait loop without a timeout hung the whole run** when an earlier check failed. All wait loops now have deadlines.
4. **Real OS focus loss paused the game mid-test** (root cause of the two intermittent failures). The game is *designed* to pause when its
   window loses focus. When another window took focus during a run (I was running other commands, and a second Godot editor was open),
   the game paused, input was disabled, and the next tap was swallowed as the "resume" tap. This showed up as taps being ignored right after a
   fresh scene (state 3 = PAUSED, `input.enabled=false` in the diagnostic line; seen in two runs, plus one run that exited early).
   The game behaved correctly. The suite now (a) keeps its window on top and grabs focus, (b) counts any pause it did not cause itself,
   (c) resumes through the normal tap-to-resume path and carries on, and (d) reports **INVALID RUN (exit code 2)** if such a pause coincided with a failure.
   One of the three final runs had exactly such a pause and passed after recovery.
5. **"Same instant" touch tests depend on delivery latency.** Two back-to-back `parse_input_event` calls are only simultaneous if
   they land within the 25 ms debounce. One run on a busy machine took longer and the test failed. Those tests now measure the delivery time and
   report SKIP (inconclusive) instead of failing when the scenario was not achieved. (It also hints at a physical-device question: see section 8, item 3.)

---

## 6. Behaviours confirmed that you may want to decide on (unchanged)

- **Two fingers landing within 25 ms count as one tap**, even on opposite sides (by design: "prevent double registration"). A player
  trying to hit both zones at the same instant gets one valid tap. Normal alternating tapping is unaffected.
- **The session timer counts the success animation** (it only stops when a run ends), so it exceeds the sum of level times.
- **The resume tap is swallowed** and resets alternation; it is never a gameplay tap.
- The pause triggers include `NOTIFICATION_WM_WINDOW_FOCUS_OUT`, so on desktop clicking another window pauses the game.

## 7. Known weaknesses of this test suite

- Two assertions are loose by design: "timer value at pause is sane" allows 0.1 s; "resume tap added no progress" accepts any value
  that is not higher than before (decay could lower it).
- Only levels 1-6 were played; later levels are covered by curve-math tests only.
- Taps arrive about 35 ms apart (about 28/s), faster than a person; no test of slow, irregular, or very high rate tapping,
  nor of sustained long sessions.
- Real mouse hardware events were not produced; synthetic `InputEventMouseButton` objects were.
- The suite needs an interactive desktop window and is sensitive to focus theft (handled, but a run that reports INVALID must be repeated).
- It runs about 107 s on a single machine (Intel UHD graphics, Windows 11); timings were not tried on other hardware.
- Visual behaviour of the animations (smoothness as seen by a player) was measured numerically, not watched in real time.

---

## 8. Tests that STILL REQUIRE PHYSICAL ANDROID TESTING

None of these has been done. Do not treat them as validated.

1. Real touch input: that a finger produces `InputEventScreenTouch` with the coordinates/ordering assumed here, on several screen sizes and aspect ratios (including tall 20:9 phones and notches / gesture-navigation zones near the bottom tap panels).
2. Multi-touch on hardware: two thumbs alternating at high speed; touch ordering and timestamps from the digitizer; palm touches; finger sliding off a zone or across the boundary; `canceled` touches.
3. Sustained fast tapping: whether the 25 ms debounce is right for real double-registration (touch jitter) and not too aggressive for fast two-thumb play.
4. Android lifecycle: home button, app switcher, screen lock, incoming call, notification shade, orientation lock, back button / back gesture (`NOTIFICATION_APPLICATION_PAUSED` / `FOCUS_OUT` / `WM_GO_BACK_REQUEST` actually delivered and timers genuinely frozen across a long background period).
5. Behaviour after the OS kills the app in the background (not handled at all yet - no saving exists).
6. Performance on mid-range and low-end devices: frame rate, frame-time spikes during taps and during the success animation, startup time (the scene generates its meshes at load), memory, thermal throttling.
7. Haptics (none implemented) and tap latency perceived by a player.
8. Export configuration, signing, installation, and the portrait-lock / stretch behaviour on real hardware.

---

## 9. Verdict for this milestone

On the simulated-input level, the core gameplay loop is now validated and two small defects are fixed:
the input rules, extraction maths, sword tracking, six-level progression, timers, and pause/resume behave exactly as specified,
with 191 automated checks passing in repeated runs. That is a good foundation for continuing with visual production.

It is **not** validated on a phone. Section 8 is the remaining risk. Nothing in this report should be read as a claim of mobile readiness.
