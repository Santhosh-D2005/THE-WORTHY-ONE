-- THE WORTHY ONE - add account deletion to an existing v2 project. Safe to run more than once. Deletes nothing by itself.
-- Run it once in Supabase > SQL Editor. Same function as in schema.sql.

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


revoke all on function public.delete_account(text) from public, anon, authenticated;
grant execute on function public.delete_account(text) to authenticated;
