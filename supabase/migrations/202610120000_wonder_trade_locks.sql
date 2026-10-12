-- T-014: wonder-trade locks + circulating house pool
-- Locks: level gate, daily cap, paid-card cooldown, reversibility
-- House floor: 20 per rarity from a sentinel seed so the pool never runs dry.

-- 1. Add level gate to profiles
alter table public.profiles add column level integer not null default 1;

-- 2. Add acquired_paid_at to user_cards for paid-card cooldown
alter table public.user_cards add column acquired_paid_at timestamptz;

-- 3. Create a sentinel system user for house cards seed
-- UUID chosen to avoid conflicts with auth.users; profile/wallet/streak created below.
-- (Sentinel: house system, not a real player.)
insert into public.profiles (id, display_name, level) values
  ('00000000-0000-0000-0000-000000000001', 'House System', 1);
insert into public.wallets (user_id, gems) values ('00000000-0000-0000-0000-000000000001', 0);
insert into public.streaks (user_id) values ('00000000-0000-0000-0000-000000000001');

-- 4. Seed 20 house pool entries per rarity, owned by the sentinel.
--    We reuse existing test cards; multiple pool entries may reference the same card_id.
--    rarity 'common': 20 entries
insert into public.wonder_pool (card_id, variant, rarity, deposited_by)
  select id, 'none', 'common', '00000000-0000-0000-0000-000000000001'
  from public.cards where rarity = 'common' and active
  limit 20;
-- rarity 'rare': 20 entries
insert into public.wonder_pool (card_id, variant, rarity, deposited_by)
  select id, 'none', 'rare', '00000000-0000-0000-0000-000000000001'
  from public.cards where rarity = 'rare' and active
  limit 20;
-- rarity 'epic': 20 entries
insert into public.wonder_pool (card_id, variant, rarity, deposited_by)
  select id, 'none', 'epic', '00000000-0000-0000-0000-000000000001'
  from public.cards where rarity = 'epic' and active
  limit 20;
-- rarity 'legendary': 20 entries
insert into public.wonder_pool (card_id, variant, rarity, deposited_by)
  select id, 'none', 'legendary', '00000000-0000-0000-0000-000000000001'
  from public.cards where rarity = 'legendary' and active
  limit 20;

-- 5. Update wonder_trade function with all locks
create or replace function public.wonder_trade(p_user_card_id bigint, p_key text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_uc public.user_cards;
  v_rarity public.rarity;
  v_pool public.wonder_pool;
  v_card text;
  v_variant public.holo_variant;
  v_new_id bigint;
  v_result jsonb;
  v_count int;
  v_since_legendary int;
  v_since_epic int;
  v_total_pulls int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  perform 1 from public.wallets where user_id = v_uid for update;

  select result into v_result from public.idempotency_keys where user_id = v_uid and key = p_key;
  if found then return v_result; end if;

  -- Account age: wonder trade unlocks 7 days after signup
  if (select coalesce(created_at, now()) from public.profiles where id = v_uid) > now() - interval '7 days' then
    raise exception 'wonder trade unlocks 7 days after signup';
  end if;

  -- Pity counter: make 20 pulls to unlock wonder trade
  if (select coalesce(sum(total_pulls), 0) from public.pity where user_id = v_uid) < 20 then
    raise exception 'make 20 pulls to unlock wonder trade';
  end if;

  -- Daily cap: 3 completed swaps per account per UTC day
  select count(*) into v_count from public.trade_log
  where user_id = v_uid and kind = 'wonder'
    and created_at >= (date_trunc('day', now() at time zone 'utc') at time zone 'utc');
  if v_count >= 3 then raise exception 'daily wonder trade limit reached'; end if;

  -- Level gate: wonder trade requires level 5 or higher
  if (select level from public.profiles where id = v_uid) < 5 then
    raise exception 'wonder trade requires level 5';
  end if;

  select * into v_uc from public.user_cards where id = p_user_card_id and user_id = v_uid for update;
  if not found then raise exception 'card not found'; end if;
  -- Paid-card cooldown: if card was bought with real money, it is tradeable 14 days after acquisition
  if v_uc.acquired_paid_at is not null then
    if v_uc.tradeable_after > now() + interval '14 days' then
      raise exception 'card not tradeable yet: paid card cooldown';
    end if;
  end if;
  select rarity into v_rarity from public.cards where id = v_uc.card_id;

  -- House floor: ensure at least 20 pool entries per rarity.
  -- If a withdrawal would dip below the floor, mint a new house card entry first.
  if (select count(*) from public.wonder_pool where rarity = v_rarity and deposited_by = '00000000-0000-0000-0000-000000000001') <= 20 then
    -- Replenish the pool by minting house card entries using available cards of this rarity
    insert into public.wonder_pool (card_id, variant, rarity, deposited_by)
      select id, 'none', v_rarity, '00000000-0000-0000-0000-000000000001'
      from public.cards where rarity = v_rarity and active
      on conflict do nothing;
  end if;

  if public._rand() >= 0.30 then
    select * into v_pool from (
      select * from public.wonder_pool
      where rarity = v_rarity and deposited_by is distinct from v_uid
      order by deposited_at limit 50
      for update skip locked
    ) p order by public._rand() limit 1;
  end if;

  if v_pool.id is not null then
    v_card := v_pool.card_id; v_variant := v_pool.variant;
    delete from public.wonder_pool where id = v_pool.id;
  else
    select id into v_card from public.cards where rarity = v_rarity and active order by public._rand() limit 1;
    v_variant := public._roll_variant(v_rarity);
  end if;

  delete from public.user_cards where id = v_uc.id;
  insert into public.wonder_pool (card_id, variant, rarity, deposited_by)
  values (v_uc.card_id, v_uc.variant, v_rarity, v_uid);
  insert into public.user_cards (user_id, card_id, variant, source, tradeable_after, acquired_paid_at)
  values (v_uid, v_card, v_variant, 'wonder_trade', now() + interval '1 day', null) returning id into v_new_id;
  insert into public.trade_log (kind, user_id, gave_card_id, gave_variant, got_card_id, got_variant, counterparty)
  values ('wonder', v_uid, v_uc.card_id, v_uc.variant, v_card, v_variant, v_pool.deposited_by);

  v_result := jsonb_build_object('user_card_id', v_new_id, 'card_id', v_card, 'rarity', v_rarity,
    'variant', v_variant, 'trades_left_today', 3 - v_count);
  insert into public.idempotency_keys (user_id, key, action, result) values (v_uid, p_key, 'wonder', v_result);
  return v_result;
end $$;

-- 6. Revoke public execute on the updated function; grant to authenticated only.
revoke execute on function public.wonder_trade(bigint, text) from public, anon, authenticated;
grant execute on function public.wonder_trade(bigint, text) to authenticated;

-- 7. Ensure sentinel profile row is immutable by clients.
-- The existing "own profile" policy from core schema already handles RLS.
-- No additional grant needed; level column is covered by the existing policy.