extends "res://tests/test_case.gd"
## T-013: soft pity ramp.
##
## The ramp lives in Postgres; this harness has no database (builder rule). So the
## server guards are pinned to the migration source text, and the client copy is
## exercised through Api + PackMath with injected server JSON. Delete a guard in
## the migration and the matching test here FAILS.

const MIGRATIONS_DIR := "res://../supabase/migrations"
const MigV1 := "20261012120000_soft_pity_ramp.sql"
const Venv1 := "20261012120001_soft_pity_ramp_test.sql"
const ApiScript := preload("res://scripts/app/api.gd")
const PackMathScript := preload("res://scripts/app/pack_math.gd")


func _read(path: String) -> String:
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if f == null:
		push_warning("soft pity test cannot read " + path)
		return ""
	return f.get_as_text()


func _squash(s: String) -> String:
	var re := RegEx.new()
	re.compile("\\s+")
	return re.sub(s, " ", true)


func _migration() -> String:
	return _squash(_read(MIGRATIONS_DIR + "/" + MigV1))


func _migration_test() -> String:
	return _squash(_read(MIGRATIONS_DIR + "/" + Venv1))


func _assert_contains(haystack: String, needle: String, why: String) -> void:
	assert_true(haystack.find(needle) >= 0, why + " (missing: " + needle + ")")


# --- server guards -----------------------------------------------------------

func test_migration_defines_the_ramp_table() -> void:
	var sql := _migration()
	_assert_contains(sql, "create table if not exists public.pity_ramp",
		"the ramp must be a data table, not arithmetic in code")
	for col in ["base_pct", "step_pct", "cap_pct"]:
		_assert_contains(sql, col, "pity_ramp carries " + col)


func test_ramp_rows_are_the_agreed_numbers() -> void:
	var sql := _migration()
	_assert_contains(sql, "('epic', 5.0, 0.4, 25.0)", "epic ramp numbers")
	_assert_contains(sql, "('legendary', 1.0, 0.15, 10.0)", "legendary ramp numbers")


func test_roll_rarity_reads_the_ramp_table_and_drops_the_hard_thresholds() -> void:
	var sql := _migration()
	_assert_contains(sql, "from public.pity_ramp where tier = 'epic'",
		"_roll_rarity must read the epic ramp row")
	_assert_contains(sql, "from public.pity_ramp where tier = 'legendary'",
		"_roll_rarity must read the legendary ramp row")
	_assert_contains(sql, "least(base_pct + step_pct", "odds are base + step")
	_assert_contains(sql, "cap_pct", "odds are capped")
	assert_true(sql.find("p_since_epic + 1 >= 10") < 0, "the 10th-pull epic cliff is gone")
	assert_true(sql.find("p_since_legendary + 1 >= 80") < 0, "the 80th-pull legendary cliff is gone")


func test_pull_locks_the_pity_row_for_update() -> void:
	var sql := _migration()
	_assert_contains(sql, "from public.pity where user_id = v_uid for update",
		"the pity row must be locked, or racing pulls skip ramp increments")
	_assert_contains(sql, "from public.wallets where user_id = v_uid for update",
		"the wallet row must be locked, or a pull can double-spend")


func test_counter_reset_is_per_tier() -> void:
	var sql := _migration()
	var leg_at := sql.find("if v_rarity = 'legendary' then")
	var epic_at := sql.find("elsif v_rarity = 'epic' then")
	assert_true(leg_at >= 0 and epic_at > leg_at, "pull() has a legendary branch then an epic branch")
	if leg_at < 0 or epic_at <= leg_at:
		return
	var legendary_branch := sql.substr(leg_at, epic_at - leg_at)
	assert_true(legendary_branch.find("since_legendary := 0") >= 0, "a legendary resets since_legendary")
	assert_true(legendary_branch.find("since_epic := 0") < 0, "a legendary must NOT reset since_epic")

	var else_at := sql.find("else", epic_at)
	assert_true(else_at > epic_at, "pull() has a non-hit else branch")
	if else_at <= epic_at:
		return
	var epic_branch := sql.substr(epic_at, else_at - epic_at)
	assert_true(epic_branch.find("since_epic := 0") >= 0, "an epic resets since_epic")
	assert_true(epic_branch.find("since_legendary := 0") < 0, "an epic must NOT reset since_legendary")


func test_idempotency_and_pull_log_are_unchanged() -> void:
	var sql := _migration()
	_assert_contains(sql, "from public.idempotency_keys where user_id = v_uid and key = p_key", "idempotency read")
	_assert_contains(sql, "insert into public.idempotency_keys", "idempotency write")
	_assert_contains(sql, "insert into public.pull_log", "every pull is still logged")


func test_holo_odds_are_not_touched() -> void:
	var sql := _migration()
	assert_true(sql.find("create or replace function public._roll_variant") < 0,
		"holo variants roll independently of rarity and must not be redefined here")


func test_migration_is_rerunnable() -> void:
	var sql := _migration()
	_assert_contains(sql, "create table if not exists", "table creation is guarded")
	_assert_contains(sql, "on conflict (tier) do update", "ramp rows upsert, so a re-apply is safe")


func test_sql_test_file_covers_the_required_probes() -> void:
	var t := _migration_test()
	assert_true(not t.is_empty(), "the SQL test file must exist")
	for fragment in ["rollback", "for update", "_roll_rarity", "pity_ramp"]:
		_assert_contains(t, fragment, "SQL test covers " + fragment)
	_assert_contains(t, "1000", "SQL test simulates 1000 pulls")


# --- server JSON -> client label ---------------------------------------------

func test_server_ramp_reaches_the_pull_screen() -> void:
	var banners := ApiScript.parse_banners([{
		"id": "standard",
		"odds": {"common": 0.715217, "rare": 0.224783, "epic": 0.05, "legendary": 0.01},
		"pity": {"ramp": {
			"epic": {"base": 0.05, "step": 0.004, "cap": 0.25},
			"legendary": {"base": 0.01, "step": 0.0015, "cap": 0.10},
		}},
	}])
	var text := PackMathScript.pity_text(
		{"since_epic": 5, "since_legendary": 0}, banners[0]["pity"])
	assert_true(text.find("7.0% now") >= 0, "epic odds climbed from the server numbers")
	assert_true(text.find("up to 25.0%") >= 0, "epic cap shown")
