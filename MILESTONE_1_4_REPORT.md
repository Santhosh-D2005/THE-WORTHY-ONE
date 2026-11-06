# Milestone 1.4 report - performance, startup, session timer

Build: version 0.1.4 (code 2), debug APK, Godot 4.7.2 mono export template.
Device for every phone number below: **vivo V2129** (Android 13, Adreno 610, 720x1600, 60 Hz, ~5.8 GB RAM, heavily used: ~150 MB free, 2.8 GB swapped).
Desktop numbers are never mixed with phone numbers: every FPS / startup / memory figure in this report was measured on the phone, except where marked "desktop".
A backup of the pre-milestone project is in `..\THE WORTHY ONE_backup_1_3` (not a git repo).

## 1. Original measurements (Milestone 1.3 code + the new probe, quality "original")

Measured with `PerfProbe` (in-game frame deltas, see section 9) on the phone, ~13 s idle then taps sent with `adb shell input tap`:

| State | Frames | Avg FPS | Median | P95 | P99 |
|---|---|---|---|---|---|
| Idle (READY) | 194-495 | 19.6-20.0 | 48.8-50.1 ms | 53-54 ms | 59-67 ms |
| Active play (PLAYING) | 54-97 | 19.6-20.3 | 49.6-51.2 ms | 50-52 ms | 50-54 ms |
| Extraction animation | 134-141 | 18.8-19.5 | 50.0-51.4 ms | 50-55 ms | 127-129 ms |

(two runs; one of them includes a failure screen stretch). Draw calls ~152/frame, ~51k triangles/frame, PSS 287-319 MB.
The Milestone 1.3 report said "~30 FPS" (measured with SurfaceFlinger). Today the same visuals measure ~20 FPS; frames are locked at 3 vsyncs (50 ms). I did not find the reason (device state/thermals/memory pressure are possible); all before/after numbers here were taken in the same session so they compare with each other, not necessarily with the old 30.
Cold start of the un-baked build: **10.7 s** launch to first frame (one run; 1.3 reported 11-16 s).

## 2. Bottlenecks (measured one change at a time, idle scene, launch args via `user://launch_args.txt`)

| Change vs original (20.2 FPS, repeat runs 20.2 / 20.3 / 19.4) | Avg FPS | Verdict |
|---|---|---|
| 3D scale 0.75 / 0.6 | 28.0 / 34.3 | **biggest lever: the game is pixel-bound** |
| Shadow map 1024 / 2048 (from 4096) | 25.5 / 24.4 | large |
| Shadow filter quality 0 (from 2) | 24.5 | large |
| Fog off | 23.7 | moderate (fog sun-scatter term alone: 19.6, no effect) |
| Shadows off | 22.8 | moderate |
| Colour grading (adjustment) off | 20.5 | none |
| Bark normal maps off | 20.9 | ~none |
| Shadow blur 0 | 20.4 | none |
| Combo: 0.75 + 1024 + filter 0 | 41.8 | |
| Combo: 0.7 + 1024 + filter 0 + no sun-scatter | 42.8 | |
| Combo: 0.6 + 1024 + filter 0 + no sun-scatter ("balanced") | 58.2 | **chosen** |
| Same + fog off + shadows off | 59.5 | only +1.3 over balanced, so fog and shadows were kept |

Not measured: floor shader, overdraw, transparency (one alpha contact-shadow quad), mesh count (~150 draw calls; not the limit). I did not assume they matter; at 3 texture reads the floor shader is small next to the numbers above, but no experiment isolated it.

## 3. Changes implemented

- `RenderQuality` (`scripts/systems/render_quality.gd`): configurable knobs (3D scale, shadows on/off, shadow-map size, shadow filter, shadow blur, fog, fog sun-scatter, grading, bark normal maps) and presets `original` (= 1.3 look, desktop/test default), `high` (= original), `balanced` (**Android default**: scale 0.6, shadow map 1024, filter 0, no fog sun-scatter), `low` (scale 0.5, no shadows; **not measured on the phone**). Select with `--quality=<name>` and override single knobs with `--rq=key=value,...`. Debug builds also read `user://launch_args.txt` (needed because the Android launcher activity does not forward intent extras).
- `ForestEnvironment`, `MaterialFactory`, `StumpBuilder` read the settings; the 3D scale is applied to the root viewport (HUD stays full resolution).
- `AssetCache` + `tools/bake_assets.tscn`: 55 meshes and 11 noise textures baked into `assets/baked/` (7.1 MB), loaded at start; the procedural builders remain as fallback. Re-run the bake after changing any procedural parameter.
- `PerfProbe` autoload + `tools/analyze_perf_log.py`: frame/startup logging, inert unless `--perf-log`.
- Not changed: gameplay, scenes' composition, tests, shaders.

## 4. Before / after (phone, same session)

| | Original look (1.3 settings) | Balanced (new Android default) |
|---|---|---|
| Idle FPS (avg / median / p95 / p99) | 20.0 / 48.8 / 53.1 / 66.7 ms | **58.0** / 16.7 / 20.0 / 25.2 ms (1466 frames) |
| Active play | 20.3 / 49.6 / 50.0 / 50.0 ms | **57.4** / 16.7 / 20.4 / 24.0 ms (144 frames) |
| Extraction animation | 19.5 / 50.0 / 50.0 / 126.8 ms | **53.2** / 16.8 / 23.1 / 29.7 ms (375 frames) |
| All frames | 19.7 FPS | **56.9 FPS** (median 16.7, p95 20.4, p99 27.7 ms) |
| PSS memory (dumpsys meminfo, end of run) | 287 MB (RSS 367) | 290 MB (RSS 371) |
| Draw calls / triangles per frame | 153 / 51k | 151 / 51k |

Worst single frames are 150 ms in both (a first-time hitch, see limitations). Extraction is the weakest state (53 FPS avg): the sword animation adds work.
Memory did not improve; balanced uses slightly more graphics memory (46 vs 42 MB).
Gameplay frames were driven by `adb input tap` (injected touches, not a finger); that run reached 3 extractions in each build.

## 5. Startup

Launch (`am start`) to first rendered frame, phone clock:

| Build | Runs | Result |
|---|---|---|
| Before (procedural, 1 run) | 1 | 10.65 s |
| Baked assets, original look | 4 | 8.08 / 8.15 / 8.27 / 8.15 s |
| Baked assets, balanced | 4 | 8.05 / 7.90 / 7.96 / 8.24 s |

Breakdown of an ~8.1 s start: ~4.8 s before the first script runs (Android process, engine, Vulkan init, loading a 36 MB package that includes the mono template), ~0.6 s building the scene (was ~1.3 s: trees 774 -> ~165 ms, terrain 118 -> 80 ms, stump trunk 208 -> 104 ms, measured on the phone), and ~2.6 s from scene ready to the first drawn frame (not broken down further; most likely GPU pipeline/shader compilation).
**The target "below 5 s" was NOT reached.** The baked-asset saving is about 2.5 s on the comparison I have (single "before" run, so the size of the saving is uncertain).
Outliers seen: the first launch after a fresh `adb install` took 16 s to 59 s before the first script ran (shader cache rebuilt / phone under memory pressure; not reproduced on later launches). Normal users would hit a slow first launch after install/update.
What did not help or was not tried: noise textures were already generated off the main thread, so baking them mattered less than the meshes; a non-mono export template (would shrink the package and engine start) is not installed here and was not tried; pipeline pre-warming was not tried.

## 6. Session timer

Required behaviour: zero in READY; starts on the first valid alternating tap; continues through extraction and the next level; stops on failure; resets to zero on retry and waits for a tap; the level timer unchanged.
**Finding: the code already behaved this way; I found no defect and made no change to `timer_manager.gd` or the level flow.** New `tests/timer_tests.gd` (25 checks, desktop, simulated input) proves each point end to end, including the HUD text, a wrong-side tap not starting it, and backgrounding not being counted. If you saw different behaviour on the phone, tell me what you saw: it is not reproducible from the code or these tests.

## 7. Visual trade-offs (balanced vs original)

Desktop screenshots compared (`build/shots/original.png`, `balanced.png`, `low.png`): same composition, fog, shadows, light and HUD. At 0.6 scale the 3D image is softer and edges of trunks/stump show visible stair-stepping; shadow edges are harder (filter 0) and fog has no sun-glow term; HUD text stays sharp. On the phone itself I did not take screenshots (lock-screen privacy), so how it looks in the hand is not judged. A 0.75 scale gives ~42 FPS with a cleaner image if you prefer sharpness: `--rq=scale_3d=0.75`.

## 8. Automated tests (desktop, simulated input; clean runs, no focus loss)

| Suite | Result |
|---|---|
| Unit (`run_tests.gd`) | all pass (0 failures) |
| Integration | 191 / 191 |
| Failure | 116 / 116 |
| Layout | 256 / 256 |
| **New:** timer lifecycle | 25 / 25 |
| **New:** startup (baked == procedural, quality args, settings applied) | 14 / 14 |

Baked-equals-procedural: terrain, stump trunk and cut face, and the shared noise texture compared against fresh builds (positions within 0.1 mm, normals/colours/UVs within small tolerances because the engine stores them compressed, indices and texture pixels exact). Only 3 of the 55 meshes and 1 of 11 textures were compared individually; the scene-build check confirms all 65 loads came from baked files and 0 were built.
An earlier regression run during this session showed 1 integration and 5 failure-test failures while the test window lost OS focus (the harness's known invalid-run condition); the clean re-run above passes everything.

## 9. Physical Android results

Everything in sections 1, 2, 4, 5 was run on the vivo V2129 (debug APK 0.1.4 built from this code is installed). Method: `PerfProbe` logs each frame's delta (includes vsync waits, so 16.7 ms is the floor on this 60 Hz panel) plus game state, pulled with `run-as`; startup from the phone clock; memory from `dumpsys meminfo`; taps injected with `adb shell input tap`. Not done: human-finger play, multi-touch, other devices, battery/thermals, release build. The installed APK has no launch args file, so it runs "balanced" with the probe off.

## 10. Remaining limitations

- Startup is ~8 s, not <5 s; first launch after install can be far slower.
- Android Back still pauses (Milestone 1.3 behaviour); still awaiting your decision whether it should quit.
- Extraction animation has the lowest frame rate (53 FPS) and a one-off ~150 ms hitch on first use (likely first-use pipeline compilation); not investigated further.
- The 3D image is rendered at 60 %: softer and aliased edges. A better upscaler (FSR) or cheaper post would be the next experiments, not measured here.
- `low` preset unmeasured on the phone; floor shader / transparency / overdraw not isolated.
- The "~30 FPS" in the 1.3 report is not reproduced; baseline today is ~20 FPS.
- Debug APK only; the `launch_args.txt` hook exists only in debug builds.

## Correction added in Milestone 1.5

The "~150 ms hitch on first extraction" in section 10, and the 127-150 ms worst/p99 values in the EXTRACTING rows of sections 1 and 4, were wrong:
those frames belong to the start-up entrance sequence, which the probe also labels EXTRACTING (before the first READY). Excluding frames before the first READY,
extractions on the balanced preset measured 56.6 FPS with a worst frame of 42 ms (one run). `tools/analyze_perf_log.py` now reports start-up frames separately.
