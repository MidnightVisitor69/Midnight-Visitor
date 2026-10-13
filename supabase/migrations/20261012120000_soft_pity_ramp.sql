-- T-013: soft pity ramp replaces the hard epic/legendary guarantees.
--
-- Per-pull odds for epic and legendary rise with the number of pulls since the
-- last hit of that tier. There is no hard "every 10th pull is epic" cliff any
-- more: the ramp itself is the bail-out, so bad luck still always recovers but
-- never on a predictable step.
--
-- The numbers live in a DATA table (pity_ramp), not in the function body, so the
-- dev can retune them by editing the values and re-applying; the functions only
-- ever read the table.
--
-- Re-applying this file is safe: the table is created only if missing and the
-- ramp rows are upserted, so a re-run updates the tuning instead of erroring.
-- Every statement is transactional DDL, so applying it inside a transaction that
-- is later rolled back leaves the schema exactly as it was (see the _test file).

-- The ramp: one row per boosted tier. Values are PERCENTAGES (5 = 5%), matching
-- the column names; the JSON API converts them to the fractions the client uses.
create table if not exists public.pity_ramp (
  tier     public.rarity    primary key,
  base_pct double precision not null check (base_pct >= 0 and base_pct <= 100),
  step_pct double precision not null check (step_pct >= 0),
  cap_pct  double precision not null check (cap_pct >= base_pct and cap_pct <= 100)
);
alter table public.pity_ramp enable row level security;
-- No policies: only security-definer functions read it. Clients never see it.

-- Coordinator's proposed ramp (dev approves / edits at review):
--   epic:      base 5%,  +0.4%  per pull since the last epic,      cap 25%
--   legendary: base 1%,  +0.15% per pull since the last legendary, cap 10%
-- Holo variant odds are NOT here: they are independent of rarity and rolled
-- separately by _roll_variant, which this migration does not touch.
insert into public.pity_ramp (tier, base_pct, step_pct, cap_pct) values
  ('epic',      5.0, 0.4,  25.0),
  ('legendary', 1.0, 0.15, 10.0)
on conflict (tier) do update
  set base_pct = excluded.base_pct,
      step_pct = excluded.step_pct,
      cap_pct  = excluded.cap_pct;

-- Soft ramp roll. Reads the table so the odds themselves climb every pull since
-- the last hit of that tier, capped. Common and rare split whatever is left in
-- the published 70:22 ratio, so each pull still sums to exactly 1.
create or replace function public._roll_rarity(p_since_epic int, p_since_legendary int)
returns table (rarity public.rarity, pity_hit boolean)
language plpgsql volatile set search_path = '' as $$
declare
  r double precision := public._rand();
  v_epic_odds double precision;
  v_legendary_odds double precision;
  v_rest double precision;
  v_common_odds double precision;
  v_rare_odds double precision;
begin
  -- Ramp odds come from the table, never from thresholds hardcoded here.
  select least(base_pct + step_pct * greatest(p_since_epic, 0), cap_pct) / 100.0
    into v_epic_odds from public.pity_ramp where tier = 'epic';
  select least(base_pct + step_pct * greatest(p_since_legendary, 0), cap_pct) / 100.0
    into v_legendary_odds from public.pity_ramp where tier = 'legendary';
  v_epic_odds := coalesce(v_epic_odds, 0.0);
  v_legendary_odds := coalesce(v_legendary_odds, 0.0);

  v_rest := greatest(1.0 - v_epic_odds - v_legendary_odds, 0.0);
  v_common_odds := v_rest * (0.70 / 0.92);
  v_rare_odds := v_rest * (0.22 / 0.92);

  if r < v_common_odds then
    rarity := 'common';
  elsif r < v_common_odds + v_rare_odds then
    rarity := 'rare';
  elsif r < v_common_odds + v_rare_odds + v_epic_odds then
    rarity := 'epic';
  else
    rarity := 'legendary';
  end if;
  -- Soft pity has no discrete bail-out event to flag. Log a boosted hit instead:
  -- the tier only had a chance because its counter was above zero.
  pity_hit := (rarity = 'epic' and p_since_epic > 0)
           or (rarity = 'legendary' and p_since_legendary > 0);
  return next;
end $$;

-- PULL: 1 or 10 cards. Same key twice = same result, no double charge.
-- Only the counter update changes from the hard-pity version: each counter is
-- independent, so a hit resets ONLY its own tier and the other keeps counting.
create or replace function public.pull(p_banner_id text, p_count int, p_key text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_banner public.banners;
  v_pity public.pity;
  v_rarity public.rarity;
  v_pity_hit boolean;
  v_card text;
  v_variant public.holo_variant;
  v_uc_id bigint;
  v_cards jsonb := '[]'::jsonb;
  v_result jsonb;
  v_gems int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_count not in (1, 10) then raise exception 'invalid count'; end if;

  -- Wallet row lock first: two racing pulls by one user serialize on it, so a
  -- double-spend is impossible even before the pity row is locked.
  perform 1 from public.wallets where user_id = v_uid for update;

  select result into v_result from public.idempotency_keys where user_id = v_uid and key = p_key;
  if found then return v_result; end if;

  select * into v_banner from public.banners
  where id = p_banner_id and starts_at <= now() and (ends_at is null or ends_at > now());
  if not found then raise exception 'banner not available'; end if;

  v_gems := public._spend_gems(v_uid,
    case when p_count = 1 then v_banner.cost_single else v_banner.cost_ten end, 'pull', p_banner_id);

  insert into public.pity (user_id) values (v_uid) on conflict do nothing;
  -- Row lock on the pity row: concurrent pulls cannot both read the same counter
  -- and then both write it, which would skip ramp increments.
  select * into v_pity from public.pity where user_id = v_uid for update;

  for i in 1..p_count loop
    select r.rarity, r.pity_hit into v_rarity, v_pity_hit
    from public._roll_rarity(v_pity.since_epic, v_pity.since_legendary) r;
    v_card := public._pick_card(p_banner_id, v_rarity);
    v_variant := public._roll_variant(v_rarity);

    insert into public.user_cards (user_id, card_id, variant, source)
    values (v_uid, v_card, v_variant, 'pull') returning id into v_uc_id;
    insert into public.pull_log (user_id, banner_id, card_id, rarity, variant, pity_triggered)
    values (v_uid, p_banner_id, v_card, v_rarity, v_variant, v_pity_hit);

    v_pity.total_pulls := v_pity.total_pulls + 1;
    -- Counters reset ONLY for the tier that hit. A legendary is not an epic, so
    -- since_epic keeps counting when a legendary lands, and vice versa.
    if v_rarity = 'legendary' then
      v_pity.since_legendary := 0; v_pity.since_epic := v_pity.since_epic + 1;
    elsif v_rarity = 'epic' then
      v_pity.since_epic := 0; v_pity.since_legendary := v_pity.since_legendary + 1;
    else
      v_pity.since_epic := v_pity.since_epic + 1; v_pity.since_legendary := v_pity.since_legendary + 1;
    end if;

    v_cards := v_cards || jsonb_build_object('user_card_id', v_uc_id, 'card_id', v_card,
      'rarity', v_rarity, 'variant', v_variant, 'pity', v_pity_hit);
  end loop;

  update public.pity set since_epic = v_pity.since_epic, since_legendary = v_pity.since_legendary,
    total_pulls = v_pity.total_pulls
  where user_id = v_uid;

  v_result := jsonb_build_object('cards', v_cards, 'gems', v_gems,
    'pity', jsonb_build_object('since_epic', v_pity.since_epic, 'since_legendary', v_pity.since_legendary));
  insert into public.idempotency_keys (user_id, key, action, result) values (v_uid, p_key, 'pull', v_result);
  return v_result;
end $$;

-- Published odds must match what _roll_rarity does. The base rates come from the
-- ramp table (at counter 0) and the ramp itself is published so the client can
-- show the climb in plain language without ever hardcoding the numbers.
-- stable (was immutable): it now reads the tuning table.
create or replace function public._published_odds() returns jsonb
language sql stable set search_path = '' as $$
  with ramp as (
    select tier, base_pct / 100.0 as base, step_pct / 100.0 as step, cap_pct / 100.0 as cap
    from public.pity_ramp
  ), base as (
    select
      coalesce((select base from ramp where tier = 'epic'), 0.05) as epic,
      coalesce((select base from ramp where tier = 'legendary'), 0.01) as legendary
  )
  select jsonb_build_object(
    'odds', jsonb_build_object(
      'common', round((1 - base.epic - base.legendary) * (0.70 / 0.92), 6),
      'rare',   round((1 - base.epic - base.legendary) * (0.22 / 0.92), 6),
      'epic', base.epic,
      'legendary', base.legendary),
    'pity', jsonb_build_object(
      'ramp', coalesce(
        (select jsonb_object_agg(tier, jsonb_build_object('base', base, 'step', step, 'cap', cap))
         from ramp),
        '{}'::jsonb)),
    'holo_odds', jsonb_build_object('none', 0.85, 'silver', 0.08, 'rainbow', 0.04, 'gold', 0.02,
                                    'prism', 0.008, 'galaxy', 0.002))
  from base
$$;

-- Re-issue the revokes so a freshly applied database is locked down exactly the
-- same as after the earlier migrations (create or replace keeps prior grants, but
-- this makes the new file self-sufficient).
revoke execute on function public._roll_rarity(int, int) from public, anon, authenticated;
revoke execute on function public.pull(text, int, text) from public, anon;
revoke execute on function public._published_odds() from public, anon, authenticated;
grant execute on function public.pull(text, int, text) to authenticated;
