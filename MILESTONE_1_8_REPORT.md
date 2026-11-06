# Milestone 1.8 - Difficulty rebalancing and achievement experience (version 0.1.8)

**Read this first - what was and was not tested.**
- **Desktop automated tests:** done, all pass (section 8).
- **Android injected-input tests:** **NOT done for 0.1.8.** The phone was disconnected from adb when it was time to install, and you chose to skip phone testing. The 0.1.8 APK was exported (`build/android/TheWorthyOne-debug.apk`) but has **never been installed or run on the device**. No Android FPS, memory or Back/pause measurement exists for 0.1.8.
- **Human playtest:** none. Everything about how the game "feels" is design intent, not a verdict.

The performance target in the brief (55-60 FPS during extraction) is therefore **unverified**.

---

## 1. Difficulty changes

| Parameter | 0.1.7 | 0.1.8 |
|---|---|---|
| A. Taps required | 50 -> 130 over levels 1-10 | exactly 15, 17, 20, 23, 26, 30, 34, 38, 42, 46 (configurable table) |
| B. Longest allowed gap between taps | 330 ms -> 259 ms (level 10) | 400 ms -> 310 ms (level 10), floor 230 ms |
| C. Extraction resistance | 0 -> 0.21 (level 10) | 0 -> 0.16 (level 10), cap 0.30 |
| Decay and grace | 5 %/s -> 14 %/s, 0.5 s -> 0.25 s | **unchanged** (same curves, same numbers) |

How it works:
- `required_taps_table` in `DifficultyConfig` holds the exact target for levels 1-10 and can be edited in the inspector. Beyond the table the requirement keeps growing, slowing down gradually (+4 per level at first, fading out over about 8 levels): level 12 = 53, level 20 = 69, level 30 = 75, levelling off near 78. No cliff.
- The target is the **effective** tap count. Because resistance makes late taps worth a little less, the gain per tap is solved so that exactly the target number of taps fills the bar. It is verified tap by tap in a unit test: levels 1-10 need exactly 15 17 20 23 26 30 34 38 42 46.
- The three parameters are independent (tested): changing the table does not move the gap, resistance, decay or grace.
- An empty table switches back to the old start/end curve. The `forgiving`, `demanding` and `gain_high` presets use that (their numbers were retuned to the new, gentler scale; `forgiving` allows 460 ms -> 260 ms, more than the default).
- Maximum gap: level 1 is 400 ms (2.5 taps/s), the value players approved in 1.6. It tightens to 310 ms at level 10 (3.2 taps/s) and approaches 230 ms (4.3 taps/s) at very high levels. Each level is 8-16 ms tighter than the last, so there are no jumps.

**Decay caution (not changed, as instructed).** Because one tap is now worth more (6.67 % at level 1) and decay is unchanged, the cost of a lapse in *taps* grows with level: a 1 s lapse costs 0.75 taps at level 1 but about 4 taps at level 10 and about 8 at level 30. A player who keeps tapping within the allowed gap never decays at all (grace is longer than the gap), so this only bites after a real stall. Whether that feels fair needs a human playtest; the decay numbers are the first thing to revisit if late levels feel harsh.

## 2. Old versus new progression

| Level | 0.1.7 taps | 0.1.8 taps | 0.1.8 gain per tap | 0.1.7 gap | 0.1.8 gap |
|---|---|---|---|---|---|
| 1 | 50 | 15 | 6.67 % | 330 ms | 400 ms |
| 2 | 61 | 17 | 5.95 % | 319 | 386 |
| 3 | 73 | 20 | 5.11 % | 308 | 374 |
| 4 | 83 | 23 | 4.49 % | 299 | 362 |
| 5 | 92 | 26 | 4.01 % | 290 | 352 |
| 6 | 100 | 30 | 3.51 % | 283 | 342 |
| 7 | 109 | 34 | 3.12 % | 276 | 333 |
| 8 | 116 | 38 | 2.82 % | 270 | 325 |
| 9 | 124 | 42 | 2.57 % | 264 | 317 |
| 10 | 130 | 46 | 2.36 % | 259 | 310 |

## 3. Actual taps required per level (full table, from `tools/difficulty_table.gd`)

| Level | Taps | Gain %/tap | Gap ms | Resistance | Decay %/s | Grace s | Reward strength |
|---|---|---|---|---|---|---|---|
| 1 | 15 | 6.67 | 400 | 0.00 | 5.0 | 0.50 | 0.0 |
| 2 | 17 | 5.95 | 386 | 0.02 | 5.7 | 0.48 | 0.1 |
| 3 | 20 | 5.11 | 374 | 0.05 | 6.4 | 0.46 | 0.2 |
| 4 | 23 | 4.49 | 362 | 0.07 | 7.0 | 0.44 | 0.3 |
| 5 | 26 | 4.01 | 352 | 0.09 | 7.6 | 0.43 | 0.4 |
| 6 | 30 | 3.51 | 342 | 0.10 | 8.1 | 0.41 | 0.5 |
| 7 | 34 | 3.12 | 333 | 0.12 | 8.5 | 0.40 | 0.6 |
| 8 | 38 | 2.82 | 325 | 0.13 | 9.0 | 0.39 | 0.7 |
| 9 | 42 | 2.57 | 317 | 0.15 | 9.4 | 0.38 | 0.8 |
| 10 | 46 | 2.36 | 310 | 0.16 | 9.7 | 0.37 | 0.9 |
| 12 | 53 | 2.08 | 298 | 0.18 | 10.4 | 0.35 | 1.0 |
| 15 | 61 | 1.83 | 283 | 0.21 | 11.2 | 0.33 | 1.0 |
| 20 | 69 | 1.65 | 265 | 0.24 | 12.2 | 0.30 | 1.0 |
| 25 | 73 | 1.58 | 253 | 0.26 | 12.8 | 0.28 | 1.0 |
| 30 | 75 | 1.55 | 245 | 0.27 | 13.2 | 0.27 | 1.0 |

Counts were verified on the desktop (unit tests simulate every tap; the integration/experience tests play levels 1-3 for real through the input system and compare with the prediction). **They were not re-run on the phone.**

Design observation: level 1 needs 15 taps, about 6 seconds at the minimum allowed rhythm and 2-3 seconds at a brisk pace, which should feel welcoming. Each of levels 2-10 asks 2-4 more taps than the one before.

## 4. Extraction animation changes (phases A-D)

Timeline at level 1 (a little longer at higher levels); the whole sequence from last tap to the next sword is about 2 s:

| Time | Phase | What happens |
|---|---|---|
| from about 70 % progress | **A. Final resistance** | The camera creeps toward the sword (up to 0.30 units) and the clearing dims by up to 6 %, both smoothed so rapid taps never make them jump. They ease back if progress is lost. The sword itself does not shake. |
| 0 - 0.20 s | A | After the last tap the blade finishes its smooth rise to the very top (the height spring keeps running) and is then **held there for a heartbeat** with the camera at its tightest. |
| 0.20 s | **B. Release** | A decisive quint-out pull: the blade leaves the wood in about 0.35 s, fastest at the start. At the same instant a **dark empty slot appears in the stump** (so the separation is visible), the camera thumps once (a deterministic damped shake, not random) and rises with the blade, the sun swells about 10 % (up to 30 % at high levels) and the card begins to appear. |
| 0.55 s - | **C. Reward** | The freed sword floats slightly higher, drifts toward the camera and turns a slow 0.3 rad about its own axis; the camera has moved in and up to frame it. |
| hold | **D. Achievement** | Card: "THE SWORD YIELDS", "LEVEL N COMPLETE", time and taps, and the **session time** (every fifth level also the number of swords freed). Top labels fade while it is up. |
| end | lift and next level | The sword lifts out of frame (0.45 s) while the camera returns to its framing; the next sword is dropped in. |

What changed from 1.7:
- Anticipation and a real release moment were added (in 1.7 the pull simply continued upward).
- The generic **FOV zoom was replaced** by a physical camera move (dolly in and tilt up following the blade).
- The camera shake is now deterministic (no random values).
- The sun dims slightly during the resistance and swells at the release.
- The empty slot in the stump was added.
- The hold is shorter: 0.75 s at level 1 up to 1.2 s from level 11 (1.7 had 0.9 -> 1.5), so completion does not interrupt the flow.
- The card now shows session time.

Avoided, as requested: no neon, no particles, no flash, no cartoon effects, no extra UI.

**Higher levels** (reward strength 0 at level 1 rising by 0.1 per level to 1 at level 11, so each level is a little more than the last, not a sudden change): the hold lengthens (0.75 -> 1.2 s), the sword rises higher (+0.25 units) and drifts closer to the camera (0.3 -> 0.7 units), the camera moves in more (0.55 -> 0.85 units) and rises more (0.55 -> 0.85), and the sun swell grows (+10 % -> +30 %). The total sequence grows from about 1.75 s to about 2.2 s.

Audio: still no audio assets exist, so nothing plays; the named cues (`first_tap`, `tap`, `tap_slow`, `planted`, `pull`, `freed`, `level_complete`, `failure`) are integration points only.

Whether it is **emotionally satisfying cannot be claimed**: this needs a human playtest.

## 5. Sword stability measurements (desktop, `tools/sword_motion`)

12 real alternating taps at the level-1 gain (6.67 % per tap), in phone render pixels (the phone renders the 3D scene 432 px wide). No decay.

| Tap gap | sideways range | sideways flips/s | vertical direction flips/s | max speed change per frame | max single-frame move | lag behind progress |
|---|---|---|---|---|---|---|
| 300 ms | 0.00 px | 0.0 | 0.0 | 0.38 px | 0.82 px | 5.3 px |
| 220 ms | 0.00 | 0.0 | 0.0 | 0.37 | 0.88 | 5.5 |
| 120 ms | 0.00 | 0.0 | 0.0 | 0.36 | 1.06 | 6.4 |
| 70 ms | 0.00 | 0.0 | 0.0 | 0.36 | 1.53 | 8.5 |

- No sideways movement and no up-down reversals at any speed, including very rapid tapping.
- The sword's spring was **not changed**. What changed is the tap size: each tap now moves the blade about three times as far as at 2 % per tap, so the per-frame move and the lag behind the bar are naturally larger than in 1.7 (1.7 measured 0.25-0.53 px steps and 1.5-2.7 px lag at 2 % per tap). The 0.1.6 sword at 8 % per tap had 2.3-2.8 px single-frame steps (earlier measurement). I tried a slower spring (follow speed 18) and it did not clearly improve the numbers, so it was left at 24.
- This is a desktop measurement. **Sword stability on the phone with 0.1.8 was not measured.**

## 6. Android FPS measurements

**None for 0.1.8** (phone not available, testing skipped by your choice).

For reference, the last device measurements, on 0.1.7 final (baked discs), were: about 58 FPS overall, 59 idle, **47-48 FPS during extraction**, memory about 278 MB. The brief asks to investigate the cost of the extraction and reach 55-60 FPS. What is known and not known:
- Not measured: which part of the 1.7 cinematic cost the frames (the FOV zoom, the sun-energy change, the card, the sword approaching the camera, or the level transition itself).
- Changed in 0.1.8 in a way that *might* help, but is **unproven**: no FOV change any more (the camera moves instead), no random per-frame camera offsets (a deterministic damped shake lasting about 1 s), no first-use hitch for the new slot mesh (it is built at start-up, one tiny unlit box), the card stays up 0.1 s shorter.
- Changed in a way that might *cost*: the camera transform is updated every frame during the move (about 1.7 s per level), and one extra tiny mesh exists.
- I added debug-only switches to isolate the cost on the phone, to use when it is available: put `--no-cam-fx`, `--no-light-fx` or `--no-card` (with `--perf-log`) in `user://launch_args.txt` of a debug build. `tools/extraction_dump.tscn` prints the sword/camera/light values frame by frame for any level.

## 7. Extraction release behaviour (desktop-verified)

Frame-by-frame dump at level 1 (`tools/extraction_dump`): the blade is at 99.3 % of its height 0.05 s before the release; at 0.2 s the release begins and the sword reaches its top position (+0.6 units above the wood) by about 0.45 s, with the cut slot visible from the moment of release; the rotation reaches 0.30 rad and the drift 0.30 units before the lift; the camera dolly reaches 0.55 units and returns to 0.000 by the end; the sun peaks at +10 % and returns to 2.10. Tests check: the blade never moves down, no sideways movement or tilt, no spin, still during the hold, smooth rise (<0.26 units per 60 Hz frame), the release time, the slot, the camera dolly at levels 1 and 11, the light swell, the return to normal.

## 8. Test results (all desktop automated)

| Suite | Checks | Result |
|---|---|---|
| unit (`run_tests`) | all | ALL PASSED, 0 failures |
| integration | 194 | 0 failed |
| failure/retry | 116 | 0 failed |
| layout / safe area | 256 | 0 failed |
| timer | 25 | 0 failed |
| startup | 16 | 0 failed |
| pause / Back | 41 | 0 failed |
| rhythm | 63 | 0 failed |
| experience (progress, extraction, card, discs, motion) | 71 | 0 failed |

Notes, for honesty:
- Existing checks that encoded a deliberately changed rule were adapted, with the reason in a comment (the 1.7 tap counts and 330 ms gap; rectangular/2 %-per-tap assumptions; the FOV zoom; hold lengths; the disc check). No check was deleted to make a test pass, with one exception: the integration decay test used a longer burst of 12 taps for the 2 %-per-tap design and now uses 4 taps (so 3 progress taps), which lowered that suite from 202 to 194 checks because the per-tap progress lines were part of the loop.
- The frame-timing tests need a real window; they report `INVALID RUN` if the OS takes focus away. This happened repeatedly on this PC during the session (not caused by the game) and runs had to be repeated; the final results above are from runs with 0 focus-loss pauses. Headless runs are useful for logic but give meaningless frame timing, so the experience suite was only accepted from a windowed run.
- Slow, normal and rapid input patterns, maximum gap behaviour, decay, failure/retry, pause/resume and Back are covered by desktop tests with simulated input. **None of this was run on Android for 0.1.8.** Levels 1-10 were last played on the phone with injected taps in 0.1.7 (with different tap counts).
- **No human playtest** of 0.1.8.

## 9. Screenshots of level 1, 5 and 10 completion

These are **desktop captures** (540x960 window, not the phone). Each sheet is 8 frames of one completion, left to right and top to bottom, from just before the release to the lift. The level is set directly by the tool, so the "swords freed" count on the card can read 1.
- `build/shots/m18_L1_strip.png`
- `build/shots/m18_L5_strip.png`
- `build/shots/m18_L10_strip.png`

(Frames from 0.1.7 on the phone are in `build/shots/dev17*.png`.) No 0.1.8 screenshot from the phone exists.

## 10. Remaining problems

1. **Android not tested for 0.1.8** (FPS, memory, crashes, transition freezes). The 55-60 FPS extraction target is unverified; the last measured value is 47-48 FPS on 0.1.7.
2. **No human playtest**: difficulty, the release moment and the card are unjudged by a person.
3. Decay is unchanged as instructed, but with larger taps the cost of a lapse in taps rises with the level (section 1); revisit if late levels feel harsh.
4. Larger taps mean a larger per-tap movement of the sword and a larger lag behind the bar (desktop numbers in section 5); smooth, but not as fine as the 2 %-per-tap design.
5. Audio cues have no assets, so the game is silent.
6. The level-1 completion is deliberately the mildest; higher levels are only verified on the desktop.
7. The debug switches (`--no-cam-fx`, `--no-light-fx`, `--no-card`, `--no-discs`) remain in the code; they only act in debug builds with a launch-args file.

## 11. Features not implemented

Main menu, Endless mode, Ruthless mode, online leaderboards (not requested), real audio assets, particle or neon effects (avoided on purpose), and any Android measurement of this version.
