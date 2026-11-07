-- =====================================================================================================================
-- THE WORTHY ONE - server schema v2: username + password accounts (PostgreSQL / Supabase)
-- Fresh-install version. To move an EXISTING project from v1 to v2 use server/migration_v1_to_v2.sql instead (read its warning first).
--
-- DESIGN
--  * A player is an ACCOUNT (username + bcrypt password hash). Supabase gives every app install an anonymous session; logging in BINDS that
--    session to the account (table `sessions`). Reinstalling and logging in binds the new session to the same account: same records.
--  * The password is never stored in the app and never returned by any function. Only bcrypt hashes live in the database, in a table
--    that no client role can read. Wrong-password and unknown-username answers are identical (no username probing). Repeated failures
--    lock the username (and the session) for 15 minutes.
--  * There is NO password reset (no email). A forgotten password cannot be recovered; the game says so at sign-up.
--  * The game never writes tables. Every change goes through the functions below, which act as the account bound to the caller's session.
--  * Run/session ids are issued by the server; levels are validated for order, time floor (from the game's own difficulty maths), the
--    server clock and, for Ruthless, the gap between levels. Rankings are computed only here. Endless and Ruthless never mix.
--  * Accounts idle for 90 days can be released (release_idle_accounts, service role only): the name becomes free again.
-- =====================================================================================================================

-- On Supabase pgcrypto lives in the `extensions` schema.
create extension if not exists pgcrypto with schema extensions;

-- ---- tables ---------------------------------------------------------------------------------------------------

create table if not exists public.players (
  id                  uuid primary key default gen_random_uuid(),
  username            text not null,
  password_hash       text not null,
  created_at          timestamptz not null default now(),
  last_seen_at        timestamptz not null default now(),
  password_changed_at timestamptz,
  banned              boolean not null default false
);
create unique index if not exists players_username_lower_idx on public.players (lower(username));

-- Which account each app session (Supabase anonymous user) is logged in to.
create table if not exists public.sessions (
  auth_uid   uuid primary key references auth.users (id) on delete cascade,
  player_id  uuid not null references public.players (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists sessions_player_idx on public.sessions (player_id);

create table if not exists public.login_attempts (
  id           bigserial primary key,
  username_key text not null,
  auth_uid     uuid,
  success      boolean not null,
  attempted_at timestamptz not null default now()
);
create index if not exists login_attempts_user_idx on public.login_attempts (username_key, attempted_at desc);
create index if not exists login_attempts_auth_idx on public.login_attempts (auth_uid, attempted_at desc);

create table if not exists public.runs (
  id            uuid primary key default gen_random_uuid(),
  player_id     uuid not null references public.players (id) on delete cascade,
  mode          text not null check (mode in ('endless', 'ruthless')),
  status        text not null default 'active' check (status in ('active', 'failed', 'invalidated', 'closed', 'expired', 'completed')),
  started_at    timestamptz not null default now(),
  last_event_at timestamptz not null default now(),
  last_level    int not null default 0,
  ended_at      timestamptz
);
create index if not exists runs_player_idx on public.runs (player_id, started_at desc);

create table if not exists public.run_levels (
  run_id       uuid not null references public.runs (id) on delete cascade,
  level        int not null check (level between 1 and 9999),
  seconds      numeric(9, 3) not null check (seconds > 0),
  submitted_at timestamptz not null default now(),
  primary key (run_id, level)
);

create table if not exists public.records (
  player_id    uuid not null references public.players (id) on delete cascade,
  mode         text not null check (mode in ('endless', 'ruthless')),
  best_level   int not null check (best_level between 1 and 9999),
  best_seconds numeric(9, 3) not null check (best_seconds > 0),
  achieved_at  timestamptz not null default now(),
  run_id       uuid references public.runs (id) on delete set null,
  primary key (player_id, mode)
);
create index if not exists records_rank_idx on public.records (mode, best_level desc, best_seconds asc, achieved_at asc);

create table if not exists public.flags (
  id         bigserial primary key,
  player_id  uuid references public.players (id) on delete cascade,
  run_id     uuid,
  reason     text not null,
  detail     jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- ---- row level security: ON everywhere, NO policies and NO table grants: nothing is readable or writable except through the functions ----

alter table public.players        enable row level security;
alter table public.sessions       enable row level security;
alter table public.login_attempts enable row level security;
alter table public.runs           enable row level security;
alter table public.run_levels     enable row level security;
alter table public.records        enable row level security;
alter table public.flags          enable row level security;

revoke all on public.players, public.sessions, public.login_attempts, public.runs, public.run_levels, public.records, public.flags
  from public, anon, authenticated;

-- ---- username and password rules --------------------------------------------------------------------------------------------

-- A username is the login id: 3-20 characters, a letter first, then letters, digits or underscore. Returns null if fine, else a code.
create or replace function public.username_error(raw text) returns text
language plpgsql immutable set search_path = public as $$
declare
  n text := btrim(coalesce(raw, ''));
  squashed text;
  w text;
begin
  if char_length(n) < 3 then return 'too_short'; end if;
  if char_length(n) > 20 then return 'too_long'; end if;
  if n !~ '^[A-Za-z][A-Za-z0-9_]*$' then
    if n ~ '^[^A-Za-z]' then return 'bad_start'; end if;
    return 'bad_character';
  end if;
  squashed := regexp_replace(translate(lower(n), '013457', 'oieast'), '[^a-z]', '', 'g');
  foreach w in array array['admin', 'moderator', 'support', 'system', 'official', 'staff', 'developer', 'gamemaster'] loop
    if position(w in squashed) > 0 then return 'reserved'; end if;
  end loop;
  foreach w in array array['fuck', 'shit', 'bitch', 'cunt', 'nigg', 'asshole', 'bastard', 'slut', 'whore', 'rape', 'nazi', 'hitler', 'dick', 'pussy', 'cock'] loop
    if position(w in squashed) > 0 then return 'not_allowed'; end if;
  end loop;
  return null;
end $$;

-- 8-72 bytes (bcrypt ignores anything past 72), not the username, not obviously common.
create or replace function public.password_error(pw text, uname text) returns text
language plpgsql immutable set search_path = public as $$
begin
  if pw is null or char_length(pw) < 8 then return 'pw_too_short'; end if;
  if octet_length(pw) > 72 then return 'pw_too_long'; end if;
  if lower(pw) = lower(coalesce(uname, '')) then return 'pw_same_as_username'; end if;
  if lower(pw) = any (array['password', 'password1', 'password123', '12345678', '123456789', '1234567890', 'qwertyui', 'qwerty123', 'iloveyou', 'abcdefgh', 'theworthyone', 'worthyone', '11111111', '00000000']) then
    return 'pw_too_common';
  end if;
  if pw ~ '^(.)\1+$' then return 'pw_too_common'; end if;
  return null;
end $$;

-- ---- the physical floor for a level (from the game's own difficulty curves) -----------------------------------------------
-- Mirrors DifficultyConfig.simulate_extraction_seconds(level, 130): the fastest anyone could extract (a steady 130 ms tapper). The server
-- accepts 85 % of it. If the game's curves change, server/floor_expected.json must be regenerated (the tests compare both).
create or replace function public.min_level_seconds(p_mode text, p_level int) returns numeric
language plpgsql immutable set search_path = public as $$
declare
  sp numeric; ep numeric; pr numeric; sr numeric; er numeric; rr numeric;
  gain numeric; res numeric; progress numeric := 0; seconds numeric := 0;
  lvl numeric := least(greatest(p_level, 1), 100) - 1;      -- difficulty stops rising at level 100
  steady numeric := lvl / 99.0;
begin
  -- Endless and Ruthless share one hardness (resources/difficulty/default_difficulty.tres = ruthless_difficulty.tres), so one set of numbers.
  sp := 5.2; ep := 3.2; pr := 6.0; sr := 0.08; er := 0.6; rr := 6.0;
  -- the same blend as DifficultyConfig._curve: 65 % quick exponential rise + 35 % steady rise to level 100
  gain := sp + (ep - sp) * (0.65 * (1 - exp(-lvl / pr)) + 0.35 * steady);
  res := least(greatest(sr + (er - sr) * (0.65 * (1 - exp(-lvl / rr)) + 0.35 * steady), 0), 0.9);
  for i in 1..3000 loop
    seconds := seconds + 0.130;
    progress := progress + gain * (1 - res * progress / 100);
    if progress >= 100 - 0.0001 then return seconds; end if;
  end loop;
  return seconds;
end $$;

-- ---- helpers ---------------------------------------------------------------------------------------------------------

create or replace function public._fail(p_error text, p_extra jsonb default '{}'::jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object('ok', false, 'error', p_error) || p_extra
$$;

create or replace function public._flag(p_player uuid, p_run uuid, p_reason text, p_detail jsonb) returns void
language sql security definer set search_path = public as $$
  insert into public.flags (player_id, run_id, reason, detail) values (p_player, p_run, p_reason, p_detail)
$$;

-- The account this session is logged in to (null if none). Also refreshes last_seen_at at most once an hour.
create or replace function public._account_id() returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  pid uuid;
begin
  select s.player_id into pid from public.sessions s where s.auth_uid = auth.uid();
  if pid is not null then
    update public.players set last_seen_at = now() where id = pid and last_seen_at < now() - interval '1 hour';
  end if;
  return pid;
end $$;

-- A fixed bcrypt hash of a throwaway string: unknown usernames are checked against it so they cost the same time as real ones.
create or replace function public._dummy_hash() returns text
language sql immutable set search_path = public as $$ select '$2a$10$7EqJtq98hPqEX7fNZaFWoOa9Yv8b7yQe0v3a5h0Qv1m2y7jGqf0Wy'::text $$;

-- ---- accounts -------------------------------------------------------------------------------------------------------

-- Create an account and log this session in to it. Errors: username rules, pw_*, username_taken, already_logged_in, rate_limited.
create or replace function public.register_account(p_username text, p_password text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  uname text := btrim(coalesce(p_username, ''));
  problem text;
  new_id uuid;
begin
  if uid is null then return public._fail('not_authenticated'); end if;
  if exists (select 1 from public.sessions where auth_uid = uid) then return public._fail('already_logged_in'); end if;
  problem := public.username_error(uname);
  if problem is not null then return public._fail(problem); end if;
  problem := public.password_error(p_password, uname);
  if problem is not null then return public._fail(problem); end if;
  if (select count(*) from public.players where created_at > now() - interval '1 hour') >= 300 then
    return public._fail('rate_limited');
  end if;
  begin
    insert into public.players (username, password_hash) values (uname, crypt(p_password, gen_salt('bf', 10))) returning id into new_id;
  exception when unique_violation then
    return public._fail('username_taken');
  end;
  insert into public.sessions (auth_uid, player_id) values (uid, new_id);
  return jsonb_build_object('ok', true, 'player_id', new_id, 'username', uname);
end $$;

-- Log this session in to an existing account. The answer for an unknown username and for a wrong password is the same.
create or replace function public.login(p_username text, p_password text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  key text := lower(btrim(coalesce(p_username, '')));
  acct public.players;
  fails_user int;
  fails_session int;
  oldest timestamptz;
  good boolean;
begin
  if uid is null then return public._fail('not_authenticated'); end if;
  select count(*), min(attempted_at) into fails_user, oldest from public.login_attempts
    where username_key = key and not success and attempted_at > now() - interval '15 minutes';
  select count(*) into fails_session from public.login_attempts
    where auth_uid = uid and not success and attempted_at > now() - interval '15 minutes';
  if fails_user >= 5 or fails_session >= 10 then
    return public._fail('locked', jsonb_build_object('wait_seconds', greatest(ceil(extract(epoch from (coalesce(oldest, now()) + interval '15 minutes' - now()))), 1)));
  end if;
  select * into acct from public.players where lower(username) = key;
  if found then
    good := acct.password_hash = crypt(coalesce(p_password, ''), acct.password_hash);
  else
    perform crypt(coalesce(p_password, ''), public._dummy_hash());
    good := false;
  end if;
  insert into public.login_attempts (username_key, auth_uid, success) values (key, uid, coalesce(good, false));
  if not good then return public._fail('wrong_credentials'); end if;
  if acct.banned then return public._fail('banned'); end if;
  delete from public.login_attempts where username_key = key and not success;
  insert into public.sessions (auth_uid, player_id) values (uid, acct.id)
    on conflict (auth_uid) do update set player_id = excluded.player_id, created_at = now();
  update public.players set last_seen_at = now() where id = acct.id;
  return jsonb_build_object('ok', true, 'player_id', acct.id, 'username', acct.username);
end $$;

create or replace function public.logout() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return public._fail('not_authenticated'); end if;
  delete from public.sessions where auth_uid = auth.uid();
  return jsonb_build_object('ok', true);
end $$;

-- Change the password. Every OTHER session of the account is logged out.
create or replace function public.change_password(p_old text, p_new text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  pid uuid := public._account_id();
  acct public.players;
  problem text;
begin
  if auth.uid() is null then return public._fail('not_authenticated'); end if;
  if pid is null then return public._fail('not_logged_in'); end if;
  select * into acct from public.players where id = pid;
  if (select count(*) from public.login_attempts where username_key = lower(acct.username) and not success and attempted_at > now() - interval '15 minutes') >= 5 then
    return public._fail('locked');
  end if;
  if acct.password_hash <> crypt(coalesce(p_old, ''), acct.password_hash) then
    insert into public.login_attempts (username_key, auth_uid, success) values (lower(acct.username), auth.uid(), false);
    return public._fail('wrong_credentials');
  end if;
  problem := public.password_error(p_new, acct.username);
  if problem is not null then return public._fail(problem); end if;
  update public.players set password_hash = crypt(p_new, gen_salt('bf', 10)), password_changed_at = now() where id = pid;
  delete from public.sessions where player_id = pid and auth_uid <> auth.uid();
  return jsonb_build_object('ok', true);
end $$;

-- Permanently delete the account this session is logged in to: its records, runs, login sessions and flags go with it (the foreign keys
-- cascade), and the username is free again. The password must be typed again (a stolen session alone cannot delete the account).
-- The Supabase anonymous user remains but no longer leads to any account. Errors: not_logged_in, wrong_credentials, locked.
create or replace function public.delete_account(p_password text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  pid uuid := public._account_id();
  acct public.players;
begin
  if auth.uid() is null then return public._fail('not_authenticated'); end if;
  if pid is null then return public._fail('not_logged_in'); end if;
  select * into acct from public.players where id = pid;
  if (select count(*) from public.login_attempts where username_key = lower(acct.username) and not success and attempted_at > now() - interval '15 minutes') >= 5 then
    return public._fail('locked');
  end if;
  if acct.password_hash <> crypt(coalesce(p_password, ''), acct.password_hash) then
    insert into public.login_attempts (username_key, auth_uid, success) values (lower(acct.username), auth.uid(), false);
    return public._fail('wrong_credentials');
  end if;
  delete from public.login_attempts where username_key = lower(acct.username);
  delete from public.players where id = pid;
  return jsonb_build_object('ok', true);
end $$;

-- The account screen: username, creation date and own records. Never includes the hash or anything about other players.
create or replace function public.get_account() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  pid uuid := public._account_id();
  acct public.players;
begin
  if auth.uid() is null then return public._fail('not_authenticated'); end if;
  if pid is null then return public._fail('not_logged_in'); end if;
  select * into acct from public.players where id = pid;
  return jsonb_build_object('ok', true, 'player_id', acct.id, 'username', acct.username, 'created_at', acct.created_at,
    'records', coalesce((select jsonb_object_agg(r.mode, jsonb_build_object('best_level', r.best_level, 'best_seconds', r.best_seconds, 'achieved_at', r.achieved_at))
                         from public.records r where r.player_id = pid), '{}'::jsonb));
end $$;

-- ---- runs and levels (the anti-cheat core) ---------------------------------------------------------------------------------

-- Ruthless: seconds allowed between two submissions beyond the level's own time (animation, level card, READY wait, pause menu).
create or replace function public._ruthless_slack_seconds() returns numeric
language sql immutable set search_path = public as $$ select 60::numeric $$;

create or replace function public.start_run(p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  pid uuid := public._account_id();
  recent int;
  new_run public.runs;
begin
  if auth.uid() is null then return public._fail('not_authenticated'); end if;
  if pid is null then return public._fail('not_logged_in'); end if;
  if p_mode is null or p_mode not in ('endless', 'ruthless') then return public._fail('bad_mode'); end if;
  if exists (select 1 from public.players where id = pid and banned) then return public._fail('banned'); end if;
  select count(*) into recent from public.runs where player_id = pid and started_at > now() - interval '1 hour';
  if recent >= 40 then
    perform public._flag(pid, null, 'run_rate', jsonb_build_object('runs_last_hour', recent));
    return public._fail('rate_limited');
  end if;
  update public.runs set status = 'closed', ended_at = now() where player_id = pid and status = 'active';
  insert into public.runs (player_id, mode) values (pid, p_mode) returning * into new_run;
  return jsonb_build_object('ok', true, 'run_id', new_run.id, 'mode', new_run.mode, 'started_at', new_run.started_at);
end $$;

create or replace function public.submit_level(p_run uuid, p_level int, p_seconds numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  pid uuid := public._account_id();
  r public.runs;
  floor_seconds numeric;
  elapsed numeric;
  rec public.records;
  improved boolean := false;
begin
  if auth.uid() is null then return public._fail('not_authenticated'); end if;
  if pid is null then return public._fail('not_logged_in'); end if;
  select * into r from public.runs where id = p_run and player_id = pid for update;
  if not found then return public._fail('unknown_run'); end if;
  if r.status <> 'active' then return public._fail('run_not_active', jsonb_build_object('status', r.status)); end if;
  if exists (select 1 from public.players where id = pid and banned) then return public._fail('banned'); end if;
  if p_level is null or p_seconds is null or p_seconds <= 0 or p_seconds > 3600 then return public._fail('bad_time'); end if;
  if p_level > 9999 then return public._fail('bad_level'); end if;  -- level 9999 is the last level
  if p_level <> r.last_level + 1 then
    perform public._flag(pid, p_run, 'bad_sequence', jsonb_build_object('expected', r.last_level + 1, 'got', p_level));
    return public._fail('bad_sequence', jsonb_build_object('expected', r.last_level + 1));
  end if;
  floor_seconds := public.min_level_seconds(r.mode, p_level) * 0.85;
  if p_seconds < floor_seconds then
    perform public._flag(pid, p_run, 'implausible_time', jsonb_build_object('level', p_level, 'seconds', p_seconds, 'floor', floor_seconds));
    return public._fail('implausible_time');
  end if;
  elapsed := extract(epoch from (now() - r.last_event_at));
  if p_seconds > elapsed + 2 then
    perform public._flag(pid, p_run, 'time_exceeds_elapsed', jsonb_build_object('level', p_level, 'seconds', p_seconds, 'elapsed', elapsed));
    return public._fail('time_exceeds_elapsed');
  end if;
  if r.mode = 'ruthless' and elapsed > p_seconds + public._ruthless_slack_seconds() then
    update public.runs set status = 'expired', ended_at = now() where id = p_run;
    perform public._flag(pid, p_run, 'ruthless_gap', jsonb_build_object('level', p_level, 'seconds', p_seconds, 'elapsed', elapsed));
    return public._fail('run_expired');
  end if;
  insert into public.run_levels (run_id, level, seconds) values (p_run, p_level, p_seconds);
  update public.runs set last_level = p_level, last_event_at = now() where id = p_run;
  select * into rec from public.records where player_id = pid and mode = r.mode;
  if not found then
    insert into public.records (player_id, mode, best_level, best_seconds, run_id) values (pid, r.mode, p_level, p_seconds, p_run);
    improved := true;
  elsif p_level > rec.best_level or (p_level = rec.best_level and p_seconds < rec.best_seconds) then
    update public.records set best_level = p_level, best_seconds = p_seconds, achieved_at = now(), run_id = p_run
      where player_id = pid and mode = r.mode;
    improved := true;
  end if;
  return jsonb_build_object('ok', true, 'level', p_level, 'new_best', improved);
end $$;

-- reason: 'failed' | 'left' | 'invalidated' | 'completed' (only counts if level 9999 was reached). Idempotent. Ended runs accept nothing more.
create or replace function public.end_run(p_run uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  pid uuid := public._account_id();
  r public.runs;
  new_status text;
begin
  if auth.uid() is null then return public._fail('not_authenticated'); end if;
  if pid is null then return public._fail('not_logged_in'); end if;
  if p_reason is null or p_reason not in ('failed', 'left', 'invalidated', 'completed') then return public._fail('bad_reason'); end if;
  select * into r from public.runs where id = p_run and player_id = pid for update;
  if not found then return public._fail('unknown_run'); end if;
  if r.status <> 'active' then return jsonb_build_object('ok', true, 'status', r.status); end if;
  new_status := case when p_reason = 'failed' then 'failed' when p_reason = 'completed' and r.last_level >= 9999 then 'completed'
                     when p_reason = 'invalidated' and r.mode = 'ruthless' then 'invalidated' else 'closed' end;
  update public.runs set status = new_status, ended_at = now() where id = p_run;
  return jsonb_build_object('ok', true, 'status', new_status);
end $$;

-- ---- leaderboards ------------------------------------------------------------------------------------------------------------
-- Rank = 1 + the number of players with a higher level, or the same level in a faster time. Equal level and time share a rank.

create or replace function public._rank_of(p_mode text, p_level int, p_seconds numeric) returns bigint
language sql stable security definer set search_path = public as $$
  select 1 + count(*) from public.records r join public.players p on p.id = r.player_id
  where r.mode = p_mode and not p.banned and (r.best_level > p_level or (r.best_level = p_level and r.best_seconds < p_seconds))
$$;

create or replace function public.leaderboard_page(p_mode text, p_limit int default 25, p_offset int default 0) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  pid uuid := public._account_id();
  lim int := least(greatest(coalesce(p_limit, 25), 1), 100);
  off int := greatest(coalesce(p_offset, 0), 0);
  entries jsonb;
  total bigint;
  mine public.records;
  me jsonb := null;
begin
  if auth.uid() is null then return public._fail('not_authenticated'); end if;
  if p_mode is null or p_mode not in ('endless', 'ruthless') then return public._fail('bad_mode'); end if;
  select count(*) into total from public.records r join public.players p on p.id = r.player_id where r.mode = p_mode and not p.banned;
  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.rank, t.achieved_at, t.player_ord), '[]'::jsonb) into entries from (
    select public._rank_of(p_mode, r.best_level, r.best_seconds) as rank, p.username as name, r.best_level as level,
           r.best_seconds as seconds, r.achieved_at, (pid is not null and r.player_id = pid) as is_me, r.player_id::text as player_ord
    from public.records r join public.players p on p.id = r.player_id
    where r.mode = p_mode and not p.banned
    order by r.best_level desc, r.best_seconds asc, r.achieved_at asc, r.player_id
    limit lim offset off
  ) t;
  select coalesce(jsonb_agg(e - 'player_ord'), '[]'::jsonb) into entries from jsonb_array_elements(entries) e;
  if pid is not null then
    select * into mine from public.records where player_id = pid and mode = p_mode;
    if found and not exists (select 1 from public.players where id = pid and banned) then
      me := jsonb_build_object('rank', public._rank_of(p_mode, mine.best_level, mine.best_seconds), 'level', mine.best_level,
                               'seconds', mine.best_seconds, 'achieved_at', mine.achieved_at);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'mode', p_mode, 'total', total, 'offset', off, 'limit', lim, 'entries', entries, 'me', me);
end $$;

-- ---- housekeeping (service role only; schedule it, see docs/BACKEND_API.md) -------------------------------------------------------------

-- Delete accounts not used for p_days (default 90): their records go with them and the username is free again. Also purges old login attempts.
create or replace function public.release_idle_accounts(p_days int default 90) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_days < 30 then raise exception 'p_days must be at least 30'; end if;
  delete from public.players where last_seen_at < now() - make_interval(days => p_days);
  get diagnostics n = row_count;
  delete from public.login_attempts where attempted_at < now() - interval '1 day';
  update public.runs set status = 'expired', ended_at = now() where status = 'active' and last_event_at < now() - interval '1 day';
  return n;
end $$;

-- ---- who may call what --------------------------------------------------------------------------------------------------------

revoke all on function public.username_error(text), public.password_error(text, text), public.min_level_seconds(text, int),
  public._fail(text, jsonb), public._flag(uuid, uuid, text, jsonb), public._account_id(), public._dummy_hash(), public._ruthless_slack_seconds(),
  public._rank_of(text, int, numeric), public.register_account(text, text), public.login(text, text), public.logout(),
  public.change_password(text, text), public.get_account(), public.start_run(text), public.submit_level(uuid, int, numeric),
  public.end_run(uuid, text), public.leaderboard_page(text, int, int), public.release_idle_accounts(int) from public, anon, authenticated;

grant execute on function public.register_account(text, text), public.login(text, text), public.logout(), public.change_password(text, text),
  public.get_account(), public.start_run(text), public.submit_level(uuid, int, numeric), public.end_run(uuid, text),
  public.leaderboard_page(text, int, int), public.username_error(text), public.password_error(text, text) to authenticated;
grant execute on function public.release_idle_accounts(int) to service_role;

revoke all on function public.delete_account(text) from public, anon, authenticated;
grant execute on function public.delete_account(text) to authenticated;
