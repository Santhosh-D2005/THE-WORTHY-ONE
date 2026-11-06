# THE WORTHY ONE – Physical Android Test Report (Milestones up to 1.18)

Device: vivo V2129, Android 13, 720×1600, USB. Build tested: `build\android\TheWorthyOne-debug.apk`, **37,098,813 bytes**, version 0.1.9 (code 7). No laptop simulation was used for these results; the game ran on the phone.

**What "physical" means here.** The app ran on the real phone and I read its screen with screenshots. All touches were **injected with `adb shell input tap`** (a script), not a human thumb, so this says nothing about how the game feels to play. I **cannot hear audio**, so nothing here says what the sounds sound like.

## 1. Headline results

| # | Finding | Result |
|---|---|---|
| 1 | **The 1.18 build crashed the game on the phone** (SIGSEGV in the audio thread, about 20 s after launch, even sitting on the menu) | **FOUND AND FIXED** (see 2) |
| 2 | A screenshot burst accidentally captured another app (see 3) | **Incident, images deleted** |
| 3 | Everything else tested passed on the phone | see section 4 |
| 4 | FPS: not 60; PLAYING is about 5-7 FPS below the 1.9.2 measurement | see section 5 |

## 2. The crash (the most important result)

- Android's crash log showed repeated native crashes of the game (14:33, 14:34, 14:38, 14:40): `SIGSEGV` in the `AudioTrack` thread inside `libgodot_android.so`, always 18-26 s after launch.
- Reproduced with a cold launch and **no touching at all**: the game died on the main menu after about 18-21 s. That matches the 16 s ambience loop wrapping around.
- Cause (best explanation, not proven): the ambience loop ended exactly at the end of the audio buffer and the Android mixer read past it when wrapping. The desktop tests could not catch it (the headless dummy audio driver never runs the real mixer).
- Fix: the loop now ends 64 frames (about 3 ms) before the end of the data (`scripts/systems/game_audio.gd`, `LOOP_END_MARGIN_FRAMES`).
- **Verified on the phone:** the fixed build stayed alive for 106 s on the menu (several loop wraps), then through all the tests below including two perf runs; the crash count stayed at 5 (all old) from then on.
- **Correction to my 1.18 report:** it said Android Back "closed the app". That process had in fact crashed. I corrected `MILESTONE_1_18_REPORT.md`. The crashing build is kept as `TheWorthyOne-debug-1.18-CRASHES.apk`.

## 3. Privacy incident (please read)

When the game crashed mid-test, Android returned to the app that was open before it: **a stock-trading app** (Groww). My next screenshot burst (10 images) captured that app's screen, and my injected taps (at roughly the bottom-left and bottom-right of the screen, repeated for several seconds) landed in that app. My safety check only confirmed the phone was unlocked, not that the game was in front.
- I **deleted all 10 images immediately** and did not look at them again. They were never saved elsewhere or sent anywhere.
- The taps were at the "Top movers today" row area; nothing at those positions is a buy/sell control as far as the screenshot showed, but **please open that app and check that nothing was changed** (for example the Gainers/Losers filter).
- From then on every tap and screenshot was guarded: the script aborts unless the game itself is the foreground app (and the phone is unlocked).

## 4. Functional tests on the phone (all with injected taps)

| Test | Result |
|---|---|
| Install and launch | PASS. Opens straight on the main menu. |
| Main menu (title, tagline, stump with faint cracks, PLAY, QUIT) | PASS. Rendered as designed, nothing clipped. |
| PLAY with a real press on the screen | PASS. Game scene starts and reaches READY. |
| Gameplay HUD (level, timers, extraction bar, tap discs) | PASS. Readable. |
| Alternating taps: levels 1-4 | PASS. Completed in 2.6, 4.1, 3.1, 3.6 s. |
| Extraction effects: bar fill, sword lifts, empty slot, stump cracks visible at about 70 % progress | PASS (seen in screenshots). |
| Completion card: "THE SWORD YIELDS / LEVEL n COMPLETE / EXTRACTION TIME / n SWORDS EXTRACTED", no tap counts | PASS. Legible, not clipped. |
| Back → pause menu (PAUSED, RESUME, MAIN MENU) | PASS. State goes to PAUSED. |
| RESUME | PASS. Game continues (level 5 attempt). |
| Back → MAIN MENU | PASS. Returns to the main menu. |
| Failure (one tap, then nothing) | PASS. Stays on the failure screen: "THE SWORD REMAINS", "THE WOOD HOLDS FAST", statistics panel, TRY AGAIN, MAIN MENU, all legible. |
| TRY AGAIN | PASS. Fresh level 1, READY, progress 0 %, stump clean (no leftover cracks). |
| Second failure, then MAIN MENU | PASS. Returns to the menu. |
| QUIT button | PASS. App exits, no crash. |
| Android Back on the main menu | PASS. App exits, no crash. |
| Audio output active (Android lists a started audio player for the game) in menu and game | PASS (only shows the output stream runs; **not** that anything is audible). |
| Crashes during the tests after the fix | 0 new. |
| Debug files and stay-awake setting | Removed / restored. |

Harness note: one early failure test went wrong because my script's failure detection lagged (the perf log is only written every 4 s) and my own taps then pressed TRY AGAIN. That was a test-script artifact, not a game bug; a single clean tap behaves correctly.

## 5. Performance (same protocol as the earlier baselines: cold launch, PLAY, 12 s idle, 3 bursts of 20 tap pairs; injected taps)

| Run | READY | PLAYING | EXTRACTING | Memory (PSS) | Battery temp |
|---|---|---|---|---|---|
| Phone test run 1 | 51.1 | 45.7 | 44.8 | 315 MB | 41.8 °C |
| Phone test run 2 | 48.9 | 45.8 | 44.9 | 309 MB | 41.7 °C |
| 1.9.2 (earlier, for comparison) | 52-58 | 50-53 | 44-48 | 281-283 MB | about 33-36 °C |
| 1.7 (earlier baseline) | 59.5 | 58.6 | 47-48 | 278 MB | n/a |

- The 60 FPS target is **not** met. PLAYING is about 5-7 FPS below 1.9.2 and memory is about 30 MB higher. The phone was hot (41.8 °C vs 33-36 °C earlier), which can lower FPS by itself, so this does not show how much comes from the 1.10-1.18 additions (compression, cracks/glow, audio). I did not isolate them this time.
- p95 frame times were 25-30 ms; worst single frames 99-150 ms in the READY phase (a few hitches).
- The "about 30 FPS in real play" you reported was **not reproduced** by this measurement (it uses injected taps).

## 6. Not tested or not verified

- **Human feel:** nobody played with real thumbs; difficulty, touch comfort and whether the effects feel right are unknown.
- **Sound:** whether any sound is audible, how it sounds, and levels. Also whether audio pauses when the game is paused (only checked in desktop tests).
- **Launcher icon and themed icon:** not viewed on the phone (opening the home screen could show personal content).
- **Visual effects not judged on the phone:** forest compression (1.11) and the amber glow (1.13) were not separately confirmed in the screenshots; the micro-motion of the sword (1.10) cannot be judged from stills. Cracks were seen.
- **Levels beyond 5**, other tap patterns (slow, rapid, same-side), long-session heat behaviour, and rotation / app-switch behaviour were not re-run this time.
- The previous milestones' desktop-only claims remain desktop-only.

## 7. Builds

- Current (fixed): `D:\photos\gamic\THE WORTHY ONE\build\android\TheWorthyOne-debug.apk`, 37,098,813 bytes. Installed on the phone and used for all results above.
- Kept: `TheWorthyOne-debug-1.18-CRASHES.apk` (37,098,813 bytes, the crashing audio build), `-1.17`, `-1.16`, `-1.15`, `-before-1.15`.

## 8. What I recommend next

1. Check the other app for any changed filter (section 3).
2. Play the fixed build by hand and listen: tell me what is too loud, too quiet, or wrong.
3. If FPS matters more than the new effects, measure with `--no-fx` / `--no-cracks` / `--no-compress` on a cool phone to see which addition costs the most.
