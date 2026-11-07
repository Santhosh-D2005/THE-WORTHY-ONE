# THE WORTHY ONE - physical phone test checklist

Build to test: `build/android/TheWorthyOne-release.apk` (signed with the release key). Tick each box. Write what you saw next to anything that fails.

## 0. Install
- [ ] Uninstall any older version of the game first (an older debug build uses a different signing key and blocks the install).
- [ ] Copy the APK to the phone, allow "install unknown apps" for the app you opened it with, and install.
- [ ] The launcher shows the name "THE WORTHY ONE" and the new violet-and-gold icon (sword in a glowing stump), cropped well in a circle and in a squircle.
- [ ] On Android 13 or newer with themed icons on, the icon shows as a single-colour sword and stump.
- [ ] The game opens in portrait and stays in portrait when you turn the phone.

## 1. First launch and account
- [ ] A fresh install asks you to log in, create an account, or play offline.
- [ ] Create an account with a username that is already taken (try a famous name or one you already made): it says "That username is already taken." and does not accept it.
- [ ] Bad usernames are refused with a clear message: 2 letters, starts with a number, has a space or symbol, a reserved word like "admin".
- [ ] Bad passwords are refused: under 8 characters, the same as the username, an obvious one like "password123".
- [ ] A new unique username with a good password creates the account and logs you in. The Account screen shows your name and "LOGGED IN".
- [ ] Wrong password at login says "Wrong username or password." Five wrong tries in a row lock it for a while.
- [ ] Log out, then log in again: it works and your progress is still there.
- [ ] Reinstall test: note your best level, uninstall the game, install again, log in. Your best level and Hall of Fame place come back.

## 2. Playing
- [ ] PLAY starts a run. Tapping the left and right halves of the screen alternately pulls the sword. Fast, steady taps feel responsive, with no missed taps.
- [ ] Tapping the same side twice, or too slowly, does not progress the bar.
- [ ] Level 1 is winnable; levels 2 to 5 feel clearly harder but fair (note any level that feels unfair).
- [ ] Failing a run shows the failure screen, with TRY AGAIN and MAIN MENU working.
- [ ] Pause with the Android Back button: the pause menu appears. RESUME continues exactly where you were. MAIN MENU asks for confirmation when needed.
- [ ] MODES: Endless and Ruthless both start. In Ruthless, leaving the app (Home button or switching apps) ends the run.
- [ ] Switch to another app mid-run in Endless and come back: the game is paused, not broken.
- [ ] Take a phone call or pull the notification bar during a run: nothing crashes. (Pulling the notification bar does not pause the game; that is a known limit.)

## 3. Hall of Fame
- [ ] Online: HALL OF FAME shows rankings with rank, name, level and time. ENDLESS and RUTHLESS tabs both work, PREV/NEXT page through, REFRESH works.
- [ ] Your own row is highlighted and "YOUR PLACE" shows at the bottom.
- [ ] Finish a level while online, then open the Hall of Fame (REFRESH): your result appears or improves.
- [ ] Airplane mode on: the Hall of Fame shows "You are offline" and your own best on this device, marked as this device only.
- [ ] Play a run in airplane mode: it works and counts for your local best. (Offline runs are never sent to the online board.) Turn the connection back on: the next online run submits normally.

## 4. Settings
- [ ] SETTINGS button (top right of the main menu, and in the pause menu) opens the panel.
- [ ] SOUND - and + change the level in 10% steps and you hear the whole game get quieter or louder, including the forest ambience. At 0% everything is silent.
- [ ] SFX - and + change only the effects (taps, bell, blade); the ambience stays the same. SFX at 0% silences the effects only.
- [ ] QUALITY cycles AUTO, HIGH, BALANCED, LOW. After changing it, start a new run: the picture changes. LOW looks softer.
- [ ] FRAME RATE cycles UNLIMITED, 60, 30. Check the game still plays well at 30.
- [ ] Close the game fully and reopen it: your settings were kept.
- [ ] RESET TO DEFAULTS puts everything back.
- [ ] CREDITS shows the credits page, and BACK TO SETTINGS and the Back button return to the settings.

## 5. Delete account
- [ ] ACCOUNT, then DELETE ACCOUNT shows a warning and a password box.
- [ ] CANCEL goes back and nothing is deleted.
- [ ] DELETE FOREVER with no password asks for the password. With a wrong password it refuses and the account stays.
- [ ] With the right password the account is deleted and the screen shows "NOT LOGGED IN".
- [ ] Logging in with the deleted username and password no longer works. The username can be registered again.
- [ ] After deleting, the Hall of Fame no longer lists that name.

## 6. Screen, sound and comfort
- [ ] Nothing is hidden by the camera cut-out or the gesture bar. Every button is easy to tap with a thumb (PLAY, QUIT, the bottom tap areas).
- [ ] Text is readable at your usual brightness. The title and sword look right.
- [ ] Sound: the forest ambience is quiet and pleasant, the taps do not annoy after 5 minutes, and there is no crackle or silence glitch (an earlier build crashed the audio, so listen for a crash after 20 seconds).
- [ ] Play for 10 minutes: note how warm the phone gets and how much battery it used. Note any stutter. Repeat once with QUALITY set to LOW.
- [ ] Open the game three times in a row from cold start: it always reaches the menu quickly with no black screen.

## 7. Result
- [ ] Note the phone model and Android version here: ____________________
- [ ] Crashes or freezes (when, what you were doing): ____________________
- [ ] Anything that felt too hard, too easy, or confusing: ____________________
