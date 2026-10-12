-- Shop prices published server-side via app_config (T-017)
-- Prices are the dev-approved price sheet; never hardcode in client.

-- Insert/upsert the approved price sheet into app_config.
-- This uses the existing app_config table created in T-003 / prototype reads.
insert into public.app_config (key, value) values (
  'shop_prices',
  '{"pull_single":100,"pull_ten":900,"packs":[{"id":"pocketful","usd_cents":99,"gems":80,"first_buy_double_gems":160},{"id":"wallet","usd_cents":499,"gems":500,"first_buy_double_gems":1000},{"id":"safe","usd_cents":999,"gems":1100,"first_buy_double_gems":2200},{"id":"vault","usd_cents":1999,"gems":2400,"first_buy_double_gems":4800}],"monthly_pass":{"usd_cents":499,"days":30,"upfront_gems":300,"daily_gems":120,"bank_missed_days":false},"ad_free_pass":{"usd_cents":299,"one_time":true},"streak_repair":{"gem_cost":60,"max_held":2,"ad_repairs_per_month":1},"ads":{"max_per_day":4,"gems_per_ad":null}}'::jsonb
) on conflict (key) do update set value = excluded.value, updated_at = now();

-- Security-definer function that returns the shop_prices jsonb value.
-- Mirrors the pattern of is_alpha() / get_home(): security definer so anon/authenticated
-- can read it without RLS policies on app_config itself.
create function public.get_shop() returns jsonb
language sql stable set search_path = public
as $$
  select value from public.app_config where key = 'shop_prices'
$$;

-- Revoke public execute; only authenticated and anon can read via definer.
revoke execute on function public.get_shop() from public, anon, authenticated;
grant execute on function public.get_shop() to authenticated;
grant execute on function public.get_shop() to anon;