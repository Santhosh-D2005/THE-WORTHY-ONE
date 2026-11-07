-- THE WORTHY ONE - Endless now has the same hardness as Ruthless, so the server's per-level time floor uses the same numbers for both.
-- Run once in Supabase > SQL Editor. Safe to run more than once. Deletes nothing.

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
