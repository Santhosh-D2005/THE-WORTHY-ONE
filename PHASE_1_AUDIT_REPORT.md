# THE WORTHY ONE – Phase 1: Project Audit (Endless / Ruthless / Online Hall of Fame)

Read-only phase: **no game code was changed**. Based on the files in the project and a few web searches (sources at the end; third-party pricing pages disagree and must be re-checked on the providers' own sites).

## 1. Architecture as it exists

| Area | What is really there |
|---|---|
| Scenes | `main_menu.tscn` (main scene, UI built in code), `main.tscn` (the game), `failure_screen.tscn`. Only 3 scenes; all UI is code-built (`UiStyle` shared styling, `SafeArea`). |
| Autoloads | `GameManager` (state machine, level counter) and `PerfProbe` (debug). |
| States | READY, PLAYING, EXTRACTING, PAUSED, FAILED. `begin_failure()` is the single failure gate (once per run). |
| Level loop | `LevelManager` (308 lines) runs it: `GameManager.reset_run()` on `_ready`, `_on_extraction_completed` -> `extraction_succeeded(level, seconds)` -> `advance_level()` -> `_start_level_sequence`. **No maximum level exists in code.** |
| Difficulty | `DifficultyManager` + `DifficultyConfig` (`default_difficulty.tres`, presets forgiving/demanding/...). Levels converge to constants (exponential saturation), they never become exactly flat. Config is a Resource, so a second config for Ruthless is possible. **Not yet verified:** how `DifficultyManager` selects the config (needs a look in Phase 2). |
| Run data | `RunResult` holds the **failed** level (`level_reached`), `extractions`, times. "Highest completed level" is `level_reached - 1` (= `run_extractions`). Per-level extraction time is available from `extraction_succeeded(level, seconds)`. |
| Persistence | **None.** No save file, no personal best, no settings. `RunResult` and `GameManager` comments say a save system does not exist yet. |
| Lifecycle | `LevelManager._notification`: `APPLICATION_FOCUS_OUT`, `APPLICATION_PAUSED`, `WM_WINDOW_FOCUS_OUT` all call `_pause()`. Back opens the pause menu. Godot on Android does **not** report the notification shade, so that case neither pauses nor will it invalidate a Ruthless run (known from Milestone 1.21). |
| Menu | PLAY and QUIT only (`main_menu.gd`, signals `play_pressed`, `quit_pressed`). |
| Export | Gradle build **off**; APK only; arm64; min/target SDK left default; **no permissions at all (no INTERNET)**; no release keystore; version 0.1.9 / code 7. |
| Tests | 16 headless scenes + `run_tests.gd` (desktop, dummy audio, injected events). Real-device tests so far are screenshot-and-ADB-tap based. |
| Env | Godot 4.7.2 mono, Java 24 (found), debug keystore `~/.android/debug.keystore`. |

## 2. Findings that shape the design

1. **Highest completed level** must be computed from successes, never from `level_reached`, or a failed level would be credited.
2. **Ruthless needs a different lifecycle rule than the existing one.** Today focus loss = pause; in Ruthless it must = invalidate. Ordinary transitions (level card, entrance, failure animation, scene change, the in-app pause menu opened by Back) must not invalidate. The pause menu in Ruthless needs a policy (see section 5) because it lets a player stall indefinitely.
3. **Process kill:** no callback is guaranteed. Design: write `run_active=true` to disk when a Ruthless run starts and only set it false on a clean finish; on next launch, a run still marked active is closed as "abandoned" and never resumable. Server side: the run token expires and cannot be submitted after an invalidation.
4. **The notification shade will not invalidate a Ruthless run** (platform limit). Documented as a known gap; a server-side time plausibility check is the only mitigation.
5. **Nothing in the game can currently reach the internet**: needs the INTERNET permission and a networking layer.
6. **Google sign-in on Android needs a Gradle-based export** (plugin AARs). That is a large change to the build pipeline (Android build template, JDK/Gradle versions) and must be tested separately, because it can change APK size, signing and start-up.
7. **Google OAuth needs the APK signing SHA-1** to be registered. Debug builds currently use two different keys (Godot's debug key and `~/.android/debug.keystore`), and there is no release key. Sign-in will fail ("cancelled immediately") until a stable key's SHA-1 is registered.
8. **Performance is unresolved** (about 45 FPS, 309-315 MB, about 42 C). Every new screen and the Gradle build must be measured against that, not assumed free.

## 3. Backend comparison (recommendation needed before Phase 4)

Requirements: guest auth, Google linking onto the same account, two leaderboards, server-side validation, no admin secrets in the client, Godot-friendly, affordable.

| | Supabase (hosted Postgres + Auth + Edge Functions) | Nakama (self-hosted or Heroic Cloud) | Talo |
|---|---|---|---|
| Guest auth | Anonymous sign-ins (from my knowledge; **verify in its docs**) | Device-ID auth built in | Player aliases/identifiers |
| Google linking to the same account | Possible; I would do it with **my own Edge Function** that verifies the Google ID token and attaches it to the existing user, with a conflict response | Built in (link Google to the current account) | **Not found** in anything I read; would fail this requirement unless confirmed |
| Leaderboards | Not built in: two tables + SQL ranking (`rank()` with tie-break on time), full control | Built-in, rank by score with subscore (fits the tie-break) | Built in |
| Server-side validation | Edge Functions / SQL (TypeScript/SQL, full control) | Server runtime (Go/Lua/TS) | Limited |
| Godot client | Plain HTTPS from `HTTPRequest` (no SDK needed) | Official Godot 4 client | Godot plugin |
| Cost (to re-check) | Free tier reported as 50,000 MAU, 500 MB DB, 5 GB egress, **projects pause after a week of inactivity**; Pro about $25/month | Server is free/open source, but **someone must host it** (a VPS, ongoing admin); Heroic Cloud reported at about $600/month or "contact us" | Free hosted tier reported under 10,000 players, inactive accounts may be deleted; paid prices not found |
| Scalability | Good; a paid plan removes pausing | Best fit for games, highest ops burden | Smaller platform |

**Recommendation: Supabase**, with all ranking and validation in SQL/Edge Functions, and Google verification done server-side by my own endpoint. Reasons: it meets every requirement (including honest account linking with conflict handling), needs no server for you to run, has a real free tier to start, and the client is just HTTPS. Risks to prototype first: (a) free projects pause after inactivity, so a real launch needs the paid plan; (b) I have not read Supabase's anonymous-auth docs in this session, so I will verify before committing; (c) the leaderboard ranking and anti-cheat logic are ours to write and test, not a built-in feature.
**Runner-up: Nakama** if you are willing to run a server (or pay for Heroic Cloud): best native fit, but the most operating work. **Talo is not recommended** unless it is shown to support verified Google linking.

## 4. Anti-cheat: what is and is not possible (design preview)

Protectable: server-issued run ID, level-sequence check (levels must be submitted 1, 2, 3 ... in order, each against the run's token), no duplicate submissions (unique run/level), mode bound to the run, a Ruthless run ended by invalidation can never be accepted, per-level time plausibility using the real difficulty maths (`DifficultyConfig.simulate_extraction_seconds` gives a physical floor per level), rate limits, ranking computed only by the server.
Not protectable: the game runs on the player's device and taps are not replayable on the server, so a modified client that sends plausible timings, or an automated tapper, cannot be reliably detected. The shade-not-detected gap in Ruthless is also not closable on the client. This will be documented as a limitation, not hidden.

## 5. Decisions and external setup I need before Phase 4

1. **Approve the backend** (Supabase recommended) and create the project; I will need only its **URL and public anon key** (these may live in the client; **never the service-role key**).
2. **Google Cloud:** a project with an OAuth *Web* client ID (verifies the token) and an *Android* client with the package `com.theworthyone.game` and the **SHA-1 of the signing key**. That means deciding which key (a proper release keystore is the right answer; creating it is your decision).
3. **Approve switching the export to Gradle** (needed for Google sign-in), accepting a one-off risk to the build.
4. **Version bump:** this is a large feature set; I will not change 0.1.9/7 without your approval.
5. **Ruthless pause policy:** options: (a) Back/pause menu is allowed and counts as foreground, with the run timer still advancing for server plausibility; (b) Back during Ruthless ends the run. I recommend (a) with a clear notice, but it is your game rule.
6. **Ruthless difficulty:** a separate `DifficultyConfig` resource for Ruthless (I will model it from the existing curves and show you the table first). Endless keeps the current config.
7. **Display-name rules** (length, allowed characters, profanity filter approach, change frequency).

## 6. Proposed plan (unchanged from your phases)

Phase 2: `RunMode` + local `SaveStore` (atomic writes, run-active flag) + Endless/Ruthless rules + lifecycle invalidation + tests. Phase 3: guest account (secure local storage via an encrypted `ConfigFile` keyed per install; limits documented) + first-launch warning. Phases 4-6 need the items in section 5. UI (Phase 7) can be built against a clearly marked "offline / not configured" state without faking data.

Phases 2 and 3 need none of the external setup, so I can proceed with them as soon as you approve.

## Sources (third party; verify on the providers' own pages)
- Supabase pricing summaries: https://www.jetadmin.io/blog/supabase-pricing-2026-guide-to-plans-limits-and-real-world-costs/ , https://automationatlas.io/answers/supabase-free-tier-limits-2026/
- Heroic Cloud pricing: https://heroiclabs.com/pricing
- Talo: https://github.com/TaloDev/backend
- Godot Google sign-in plugins: https://godotengine.org/asset-library/asset/4578 , https://github.com/eskandrej/one-tap-android-godot
