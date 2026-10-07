create type public.rarity as enum ('common','rare','epic','legendary');
create type public.holo_variant as enum ('none','silver','rainbow','gold','prism','galaxy');
create type public.card_source as enum ('pull','wonder_trade','admin','reward');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text check (char_length(display_name) between 1 and 24),
  created_at timestamptz not null default now()
);

create table public.wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  gems integer not null default 0 check (gems >= 0),
  updated_at timestamptz not null default now()
);

create table public.currency_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  delta integer not null,
  balance_after integer not null,
  reason text not null,
  ref text,
  created_at timestamptz not null default now()
);
create index currency_ledger_user_idx on public.currency_ledger (user_id, created_at desc);

create table public.cards (
  id text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null,
  rarity public.rarity not null,
  set_id text not null,
  art_path text not null,
  depth_path text,
  char_path text,
  bg_path text,
  tags text[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index cards_rarity_idx on public.cards (rarity) where active;

create table public.banners (
  id text primary key,
  name text not null,
  cost_single integer not null check (cost_single > 0),
  cost_ten integer not null check (cost_ten > 0),
  starts_at timestamptz not null default now(),
  ends_at timestamptz
);

create table public.banner_cards (
  banner_id text references public.banners(id) on delete cascade,
  card_id text references public.cards(id) on delete cascade,
  primary key (banner_id, card_id)
);

create table public.user_cards (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  card_id text not null references public.cards(id),
  variant public.holo_variant not null default 'none',
  source public.card_source not null,
  tradeable_after timestamptz not null default now(),
  obtained_at timestamptz not null default now()
);
create index user_cards_user_idx on public.user_cards (user_id, card_id);

create table public.pity (
  user_id uuid references public.profiles(id) on delete cascade,
  banner_id text references public.banners(id) on delete cascade,
  since_epic integer not null default 0,
  since_legendary integer not null default 0,
  total_pulls integer not null default 0,
  primary key (user_id, banner_id)
);

create table public.pull_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  banner_id text not null references public.banners(id),
  card_id text not null references public.cards(id),
  rarity public.rarity not null,
  variant public.holo_variant not null,
  pity_triggered boolean not null default false,
  created_at timestamptz not null default now()
);
create index pull_log_user_idx on public.pull_log (user_id, created_at desc);

create table public.streaks (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  current integer not null default 0,
  best integer not null default 0,
  last_claim date,
  freezes integer not null default 0 check (freezes between 0 and 3)
);

create table public.idempotency_keys (
  user_id uuid references public.profiles(id) on delete cascade,
  key text check (char_length(key) between 8 and 64),
  action text not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_id, key)
);

create table public.wonder_pool (
  id bigint generated always as identity primary key,
  card_id text not null references public.cards(id),
  variant public.holo_variant not null,
  rarity public.rarity not null,
  deposited_by uuid references public.profiles(id) on delete set null,
  deposited_at timestamptz not null default now()
);
create index wonder_pool_rarity_idx on public.wonder_pool (rarity, deposited_at);

create table public.trade_log (
  id bigint generated always as identity primary key,
  kind text not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  gave_card_id text not null,
  gave_variant public.holo_variant not null,
  got_card_id text not null,
  got_variant public.holo_variant not null,
  counterparty uuid,
  created_at timestamptz not null default now()
);
create index trade_log_user_idx on public.trade_log (user_id, created_at desc);

-- Row Level Security: clients may only READ their own rows. All writes go through functions.
alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.currency_ledger enable row level security;
alter table public.cards enable row level security;
alter table public.banners enable row level security;
alter table public.banner_cards enable row level security;
alter table public.user_cards enable row level security;
alter table public.pity enable row level security;
alter table public.pull_log enable row level security;
alter table public.streaks enable row level security;
alter table public.idempotency_keys enable row level security;
alter table public.wonder_pool enable row level security;
alter table public.trade_log enable row level security;

create policy "own profile" on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy "own wallet" on public.wallets for select to authenticated using (user_id = (select auth.uid()));
create policy "own ledger" on public.currency_ledger for select to authenticated using (user_id = (select auth.uid()));
create policy "active cards" on public.cards for select to authenticated using (active);
create policy "banners" on public.banners for select to authenticated using (true);
create policy "banner cards" on public.banner_cards for select to authenticated using (true);
create policy "own cards" on public.user_cards for select to authenticated using (user_id = (select auth.uid()));
create policy "own pity" on public.pity for select to authenticated using (user_id = (select auth.uid()));
create policy "own pulls" on public.pull_log for select to authenticated using (user_id = (select auth.uid()));
create policy "own streak" on public.streaks for select to authenticated using (user_id = (select auth.uid()));
create policy "own trades" on public.trade_log for select to authenticated using (user_id = (select auth.uid()));
-- idempotency_keys and wonder_pool: no policies = no client access at all.

-- New signups get a profile, wallet (welcome gems = one 10-pull), and streak row.
create function public._handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id);
  insert into public.wallets (user_id, gems) values (new.id, 1600);
  insert into public.currency_ledger (user_id, delta, balance_after, reason) values (new.id, 1600, 1600, 'welcome');
  insert into public.streaks (user_id) values (new.id);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function public._handle_new_user();

revoke execute on function public._handle_new_user() from public, anon, authenticated;
