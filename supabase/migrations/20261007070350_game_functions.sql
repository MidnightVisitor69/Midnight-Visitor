-- Cryptographic random in [0,1). random() is predictable-ish; gacha odds deserve better.
create function public._rand() returns double precision
language sql volatile set search_path = '' as $$
  select ('x' || encode(extensions.gen_random_bytes(6), 'hex'))::bit(48)::bigint / 281474976710656.0
$$;

-- Rates: legendary 1.5%, epic 6.5%, rare 22%, common 70%.
-- Pity: every 10th pull is epic+, 80th pull is guaranteed legendary.
create function public._roll_rarity(p_since_epic int, p_since_legendary int)
returns table (rarity public.rarity, pity_hit boolean)
language plpgsql volatile set search_path = '' as $$
declare r double precision := public._rand();
begin
  if p_since_legendary + 1 >= 80 then
    return query select 'legendary'::public.rarity, true; return;
  end if;
  if r < 0.015 then rarity := 'legendary';
  elsif r < 0.080 then rarity := 'epic';
  elsif r < 0.300 then rarity := 'rare';
  else rarity := 'common';
  end if;
  pity_hit := false;
  if rarity in ('common','rare') and p_since_epic + 1 >= 10 then
    rarity := 'epic'; pity_hit := true;
  end if;
  return next;
end $$;

-- Holo only on rare+. none 85, silver 8, rainbow 4, gold 2, prism 0.8, galaxy 0.2
create function public._roll_variant(p_rarity public.rarity) returns public.holo_variant
language plpgsql volatile set search_path = '' as $$
declare r double precision;
begin
  if p_rarity = 'common' then return 'none'; end if;
  r := public._rand();
  if r < 0.002 then return 'galaxy';
  elsif r < 0.010 then return 'prism';
  elsif r < 0.030 then return 'gold';
  elsif r < 0.070 then return 'rainbow';
  elsif r < 0.150 then return 'silver';
  end if;
  return 'none';
end $$;

create function public._pick_card(p_banner_id text, p_rarity public.rarity) returns text
language plpgsql volatile set search_path = '' as $$
declare v_card text;
begin
  select c.id into v_card
  from public.banner_cards bc join public.cards c on c.id = bc.card_id
  where bc.banner_id = p_banner_id and c.rarity = p_rarity and c.active
  order by public._rand() limit 1;
  if v_card is null then raise exception 'banner % has no % cards', p_banner_id, p_rarity; end if;
  return v_card;
end $$;

create function public._spend_gems(p_uid uuid, p_amount int, p_reason text, p_ref text) returns int
language plpgsql set search_path = '' as $$
declare v_gems int;
begin
  update public.wallets set gems = gems - p_amount, updated_at = now()
  where user_id = p_uid and gems >= p_amount returning gems into v_gems;
  if v_gems is null then raise exception 'not enough gems'; end if;
  insert into public.currency_ledger (user_id, delta, balance_after, reason, ref)
  values (p_uid, -p_amount, v_gems, p_reason, p_ref);
  return v_gems;
end $$;

create function public._grant_gems(p_uid uuid, p_amount int, p_reason text, p_ref text) returns int
language plpgsql set search_path = '' as $$
declare v_gems int;
begin
  update public.wallets set gems = gems + p_amount, updated_at = now()
  where user_id = p_uid returning gems into v_gems;
  insert into public.currency_ledger (user_id, delta, balance_after, reason, ref)
  values (p_uid, p_amount, v_gems, p_reason, p_ref);
  return v_gems;
end $$;

-- PULL: 1 or 10 cards. Same key twice = same result, no double charge.
create function public.pull(p_banner_id text, p_count int, p_key text) returns jsonb
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

  perform 1 from public.wallets where user_id = v_uid for update;

  select result into v_result from public.idempotency_keys where user_id = v_uid and key = p_key;
  if found then return v_result; end if;

  select * into v_banner from public.banners
  where id = p_banner_id and starts_at <= now() and (ends_at is null or ends_at > now());
  if not found then raise exception 'banner not available'; end if;

  v_gems := public._spend_gems(v_uid,
    case when p_count = 1 then v_banner.cost_single else v_banner.cost_ten end, 'pull', p_banner_id);

  insert into public.pity (user_id, banner_id) values (v_uid, p_banner_id) on conflict do nothing;
  select * into v_pity from public.pity where user_id = v_uid and banner_id = p_banner_id for update;

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
    if v_rarity = 'legendary' then
      v_pity.since_legendary := 0; v_pity.since_epic := 0;
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
  where user_id = v_uid and banner_id = p_banner_id;

  v_result := jsonb_build_object('cards', v_cards, 'gems', v_gems,
    'pity', jsonb_build_object('since_epic', v_pity.since_epic, 'since_legendary', v_pity.since_legendary));
  insert into public.idempotency_keys (user_id, key, action, result) values (v_uid, p_key, 'pull', v_result);
  return v_result;
end $$;

-- DAILY LOGIN: 7-day cycle, day 7 pays big and grants a streak freeze (max 3).
create function public.claim_daily() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'utc')::date;
  s public.streaks;
  v_reward int;
  v_used_freeze boolean := false;
  v_gems int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  perform 1 from public.wallets where user_id = v_uid for update;
  select * into s from public.streaks where user_id = v_uid for update;

  if s.last_claim = v_today then raise exception 'already claimed today'; end if;
  if s.last_claim = v_today - 1 then
    s.current := s.current + 1;
  elsif s.last_claim = v_today - 2 and s.freezes > 0 then
    s.freezes := s.freezes - 1; s.current := s.current + 1; v_used_freeze := true;
  else
    s.current := 1;
  end if;
  s.best := greatest(s.best, s.current);

  v_reward := case when s.current % 7 = 0 then 500 else 100 + 20 * ((s.current - 1) % 7) end;
  if s.current % 7 = 0 then s.freezes := least(s.freezes + 1, 3); end if;

  update public.streaks set current = s.current, best = s.best, last_claim = v_today, freezes = s.freezes
  where user_id = v_uid;
  v_gems := public._grant_gems(v_uid, v_reward, 'daily', v_today::text);

  return jsonb_build_object('streak', s.current, 'best', s.best, 'reward', v_reward,
    'freezes', s.freezes, 'used_freeze', v_used_freeze, 'gems', v_gems);
end $$;

-- WONDER TRADE: give one card, get a random card of the same rarity.
create function public.wonder_trade(p_user_card_id bigint, p_key text) returns jsonb
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
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  perform 1 from public.wallets where user_id = v_uid for update;

  select result into v_result from public.idempotency_keys where user_id = v_uid and key = p_key;
  if found then return v_result; end if;

  if (select created_at from public.profiles where id = v_uid) > now() - interval '3 days' then
    raise exception 'wonder trade unlocks 3 days after signup';
  end if;
  if (select coalesce(sum(total_pulls), 0) from public.pity where user_id = v_uid) < 20 then
    raise exception 'make 20 pulls to unlock wonder trade';
  end if;
  select count(*) into v_count from public.trade_log
  where user_id = v_uid and kind = 'wonder'
    and created_at >= (date_trunc('day', now() at time zone 'utc') at time zone 'utc');
  if v_count >= 5 then raise exception 'daily wonder trade limit reached'; end if;

  select * into v_uc from public.user_cards where id = p_user_card_id and user_id = v_uid for update;
  if not found then raise exception 'card not found'; end if;
  if v_uc.tradeable_after > now() then raise exception 'card not tradeable yet'; end if;
  select rarity into v_rarity from public.cards where id = v_uc.card_id;

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
  insert into public.user_cards (user_id, card_id, variant, source, tradeable_after)
  values (v_uid, v_card, v_variant, 'wonder_trade', now() + interval '1 day') returning id into v_new_id;
  insert into public.trade_log (kind, user_id, gave_card_id, gave_variant, got_card_id, got_variant, counterparty)
  values ('wonder', v_uid, v_uc.card_id, v_uc.variant, v_card, v_variant, v_pool.deposited_by);

  v_result := jsonb_build_object('user_card_id', v_new_id, 'card_id', v_card, 'rarity', v_rarity,
    'variant', v_variant, 'trades_left_today', 4 - v_count);
  insert into public.idempotency_keys (user_id, key, action, result) values (v_uid, p_key, 'wonder', v_result);
  return v_result;
end $$;

revoke execute on function public._rand() from public, anon, authenticated;
revoke execute on function public._roll_rarity(int, int) from public, anon, authenticated;
revoke execute on function public._roll_variant(public.rarity) from public, anon, authenticated;
revoke execute on function public._pick_card(text, public.rarity) from public, anon, authenticated;
revoke execute on function public._spend_gems(uuid, int, text, text) from public, anon, authenticated;
revoke execute on function public._grant_gems(uuid, int, text, text) from public, anon, authenticated;
revoke execute on function public.pull(text, int, text) from public, anon;
revoke execute on function public.claim_daily() from public, anon;
revoke execute on function public.wonder_trade(bigint, text) from public, anon;
grant execute on function public.pull(text, int, text) to authenticated;
grant execute on function public.claim_daily() to authenticated;
grant execute on function public.wonder_trade(bigint, text) to authenticated;
