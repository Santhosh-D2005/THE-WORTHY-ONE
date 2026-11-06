# Android export guide - THE WORTHY ONE

Verified on: Godot 4.7.2 stable (.NET editor build) on Windows 11, and one physical phone
(vivo V2129, Android 13, arm64, Adreno 610). Anything not marked "verified" has not been tried.

## 1. What the project is configured for

| Setting | Value | Where |
|---|---|---|
| Orientation | Portrait, locked (`screenOrientation=1` in the built manifest) | `project.godot` `display/window/handheld/orientation=1` |
| Base resolution | 1080 x 1920, stretch `canvas_items`, aspect `expand` | `project.godot` |
| Input | Touch handled natively; mouse and touch emulation both OFF | `project.godot` `input_devices/pointing/*` |
| Renderer | Mobile (Vulkan). Texture compression ETC2/ASTC enabled | `project.godot` |
| Immersive mode | On (system bars hidden) | export preset `screen/immersive_mode` |
| Package | `com.theworthyone.game`, name "THE WORTHY ONE", version 0.1.9 (code 7) | export preset |
| ABI | `arm64-v8a` only | export preset `architectures/*` |
| Min / target SDK | 24 / 36 (Godot template defaults; verified from the built APK) | built manifest |
| Permissions | None requested (verified: no `uses-permission` in the APK) | export preset |
| Packaged files | Everything except `tests/`, `docs/`, `build/`, `*.md` | `exclude_filter` |
| Launcher icon | `icon.svg` - a PLACEHOLDER | `project.godot` `config/icon` |

Screen handling: the HUD and failure screen are anchored, so they adapt to any portrait aspect ratio.
They also read the OS safe area (`scripts/systems/safe_area.gd`) so they clear camera cut-outs and gesture bars.
On the test phone the 46 px cut-out inset was applied (verified from the screenshot geometry).
The camera keeps the 9:16 composition on every aspect ratio (`scripts/gameplay/gameplay_camera.gd`).

## 2. Requirements on the build machine

All of these were present on this machine and used for the verified export:

1. Godot 4.7.2 and its matching **export templates** (`%APPDATA%\Godot\export_templates\4.7.2.stable.mono\`
   containing `android_debug.apk`, `android_release.apk`, `android_source.zip`). Editor > Manage Export Templates installs them.
2. **Android SDK** with `platform-tools` (adb) and `build-tools` (Godot picked `36.0.0` for `apksigner`/`zipalign`).
   Platform `android-34`/`android-37` were installed. Godot's own validation also asks for SDK *cmdline-tools*, which are **not** installed
   here; the non-Gradle export did not need them (verified: export succeeded without them).
3. **JDK 17** (OpenJDK 17.0.9 was used, found under the Unity Hub install). JDK 24/25 are also on the machine but are not what Godot is configured to use.
4. A **debug keystore** (`D:/Godot/debug.keystore`). Editor Settings > Export > Android must point to the SDK, the JDK and the keystore
   (they already did: `export/android/android_sdk_path`, `java_sdk_path`, `debug_keystore`).
5. On the phone: **Developer options > USB debugging** on, and the "Allow USB debugging?" prompt accepted
   (the phone shows `unauthorized` in `adb devices` until you do).

NOT prepared (not needed for sideloading a test build): a release keystore, release signing, Gradle build, Android App Bundle (.aab) for Google Play.
Google Play needs an AAB, i.e. a Gradle build and a release keystore. That is future work.

## 3. Exporting

Project root: `D:\photos\gamic\THE WORTHY ONE`. The preset is `export_presets.cfg` ("Android").

Command line (verified):
```
"D:\Godot\editor\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe" ^
  --headless --path . --export-debug "Android" build/android/TheWorthyOne-debug.apk
```
Output: `build/android/TheWorthyOne-debug.apk` (about 28 MB, signed with the debug key). Godot prints
`ERROR: EditorSettings not instantiated yet ... shutdown_adb_on_exit` at the end in headless mode; the APK is still produced and signed. It is harmless engine noise.
In the editor: Project > Export > Android > Export Project (turn "Export With Debug" on).

## 4. Installing and running on a phone (all verified on the test phone)

`adb` lives in `C:\Users\user\AppData\Local\Android\Sdk\platform-tools\adb.exe`.
```
adb devices -l                                   # must say "device", not "unauthorized"
adb install -r build/android/TheWorthyOne-debug.apk
adb shell am start -n com.theworthyone.game/com.godot.game.GodotAppLauncher
adb exec-out screencap -p > shot.png             # screenshot from the phone
adb shell input tap 188 1445                     # an OS-level touch (left tap panel on a 720x1600 screen)
adb shell am force-stop com.theworthyone.game
```
The launchable component is `GodotAppLauncher`; the underlying `GodotApp` activity is not exported, so launching it by name fails with a SecurityException.
Note: `adb shell input tap` is an injected touch. It runs through Android's real input system, but it is not a human finger.

## 5. Difficulty presets for playtesting

Presets live in `resources/difficulty/presets/` (see `docs/PLAYTEST_PRESETS.md` for what each one changes).
Select one by passing `--difficulty-preset=<name>`:
- Android: Project > Export > Android > **Command Line > Extra Args** = `--difficulty-preset=forgiving`, then re-export (verified on the phone).
- Desktop: `godot --path . -- --difficulty-preset=forgiving`.
A non-default preset shows a small "PLAYTEST PRESET - NAME" label under the timers so testers can tell which build they are running.
Do not rely on `print()` or logcat to see it: `print()` output did not appear in `adb logcat` on the test phone.

## 6. Known risks / things to check on each new device

- **Vulkan is required** (the manifest declares `android.hardware.vulkan.*`). Phones without Vulkan 1.0 cannot install it. Falling back to the
  Compatibility (OpenGL) renderer is possible but has not been tried; shaders and shadows may need changes.
- **Performance (Milestones 1.4-1.5):** the Android default is the `balanced` render quality: 3D scale 0.6 with FSR 1.0 upscaling, 4x anisotropic filtering, 1024 shadow map (about 58 FPS on the test phone instead of about 20). Change it with `--quality=<original|balanced|low>` / `--rq=key=value`; in debug builds also via `user://launch_args.txt`. See `MILESTONE_1_4_REPORT.md` and `MILESTONE_1_5_REPORT.md`.
- **Back button:** `application/config/quit_on_go_back=false`; Back opens the pause menu (RESUME / QUIT). QUIT leaves the app until a main menu exists.
- **Cold start** is about 3.7 s (interactive) on repeat launches on the test phone (meshes and noise textures are pre-baked in `assets/baked/`; re-run `tools/bake_assets.tscn` after changing procedural parameters). The first launch after an install can be much slower.
- The mono export template adds the .NET runtime to the APK and logs `Unable to load System.Security.Cryptography.Native.Android library`; harmless (the project has no C#).
- `aapt2` reports a missing `themed_icon.xml` warning for the template's monochrome icon; harmless.
- The launcher icon is a placeholder SVG.
- Battery/thermals were not measured. Only one device (Android 13, 720x1600, 60 Hz) has been used.
