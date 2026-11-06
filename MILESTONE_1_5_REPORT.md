# Milestone 1.5 report - visual quality / performance balance, startup, Back button

Build: version 0.1.5 (code 3), debug APK, installed on the vivo V2129 (Android 13, Adreno 610, 720x1600, 60 Hz).
Every FPS / frame-time / startup / memory number below was measured **on that phone**; desktop is used only for tests and screenshot comparisons and is labelled so.
Method (unchanged from 1.4): `PerfProbe` logs each frame's delta (includes the vsync wait, so 16.7 ms is the floor on this panel) plus game state; startup from engine/phone clocks; memory from `dumpsys meminfo` PSS; gameplay driven by injected `adb input tap` (not a finger). Per-run protocol: launch, ~12 s idle in READY, three bursts of alternating taps (three extractions), pull log. Frames before the first READY (load + entrance) are now reported separately.
Backups: `..\THE WORTHY ONE_backup_1_3`, `..\THE WORTHY ONE_backup_1_4`.

## 1. Baseline

Read: 1.3 and 1.4 reports. Existing optimisations (1.4): pre-baked meshes/noise textures (`assets/baked`, startup), `balanced` quality = 3D scale 0.6 bilinear, 1024 shadow map, shadow filter 0, no fog sun-glow (the pixel-bound GPU fix). Kept: one sun light with one shadow cascade, fog, grading, bark normal maps, ~150 draw calls.
Baseline for this milestone = the 1.4 `balanced` configuration, re-measured in this session (`--rq=fsr=0,aniso=2`, bracketing the final runs):

| | Control A | Control B |
|---|---|---|
| All frames, avg FPS | 57.6 | 58.1 |
| Idle / active / extraction FPS | 58.4 / 57.6 / 54.6 | 58.9 / 56.8 / 55.4 |
| Median / P95 / P99 | 16.7 / 19.4 / 27.9 ms | 16.7 / 18.8 / 27.6 ms |
| Worst frame (steady state) | 147 ms (one hitch in idle) | 77 ms |
| PSS | 273 MB | 268 MB |

Run-to-run noise is about +-1 FPS. Two real sources of drift were seen: the **first run after `adb install` is slower** (47.7 FPS in the 0.60 rep 1 below, same config as the 58 FPS runs) and a long session of back-to-back runs **heats the phone** (one control at the end of a ~25 run session read 54 FPS). The 1.3 report's "~30 FPS" at full resolution is still not reproduced here.

## 2. Rendering-scale benchmark (all other settings = 1.4 balanced; 2 runs per scale, interleaved)

Frame stats exclude start-up frames. Idle = READY, active = PLAYING, extraction = EXTRACTING states.

| Scale | Run | All avg FPS | Idle / active / extraction FPS | Avg(=1000/FPS) / median ms | P95 / P99 ms | Worst ms | PSS MB |
|---|---|---|---|---|---|---|---|
| 0.60 | 1 (first after install) | 47.7 | 47.9 / 47.6 / 47.0 | 21.0 / 20.4 | 30.2 / 32.5 | 142.6 | 288 |
| 0.60 | 2 | **58.4** | 58.9 / 57.2 / 56.6 | 17.1 / 16.7 | 18.1 / 28.0 | 76.1 | 301 |
| 0.65 | 1 | 44.3 | 44.0 / 45.4 / 45.3 | 22.6 / 22.2 | 27.1 / 28.8 | 87.1 | 301 |
| 0.65 | 2 | 44.2 | 43.8 / 45.1 / 45.3 | 22.6 / 22.2 | 27.8 / 33.1 | 78.2 | 300 |
| 0.70 | 1 | 43.1 | 43.4 / 43.4 / 44.4 | 23.2 / 22.7 | 29.1 / 30.5 | 105.0 | 299 |
| 0.70 | 2 | 43.1 | 42.6 / 44.1 / 44.7 | 23.2 / 22.7 | 28.4 / 29.4 | 75.0 | 301 |
| 0.75 | 1 | 42.0 | 41.5 / 43.9 / 43.2 | 23.8 / 23.8 | 29.6 / 30.7 | 75.8 | 301 |
| 0.75 | 2 | 42.2 | 41.5 / 43.9 / 44.1 | 23.7 / 23.8 | 26.7 / 28.3 | 95.9 | 299 |

Reading: **0.60 is a cliff, not a slope.** It is the only scale that fits the 16.7 ms frame; 0.65-0.75 fall to a mix of 16.7 and 33 ms frames (~42-45 FPS, median 22-24 ms, P95 27-30 ms) and are almost indistinguishable from each other. Rep 1 at 0.60 shows how close to the edge it is (a cold/first-after-install state drops it to 47.7), but 8 later runs of the same config gave 57.5-58.9.
Things that did NOT lift 0.65-0.70 to 60 FPS: shadows off (0.70: 43.8; 0.65: 46.1), fog off (0.70: 43.6-44.5), 512 shadow map at 0.65 (45.1).
Memory: ~288-301 MB PSS in these runs (268-273 in later runs; no scale-dependent signal beyond noise).
Visible differences (desktop screenshots, `build/shots/up_compare.png`): 0.75 is a little crisper than 0.60; the gap is smaller than the gap between bilinear and FSR at the same scale, and 0.65-0.75 do not reach 60 FPS on this phone.

## 3. Chosen configuration (Android default "balanced")

**3D scale 0.60 + FSR 1.0 upscaling + 4x anisotropic filtering; shadows 1024 / filter 0 / no fog sun-glow (unchanged); no MSAA, no FXAA.**
Why: it is the only scale that holds ~58 FPS; FSR and anisotropy were measured free (below); anything that adds sharpness by spending frame time falls off the 60 FPS cliff.
`--quality=low` is now 0.50 + FSR (measured: 59.6 FPS, P99 18.1 ms, i.e. a solid 60 with headroom for hot phones, but softer). `--quality=original` (desktop/test default) is unchanged.

Option measurements (all at 0.60, idle/active/extraction avg FPS in "all frames"):

| Option | All-frames FPS | Verdict |
|---|---|---|
| control (bilinear, aniso 2) | 58.3 / 57.9 / 57.5 | baseline |
| **FSR 1.0 upscaling** | 58.2 | **free; adopted** (sharper than bilinear) |
| **Anisotropy 4x / 8x** | 58.1 / 58.1 | **free; 4x adopted** |
| FXAA | 40.9 | rejected: -17 FPS |
| MSAA 2x / 4x | 44.3 / 42.9 | rejected: -14 / -15 FPS |
| MSAA 2x with shadows off | 45.7 | rejected: still far below 60 |
| FSR at 0.50 | 59.6 | kept as `low` |
Final build vs control, same session (final = defaults, no arguments): All-frames FPS 57.9 / 58.5 (control 57.6 / 58.1); idle 58.5 / 59.1; active 56.7 / 58.3; extraction 56.0 / 56.4 (control 54.6 / 55.4); P95 19.4 / 18.2 ms; P99 27.7 / 27.9 ms; worst 81.6 / 93.9 ms; PSS 268 MB. **No measurable change in frame time and a small, possibly noise-level gain in extraction.** The benefit of this milestone's rendering work is image quality at equal frame rate, not more FPS.

## 4. Visual improvements made

- **Upscaler:** FSR 1.0 instead of bilinear for the 0.6 scale: cleaner edges and less smear than bilinear in desktop comparisons (`build/shots/up_compare.png`: top-left bilinear, top-right FSR). Not judged on the phone itself (no screenshot comparison on device).
- **Anisotropic filtering 4x:** sharper bark/floor at a slant, no frame-time cost. The visible effect is subtle; I did not capture a before/after of it.
- **Sword steel:** the blade rendered dull and dark because a fully metallic surface mirrors the dark forest. It is now less metallic (0.62, was 0.85) with a brighter albedo and lower roughness (0.27, was 0.34): it reads as lit polished steel with a visible fuller (desktop crops `build/shots/crop_sword_original.png` vs `crop_sword_steel_new.png`). Gold, leather unchanged. This changes the sword look noticeably; revert in `MaterialFactory.steel()` if you prefer the old one.
- **Not changed:** the wood cut face, bark, trunks, sun/shadows and fog are as before. No bloom, neon, particles or heavy post-processing were added. Mipmaps on the noise textures: the generator already produced them (no change).
- **Stair-stepping** is only reduced, not removed: MSAA/FXAA would remove it but cost 14-17 FPS (see section 3).

## 5. Performance findings (profiling evidence)

- GPU/pixel-bound, as in 1.4: render scale dominates; shadow-map size, shadow filter and fog gave smaller gains at 1.0 scale (1.4 data); at 0.60 the remaining budget is fully used (P95 18 ms).
- **Extraction frame drops were a measurement artefact.** The 142-150 ms "extraction spikes" in the 1.4 report were the start-up entrance (also state EXTRACTING). With start-up frames separated, extraction is 56-57 FPS with worst frames of 31-42 ms. No shader first-use stutter was visible after READY in these logs (worst steady-state spikes were 75-147 ms, one-offs mostly in idle, ~1-3 per run; not attributed to a cause). The 1.4 report carries a correction.
- Not changed: per-frame HUD text/redraw cost (CPU, not the limiter), because nothing in the profile pointed at the CPU.
- Not done: a GPU profiler capture (no tool available on this setup); conclusions come from A/B frame-time runs.

## 6. Startup (phone clock / engine time; "interactive" = first READY, input enabled)

Same session, same build, 3-4 launches each, engine seconds since process start (add ~1.2 s for process spawn after the launch command):

| Case | Runs | Interactive (READY) |
|---|---|---|
| Baked assets (shipping) - repeat launches | 3.66 / 3.88 / 3.68 / 3.63 / 3.82 s | **3.6-3.9 s** |
| Procedural (`--no-baked`) - same session | 6.65 / 7.03 / 7.01 / 6.55 / 6.38 s | 6.4-7.0 s |
| Baked, first launch after `adb install` | 6.55 / 5.63 / 4.49 s (earlier build, same assets) | 4.5-6.6 s |
| Baked, repeat launches (earlier build, same session) | 4.16 / 4.87 / 3.71 / 3.63 / 3.75 s | 3.6-4.9 s |

Breakdown of a baked repeat launch: ~2.8 s engine/Android before the first script, ~0.6 s building the scene, ~0.15 s to the first drawn frame. Baking saves ~2.9 s (scene build 1.5 -> 0.65 s, first-frame gap 2.2 -> 0.15 s). Compared with the 1.4 report (8 s from launch) the same baked build is much faster today; I did not isolate why (phone memory pressure and driver caches vary, and the 1.4 numbers were taken right after install). Treat 3.7 s as the warm-device figure and ~5-7 s as the first-launch-after-install figure. Outliers seen in 1.4: a first launch after install once took 16-59 s before the first script; not reproduced in 1.5 (5 installs).
So "below 5 s" holds on repeat launches (about 4.9 s including process spawn) and not reliably on the first launch after an install.

**Non-.NET export (investigated, not done).** The project is pure GDScript (no .cs/.csproj), so the standard (non-.NET) editor and export templates are compatible in principle; the standard editor is already installed on this machine, but only the *mono* export templates (`4.7.2.stable.mono`) are installed, so a standard APK could not be built or measured here. The mono APK contains a 76 MB `libgodot_android.so`; what a standard build would save in size or startup is **unmeasured**. Benefit expected: smaller package/library, maybe slightly faster engine start (unverified). Risks: needs a ~1 GB template download, a new export/signing check, and a re-validation of the whole device protocol; no scripting migration is involved. Recommendation: try it as a single measured experiment (needs your OK for the download); do not change the architecture.

## 7. Android Back button and pause menu - implemented and tested on the phone

- `application/config/quit_on_go_back=false` (before, Android Back would have quit the game directly).
- Back (or Escape on desktop): READY / PLAYING / EXTRACTING -> pauses and opens the **PAUSED** menu with **RESUME** and **QUIT**; Back again resumes; on the failure screen Back does nothing; after an app-focus loss (the old "tap to resume" pause) Back upgrades it to the menu.
- Pause freezes timers, progress decay, input and animations (the tree is paused); RESUME restores the exact state (progress identical, timers continue without the paused time, level keeps its state; the extraction animation continues and the level advances once).
- The menu swallows every touch; presses in the first 350 ms are ignored; taps outside the buttons do nothing.
- **QUIT** does not emit `run_failed`, create a result or mark the run over. With no main menu scene it **exits the app** (documented limitation); if `res://scenes/ui/main_menu.tscn` exists it will go there instead.
- Ruthless hook: `GameplayConfig.confirm_quit_during_run` (default off). When on and a run is in progress (session timer started), the first QUIT press only asks "CONFIRM QUIT?". Implemented and unit-tested; the Ruthless mode itself is not started.
- **On the phone (real `adb shell input keyevent KEYCODE_BACK`, injected taps):** Back opened the menu and the app stayed alive; screenshot of the in-game menu taken (game visible, not the lock screen); RESUME returned to PLAYING; Back/Back toggled PAUSED -> PLAYING; Back + QUIT ended the process and the game log contained 0 FAILED states. Not tested: a human thumb on the menu, the system Back gesture on a device with gesture navigation, a confirm-quit flow on the device.

## 8. Tests (desktop, simulated input; clean runs)

| Suite | Result |
|---|---|
| Unit (`run_tests.gd`) | all pass (0 failures) |
| Integration | 191 / 191 |
| Failure | 116 / 116 |
| Layout | 256 / 256 |
| Timer lifecycle (1.4) | 25 / 25 |
| Startup / quality settings / baked equality | 15 / 15 (one check added for the new defaults) |
| **New: pause menu / Back** | 41 / 41 |

The new pause tests cover: Back in READY; mid-run pause with progress, level and session timers frozen over 2.5 s, taps ignored and no failure while paused; exact restore on RESUME; failure still happening exactly once afterwards; the input guard and Back toggle; Escape; Back ignored on the failure screen; pause during the extraction animation (frozen, one level advance after resume); QUIT without game over; optional quit confirmation; focus loss versus menu.
All existing tests still pass. `pause_tests` uses an injected quit handler (the app is not actually closed in desktop tests); the real quit was verified on the phone. Earlier in the session one run showed false failures when the test window lost OS focus; the final run above was clean.

## 9. Remaining visual weaknesses

- The 3D layer is rendered at 60 % and upscaled: thin geometry (sword guard, grass blades, trunk edges) still shows stair-stepping/shimmer, and fine bark/wood detail is soft. The only fixes found (MSAA/FXAA/higher scale) cost 14-17 FPS or more.
- The cut-face growth rings look slightly polygonal at this resolution; the sword is still simple geometry with no baked detail (no engraving, no wear).
- Shadows are hard-edged (filter 0, 1024 map) and fog has no sun-glow, to hit 60 FPS.
- Nothing here was judged by eye on the phone beyond one screenshot of the pause menu.

## 10. Recommended next milestone

1. **Human playtest of 0.1.5 on the phone** (finger input, Back gesture, feel of the pause menu, sharpness at 0.6 + FSR, the new steel): decide whether the image is sharp enough or whether to trade FPS for resolution (0.75 at ~42 FPS).
2. **Standard (non-.NET) export experiment** for package size and startup (needs the template download approved).
3. Then, if the image is judged too soft: sharper art at the source (higher-detail sword/trunk geometry, a sharper cut-face shader) rather than more resolution; and a real main menu so QUIT can return to it.

## Exact next action required from you

Play the installed build (version 0.1.5) for a few minutes with your fingers, use the Back button/gesture mid-run, and tell me: (a) is the image sharp enough, (b) does Back/RESUME/QUIT feel right, (c) may I download the standard Godot export templates (~1 GB) to test a non-.NET build. Remaining limitation to know: the phone must stay unlocked for my device tests, and QUIT currently exits the app because no main menu exists.
