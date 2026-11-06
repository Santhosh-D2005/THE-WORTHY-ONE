// Tests the v2 server schema (username + password accounts) on a REAL PostgreSQL engine (PGlite = PostgreSQL 18 in WebAssembly).
// Run: npm test (in server/). It builds the migration first, then tests BOTH paths: (A) old v1 objects + migration, (B) a fresh install.
// STUBBED, and only these: Supabase's `auth` schema (auth.users, auth.uid()), the three Supabase roles, and pgcrypto's crypt()/gen_salt()
// (PGlite has no pgcrypto, so a fake salted hash stands in: these tests prove the LOGIC around passwords: lockout, no username probing,
// binding, hash never exposed. They do NOT prove bcrypt itself; that is checked once on the real project after the migration is applied).
// NOT tested here: Supabase Auth, HTTP/PostgREST, the network, any phone.
import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

execFileSync(process.execPath, [fileURLToPath(new URL('./build_migration.mjs', import.meta.url))], { stdio: 'inherit' });
const schema = fs.readFileSync(new URL('./schema.sql', import.meta.url), 'utf8');
const migration = fs.readFileSync(new URL('./migration_v1_to_v2.sql', import.meta.url), 'utf8');
const stripExtension = (sql) => sql.replace(/create extension if not exists pgcrypto with schema extensions;/g, '-- (pgcrypto create skipped: PGlite has no pgcrypto; stub installed by the harness)');

let checks = 0, failures = 0;
function check(ok, label) { checks++; if (ok) console.log('  PASS ', label); else { failures++; console.log('  FAIL ', label); } }
const section = (t) => console.log('\n' + t);

async function baseDb() {
  const db = new PGlite();
  await db.exec(`
    create role anon nologin; create role authenticated nologin; create role service_role nologin;
    create schema auth; create table auth.users (id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create schema extensions;
    create function extensions.gen_salt(t text, n int default 10) returns text language sql volatile as $$ select '$2a$10$' || substr(md5(random()::text || clock_timestamp()::text), 1, 22) $$;
    create function extensions.crypt(pw text, salt text) returns text language sql immutable as $$ select substr(salt, 1, 29) || md5(substr(salt, 1, 29) || pw) $$;
    grant usage on schema auth, extensions to anon, authenticated, service_role;
    grant usage on schema public to anon, authenticated, service_role;
  `);
  return db;
}

// The old v1 objects the live project has (enough shape for the migration to find and drop).
const v1Objects = `
  create table public.players (id uuid primary key references auth.users (id), display_name text not null);
  create table public.runs (id uuid primary key, player_id uuid references public.players (id));
  create table public.google_identities (google_sub text primary key, player_id uuid references public.players (id));
  create function public.register_player(p_name text default null) returns jsonb language sql as $$ select '{}'::jsonb $$;
  create function public.set_display_name(p_name text) returns jsonb language sql as $$ select '{}'::jsonb $$;
  create function public.link_google_identity(p_player uuid, p_sub text) returns jsonb language sql as $$ select '{}'::jsonb $$;
  insert into auth.users values ('00000000-0000-4000-8000-000000000001');
  insert into public.players values ('00000000-0000-4000-8000-000000000001', 'Old Guest');
`;

let db;
async function as(uid, sql, params = [], role = 'authenticated') {
  await db.exec(`select set_config('request.jwt.claim.sub', '${uid ?? ''}', false); set role ${role};`);
  try { return (await db.query(sql, params)).rows; } finally { await db.exec('reset role'); }
}
async function rpc(uid, call, params = [], role = 'authenticated') { return (await as(uid, `select public.${call} as r`, params, role))[0].r; }
async function denied(uid, sql, role = 'authenticated') {
  try { await as(uid, sql, [], role); return false; } catch (e) { return /permission denied|must be owner|does not exist/i.test(String(e.message)); }
}
async function sql(q, p = []) { return (await db.query(q, p)).rows; }
async function newSession() { const id = crypto.randomUUID(); await db.exec(`insert into auth.users (id) values ('${id}')`); return id; }
const PW = 'Correct-Horse-7';
async function account(name, pw = PW) { const uid = await newSession(); const r = await rpc(uid, 'register_account($1,$2)', [name, pw]); return { uid, id: r.player_id, name, r }; }
const login = (uid, name, pw) => rpc(uid, 'login($1,$2)', [name, pw]);
const age = (run, seconds) => db.exec(`update public.runs set last_event_at = now() - interval '${seconds} seconds' where id = '${run}'`);
async function startRun(uid, mode) { const r = await rpc(uid, 'start_run($1)', [mode]); return r.run_id; }
const submit = (uid, run, level, seconds) => rpc(uid, 'submit_level($1::uuid,$2::int,$3::numeric)', [run, level, seconds]);

async function suite(label) {
  console.log(`\n################ ${label} ################`);

  section('[2] SECURITY');
  const a = await account('Alpha'), b = await account('Bravo'), c = await account('Charlie'), d = await account('Delta');
  for (const t of ['players', 'sessions', 'login_attempts', 'runs', 'run_levels', 'records', 'flags']) {
    check(await denied(a.uid, `select * from public.${t}`), `a player cannot read table ${t} directly (hashes and everything else are only reachable through the functions)`);
  }
  check(await denied(a.uid, `insert into public.records (player_id, mode, best_level, best_seconds) values ('${a.id}', 'endless', 99, 1)`), 'a player cannot write a record directly');
  check(await denied(a.uid, `update public.players set banned = false where id = '${a.id}'`), 'a player cannot update accounts directly');
  check(await denied(a.uid, `update public.players set password_hash = 'x' where id = '${b.id}'`), "a player cannot overwrite someone's password hash");
  check(await denied(null, `select public.login('Alpha', 'x')`, 'anon'), 'a caller with no session at all cannot call the functions');
  check(await denied(a.uid, `select public.release_idle_accounts(90)`), 'a player cannot call release_idle_accounts');
  check((await rpc(null, 'login($1,$2)', ['Alpha', PW])).error === 'not_authenticated', 'a call with no user id is refused');
  const outputs = JSON.stringify([a.r, await rpc(a.uid, 'get_account()'), await login(await newSession(), 'Alpha', PW), await rpc(a.uid, 'leaderboard_page($1)', ['endless'])]);
  check(!/\$2a\$|hash|password/i.test(outputs.replace(/pw_/g, '')), 'no function output ever contains a password hash or the word password');

  section('[3] USERNAME AND PASSWORD RULES');
  const names = JSON.parse(fs.readFileSync(new URL('./username_fixtures.json', import.meta.url), 'utf8'));
  let ok = true;
  for (const [name, expected] of names) {
    const got = (await sql('select public.username_error($1) as e', [name]))[0].e;
    if (got !== expected) { ok = false; console.log('     mismatch', JSON.stringify(name), 'expected', expected, 'got', got); }
  }
  check(ok, `all ${names.length} username fixtures give the expected verdict (shared with the game's tests)`);
  const pws = JSON.parse(fs.readFileSync(new URL('./password_fixtures.json', import.meta.url), 'utf8'));
  let pwOk = true;
  for (const [pw, u, expected] of pws) {
    const got = (await sql('select public.password_error($1, $2) as e', [pw, u]))[0].e;
    if (got !== expected) { pwOk = false; console.log('     mismatch for password of length', pw.length, 'expected', expected, 'got', got); }
  }
  check(pwOk, `all ${pws.length} password fixtures agree (8-72 bytes, not the username, not common, multi-byte counted in bytes)`);

  section('[4] ACCOUNTS: REGISTER, LOGIN, LOGOUT, LOCKOUT');
  const s1 = await newSession();
  check((await rpc(s1, 'register_account($1,$2)', ['Admin', PW])).error === 'reserved' && (await rpc(s1, 'register_account($1,$2)', ['Okname', 'short'])).error === 'pw_too_short', 'registering with a bad username or password is refused with a code');
  const reg = await rpc(s1, 'register_account($1,$2)', ['Kay_The_Knight', PW]);
  check(reg.ok && reg.username === 'Kay_The_Knight' && /^[0-9a-f-]{36}$/.test(reg.player_id), 'registering creates the account and logs this session in');
  check((await rpc(s1, 'get_account()')).username === 'Kay_The_Knight', 'the session can read its own account right away');
  check((await rpc(s1, 'register_account($1,$2)', ['Another_One', PW])).error === 'already_logged_in', 'a logged-in session cannot create a second account (log out first)');
  const s2 = await newSession();
  check((await rpc(s2, 'register_account($1,$2)', ['kay_the_knight', PW])).error === 'username_taken', 'usernames are unique regardless of case');
  const stored = (await sql(`select password_hash from public.players where username = 'Kay_The_Knight'`))[0].password_hash;
  check(stored !== PW && !stored.includes(PW) && stored.startsWith('$2a$'), 'the database holds a salted hash, never the password');
  check((await rpc(s2, 'get_account()')).error === 'not_logged_in' && (await rpc(s2, 'start_run($1)', ['endless'])).error === 'not_logged_in' && (await rpc(s2, 'submit_level($1::uuid,1,5)', [crypto.randomUUID()])).error === 'not_logged_in', 'an install that is not logged in can do nothing but log in or register');
  const board0 = await rpc(s2, 'leaderboard_page($1)', ['endless']);
  check(board0.ok && board0.me === null, 'a logged-out install may still READ the leaderboard (no "me")');
  const wrong = await login(s2, 'Kay_The_Knight', 'Wrong-Password-1');
  const unknown = await login(s2, 'No_Such_Knight', 'Wrong-Password-1');
  check(!wrong.ok && wrong.error === 'wrong_credentials' && JSON.stringify(wrong) === JSON.stringify(unknown), 'a wrong password and an unknown username give the IDENTICAL answer (no username probing)');
  const good = await login(s2, 'KAY_the_knight', PW);
  check(good.ok && good.player_id === reg.player_id && good.username === 'Kay_The_Knight', 'logging in (any letter case) binds the second session to the SAME account (same player id and username)');
  check((await rpc(s2, 'get_account()')).player_id === reg.player_id, 'the second install now sees the same account');
  const run0 = await startRun(s1, 'endless');
  await age(run0, 10);
  await submit(s1, run0, 1, 5);
  check((await rpc(s2, 'get_account()')).records.endless.best_level === 1, 'a record made on one install is visible after logging in on another (reinstall restores the online progress)');
  check((await rpc(s2, 'logout()')).ok && (await rpc(s2, 'get_account()')).error === 'not_logged_in' && (await rpc(s1, 'get_account()')).ok, 'logout ends only that session; the other install stays logged in');
  check((await rpc(s2, 'logout()')).ok, 'logging out twice is harmless');
  const s3 = await newSession();
  for (let i = 0; i < 5; i++) await login(s3, 'Kay_The_Knight', 'Nope-Nope-' + i);
  const locked = await login(await newSession(), 'Kay_The_Knight', PW);
  check(!locked.ok && locked.error === 'locked' && locked.wait_seconds > 0 && locked.wait_seconds <= 900, `5 wrong passwords lock the username for 15 minutes (even the right password is refused: wait ${locked.wait_seconds} s)`);
  await db.exec(`update public.login_attempts set attempted_at = now() - interval '16 minutes'`);
  check((await login(await newSession(), 'Kay_The_Knight', PW)).ok, 'after the lock period the right password works again');
  check((await sql(`select count(*)::int as n from public.login_attempts where username_key = 'kay_the_knight' and not success`))[0].n === 0, 'a successful login clears the failed attempts');
  const s4 = await newSession();
  for (let i = 0; i < 10; i++) await login(s4, 'Guess_' + i, 'Nope-Nope-1');
  check((await login(s4, 'Kay_The_Knight', PW)).error === 'locked', 'one install trying many usernames is locked after 10 failures');
  await db.exec(`update public.players set banned = true where username = 'Kay_The_Knight'`);
  check((await login(await newSession(), 'Kay_The_Knight', PW)).error === 'banned', 'a banned account cannot log in');
  await db.exec(`update public.players set banned = false where username = 'Kay_The_Knight'`);
  const cp1 = await newSession();
  await login(cp1, 'Kay_The_Knight', PW);
  check((await rpc(cp1, 'change_password($1,$2)', ['Not-The-Password-1', 'Fresh-Password-9'])).error === 'wrong_credentials', 'changing the password needs the current one');
  check((await rpc(cp1, 'change_password($1,$2)', [PW, 'short'])).error === 'pw_too_short', 'the new password must follow the rules');
  const others = (await sql(`select count(*)::int as n from public.sessions where player_id = '${reg.player_id}'`))[0].n;
  check((await rpc(cp1, 'change_password($1,$2)', [PW, 'Fresh-Password-9'])).ok, 'a correct change works');
  const after = (await sql(`select count(*)::int as n from public.sessions where player_id = '${reg.player_id}'`))[0].n;
  check(others >= 2 && after === 1 && (await rpc(cp1, 'get_account()')).ok && (await rpc(s1, 'get_account()')).error === 'not_logged_in', 'the other installs are logged out, the one that changed it stays in');
  check(!(await login(await newSession(), 'Kay_The_Knight', PW)).ok && (await login(await newSession(), 'Kay_The_Knight', 'Fresh-Password-9')).ok, 'the old password no longer works, the new one does');

  section('[5] TIME FLOOR VS THE GAME');
  const expected = JSON.parse(fs.readFileSync(new URL('./floor_expected.json', import.meta.url), 'utf8'));
  let floorOk = true, worst = 0, count = 0;
  for (const mode of ['endless', 'ruthless']) for (const [level, secs] of Object.entries(expected[mode])) {
    const got = Number((await sql('select public.min_level_seconds($1, $2::int) as s', [mode, level]))[0].s);
    worst = Math.max(worst, Math.abs(got - secs)); count++;
    if (Math.abs(got - secs) > 0.011) { floorOk = false; console.log('     ', mode, level, 'game', secs, 'server', got); }
  }
  check(floorOk, `the server's per-level floor equals the game's simulation for ${count} sample levels, including 100, 500 and 9999 (worst difference ${worst.toFixed(4)} s)`);
  const flat = (m) => sql('select public.min_level_seconds($1, 100) as a, public.min_level_seconds($1, 101) as b, public.min_level_seconds($1, 9999) as c', [m]);
  const fe = (await flat('endless'))[0], fr = (await flat('ruthless'))[0];
  check(fe.a === fe.b && fe.b === fe.c && fr.a === fr.b && fr.b === fr.c, 'difficulty stops rising at level 100: the floor is identical for levels 100, 101 and 9999');
  const f50 = Number((await sql(`select public.min_level_seconds('endless', 50) as s`))[0].s), f99 = Number((await sql(`select public.min_level_seconds('endless', 99) as s`))[0].s);
  check(f99 > f50, 'and it is still rising between level 50 and level 99');

  section('[6] RUNS AND LEVELS');
  const p = await account('Runner_One'), q = await account('Runner_Two');
  check((await rpc(p.uid, 'start_run($1)', ['casual'])).error === 'bad_mode' && (await rpc(p.uid, 'start_run($1)', [null])).error === 'bad_mode', 'an unknown mode is refused');
  let run = await startRun(p.uid, 'endless');
  check(typeof run === 'string' && run.length === 36, 'start_run issues a server-side run id');
  await age(run, 10);
  check((await submit(p.uid, run, 2, 5)).error === 'bad_sequence', 'skipping ahead is refused');
  check((await submit(p.uid, run, 1, 0.5)).error === 'implausible_time', 'a time below the physical floor is refused');
  check((await submit(p.uid, run, 1, 60)).error === 'time_exceeds_elapsed', 'a time longer than the real time that has passed is refused');
  check((await submit(p.uid, run, 1, 0)).error === 'bad_time' && (await submit(p.uid, run, 1, -3)).error === 'bad_time' && (await submit(p.uid, run, 1, 4000)).error === 'bad_time', 'zero, negative and absurd times are refused');
  check((await rpc(p.uid, 'submit_level($1::uuid,$2::int,$3::numeric)', [crypto.randomUUID(), 1, 5])).error === 'unknown_run', 'an unknown run id is refused');
  check((await submit(q.uid, run, 1, 5)).error === 'unknown_run', "another player cannot submit to my run");
  const ok1 = await submit(p.uid, run, 1, 5);
  check(ok1.ok && ok1.new_best, 'a valid level 1 is accepted and is a new best');
  check((await submit(p.uid, run, 1, 5)).error === 'bad_sequence', 'the same level cannot be submitted twice');
  check((await sql(`select count(*)::int as n from public.flags where player_id = '${p.id}'`))[0].n >= 4, 'rejected submissions are flagged for review');
  await age(run, 10);
  check((await submit(p.uid, run, 2, 6)).ok, 'level 2 is accepted in order');
  const acc = await rpc(p.uid, 'get_account()');
  check(acc.records.endless.best_level === 2 && !acc.records.ruthless, 'the Endless record is 2 and there is no Ruthless record');
  check((await rpc(p.uid, 'end_run($1::uuid,$2)', [run, 'failed'])).status === 'failed' && (await submit(p.uid, run, 3, 6)).error === 'run_not_active', 'a failed run ends and accepts nothing more');
  check((await rpc(p.uid, 'end_run($1::uuid,$2)', [run, 'failed'])).ok && (await rpc(p.uid, 'end_run($1::uuid,$2)', [run, 'nonsense'])).error === 'bad_reason', 'ending twice is harmless; an unknown reason is refused');
  run = await startRun(p.uid, 'endless');
  for (let level = 1; level <= 300; level++) { await age(run, 12); const r = await submit(p.uid, run, level, 11); if (!r.ok) { check(false, 'level ' + level + ' accepted: ' + JSON.stringify(r)); break; } }
  check((await rpc(p.uid, 'get_account()')).records.endless.best_level === 300, '300 consecutive levels are accepted');
  // the last level: 9999
  await db.exec(`update public.runs set last_level = 9998, last_event_at = now() - interval '12 seconds' where id = '${run}'`);
  const last = await submit(p.uid, run, 9999, 11);
  check(last.ok && last.level === 9999 && (await rpc(p.uid, 'get_account()')).records.endless.best_level === 9999, 'level 9999 is accepted and becomes the record');
  await age(run, 12);
  check((await submit(p.uid, run, 10000, 11)).error === 'bad_level', 'there is no level 10000: the server refuses anything above 9999');
  check((await rpc(p.uid, 'end_run($1::uuid,$2)', [run, 'completed'])).status === 'completed', 'a run that reached 9999 can end as completed');
  const early = await startRun(p.uid, 'endless');
  check((await rpc(p.uid, 'end_run($1::uuid,$2)', [early, 'completed'])).status === 'closed', '"completed" before level 9999 is only a normal close (it cannot claim a win)');
  const old = await startRun(p.uid, 'endless');
  const newer = await startRun(p.uid, 'endless');
  check((await sql(`select status from public.runs where id = '${old}'`))[0].status === 'closed' && (await submit(p.uid, old, 1, 11)).error === 'run_not_active', 'starting a new run closes the previous one');
  const spam = await account('Spammer_X');
  let limited = false;
  for (let i = 0; i < 45; i++) { if ((await rpc(spam.uid, 'start_run($1)', ['endless'])).error === 'rate_limited') { limited = true; break; } }
  check(limited, 'starting runs too fast is rate-limited');
  const p2 = await newSession();
  await login(p2, 'Runner_One', PW);
  check((await rpc(p2, 'get_account()')).records.endless.best_level === 9999, 'logging in on a new install shows the same records (9999)');

  section('[7] RUTHLESS');
  const rr = await account('Ruth_Less');
  let rrun = await startRun(rr.uid, 'ruthless');
  await age(rrun, 8);
  check((await submit(rr.uid, rrun, 1, 2.0)).error === 'implausible_time', 'Ruthless has its own, stricter floor (2.0 s is below its 2.3 s limit for level 1)');
  const sameInEndless = await startRun(q.uid, 'endless');
  await age(sameInEndless, 8);
  check((await submit(q.uid, sameInEndless, 1, 2.0)).ok, '...while the same 2.0 s is allowed in Endless (limit 1.9 s)');
  rrun = await startRun(rr.uid, 'ruthless');
  await age(rrun, 8);
  check((await submit(rr.uid, rrun, 1, 6)).ok, 'a valid Ruthless level 1 is accepted');
  check((await rpc(rr.uid, 'end_run($1::uuid,$2)', [rrun, 'invalidated'])).status === 'invalidated', 'a Ruthless run that left the foreground is marked invalidated');
  await age(rrun, 10);
  check((await submit(rr.uid, rrun, 2, 6)).error === 'run_not_active', 'an invalidated Ruthless run can never submit another level');
  const racc = await rpc(rr.uid, 'get_account()');
  check(racc.records.ruthless.best_level === 1 && !racc.records.endless, 'the level completed before leaving stays in the Ruthless record only');
  rrun = await startRun(rr.uid, 'ruthless');
  await age(rrun, 200);
  check((await submit(rr.uid, rrun, 1, 6)).error === 'run_expired' && (await sql(`select status from public.runs where id = '${rrun}'`))[0].status === 'expired' && (await submit(rr.uid, rrun, 1, 6)).error === 'run_not_active', 'a Ruthless gap of 200 s for a 6 s level expires the run for good');
  rrun = await startRun(rr.uid, 'ruthless');
  await age(rrun, 40);
  check((await submit(rr.uid, rrun, 1, 6)).ok, 'a normal gap (40 s for a 6 s level) is accepted');
  const er = await startRun(rr.uid, 'endless');
  await age(er, 200);
  check((await submit(rr.uid, er, 1, 6)).ok && (await rpc(rr.uid, 'end_run($1::uuid,$2)', [er, 'invalidated'])).status === 'closed', 'the same gap in Endless is accepted, and "invalidated" only has meaning in Ruthless');

  section('[8] LEADERBOARDS');
  await db.exec(`truncate public.records`);
  const empty = await rpc(a.uid, 'leaderboard_page($1)', ['endless']);
  check(empty.ok && empty.total === 0 && empty.entries.length === 0 && empty.me === null, 'empty leaderboard: no entries, total 0, no "me" (nothing invented)');
  const rec = (acct, mode, level, secs, minutes) => db.exec(`insert into public.records (player_id, mode, best_level, best_seconds, achieved_at) values ('${acct.id}', '${mode}', ${level}, ${secs}, now() - interval '${minutes} minutes')`);
  await rec(a, 'endless', 10, 30, 50); await rec(b, 'endless', 10, 25, 40); await rec(c, 'endless', 12, 50, 30); await rec(d, 'endless', 10, 25, 20); await rec(a, 'ruthless', 4, 20, 10);
  let page = await rpc(a.uid, 'leaderboard_page($1, $2, $3)', ['endless', 25, 0]);
  check(page.entries.map(e => e.name).join() === 'Charlie,Bravo,Delta,Alpha', `order: highest level first, then the faster time (${page.entries.map(e => e.name).join()})`);
  check(page.entries.map(e => e.rank).join() === '1,2,2,4', `ranks: equal level and time share a rank, the next skips (${page.entries.map(e => e.rank).join()})`);
  check(page.total === 4 && page.entries.filter(e => e.is_me).length === 1 && page.entries.find(e => e.is_me).name === 'Alpha', 'the current player is flagged exactly once');
  check(Object.keys(page.entries[0]).sort().join() === 'achieved_at,is_me,level,name,rank,seconds', 'entries contain no private data (no id, no hash)');
  const pages = [];
  for (const off of [0, 2, 4]) pages.push(...(await rpc(a.uid, 'leaderboard_page($1, $2, $3)', ['endless', 2, off])).entries.map(e => e.name));
  check(pages.join() === 'Charlie,Bravo,Delta,Alpha', 'pagination in pages of 2 returns every entry once, in order');
  const bottom = await rpc(a.uid, 'leaderboard_page($1, $2, $3)', ['endless', 1, 0]);
  check(bottom.entries.length === 1 && bottom.me.rank === 4 && bottom.me.level === 10, "Alpha is not on a page of 1 but 'me' says rank 4");
  const twin = await newSession();
  await login(twin, 'Alpha', PW);
  check((await rpc(twin, 'leaderboard_page($1)', ['endless'])).me.rank === 4, 'the same account on another install gets the same rank');
  const clamp = await rpc(a.uid, 'leaderboard_page($1, $2, $3)', ['endless', 1000, -5]);
  check(clamp.limit === 100 && clamp.offset === 0 && (await rpc(a.uid, 'leaderboard_page($1, $2, $3)', ['endless', 5, 400])).entries.length === 0, 'limit is clamped to 100, a negative offset to 0, a page past the end is empty');
  const ruth = await rpc(a.uid, 'leaderboard_page($1)', ['ruthless']);
  check(ruth.total === 1 && ruth.entries[0].name === 'Alpha' && ruth.entries[0].level === 4 && (await rpc(b.uid, 'leaderboard_page($1)', ['ruthless'])).me === null, 'the Ruthless board holds only Ruthless records and Bravo has no Ruthless rank');
  check((await rpc(a.uid, 'leaderboard_page($1)', ['bogus'])).error === 'bad_mode', 'an unknown board is refused');
  await db.exec(`update public.players set banned = true where id = '${c.id}'`);
  page = await rpc(a.uid, 'leaderboard_page($1)', ['endless']);
  check(page.total === 3 && !page.entries.some(e => e.name === 'Charlie') && page.entries[0].rank === 1, 'a banned player disappears from the board and ranks close up');
  await db.exec(`update public.players set banned = false where id = '${c.id}'`);

  section('[9] IDLE ACCOUNTS (90 days)');
  const idle = await account('Idle_Knight');
  await rec(idle, 'endless', 5, 20, 5);
  await db.exec(`update public.players set last_seen_at = now() - interval '100 days' where id = '${idle.id}'`);
  await db.exec(`update public.players set last_seen_at = now() - interval '80 days' where id = '${d.id}'`);
  check((await rpc(null, 'release_idle_accounts(90)', [], 'service_role')) === 1, 'the service role releases accounts idle for 90 days (1 released: the 100-day one, not the 80-day one)');
  check((await sql(`select count(*)::int as n from public.players where id = '${idle.id}'`))[0].n === 0 && (await sql(`select count(*)::int as n from public.records where player_id = '${idle.id}'`))[0].n === 0, '...its record and sessions went with it');
  const reuse = await account('Idle_Knight');
  check(reuse.r.ok && reuse.id !== idle.id, '...and the username is free again for a new player');
  check((await sql(`select count(*)::int as n from public.players where id = '${d.id}'`))[0].n === 1, 'a recently used account is kept');
  let tooSoon = false;
  try { await rpc(null, 'release_idle_accounts(5)', [], 'service_role'); } catch (e) { tooSoon = /at least 30/.test(String(e.message)); }
  check(tooSoon, 'the idle period cannot be set below 30 days by mistake');
}

section('[1] SCHEMA AND MIGRATION');
db = await baseDb();
await db.exec(v1Objects);
await db.exec(stripExtension(migration));
check((await sql(`select count(*)::int as n from information_schema.columns where table_schema='public' and table_name='players' and column_name='password_hash'`))[0].n === 1, 'migration on a v1 database: v1 tables dropped, v2 created');
check((await sql(`select count(*)::int as n from pg_proc where proname in ('register_player','set_display_name','link_google_identity')`))[0].n === 0, '...and the old v1 functions are gone');
const first = (await sql(`select count(*)::int as n from public.players`))[0].n;
await db.exec(`insert into auth.users values ('00000000-0000-4000-8000-0000000000aa'); select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000aa',false);`);
await db.exec(`select public.register_account('Survivor', '${PW}')`);
await db.exec(stripExtension(migration));
check((await sql(`select count(*)::int as n from public.players where username = 'Survivor'`))[0].n === 1 && first === 0, 'running the migration AGAIN on v2 is harmless and keeps the accounts');
await suite('(A) v1 database + migration');

db = await baseDb();
await db.exec(stripExtension(schema));
await db.exec(stripExtension(schema));
check(true, 'schema.sql loads on an empty database, and a second time (idempotent)');
await suite('(B) fresh install');

console.log(`\n==== ${checks} checks, ${failures} failed ====`);
console.log(failures === 0 ? 'RESULT: ALL PASSED' : 'RESULT: FAILURES');
process.exit(failures === 0 ? 0 : 1);
