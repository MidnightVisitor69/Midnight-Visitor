-- Google Play requires in-app account deletion. Deleting the auth user cascades to every
-- player-owned table (profiles -> wallets, user_cards, ledger, pity, streaks, ...).
-- trade_log keeps other players' history intact: rows the player authored cascade away,
-- and their id stays only as an anonymous uuid in other players' counterparty column.
create function public.delete_my_account() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  delete from auth.users where id = v_uid;
  return jsonb_build_object('deleted', true);
end $$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
