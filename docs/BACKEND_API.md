# THE WORTHY ONE: backend schema and API (Supabase / PostgreSQL)

Project: `https://cobpxlanflhzqyjnyoti.supabase.co`. The game holds only the **public (publishable) key**. The service-role key must never be in the game, in this repository, or in a chat.

Source of truth: `server/schema.sql`. Tested on PostgreSQL 18 (PGlite) by `server/test_schema.mjs` (89 checks). Apply once: Supabase dashboard -> SQL Editor -> New query -> paste `server/schema.sql` -> Run (safe to run again).

## Authentication
- Guests use Supabase **anonymous sign-in** (dashboard: Authentication -> Sign In / Providers -> *Allow anonymous sign-ins*). The user id (`auth.uid()`) is the player id. Anonymous users have the `authenticated` role.
- Google linking (Phase 5) is done by an Edge Function using the service role after it verifies the Google ID token; it calls `link_google_identity`.
- All calls are HTTPS `POST {url}/rest/v1/rpc/<function>` with headers `apikey: <publishable key>` and `Authorization: Bearer <player access token>`, JSON body of named arguments.

## Tables (RLS on, no write policy: the app cannot write tables)
| Table | Purpose | Player can read |
|---|---|---|
| `players` | id (= auth user), unique case-insensitive `display_name`, `name_changed_at`, `banned`, `google_linked_at` | own row |
| `google_identities` | `google_sub` (PK) -> `player_id` (unique): one Google identity per player and vice versa | no |
| `runs` | server-issued run: `mode`, `status` (active/failed/invalidated/closed/expired), `last_level`, `last_event_at` | own |
| `run_levels` | accepted levels: `(run_id, level)` unique, `seconds`, `submitted_at` | no |
| `records` | best per player per mode: `best_level`, `best_seconds`, `achieved_at` | own |
| `flags` | rejected/suspicious submissions for review | no |

## Functions (all return JSON `{ok: true, ...}` or `{ok: false, error: "<code>"}`)
| Function | Caller | What it does |
|---|---|---|
| `register_player(p_name)` | player | Creates the player row (idempotent). A taken name gets a ` #1234` suffix; an invalid name falls back to a default. |
| `set_display_name(p_name)` | player | Validates (3-26 chars, rules below), unique, one change per 24 h after the first. Errors: `too_short too_long bad_character no_letters reserved not_allowed name_taken cooldown(wait_seconds) banned` |
| `get_account()` | player | Own profile and own records. Never includes secrets or other players. |
| `start_run(p_mode)` | player | `endless` / `ruthless`. Issues the run id, closes any previous live run, max 40 runs/hour (`rate_limited`). |
| `submit_level(p_run, p_level, p_seconds)` | player | See validation below. |
| `end_run(p_run, p_reason)` | player | `failed`, `left`, `invalidated`. Idempotent. `invalidated` marks a **Ruthless** run invalid (an Endless run is just closed). |
| `leaderboard_page(p_mode, p_limit, p_offset)` | player | `{entries:[{rank,name,level,seconds,achieved_at,is_me}], total, me:{rank,level,seconds,achieved_at}\|null}`. Limit clamped 1-100. `me` is returned even when the player is not on the page. |
| `name_error(p_name)` | player | The name check alone (null = fine). |
| `link_google_identity(p_player, p_sub)` | **service role only** | Adds a Google identity to an EXISTING player: `linked`, `already_linked`, or error `google_in_use` / `player_has_google` / `no_player` / `bad_identity`. Never creates a player, never changes records. |
| `player_for_google(p_sub)` | **service role only** | The player id owning a Google identity (new-device recovery). |
| `expire_stale_runs()` | **service role only** | Expires runs idle for a day (schedule it). |

## Ranking
`rank = 1 + number of players with a higher level, or the same level in a faster time`. Equal level and time share a rank; display order inside a tie is by earliest achievement. Endless and Ruthless are separate record rows and separate boards. Banned players are excluded and ranks close up. The client never sends a rank.

## `submit_level` validation (anti-cheat)
1. The run exists, belongs to the caller, and is `active` (an invalidated, failed, expired or closed run accepts nothing, whenever it reconnects).
2. `level == last_level + 1`: levels in order, once each.
3. `0 < seconds <= 3600`.
4. **Physical floor:** `seconds >= 0.85 x min_level_seconds(mode, level)`, the time of a perfect 130 ms tapper under that mode's difficulty (the SQL mirrors the game's own curves; the tests compare it with `DifficultyConfig` for 16 sample levels).
5. **Server clock:** `seconds <= (now - last_event_at) + 2 s`: a level cannot have taken longer than the real time since the run started or the previous level was accepted.
6. **Ruthless only:** `(now - last_event_at) <= seconds + 60 s`, otherwise the run is `expired`. This bounds how long a player can be away without reporting it.
7. Rejections are stored in `flags` for review.

## What is and is not protected (be realistic)
Protected: a player cannot write tables, cannot submit for someone else's run, cannot skip or repeat levels, cannot claim impossible times or times longer than the wall clock allows, cannot revive an ended or invalidated Ruthless run, cannot choose their rank, and cannot see other players' private data.
Not protected: the game runs on the player's phone. A modified client or an automated tapper that sends plausible times (above the floor, real time elapsed) cannot be told apart from a human. Ruthless invalidation is reported by the client; the 60 s gap rule limits but does not remove abuse, and Godot cannot see the Android notification shade. The server-side floor and clock make cheating cost real time, not impossible. Add moderation (the `flags` table, `banned`) before a public launch.

## Name rules (same fixtures in the game and the server tests)
3-26 characters after trimming and collapsing spaces; letters (Latin with accents, Devanagari, Bengali, Tamil, Telugu, Kannada, Malayalam), digits, space and `_ - . ' #`; at least two letters; reserved staff-like words and a small block list (also against look-alike digits). A word list is a first filter only.

## Not built yet
Google token verification Edge Function (Phase 5), the game's HTTP client and offline queue (rest of Phase 4/6), leaderboard screens (Phase 7).
