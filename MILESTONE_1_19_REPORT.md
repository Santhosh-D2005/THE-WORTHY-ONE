# THE WORTHY ONE – Milestone 1.19 Report: Stability and Audio Validation

Version stays 0.1.9 (code 7), package `com.theworthyone.game`. No gameplay, UI, icon, sound or settings change. **No new APK was needed or built**: the only change is additional tests, and the installed build was verified to be byte-identical to `build\android\TheWorthyOne-debug.apk`.

## 1. Does the loop fix look technically correct?

**Yes, by inspection and by test, but the cause is still not proven.**

- `GameAudio._make_loop` makes a looping copy of the ambience (the shared imported resource is not modified) and ends the loop `LOOP_END_MARGIN_FRAMES` (64) frames before the end of the data, computed from the real data size and sample layout (`data.size() / bytes-per-frame`, handling 8-bit, 16-bit, mono and stereo).
- Real values (printed by the new test): 352,800 frames, 22,050 Hz, 16.000 s; loop begin 0, loop end 352,736 (2.9 ms before the end of the data). The seam of the file was cross-faded when it was generated, so cutting 2.9 ms is not audible as a gap (not listened to).
- The ambience file is imported uncompressed (16-bit PCM, `compress/mode=0`) with no importer-level loop, so the code-set loop is the only loop.
- **What is NOT proven:** that "reading past the end of the buffer at the wrap" was the root cause. That was my best explanation from the crash's shape (SIGSEGV in the audio thread, 18-26 s after launch, matching the first loop wrap). The evidence is behavioural: the build with the loop at the very end crashed every time within about 20 s even on the menu; the build with the margin has not crashed in the tests below. I did not capture a symbolised native backtrace, so a different cause that the margin happens to avoid cannot be excluded.
- Minor: a code comment in `game_audio.gd` says the crash was "found by the 1.19 phone test"; it was actually found in the physical test after 1.18. It is only a comment; I left it untouched rather than rebuild the APK for a comment.

## 2. Focused tests (desktop, headless, Godot's dummy audio driver)

| Suite | Result |
|---|---|
| Audio tests (32 existing + 18 new) | **50 checks, 0 failed** |
| Menu tests | 55 checks, 0 failed |
| Startup tests | 16 checks, 0 failed |

New checks added to `tests/audio_tests.gd` (no existing assertion was changed or weakened):
- The ambience is 16-bit mono with 352,800 frames; the loop ends 64 frames before the data ends and never at it; the margin is a few milliseconds (guard against it ever being set back to the end of the buffer).
- The same rule holds for 8-bit mono, 16-bit mono and 16-bit stereo streams; a null stream gives no loop and no crash; the audio data and the shared resource are untouched.
- Start / stop / start again reuses the one ambience player; freeing the audio node leaves no player in the tree; opening and closing the menu four times leaves exactly one ambience loop each time and no player behind.
- Already covered by the existing 32: no duplicate loop on repeated `play_ambience`, pause/resume of every player, missing folder / missing file / non-stream value cannot crash, leaving a scene frees its audio, menu and game button cues.

The headless audio driver never runs the real Android mixer, which is exactly why the original crash was invisible to the desktop tests; these tests guard the configuration, not the mixer.

The gameplay suites were not run.

## 3. Was the phone tested?

Yes. The phone was connected, awake and unlocked. Before every step the script checked that the phone was unlocked and that **the game was the foreground app**, and it aborts otherwise; the soak sent no taps and took no screenshots, so nothing could reach another app.

- Installed build check: the installed `base.apk` MD5 equals the local `TheWorthyOne-debug.apk` MD5 (37597e2c36b87d33e3a1110d30273f6e), so it was **not reinstalled**.
- Crash history: Android's crash log holds 5 entries for the game, all between 14:33 and 14:40 on the crashing build and its reproduction. Everything after the fixed build was installed counts as new.

## 4. Duration and loop cycles

- **Soak:** cold launch to the main menu, no input, **342 s** (the check loop ran 342 s at 15 s intervals). **About 21 full 16 s loop cycles by wall time** (342 / 16; the game does not count loops itself, so this is an estimate, and the first cycle includes the fade-in).
- Same process the whole time (pid unchanged at every check), game in the foreground at every check.
- Earlier evidence with the same fixed build (previous physical-test report): 106 s on the menu, then two full perf runs of about 2.5 minutes each with PLAY and gameplay, with the ambience running throughout.
- Memory during the soak: 310 MB PSS at the start, 293 MB at the end (no growth).

## 5. New crashes or audio errors

- **New crashes: 0** (5 entries before the soak, 5 after; also 0 new after the Back and QUIT tests).
- **Errors in the game process's own log** (`logcat --pid`, game process only): two lines `AHardwareBuffer: GraphicBuffer(w=4, h=4) failed (Unknown error -1)` at startup. That is a graphics-buffer message from startup, not audio; the game kept running. **No audio, OpenSL, underrun or signal errors.**
- Navigation without entering gameplay: Android Back on the menu exits cleanly (process gone, no crash entry); the QUIT button (a real tap, foreground verified) exits cleanly (no crash entry).
- The phone was returned to its normal state: the stay-awake setting was restored (0) and no debug files remain in the app's data.

## 6. What remains unverified

- **Human listening.** Nobody has heard these sounds on the phone. Android reports an active audio player, which only shows the output stream runs (Godot keeps it started even when it plays silence). Whether the ambience is audible, pleasant, too loud or too quiet, and whether the loop seam is silent to the ear, is unknown.
- The root cause of the crash (see section 1).
- Audio during gameplay for long sessions, the effect of pausing audio on the phone, and the gameplay cues' loudness: not re-tested here (gameplay was out of scope).
- A very long run (hours) and behaviour with other apps playing audio or with Bluetooth audio were not tested.

## 7. New APK?

Not necessary and not generated. Evidence was sufficient: the installed build equals the current APK file; the fixed build passed 342 s of soak plus the earlier runs without a crash; the only changes in this milestone are tests. Existing APK backups are untouched: `TheWorthyOne-debug-1.18-CRASHES.apk`, `-1.17`, `-1.16`, `-1.15`, `-before-1.15`.

## 8. Status

**PASS** for what was in scope (the loop fix is consistent and test-guarded, no new crash and no audio error in a 342 s soak, clean exits). Human listening is still outstanding.
