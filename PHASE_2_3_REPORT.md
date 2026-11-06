# THE WORTHY ONE – Phases 2 and 3: Game Modes, Local Progress, Guest Account

Version stays 0.1.9 (code 7), package `com.theworthyone.game`. **Desktop (Godot headless) results only. No phone test, no new APK in these phases.** Online features (Phases 4-6) are not started: they need external accounts (see section 6).

## Phase 2 – Endless and Ruthless (implemented, desktop-tested)

**What exists now**
- `GameMode` (Endless / Ruthless), `SaveStore` (local JSON save, written through a temp file and a backup, loaded defensively), and the `Progress` autoload (records, run lifecycle, Ruthless rules).
- **Endless:** the existing difficulty config, no maximum level (1,500 levels tested), failed run keeps the best, best saved the moment each level is completed (a kill cannot lose it), same-level tie broken by faster time, levels accepted only in order, duplicates ignored.
- **Ruthless:** its own harder difficulty resource `resources/difficulty/ruthless_difficulty.tres` (level 10 at 6 taps/s: 10.3 s vs 7.8 s Endless; 20 s vs 11.7 s from level 50). Both curves flatten at high levels (existing exponential design), so "ever harder" is true for roughly the first 30 levels, then constant. Not changed, only reported.
- **Ruthless lifecycle:** focus-out / application-paused / window-focus-out (Home, app switch, screen lock) invalidates the run at once, **writes the invalidation to disk first**, ends the game in a non-paused ended state, and shows "RUN ENDED / YOU LEFT THE FOREST / NEW ATTEMPT". The run cannot be resumed (`can_resume_ruthless_run()` is always false; there is no state to resume).
- **Kill / terminate:** the run is marked `active` on disk when it starts. If the next launch finds it still active, it is closed as *abandoned*; nothing is resumable; completed levels stay recorded.
- **Not invalidated:** level transitions, the entrance, the level card, the in-app pause menu opened with Back (a policy I chose; see section 6), a normal failure.
- Failure screen now carries `mode` and `completed_level` in the run result (the failed level is never counted: highest completed = level reached - 1).
- Files: `scripts/progression/{game_mode,save_store}.gd`, `scripts/core/progress.gd`, `resources/difficulty/ruthless_difficulty.tres`; modified `level_manager.gd`, `failure_screen.gd`, `run_result.gd`, `project.godot` (autoloads).

**Tests:** `tests/modes_tests.gd`, **70 checks, 0 failed** (save file incl. damage/backup/type junk; Endless rules; Ruthless rules; relaunch after a simulated kill; the real game scene in both modes with simulated taps and lifecycle notifications).

## Phase 3 – Guest account and first-launch warning (implemented, desktop-tested)

- `Account` autoload: on first launch creates a guest **locally** (no internet): version-4 UUID player id, 256-bit secret, valid default name such as "Forest Wanderer #4821". Players are never asked for an email.
- Storage: encrypted file in the app's private storage (`AccountStore`); Android auto-backup is already off in the export. **Honest limit:** not Android Keystore (that needs a native plugin); the key derives from the device id, so it blocks casual reading and copying, not a rooted device. Lost or unreadable credentials cannot be recovered: a new guest is created (tested), exactly what the notice says.
- Names: `NameRules` (3-26 chars; letters incl. Latin accents and Indian scripts, digits, space `_ - . ' #`; at least two letters; reserved staff-like words and a small block list, also against look-alike digits; one change per 24 h after the first). A word list is a first filter only; the server must repeat it and needs a report mechanism.
- Uniqueness: random ids are unique in practice (300 of 300 in test); default names are random with a 4-digit suffix (about 290 of 300 distinct in test), so **name uniqueness is only guaranteed once the server enforces it** (Phase 4).
- **First-launch notice** (`GuestNotice`, in the game's existing visual style): exact requested copy, two steps (I UNDERSTAND unlocks CONTINUE AS GUEST), cannot be skipped (Back does nothing), blocks the menu behind it, shown once; the same text opens later with a CLOSE button. I added one accurate sentence: the online record is kept after an uninstall, but without credentials the player cannot control it (no false promise that it disappears).
- Files: `scripts/accounts/{name_rules,account_store}.gd`, `scripts/core/account.gd`, `scripts/ui/guest_notice.gd`; modified `main_menu.gd`, `project.godot`.

**Tests:** `tests/account_tests.gd`, **91 checks, 0 failed** (names; guest creation, unique ids, encrypted file not readable text, restart, rename + cooldown, secret never in the public profile, wrong key cannot open the file; the notice on the real menu incl. layout at 4 screen shapes).

**One existing test edited:** `menu_tests` counted every Button node, which now includes the notice's hidden buttons; it counts visible ones (same intent: no stray visible buttons). Headless runs auto-acknowledge the notice (unless started with `--fresh-account`) so the older suites are not blocked; `account_tests` covers the notice itself.

## Regression (desktop, after both phases)

startup 16/0, menu 55/0, audio 50/0, ui 106/0, layout 256/0, pause 42/0, failure 117/0, timer 25/0, rhythm 63/0, speed 50/0, integration 194/0, progression 35/0, difficulty logic all passed, experience 72/0 (this suite was intermittently failing earlier on timing checks; it passed this run, still flaky in principle), plus new modes 70/0 and account 91/0.

## Android / device status

**Not verified on a phone.** The lifecycle behaviour is tested by sending notifications to the node, which proves the logic, not what a real Android does. Still to confirm on the device: Home, app switching and screen lock really invalidate a Ruthless run, the notice and menu layout, and Back behaviour. Known gap: the notification shade does not reach Godot, so it will not end a Ruthless run.

## Remaining issues / risks

- Online features, leaderboards, Google linking, offline submission queue: **not started**.
- The Account/Progress save files are not tamper-proof; the server must be the authority (Phase 4/6).
- Performance and memory of the new screens: not measured on the phone.
- Account screen (to reopen the notice, rename, show the player id) does not exist yet: Phase 7. Until then a player cannot reopen the notice or rename from the UI.
- Ruthless policy: Back-opened pause menu counts as foreground and does not end the run; the pause menu therefore lets a player stall. Server-side time plausibility will have to cover this.

## What I need next (external)

1. A **Supabase project** (free, open source stack): its **URL and public (anon/publishable) key**. Never the service-role key.
2. For Google: a Google Cloud project with an OAuth **Web** client ID and an **Android** client for `com.theworthyone.game` with the **SHA-1 of the signing key**, plus a decision on a release keystore.
3. Permission to switch the Android export to Gradle (needed for the Google sign-in plugin).

## Next phase

Phase 4: server schema and rules (tables, row-level security, validation and ranking functions) written as SQL and **tested on a real PostgreSQL engine locally** (PGlite, open source, via node, which is installed), then the Godot service layer. I can do that before the credentials arrive; connecting to the live project, real Google sign-in and the phone test need the items above.
