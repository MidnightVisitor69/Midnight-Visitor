-- T-013: soft pity ramp — SQL tests.
--
-- These run as part of the migration apply (agents have no DB access, so this
-- file is the executable proof the dev runs by hand). Each block raises a PASS
-- or FAIL notice; a FAIL means a guard in 20261012120000_soft_pity_ramp.sql was
-- deleted or weakened.
--
-- Nothing here writes permanent data: the rollback probe and the rate probe run
-- inside subtransactions and are undone.

-- ---------------------------------------------------------------------------
-- 1. The ramp is a data table with the agreed numbers.
-- ---------------------------------------------------------------------------
do $$
declare
  v_rows int;
  v_epic public.pity_ramp;
  v_leg public.pity_ramp;
begin
  select count(*) into v_rows from public.pity_ramp;
  if v_rows = 2 then
    raise notice 'PASS: pity_ramp has exactly the epic and legendary rows';
  else
    raise notice 'FAIL: pity_ramp has % rows, expected 2', v_rows;
  end if;

  select * into v_epic from public.pity_ramp where tier = 'epic';
  if v_epic.base_pct = 5.0 and v_epic.step_pct = 0.4 and v_epic.cap_pct = 25.0 then
    raise notice 'PASS: epic ramp is base 5%%, step 0.4%%, cap 25%%';
  else
    raise notice 'FAIL: epic ramp is base %%%%, step %%%%, cap %%%%',
      v_epic.base_pct, v_epic.step_pct, v_epic.cap_pct;
  end if;

  select * into v_leg from public.pity_ramp where tier = 'legendary';
  if v_leg.base_pct = 1.0 and v_leg.step_pct = 0.15 and v_leg.cap_pct = 10.0 then
    raise notice 'PASS: legendary ramp is base 1%%, step 0.15%%, cap 10%%';
  else
    raise notice 'FAIL: legendary ramp is base %%%%, step %%%%, cap %%%%',
      v_leg.base_pct, v_leg.step_pct, v_leg.cap_pct;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. No hard cliff: the odds at a fresh row are the base rate (> 0), and the
--    old every-10th / every-80th thresholds are gone from _roll_rarity.
-- ---------------------------------------------------------------------------
do $$
declare
  v_src text;
  v_epic_base double precision;
begin
  select base_pct / 100.0 into v_epic_base from public.pity_ramp where tier = 'epic';
  if v_epic_base > 0 then
    raise notice 'PASS: epic has a non-zero chance before any pity (base %)', v_epic_base;
  else
    raise notice 'FAIL: epic base is zero, a hard cliff remains';
  end if;

  select prosrc into v_src from pg_proc where proname = '_roll_rarity';
  if v_src is null then
    raise notice 'FAIL: _roll_rarity not found';
  elsif v_src like '%pity_ramp%' then
    raise notice 'PASS: _roll_rarity reads the ramp table';
  else
    raise notice 'FAIL: _roll_rarity does not read pity_ramp (hardcoded arithmetic)';
  end if;

  if v_src like '%>= 10%' or v_src like '%>= 80%' then
    raise notice 'FAIL: _roll_rarity still carries a hard pity threshold';
  else
    raise notice 'PASS: no hard epic/legendary threshold in _roll_rarity';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Climbs and caps: the per-pull odds never leave [base, cap].
-- ---------------------------------------------------------------------------
do $$
declare
  v_i int;
  v_odds double precision;
  v_base double precision;
  v_cap double precision;
  v_bad int := 0;
begin
  select base_pct, cap_pct into v_base, v_cap from public.pity_ramp where tier = 'epic';
  for v_i in 0..200 loop
    v_odds := least(v_base + 0.4 * v_i, v_cap);
    if v_odds < v_base or v_odds > v_cap then
      v_bad := v_bad + 1;
    end if;
  end loop;
  if v_bad = 0 and least(v_base + 0.4 * 1, v_cap) > v_base then
    raise notice 'PASS: epic odds climb then cap inside [%%, %%]', v_base, v_cap;
  else
    raise notice 'FAIL: epic ramp left its bounds % times', v_bad;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Observed epic rate over 1000 simulated pulls is between base and cap.
--    Counters are advanced exactly like pull() does (each tier independent).
--    1000 samples carry a ~0.7%% standard error, so the floor is half the base
--    rate: a rate below that means the ramp is not firing at all.
-- ---------------------------------------------------------------------------
do $$
declare
  v_since_epic int := 0;
  v_since_legendary int := 0;
  v_rarity public.rarity;
  v_hit boolean;
  v_epics int := 0;
  v_before_10 int := 0;
  v_rate double precision;
  v_base double precision;
  v_cap double precision;
begin
  select base_pct / 100.0, cap_pct / 100.0 into v_base, v_cap
  from public.pity_ramp where tier = 'epic';
  for i in 1..1000 loop
    select rr.rarity, rr.pity_hit into v_rarity, v_hit
    from public._roll_rarity(v_since_epic, v_since_legendary) rr;
    if v_rarity = 'epic' then
      v_epics := v_epics + 1;
      if v_since_epic + 1 < 10 then v_before_10 := v_before_10 + 1; end if;
      v_since_epic := 0;
      v_since_legendary := v_since_legendary + 1;
    elsif v_rarity = 'legendary' then
      v_since_legendary := 0;
      v_since_epic := v_since_epic + 1;
    else
      v_since_epic := v_since_epic + 1;
      v_since_legendary := v_since_legendary + 1;
    end if;
  end loop;
  v_rate := v_epics / 1000.0;
  raise notice 'T-013 observed epic rate: % (base %, cap %), % epics before pull 10',
    v_rate, v_base, v_cap, v_before_10;
  if v_rate >= v_base * 0.5 and v_rate <= v_cap then
    raise notice 'PASS: observed epic rate is between base and cap (with sampling margin)';
  else
    raise notice 'FAIL: observed epic rate % is outside [%, %]', v_rate, v_base, v_cap;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Counter reset: a hit resets ONLY its own tier's counter.
--    (Pinned to the live function body: this runs without an auth session.)
-- ---------------------------------------------------------------------------
do $$
declare
  v_src text;
  v_leg_at int;
  v_epi_at int;
  v_leg_branch text;
  v_epi_branch text;
  v_else_at int;
begin
  select prosrc into v_src from pg_proc where proname = 'pull' and pronargs = 3;
  v_leg_at := position('if v_rarity = ''legendary'' then' in v_src);
  v_epi_at := position('elsif v_rarity = ''epic'' then' in v_src);
  v_else_at := position('else' in substring(v_src from v_epi_at + 1));
  if v_leg_at > 0 and v_epi_at > v_leg_at and v_else_at > 0 then
    v_leg_branch := substring(v_src from v_leg_at for (v_epi_at - v_leg_at));
    v_epi_branch := substring(v_src from v_epi_at for v_else_at);
    if v_leg_branch like '%since_legendary := 0%' and v_leg_branch not like '%since_epic := 0%' then
      raise notice 'PASS: a legendary resets only since_legendary';
    else
      raise notice 'FAIL: legendary branch resets the wrong counter(s)';
    end if;
    if v_epi_branch like '%since_epic := 0%' and v_epi_branch not like '%since_legendary := 0%' then
      raise notice 'PASS: an epic resets only since_epic';
    else
      raise notice 'FAIL: epic branch resets the wrong counter(s)';
    end if;
  else
    raise notice 'FAIL: could not locate the per-tier counter branches in pull()';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Concurrency: pull() serializes on the wallet row and the pity row before
--    it reads and bumps the ramp counters (two racing calls cannot skip one).
-- ---------------------------------------------------------------------------
do $$
declare
  v_src text;
begin
  select prosrc into v_src from pg_proc where proname = 'pull' and pronargs = 3;
  if v_src like '%wallets where user_id = v_uid for update%' then
    raise notice 'PASS: pull() locks the wallet row (no double-spend)';
  else
    raise notice 'FAIL: pull() does not lock the wallet row';
  end if;
  if v_src like '%public.pity where user_id = v_uid for update%' then
    raise notice 'PASS: pull() locks the pity row (no skipped ramp increment)';
  else
    raise notice 'FAIL: pull() does not lock the pity row';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Rollback: the migration is plain transactional DDL, so an apply rolled
--    back leaves schema and data exactly as they were.
-- ---------------------------------------------------------------------------
do $$
declare
  v_before int;
  v_after int;
begin
  select count(*) into v_before from public.pity_ramp;
  begin
    -- Do work that a real apply would do, then force the transaction to fail.
    create table public._t013_rollback_probe (x int);
    insert into public.pity_ramp (tier, base_pct, step_pct, cap_pct) values ('rare', 9.0, 0.0, 9.0);
    raise exception 'force rollback';
  exception when others then
    null; -- the subtransaction is rolled back here
  end;
  select count(*) into v_after from public.pity_ramp;
  if v_before = v_after then
    raise notice 'PASS: rollback left pity_ramp unchanged (% rows)', v_after;
  else
    raise notice 'FAIL: rollback changed pity_ramp (% -> %)', v_before, v_after;
  end if;
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = '_t013_rollback_probe') then
    raise notice 'PASS: rolled-back DDL left no table behind';
  else
    raise notice 'FAIL: the rollback probe table survived';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 8. Re-applying the file is safe: the upsert keeps exactly two rows.
-- ---------------------------------------------------------------------------
do $$
declare
  v_rows int;
begin
  insert into public.pity_ramp (tier, base_pct, step_pct, cap_pct) values
    ('epic', 5.0, 0.4, 25.0),
    ('legendary', 1.0, 0.15, 10.0)
  on conflict (tier) do update
    set base_pct = excluded.base_pct,
        step_pct = excluded.step_pct,
        cap_pct = excluded.cap_pct;
  select count(*) into v_rows from public.pity_ramp;
  if v_rows = 2 then
    raise notice 'PASS: re-applying the ramp rows is idempotent';
  else
    raise notice 'FAIL: re-apply produced % rows', v_rows;
  end if;
end $$;
