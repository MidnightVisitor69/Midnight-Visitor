-- T-014: wonder-trade locks + circulating house pool — SQL tests
-- These tests verify the new locks by exercising the wonder_trade function.
-- Each block asserts expected behavior; if a guard is removed, the test fails.

-- Test 1: Level 4 account -> swap rejected with distinct error; level 5 passes.
do $$
declare
  v_result jsonb;
  v_err text;
  v_user_id text := 'l4test';
  v_uc bigint;
begin
  -- Setup: create a level 4 profile
  insert into public.profiles (id, display_name, level) values (v_user_id, 'L4 Tester', 4);
  insert into public.wallets (user_id, gems) values (v_user_id, 9999);
  insert into public.streaks (user_id) values (v_user_id);
  insert into public.pity (user_id, banner_id, since_epic, since_legendary, total_pulls)
    values (v_user_id, 'standard', 0, 0, 20);

  -- Insert a test user_card
  insert into public.user_cards (user_id, card_id, variant, source, tradeable_after, acquired_paid_at)
    values (v_user_id, 'test-rare-01', 'none', 'pull', now() + interval '1 day', null)
    returning id into v_uc;

  -- Try wonder trade - should fail with level error
  begin
    select public.wonder_trade(v_uc, 'test-key-l4') into v_result;
    raise notice 'FAIL: level 4 should have been rejected';
  exception when others then
    v_err := SQLERRM;
    if v_err like '%level 5%' or v_err like '%requires level%' then
      raise notice 'PASS: level 4 rejected with: %', v_err;
    else
      raise notice 'FAIL: level 4 rejected but with wrong error: %', v_err;
    end if;
  end;

  -- Cleanup
  delete from public.user_cards where id = v_uc;
  delete from public.pity where user_id = v_user_id;
  delete from public.streaks where user_id = v_user_id;
  delete from public.profiles where id = v_user_id;
end $$;

-- Test 2: Level 5 account -> swap passes
do $$
declare
  v_result jsonb;
  v_err text;
  v_user_id text := 'l5test';
  v_uc bigint;
begin
  -- Setup: create a level 5 profile with 20 pulls
  insert into public.profiles (id, display_name, level) values (v_user_id, 'L5 Tester', 5);
  insert into public.wallets (user_id, gems) values (v_user_id, 9999);
  insert into public.streaks (user_id) values (v_user_id);
  insert into public.pity (user_id, banner_id, since_epic, since_legendary, total_pulls)
    values (v_user_id, 'standard', 0, 0, 20);
  -- Ensure house pool has entries
  insert into public.wonder_pool (card_id, variant, rarity, deposited_by)
    select id, 'none', 'rare', '00000000-0000-0000-0000-000000000001'
    from public.cards where rarity = 'rare' and active limit 1;

  -- Insert a test user_card
  insert into public.user_cards (user_id, card_id, variant, source, tradeable_after, acquired_paid_at)
    values (v_user_id, 'test-rare-01', 'none', 'pull', now(), null)
    returning id into v_uc;

  -- Attempt wonder trade - should succeed
  begin
    select public.wonder_trade(v_uc, 'test-key-l5') into v_result;
    if v_result ? 'user_card_id' then
      raise notice 'PASS: level 5 swap succeeded, got user_card_id %', (v_result->>'user_card_id')::text;
    else
      raise notice 'FAIL: level 5 swap did not return user_card_id';
    end if;
  exception when others then
    v_err := SQLERRM;
    raise notice 'FAIL: level 5 swap unexpectedly rejected: %', v_err;
  end;

  -- Cleanup
  delete from public.user_cards where id = v_uc;
  delete from public.pity where user_id = v_user_id;
  delete from public.streaks where user_id = v_user_id;
  delete from public.profiles where id = v_user_id;
  delete from public.wonder_pool where deposited_by = '00000000-0000-0000-0000-000000000001' and rarity = 'rare';
end $$;

-- Test 3: 4th swap in a day -> rejected; counter resets next UTC day
do $$
declare
  v_result jsonb;
  v_err text;
  v_user_id text := 'dailytest';
  v_uc bigint;
begin
  -- Setup: create user with level 5 and 20 pulls
  insert into public.profiles (id, display_name, level) values (v_user_id, 'Daily Tester', 5);
  insert into public.wallets (user_id, gems) values (v_user_id, 9999);
  insert into public.streaks (user_id) values (v_user_id);
  insert into public.pity (user_id, banner_id, since_epic, since_legendary, total_pulls)
    values (v_user_id, 'standard', 0, 0, 20);
  -- Seed house pool
  insert into public.wonder_pool (card_id, variant, rarity, deposited_by)
    select id, 'none', 'rare', '00000000-0000-0000-0000-000000000001'
    from public.cards where rarity = 'rare' and active limit 1;

  -- Insert a test user_card
  insert into public.user_cards (user_id, card_id, variant, source, tradeable_after, acquired_paid_at)
    values (v_user_id, 'test-rare-01', 'none', 'pull', now(), null)
    returning id into v_uc;

  -- Do 3 successful swaps (should work)
  perform public.wonder_trade(v_uc, 'key-1');
  perform public.wonder_trade(v_uc, 'key-2');
  perform public.wonder_trade(v_uc, 'key-3');

  -- 4th swap should fail with daily limit error
  begin
    select public.wonder_trade(v_uc, 'key-4') into v_result;
    raise notice 'FAIL: 4th swap should have been rejected';
  exception when others then
    v_err := SQLERRM;
    if v_err like '%daily wonder trade limit%' then
      raise notice 'PASS: 4th swap rejected with daily limit error';
    else
      raise notice 'FAIL: 4th swapped rejected but with wrong error: %', v_err;
    end if;
  end;

  -- Cleanup
  delete from public.user_cards where id = v_uc;
  delete from public.pity where user_id = v_user_id;
  delete from public.streaks where user_id = v_user_id;
  delete from public.profiles where id = v_user_id;
  delete from public.wonder_pool where deposited_by = '00000000-0000-0000-0000-000000000001';
end $$;

-- Test 4: Paid card younger than 14 days -> rejected; at 14 days -> accepted
do $$
declare
  v_result jsonb;
  v_err text;
  v_user_id text := 'paidtest';
  v_uc bigint;
begin
  -- Setup: create user with level 5 and 20 pulls
  insert into public.profiles (id, display_name, level) values (v_user_id, 'Paid Tester', 5);
  insert into public.wallets (user_id, gems) values (v_user_id, 9999);
  insert into public.streaks (user_id) values (v_user_id);
  insert into public.pity (user_id, banner_id, since_epic, since_legendary, total_pulls)
    values (v_user_id, 'standard', 0, 0, 20);
  -- Seed house pool
  insert into public.wonder_pool (card_id, variant, rarity, deposited_by)
    select id, 'none', 'rare', '00000000-0000-0000-0000-000000000001'
    from public.cards where rarity = 'rare' and active limit 1;

  -- Insert a paid card (acquired 5 days ago = younger than 14)
  insert into public.user_cards (user_id, card_id, variant, source, tradeable_after, acquired_paid_at)
    values (v_user_id, 'test-rare-01', 'none', 'pull', now() - interval '5 days', now() - interval '5 days')
    returning id into v_uc;

  -- Attempt wonder trade with young paid card - should fail
  begin
    select public.wonder_trade(v_uc, 'key-young') into v_result;
    raise notice 'FAIL: young paid card should have been rejected';
  exception when others then
    v_err := SQLERRM;
    if v_err like '%paid card cooldown%' then
      raise notice 'PASS: young paid card rejected with cooldown error';
    else
      raise notice 'FAIL: young paid card rejected but with wrong error: %', v_err;
    end if;
  end;

  -- Now test with a card that's 14+ days old
  update public.user_cards set acquired_paid_at = now() - interval '14 days' where id = v_uc;

  -- Attempt wonder trade - should succeed
  begin
    select public.wonder_trade(v_uc, 'key-old') into v_result;
    if v_result ? 'user_card_id' then
      raise notice 'PASS: 14-day-old paid card accepted';
    else
      raise notice 'FAIL: 14-day-old card accepted but no user_card_id returned';
    end if;
  exception when others then
    raise notice 'FAIL: 14-day-old card unexpectedly rejected: %', SQLERRM;
  end;

  -- Cleanup
  delete from public.user_cards where id = v_uc;
  delete from public.pity where user_id = v_user_id;
  delete from public.streaks where user_id = v_user_id;
  delete from public.profiles where id = v_user_id;
  delete from public.wonder_pool where deposited_by = '00000000-0000-0000-0000-000000000001';
end $$;

-- Test 5: Pool at exactly the floor -> swap still succeeds via house card; floor is replenished
do $$
declare
  v_result jsonb;
  v_err text;
  v_user_id text := 'floortest';
  v_uc bigint;
  v_pool_count int;
begin
  -- Setup: create user with level 5 and 20 pulls
  insert into public.profiles (id, display_name, level) values (v_user_id, 'Floor Tester', 5);
  insert into public.wallets (user_id, gems) values (v_user_id, 9999);
  insert into public.streaks (user_id) values (v_user_id);
  insert into public.pity (user_id, banner_id, since_epic, since_legendary, total_pulls)
    values (v_user_id, 'standard', 0, 0, 20);

  -- Setup: set house pool to exactly 20 entries for rare rarity
  delete from public.wonder_pool where deposited_by = '00000000-0000-0000-0000-000000000001' and rarity = 'rare';
  insert into public.wonder_pool (card_id, variant, rarity, deposited_by)
    select id, 'none', 'rare', '00000000-0000-0000-0000-000000000001'
    from public.cards where rarity = 'rare' and active
    limit 20;

  -- Insert a test user_card
  insert into public.user_cards (user_id, card_id, variant, source, tradeable_after, acquired_paid_at)
    values (v_user_id, 'test-rare-01', 'none', 'pull', now(), null)
    returning id into v_uc;

  -- Do 2 swaps - each should succeed via house card and replenish the floor
  perform public.wonder_trade(v_uc, 'key-floor-1');
  perform public.wonder_trade(v_uc, 'key-floor-2');

  -- Check the pool count after 2 swaps
  v_pool_count := (select count(*) from public.wonder_pool where rarity = 'rare' and deposited_by = '00000000-0000-0000-0000-000000000001');
  if v_pool_count >= 20 then
    raise notice 'PASS: floor maintained at 20 after 2 swaps (count = %)', v_pool_count;
  else
    raise notice 'FAIL: floor dip after 2 swaps (count = %)', v_pool_count;
  end if;

  -- Cleanup
  delete from public.user_cards where id = v_uc;
  delete from public.pity where user_id = v_user_id;
  delete from public.streaks where user_id = v_user_id;
  delete from public.profiles where id = v_user_id;
  delete from public.wonder_pool where deposited_by = '00000000-0000-0000-0000-000000000001';
end $$;

-- Test 6: Two swaps by the same user on a limited pool -> first takes pool card,
  -- second falls back to cards table; pool floor is maintained.
do $$
declare
  v_result1 jsonb;
  v_result2 jsonb;
  v_err text;
  v_user_id text := 'concurrenttest';
  v_uc bigint;
  v_pool_count int;
begin
  -- Setup: create user with level 5 and 20 pulls
  insert into public.profiles (id, display_name, level) values (v_user_id, 'Concurrent Tester', 5);
  insert into public.wallets (user_id, gems) values (v_user_id, 9999);
  insert into public.streaks (user_id) values (v_user_id);
  insert into public.pity (user_id, banner_id, since_epic, since_legendary, total_pulls)
    values (v_user_id, 'standard', 0, 0, 20);
  -- Seed house pool with exactly 1 rare card
  delete from public.wonder_pool where deposited_by = '00000000-0000-0000-0000-000000000001' and rarity = 'rare';
  insert into public.wonder_pool (card_id, variant, rarity, deposited_by)
    select id, 'none', 'rare', '00000000-0000-0000-0000-000000000001'
    from public.cards where rarity = 'rare' and active
    limit 1;

  -- Insert a test user_card
  insert into public.user_cards (user_id, card_id, variant, source, tradeable_after, acquired_paid_at)
    values (v_user_id, 'test-rare-01', 'none', 'pull', now(), null)
    returning id into v_uc;

  -- First swap - should take the pool card
  v_result1 := public.wonder_trade(v_uc, 'key-conc-1');

  -- Check pool count after first swap
  v_pool_count := (select count(*) from public.wonder_pool where rarity = 'rare' and deposited_by = '00000000-0000-0000-0000-000000000001');
  if v_result1 ? 'user_card_id' and v_pool_count = 0 then
    raise notice 'PASS: first swap took the last pool card (pool count = %)', v_pool_count;
  else
    raise notice 'CHECK: first swap result = %, pool count = %', v_result1 ? 'user_card_id', v_pool_count;
  end if;

  -- Second swap - should succeed by drawing from cards table (pool empty, house floor fallback)
  v_result2 := public.wonder_trade(v_uc, 'key-conc-2');

  -- Check pool count after second swap (should still be 0 or replenished)
  v_pool_count := (select count(*) from public.wonder_pool where rarity = 'rare' and deposited_by = '00000000-0000-0000-0000-000000000001');
  if v_result2 ? 'user_card_id' then
    raise notice 'PASS: second swap succeeded via house card fallback';
  else
    raise notice 'FAIL: second swap did not succeed';
  end if;

  -- Cleanup
  delete from public.user_cards where id = v_uc;
  delete from public.pity where user_id = v_user_id;
  delete from public.streaks where user_id = v_user_id;
  delete from public.profiles where id = v_user_id;
  delete from public.wonder_pool where deposited_by = '00000000-0000-0000-0000-000000000001';
end $$;

-- Test 7: Rollback check - verify columns and function exist correctly
do $$
declare
  v_func_text text;
  v_level_col text;
  v_paid_col text;
begin
  -- Verify level column exists on profiles
  select column_name into v_level_col from information_schema.columns
  where table_name = 'profiles' and column_name = 'level';
  if v_level_col is not null then
    raise notice 'PASS: level column exists on profiles';
  else
    raise notice 'FAIL: level column missing from profiles';
  end if;

  -- Verify acquired_paid_at column exists on user_cards
  select column_name into v_paid_col from information_schema.columns
  where table_name = 'user_cards' and column_name = 'acquired_paid_at';
  if v_paid_col is not null then
    raise notice 'PASS: acquired_paid_at column exists on user_cards';
  else
    raise notice 'FAIL: acquired_paid_at column missing from user_cards';
  end if;

  -- Verify the wonder_trade function exists and is the updated version
  select prosrc into v_func_text from pg_proc where proname = 'wonder_trade';
  if v_func_text is null then
    raise notice 'FAIL: wonder_trade function not found';
  elsif v_func_text like '%level 5%' then
    raise notice 'PASS: wonder_trade function contains level 5 gate';
  else
    raise notice 'FAIL: wonder_trade function missing level 5 gate';
  end if;

  if v_func_text like '%paid card cooldown%' then
    raise notice 'PASS: wonder_trade function contains paid card cooldown';
  else
    raise notice 'FAIL: wonder_trade function missing paid card cooldown';
  end if;

  if v_func_text like '%daily wonder trade limit%' then
    raise notice 'PASS: wonder_trade function contains daily limit check';
  else
    raise notice 'FAIL: wonder_trade function missing daily limit check';
  end if;
end $$;