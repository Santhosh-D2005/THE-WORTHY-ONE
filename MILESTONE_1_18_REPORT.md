# THE WORTHY ONE – Milestone 1.18 Report: Audio and Atmosphere

Version stays **0.1.9 (code 7)**, package `com.theworthyone.game`. No gameplay mechanic, timing, difficulty, progression or physics was changed, and no settings screen or audio-volume UI was added.

**Read this first.** I can only check sound by numbers and logic: I **cannot hear audio**. The sounds were designed and checked numerically, **not auditioned by a person**, and **nobody has heard them on the phone**. On the phone I verified only that the app installs, opens, and that Android reports an active audio player for it (see section 6). Whether the sounds are pleasant, too loud or too quiet is unverified.

## 1. What audio already existed

- A **cue framework, with no sound**: `GameAudio` (a pool of six players) and `LevelManager` already fired the gameplay cues (`tap`, `tap_slow`, `first_tap`, `pull`, `freed`, `level_complete`, `planted`, `failure`), but `assets/audio/` was empty and `cue_streams` was empty, so the game was silent. `pause`/`resume` cues were reserved but never fired.
- No UI sounds, no ambience, no volume settings, no documented audio origins, no audio files.

## 2. What was added or reused

- **Reused:** the existing cue names, the pool, `cue_requested` and every existing firing point in `LevelManager` (none changed).
- **New sounds (11 files, `assets/audio/*.wav`, about 1 MB):** all **original, synthesised by `tools/make_audio.py`** from filtered noise and sine waves, with no recordings, samples or third-party material, so there is no licence issue. Released CC0; documented in `assets/audio/README.md`. Fixed random seeds, so the script regenerates identical files.
  - `ambience` (16 s seamless loop of quiet wind and faint leaf rustle), `ui_tap` (soft wooden click), `ui_play` (low wooden knock with two soft tones), `tap`, `tap_slow`, `first_tap`, `planted` (soft thumps), `pull` (steel dragged from wood), `freed` (one restrained steel ring), `level_complete` (two soft low bell tones), `failure` (low sinking tone and a thump).
  - Every cue is under 2.5 s, every default level is between -17 and -10 dB, and every file starts and ends at zero.
- **Code:** `scripts/systems/game_audio.gd` now loads the files by name (safely), adds `ui_tap` and `ui_play`, a separate looping ambience player (`play_ambience`, `stop_ambience`) and pause handling. `scenes/ui/main_menu.tscn` got an `Audio` node. Small hooks in `scripts/ui/main_menu.gd` and `scripts/managers/level_manager.gd` (presentation only).
- **Not added:** sword-movement sounds beyond the existing cues (a continuous sound tied to the sword's motion could not be connected safely to existing events), pause/resume cue sounds, haptics.

## 3. Which event triggers which sound

| Event | Sound |
|---|---|
| Main menu opens | `ambience` fades in (-23 dB, 2.5 s) |
| PLAY pressed | `ui_play`; the ambience fades out with the screen fade |
| QUIT or Android Back on the menu | `ui_tap`; ambience fades out |
| Game scene starts | `ambience` fades in, quieter (-27 dB) |
| Pause menu RESUME, pause menu MAIN MENU, failure screen TRY AGAIN, failure screen MAIN MENU | `ui_tap` |
| First tap of an attempt / a valid tap / a too-slow tap | `first_tap` / `tap` / `tap_slow` (existing events) |
| Extraction completes / blade leaves the wood | `pull` / `freed` (existing events) |
| Completion card appears / next sword lands | `level_complete` / `planted` (existing events) |
| Run fails | `failure` (existing event) |

## 4. Looping, pausing and stopping

- **Looping:** `play_ambience` makes a looping copy of the imported stream (the shared resource is never modified), loop covering the whole file. The ambience file is imported **uncompressed (16-bit PCM)**, the format whose looping is certain. The file was built with a cross-faded seam; its seam step (0.021) is no larger than a normal sample step (0.019). Calling `play_ambience` again only retargets the volume, never a second loop.
- **Fades:** ambience fades in and out with sine fades and stops after fading out.
- **Pausing:** `GameAudio` listens to the game state. When the game is PAUSED, the ambience and every cue that is holding a sound are paused; on resume they continue where they were. A click played while paused (the sound of pressing RESUME) plays normally. (Godot keeps the pause flag only on players that hold a stream; idle pool players make no sound and are un-paused by `play()`.)
- **Leaving a screen:** the `Audio` node belongs to its scene, so leaving the menu or the game frees it and stops everything it was playing. The menu's ambience fades with the screen fade; the game's ambience is cut when the scene is freed (it is very quiet there).
- **Missing assets:** a missing folder, missing file, or a non-stream value in a cue slot is ignored; every cue still reports itself. The new test found one real bug here (a non-stream value in `cue_streams` crashed `play()` with an invalid cast); fixed.

## 5. Focused tests (desktop, headless, Godot's dummy audio driver)

| Suite | Result |
|---|---|
| New audio tests (files load, missing/broken assets, ambience loop and fades, pause/resume, menu events, game button events, first-tap cue) | 32 checks, 0 failed |
| Menu tests | 55 checks, 0 failed |
| Pause tests | 42 checks, 0 failed |
| Failure tests | 117 checks, 0 failed |
| UI tests | 106 checks, 0 failed |
| Startup tests | 16 checks, 0 failed |
| Import / project load | clean, no script errors |

No test was weakened or changed. Headless runs use a dummy audio driver, so these tests check logic and player state, **not audibility**.

**Not run:** the windowed experience suite, which asserts the order of the gameplay cues (first tap, pull, freed, level complete, planted) during a full extraction. No code that fires those cues was changed, and running it means playing the core game, which was out of scope. The other gameplay suites were not run either.

## 6. Physical-device audio

The phone was locked at first; I stopped and asked, and you unlocked it. I then checked it was awake and unlocked before every step. I did **not** enter the game.
- Installed the new APK; it reports version 0.1.9, code 7.
- Opened the main menu. Android's audio service listed **one started audio player** for the game's process (OpenSL ES, usage media), and the phone's media stream was not muted (speaker volume 9 of 15).
- **This does not prove the ambience is audible.** Godot keeps its output stream started even while playing silence, so a started player only shows the audio output is running.
- Pressed Android Back on the menu and the app process was gone. **CORRECTION (found in the later physical test, see `PHYSICAL_TEST_REPORT.md`): that process had actually CRASHED, not closed.** The 1.18 build crashed (SIGSEGV in the audio thread) about 20 s after launch, even on the menu. It is fixed in the current APK; the crashing build is kept as `TheWorthyOne-debug-1.18-CRASHES.apk`. The size and the "installed and opened" statements below describe the crashing build.
- **Not verified on the phone:** that any sound is audible, how any sound sounds, UI clicks, the gameplay cues, ambience in the game, pause/resume of audio, and fades.

## 7. APK

- Path: `D:\photos\gamic\THE WORTHY ONE\build\android\TheWorthyOne-debug.apk`
- Size: **37,098,813 bytes**, version 0.1.9, code 7, package unchanged. Exported to a temporary file first and swapped in afterwards; it contains the 11 imported sound files (about 0.9 MB), the new audio script and the menu scene.
- Earlier builds kept: `TheWorthyOne-debug-1.17.apk` (36,400,247 bytes), `-1.16.apk` (36,400,247), `-1.15.apk` (36,383,103), `-before-1.15.apk` (36,090,625).
- Installed and opened (menu only) on the physical phone.

## 8. Limitations and remaining work

- **Listen to the sounds.** Adjust `tools/make_audio.py` or the per-cue levels (`GameAudio.DEFAULT_VOLUMES_DB`, `MainMenu.AMBIENCE_DB`, `LevelManager.AMBIENCE_DB`) by ear on the phone speaker. Synthesised sounds can sound thin; if so, real recordings with documented licences would be the next step.
- No volume control exists for the player (no Settings screen, as instructed); the levels are fixed.
- The game's ambience cuts abruptly when the game scene is left (it is very quiet there); the menu's fades.
- `tap` can fire five or more times per second; its level and length were chosen to be soft, but its effect over a real session is unknown.
- The pause cue and resume cue have no sound (the pause itself pauses the streams).
- Unverified until played: the loop seam in the real mixer, any audible clipping or clicks, and the sound of the sword extraction cues in the real game.
