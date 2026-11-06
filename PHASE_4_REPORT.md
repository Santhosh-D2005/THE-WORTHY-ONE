# THE WORTHY ONE – Phase 4: Backend (server rules + game connection layer)

Version stays 0.1.9 (code 7). **Desktop tests plus one real round trip to the live Supabase project from desktop Godot. No phone test and no new APK in this phase.**

## What was built

**Server (Supabase / PostgreSQL), `server/schema.sql`, applied to your project (you confirmed the query succeeded)**
Tables with row-level security and no write policy, and functions for registration, rename, run start, level submission, run end, leaderboards and (service-only) Google linking. Full description: `docs/BACKEND_API.md`.
- Server-issued run ids; levels accepted only in order, once; time must be above a physical floor computed from the game's own difficulty curves and not longer than the real time since the previous event; Ruthless runs expire if more than 60 s pass beyond the level's own time; invalidated, failed, expired or closed runs accept nothing.
- Ranking is computed only on the server (level, then faster time, ties share a rank); Endless and Ruthless are separate; own rank is returned even off the first page; banned players are excluded.

**Game (Godot)**
- `Backend` autoload (`scripts/core/backend.gd`): anonymous guest sign-in, token refresh with rotated-credential saving, player registration, one `call_server()` entry point, leaderboard call, clear error codes. It **never creates a replacement account** if the stored credential is rejected (reports `session_lost`).
- `HttpTransport` (the only code that touches the network), `BackendConfig` (public URL and publishable key only).
- `RunSync` autoload: reports runs to the server through a queue saved in the save file; retries network failures (5 s growing to 60 s); drops runs the server refuses; offline-started runs stay local and are never submitted; Ruthless invalidation is reported after the levels already completed. Headless runs disable it so tests never reach the server.
- `Account` now stores the server user id and the credential (encrypted) and adopts the server's player id and name.

## Tests

| Suite | Result | What it is |
|---|---|---|
| `server/test_schema.mjs` | 89 checks, 0 failed (rerun in the background at the time of writing; see end) | the real SQL on **PostgreSQL 18 (PGlite)**; only Supabase's `auth` schema and roles are stubbed |
| `tests/backend_tests.gd` | 47 checks, 0 failed | the game's client logic against a **scripted fake network** (proves behaviour for each answer, not Supabase) |
| `tests/account_tests.gd` | 93 checks, 0 failed | includes name rules agreeing with the server on 30 shared names |
| Regression (startup, menu, audio, ui, layout, pause, failure, timer, rhythm, speed, integration, progression, experience, modes) | all 0 failed | desktop headless |

**Live round trip (manual, `tools/live_smoke.gd`, real HTTP from Godot to your project):** guest sign-in worked (anonymous sign-ins are on), registration worked and the game adopted the server's player id and name, `get_account` matched, both leaderboards answered (empty), a player calling the service-only link function got 403, a reserved name was refused. Earlier curl checks showed a call with no session gets 401, and a direct table write gets 403. **No level was ever submitted to the live project**, so its leaderboards are still empty.

## Things you should know

- **Test guests exist in your project:** about three anonymous test players (named like "Forest Wanderer", "Unknown Swordbearer #5609") with no scores. They are harmless; delete them in Authentication -> Users if you want a clean list.
- **Not tested live:** submitting levels and end_run against the real project (I deliberately did not put fake scores on your Hall of Fame). The server logic for those is proven on PostgreSQL 18, and the client logic on the fake network. First real submissions will come from your phone test.
- **Free-tier note:** a free Supabase project pauses after about a week of inactivity; a public launch needs the paid plan or a keep-alive.
- **Limits (also in the API doc):** the server cannot tell a modified client or an automated tapper that sends plausible times from a human; Ruthless invalidation is client-reported and Godot cannot see the notification shade; the 60 s Ruthless gap rule bounds that. A Ruthless level report that arrives more than about a minute late (a long outage) expires the run and is not credited.
- The player's provisional local id is replaced by the server's id on first registration (the leaderboard identity is the server's).
- Nothing in the UI uses any of this yet (no leaderboard screen, no account screen, no submission status on the result screen): that is Phase 7.

## Still to do (not started)

Phase 5 Google linking (needs the Google Cloud clients, signing-key SHA-1 and Gradle export, plus an Edge Function that verifies the Google token and calls `link_google_identity`), Phase 6/7 leaderboard, account, mode-selection and result screens, Phase 8 physical-device tests (Ruthless lifecycle, safe areas, Back, performance and memory), Phase 9 APK.
