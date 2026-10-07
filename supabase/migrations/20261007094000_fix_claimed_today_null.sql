-- A new player has last_claim = null, and null = today is null, not false; clients would read
-- "unknown" instead of "not claimed yet".
create or replace function public.get_home() returns jsonb
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
                                   'freezes', s.freezes,
                                   'claimed_today', coalesce(s.last_claim = v_today, false)),
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
