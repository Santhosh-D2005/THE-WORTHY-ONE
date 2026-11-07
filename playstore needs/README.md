# THE WORTHY ONE - Google Play upload kit

| Item | Value |
|---|---|
| App name | THE WORTHY ONE |
| Package name (application ID) | `com.theworthyone.game` (permanent once uploaded) |
| Version name / code | 0.2.0 / 8 (raise the code by 1 for every new upload) |
| Upload file | `aab/TheWorthyOne-0.2.0.aab` (Android App Bundle, signed with your release key, alias `worthyone`) |
| Target | Android phones, portrait, arm64 |
| Category | Games > Arcade (suggested) |
| Permissions | Internet, Vibrate |
| Ads / in-app purchases | None |
| Signing key | `C:\Users\user\.worthyone_keys\release.keystore` (+ release.env). BACK THIS UP. Never commit it. |

## What is in this folder
- `aab/` - the file you upload in Play Console > Release > Testing/Production.
- `app icon/app-icon-512x512.png` - the 512x512 store icon.
- `feature-graphic-1024x500.png` - the feature graphic (required).
- `screenshots/` - 9 phone screenshots (1080x1920): menu, gameplay, pause, level complete, failure, and 3 of LEVEL 9999. Play needs 2-8 per device type; choose up to 8 (the three level 9999 images are 07-09).
- `PRIVACY_POLICY.md` / `PRIVACY_POLICY.html` - the policy. Host the HTML at a public URL (e.g. GitHub Pages) and paste that URL into Play Console > App content > Privacy policy. The contact email (mrcarkstudios@gmail.com) is already filled in.

## Suggested store text
Short description (80 chars): `Tap fast, pull the sword from the stump. How far can you climb?`

Full description: One sword. One tree. One challenge. Alternate your taps left and right to pull the sword from the stump, level after level, each one harder. Play Endless or the unforgiving Ruthless mode, climb the online Hall of Fame with a username and password, or play fully offline. No ads.

## Play Console answers (from what the game does)
- Data safety: collects username, password (hashed), game results (level/time). Shared with: nobody (stored on your Supabase server). Encrypted in transit: yes. Users can request deletion: yes (in-game Account > Delete account, and by email).
- Ads: no. Target audience: 13+ (not for children). Account deletion: in-game as above; put the same text and your email in the Data deletion form.
- Content rating: no violence beyond a sword being pulled from wood, no gambling, no user-to-user chat.

## Before you press publish
1. Host the privacy policy HTML at a public URL.
2. Run `server/migration_floor_update.sql` in the Supabase SQL Editor (keeps anti-cheat in line with the game).
3. New personal developer accounts must run a closed test (about 12 testers, 14 days) before production; check your Console.
