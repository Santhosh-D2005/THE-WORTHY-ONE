# Audio assets: origin and licence

Every `.wav` file in this folder is **original work, synthesised by `tools/make_audio.py`** (numpy: filtered noise and sine waves). No recordings, samples, sound libraries or any third-party material were used.

**Licence: CC0 1.0 (public domain dedication) by the project.** There are no attribution or licence obligations.

The script uses fixed random seeds, so running `python tools/make_audio.py` regenerates identical files. To change a sound, edit the script and run it again, then let Godot re-import the folder.

| File | Used for | Length |
|---|---|---|
| `ambience.wav` | Looping, very quiet forest wind and leaf rustle (menu and gameplay). Made to loop seamlessly. | 16 s |
| `ui_tap.wav` | Soft wooden click: QUIT, RESUME, MAIN MENU, TRY AGAIN | 0.09 s |
| `ui_play.wav` | The PLAY button: a low wooden knock with two soft tones | 0.55 s |
| `tap.wav` | A valid tap that added progress (very short, soft) | 0.07 s |
| `tap_slow.wav` | A tap that was too slow (duller) | 0.12 s |
| `first_tap.wav` | The first tap of an attempt | 0.30 s |
| `pull.wav` | The extraction completes: steel dragged out of wood | 0.75 s |
| `freed.wav` | The blade leaves the wood: one restrained steel ring | 1.9 s |
| `level_complete.wav` | The completion card: two soft low bell tones (A3, E4) | 2.4 s |
| `planted.wav` | The next sword lands in the stump | 0.45 s |
| `failure.wav` | The run failed: a low sinking tone and a soft thump | 1.1 s |

Format: 22.05 kHz, 16-bit, mono WAV; about 1 MB in total.

**Not auditioned by a person.** These sounds were designed and checked numerically (peak levels, silent start and end, loop seam), not listened to by the author of this change. Judge them by ear and adjust `tools/make_audio.py` or the per-cue volumes (`GameAudio.DEFAULT_VOLUMES_DB`).
