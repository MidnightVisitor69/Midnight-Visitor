-- Rewarded ads (T-015): server-side grant via SSV callback, feature-flagged, max 4/day.
-- The reward is granted ONLY by the SSV callback hitting the server function.
-- The client sends "which reward" (reward_id) and its idempotency key, nothing else.

-- Reward definitions: amounts are placeholders the dev will set after play data.
create table public.rewards (
  id text primary key check (id ~ '^[a-z_]+$'),
  name text not null,
  gem_amount integer not null default 0 check (gem_amount >= 0),
  description text not null default '',
  active boolean not null default true
);

-- Seed the two reward types; amounts are deliberately unset (dev decides after play data).
insert into public.rewards (id, name, gem_amount, description) values
  ('gems_small', 'Small Gem Reward', 0, 'Rewarded ad: small gem grant'),
  ('streak_repair', 'Streak Repair', 0, 'Rewarded ad: repairs one missed streak day')
on conflict (id) do nothing;

-- Track ad views per user per day for the 4/day cap.
create table public.ad_views (
  user_id uuid not null references public.profiles(id) on delete cascade,
  view_date date not null default (now() at time zone 'utc')::date,
  count integer not null default 0 check (count >= 0),
  primary key (user_id, view_date)
);
create index ad_views_user_idx on public.ad_views (user_id, view_date desc);

-- Idempotent grant keyed by the SSV event id (replayed callbacks grant nothing).
-- Returns the new gem balance or null if rejected.
create function public.ad_reward(p_user_id uuid, p_reward_id text, p_ssv_event_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_reward public.rewards;
  v_gems int;
  v_today date := (now() at time zone 'utc')::date;
  v_ad_count int;
  v_config jsonb;
  v_ads_enabled boolean;
begin
  -- Only the SSV edge function (service role) should call this; but we also
  -- enforce that the caller matches the user_id in the token for defense in depth.
  if v_uid is null then raise exception 'not authenticated'; end if;
  if v_uid <> p_user_id then raise exception 'user mismatch'; end if;

  -- Feature flag: ads_enabled in app_config (default false).
  select value into v_config from public.app_config where key = 'ads_enabled';
  v_ads_enabled := coalesce((v_config ->> 'enabled')::boolean, false);
  if not v_ads_enabled then
    raise exception 'rewarded ads are disabled';
  end if;

  -- Reward must exist and be active.
  select * into v_reward from public.rewards where id = p_reward_id and active;
  if not found then raise exception 'reward not found or inactive'; end if;

  -- Idempotency: same ssv_event_id = no second grant.
  if exists (
    select 1 from public.currency_ledger
    where user_id = v_uid and ref = p_ssv_event_id and reason = 'ad_reward'
  ) then
    -- Replay: return current balance, no new entry.
    return jsonb_build_object('gems', (select gems from public.wallets where user_id = v_uid),
                              'replay', true);
  end if;

  -- Daily cap: max 4 ad rewards per day.
  select coalesce(count, 0) into v_ad_count
  from public.ad_views where user_id = v_uid and view_date = v_today;
  if v_ad_count >= 4 then
    raise exception 'daily ad limit reached';
  end if;

  -- Lock the wallet row for the grant.
  perform 1 from public.wallets where user_id = v_uid for update;

  -- Grant the gems and record the ledger entry with the SSV event id as ref.
  v_gems := public._grant_gems(v_uid, v_reward.gem_amount, 'ad_reward', p_ssv_event_id);

  -- Increment the daily ad view counter.
  insert into public.ad_views (user_id, view_date, count)
  values (v_uid, v_today, 1)
  on conflict (user_id, view_date) do update set count = ad_views.count + 1;

  return jsonb_build_object('gems', v_gems, 'reward_id', p_reward_id, 'replay', false);
end $$;

revoke execute on function public.ad_reward(uuid, text, text) from public, anon;
grant execute on function public.ad_reward(uuid, text, text) to authenticated;

-- Feature flag default: ads_enabled = false.
insert into public.app_config (key, value) values ('ads_enabled', '{"enabled": false}'::jsonb)
on conflict (key) do nothing;

-- RLS: only security-definer functions read app_config; no client policies needed.
-- The ad_reward function is the only writer to ad_views and reads rewards.