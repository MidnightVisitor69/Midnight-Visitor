-- Prototype support: one-call home summary, published odds, set sizes, and an alpha-only gem
-- faucet that the SERVER gates (a client flag could be flipped by anyone with a debugger).

create table public.app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.app_config enable row level security;
-- No policies: only security-definer functions read it.
insert into public.app_config (key, value) values ('alpha_mode', 'true'::jsonb);

-- Alpha-only content (e.g. the KaT test sets) is flagged so one update can retire it.
alter table public.cards add column alpha boolean not null default false;

-- Published odds. MUST match _roll_rarity / _roll_variant; supabase/tests checks both agree.
create function public._published_odds() returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'odds', jsonb_build_object('common', 0.70, 'rare', 0.22, 'epic', 0.065, 'legendary', 0.015),
    'pity', jsonb_build_object('epic_every', 10, 'legendary_at', 80),
    'holo_odds', jsonb_build_object('none', 0.85, 'silver', 0.08, 'rainbow', 0.04, 'gold', 0.02,
                                    'prism', 0.008, 'galaxy', 0.002))
$$;

create function public._alpha_mode() returns boolean
language sql stable set search_path = '' as $$
  select coalesce((select value = 'true'::jsonb from public.app_config where key = 'alpha_mode'), false)
$$;

create function public.get_home() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'utc')::date;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  return (
    select jsonb_build_object(
      'gems', w.gems,
      'pity', jsonb_build_object('since_epic', coalesce(p.since_epic, 0),
                                 'since_legendary', coalesce(p.since_legendary, 0),
                                 'total_pulls', coalesce(p.total_pulls, 0)),
      'streak', jsonb_build_object('current', s.current, 'best', s.best, 'last_claim', s.last_claim,
                                   'freezes', s.freezes, 'claimed_today', s.last_claim = v_today),
      'total_spent_cents', pr.total_spent_cents,
      'alpha_mode', public._alpha_mode(),
      'created_at', pr.created_at,
      'is_anonymous', coalesce((select u.is_anonymous from auth.users u where u.id = v_uid), false))
    from public.profiles pr
    join public.wallets w on w.user_id = pr.id
    join public.streaks s on s.user_id = pr.id
    left join public.pity p on p.user_id = pr.id
    where pr.id = v_uid);
end $$;

create function public.get_banners() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', b.id, 'name', b.name, 'cost_single', b.cost_single, 'cost_ten', b.cost_ten,
      'ends_at', b.ends_at) || public._published_odds()
    order by b.starts_at desc, b.id), '[]'::jsonb)
  from public.banners b
  where b.starts_at <= now() and (b.ends_at is null or b.ends_at > now())
$$;

create function public.get_set_sizes() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(set_id, n), '{}'::jsonb)
  from (select set_id, count(*) n from public.cards where active group by set_id) t
$$;

-- ALPHA FAUCET: +1600 gems, only while alpha_mode is on, idempotent, capped per day.
create function public.alpha_grant_gems(p_key text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
  v_today_count int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not public._alpha_mode() then raise exception 'alpha mode is off'; end if;
  perform 1 from public.wallets where user_id = v_uid for update;

  select result into v_result from public.idempotency_keys where user_id = v_uid and key = p_key;
  if found then return v_result; end if;

  select count(*) into v_today_count from public.currency_ledger
  where user_id = v_uid and reason = 'alpha'
    and created_at >= (date_trunc('day', now() at time zone 'utc') at time zone 'utc');
  if v_today_count >= 20 then raise exception 'alpha gem limit reached for today'; end if;

  v_result := jsonb_build_object('gems', public._grant_gems(v_uid, 1600, 'alpha', p_key));
  insert into public.idempotency_keys (user_id, key, action, result) values (v_uid, p_key, 'alpha_gems', v_result);
  return v_result;
end $$;

revoke execute on function public._published_odds() from public, anon, authenticated;
revoke execute on function public._alpha_mode() from public, anon, authenticated;
revoke execute on function public.get_home() from public, anon;
revoke execute on function public.get_banners() from public, anon;
revoke execute on function public.get_set_sizes() from public, anon;
revoke execute on function public.alpha_grant_gems(text) from public, anon;
grant execute on function public.get_home() to authenticated;
grant execute on function public.get_banners() to authenticated;
grant execute on function public.get_set_sizes() to authenticated;
grant execute on function public.alpha_grant_gems(text) to authenticated;
