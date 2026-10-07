-- Pity carries across ALL banners so switching banners never wastes progress.
drop table public.pity;
create table public.pity (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  since_epic integer not null default 0,
  since_legendary integer not null default 0,
  total_pulls integer not null default 0
);
alter table public.pity enable row level security;
create policy "own pity" on public.pity for select to authenticated using (user_id = (select auth.uid()));

-- Shown to the player in settings: lifetime real-money spend.
alter table public.profiles add column total_spent_cents integer not null default 0 check (total_spent_cents >= 0);

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

  perform 1 from public.wallets where user_id = v_uid for update;

  select result into v_result from public.idempotency_keys where user_id = v_uid and key = p_key;
  if found then return v_result; end if;

  select * into v_banner from public.banners
  where id = p_banner_id and starts_at <= now() and (ends_at is null or ends_at > now());
  if not found then raise exception 'banner not available'; end if;

  v_gems := public._spend_gems(v_uid,
    case when p_count = 1 then v_banner.cost_single else v_banner.cost_ten end, 'pull', p_banner_id);

  insert into public.pity (user_id) values (v_uid) on conflict do nothing;
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
  where user_id = v_uid;

  v_result := jsonb_build_object('cards', v_cards, 'gems', v_gems,
    'pity', jsonb_build_object('since_epic', v_pity.since_epic, 'since_legendary', v_pity.since_legendary));
  insert into public.idempotency_keys (user_id, key, action, result) values (v_uid, p_key, 'pull', v_result);
  return v_result;
end $$;

revoke execute on function public.pull(text, int, text) from public, anon;
grant execute on function public.pull(text, int, text) to authenticated;
