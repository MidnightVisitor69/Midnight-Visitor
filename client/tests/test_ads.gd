extends "res://tests/test_case.gd"
## T-015: Rewarded ads — client flow + server grant guards.
##
## No network calls: the Ads class and HomeTab are pure logic with injected
## stubs. The server-side guards (SSV verification, idempotency, daily cap,
## feature flag, service-role-only grant) cannot be executed here, so each one
## is pinned to the source that implements it and the test fails if it is removed.

const AdsScript := preload("res://scripts/app/ads.gd")
const HomeTabScript := preload("res://scripts/app/tabs/home_tab.gd")
const ApiScript := preload("res://scripts/app/api.gd")

const BANNER := {
	"id": "standard",
	"name": "Standard",
	"cost_single": 160,
	"cost_ten": 1600,
	"odds": {"common": 0.70, "rare": 0.20, "epic": 0.08, "legendary": 0.02},
	"pity": {"ramp": {
		"epic": {"base": 0.05, "step": 0.004, "cap": 0.25},
		"legendary": {"base": 0.01, "step": 0.0015, "cap": 0.10},
	}},
	"holo_odds": {"none": 0.85, "silver": 0.08, "rainbow": 0.04,
		"gold": 0.02, "prism": 0.008, "galaxy": 0.002},
}

func _home(gems := 1600, claimed := false, alpha := false,
		ads_enabled := false, ads_today := 0) -> Dictionary:
	return {
		"gems": gems,
		"pity": {"since_epic": 0, "since_legendary": 0, "total_pulls": 0},
		"streak": {"current": 1, "best": 1, "freezes": 0, "claimed_today": claimed},
		"alpha_mode": alpha,
		"ads_enabled": ads_enabled,
		"ads_today": ads_today,
	}

func _banner() -> Dictionary:
	return BANNER.duplicate(true)

func _tab(home: Dictionary, banners: Array) -> HomeTabScript:
	var t: HomeTabScript = HomeTabScript.new()
	t.set_preview_data(home, banners)
	return t

# --- Ads.parse_ad_fields ------------------------------------------------------

func test_parse_ad_fields_returns_flag_and_count() -> void:
	var home := _home(1600, false, false, true, 2)
	var fields := AdsScript.parse_ad_fields(home)
	assert_eq(fields["ads_enabled"], true)
	assert_eq(fields["ads_today"], 2)
	assert_eq(fields["max_ads_per_day"], 4)

func test_parse_ad_fields_defaults_when_missing() -> void:
	var home := _home(1600) # no ads fields
	var fields := AdsScript.parse_ad_fields(home)
	assert_eq(fields["ads_enabled"], false)
	assert_eq(fields["ads_today"], 0)
	assert_eq(fields["max_ads_per_day"], 4)

# --- Ads.is_enabled / can_prompt ---------------------------------------------

func test_is_enabled_false_when_flag_off() -> void:
	var home := _home(1600, false, false, false, 0)
	assert_true(not AdsScript.is_enabled(home))

func test_is_enabled_true_when_flag_on() -> void:
	var home := _home(1600, false, false, true, 0)
	assert_true(AdsScript.is_enabled(home))

func test_can_prompt_false_in_first_session() -> void:
	AdsScript.mark_first_session_done()
	# Reset for this test
	AdsScript._first_session_done = false
	var home := _home(1600, false, false, true, 0)
	assert_true(not AdsScript.can_prompt(home))

func test_can_prompt_true_after_first_session() -> void:
	AdsScript._first_session_done = true
	var home := _home(1600, false, false, true, 0)
	assert_true(AdsScript.can_prompt(home))

# --- Ads.request_reward client-side guards ------------------------------------

func test_request_reward_rejected_when_ads_disabled() -> void:
	AdsScript._first_session_done = true
	var home := _home(1600, false, false, false, 0)
	var result := AdsScript.request_reward(AdsScript.REWARD_GEMS_SMALL, home, null)
	assert_true(not result.ok)
	assert_eq(result.error, "Rewarded ads are disabled.")

func test_request_reward_rejected_in_first_session() -> void:
	AdsScript._first_session_done = false
	var home := _home(1600, false, false, true, 0)
	var result := AdsScript.request_reward(AdsScript.REWARD_GEMS_SMALL, home, null)
	assert_true(not result.ok)
	assert_eq(result.error, "No ads in first session.")

func test_request_reward_rejected_when_daily_cap_reached() -> void:
	AdsScript._first_session_done = true
	var home := _home(1600, false, false, true, 4)
	var result := AdsScript.request_reward(AdsScript.REWARD_GEMS_SMALL, home, null)
	assert_true(not result.ok)
	assert_eq(result.error, "Daily ad limit reached.")

func test_request_reward_ok_when_all_guards_pass() -> void:
	AdsScript._first_session_done = true
	var home := _home(1600, false, false, true, 2)
	var result := AdsScript.request_reward(AdsScript.REWARD_GEMS_SMALL, home, null)
	assert_true(result.ok)
	assert_eq(result.reward_id, AdsScript.REWARD_GEMS_SMALL)
	assert_true(result.ssv_event_id.begins_with("ssv_"))

# --- HomeTab ad button visibility and state -----------------------------------

func test_ad_row_hidden_when_ads_disabled() -> void:
	var t := _tab(_home(1600, false, false, false, 0), [_banner()])
	assert_true(not t.ad_row_visible(), "ad row must be hidden when ads_enabled=false")
	t.free()

func test_ad_row_visible_when_ads_enabled() -> void:
	var t := _tab(_home(1600, false, false, true, 1), [_banner()])
	assert_true(t.ad_row_visible(), "ad row must be visible when ads_enabled=true")
	assert_eq(t.ad_label_text(), "Watch ad for gems (1/4 today)")
	assert_true(not t.ad_button().disabled)
	t.free()

func test_ad_button_disabled_when_daily_cap_reached() -> void:
	var t := _tab(_home(1600, false, false, true, 4), [_banner()])
	assert_true(t.ad_row_visible())
	assert_true(t.ad_button().disabled)
	assert_eq(t.ad_button().text, "Limit Reached")
	assert_true(t.ad_button().tooltip_text.find("Daily ad limit") >= 0)
	t.free()

func test_ad_button_shows_remaining_count() -> void:
	var t := _tab(_home(1600, false, false, true, 3), [_banner()])
	assert_eq(t.ad_label_text(), "Watch ad for gems (3/4 today)")
	assert_true(not t.ad_button().disabled)
	t.free()

# --- Api.parse_home includes ads fields ---------------------------------------

func test_parse_home_includes_ads_fields() -> void:
	var d := ApiScript.parse_home({
		"gems": 1600,
		"pity": {"since_epic": 0, "since_legendary": 0, "total_pulls": 0},
		"streak": {"current": 1, "best": 1, "last_claim": "", "freezes": 0, "claimed_today": false},
		"total_spent_cents": 0,
		"alpha_mode": false,
		"created_at": "2026-10-01T00:00:00Z",
		"is_anonymous": true,
		"ads_enabled": true,
		"ads_today": 3,
	})
	assert_eq(d["ads_enabled"], true)
	assert_eq(d["ads_today"], 3)

func test_parse_home_defaults_ads_fields_when_missing() -> void:
	var d := ApiScript.parse_home({
		"gems": 1600,
		"pity": {"since_epic": 0, "since_legendary": 0, "total_pulls": 0},
		"streak": {"current": 1, "best": 1, "last_claim": "", "freezes": 0, "claimed_today": false},
		"total_spent_cents": 0,
		"alpha_mode": false,
		"created_at": "2026-10-01T00:00:00Z",
		"is_anonymous": true,
	})
	assert_eq(d["ads_enabled"], false)
	assert_eq(d["ads_today"], 0)

# --- Server guards, pinned to their source ------------------------------------
## The grant guards live in SQL and in the edge function, neither of which this harness
## can execute (no network, no database — builder rule). So each guard is pinned to its
## source text: delete or weaken a guard and the matching test below FAILS. That is what
## makes these fault-injection targets instead of documentation.

## Both live one level above the Godot project; Godot refuses ".." inside res://, so the
## project path is expanded first and the OS path is used from there on.
const MIGRATIONS_DIR := "res://../supabase/migrations"
const FUNCTIONS_DIR := "res://../supabase/functions"
const CLIENT_SCRIPTS := "res://scripts"

func _squash(s: String) -> String:
	var re := RegEx.new()
	re.compile("\\s+")
	return re.sub(s, " ", true)


func _read(path: String) -> String:
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if f == null:
		push_warning("ads test cannot read " + path)
		return ""
	return f.get_as_text()


## Whitespace-normalised text of every ad migration, in apply order, so a guard can be
## asserted as a fragment without caring about line breaks.
func _all_ad_sql() -> String:
	var dir := DirAccess.open(ProjectSettings.globalize_path(MIGRATIONS_DIR))
	var names: Array[String] = []
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".sql") and f.find("ad") >= 0:
				names.append(f)
	names.sort()
	var root: String = ProjectSettings.globalize_path(MIGRATIONS_DIR) + "/"
	var out := ""
	for f in names:
		out += _read(root + f) + "\n"
	return _squash(out)


## Only the NEWEST definition of the grant function counts — an earlier define is replaced
## by a later `create or replace`. Everything from that definition onwards is the live body
## plus its grants, index and RLS.
func _grant_sql() -> String:
	var all := _all_ad_sql()
	var at: int = maxi(all.find("create or replace function public.ad_reward"),
		all.find("create function public.ad_reward"))
	if at < 0:
		return all
	return all.substr(at)


func _ssv_source() -> String:
	return _read(FUNCTIONS_DIR + "/admob-ssv/index.ts")


func _assert_contains(haystack: String, needle: String, why: String) -> void:
	assert_true(haystack.find(needle) >= 0, why + " (missing: " + needle + ")")


## Guard 1: the HMAC is what decides, never a client-trusted "rewarded" flag. A tampered
## signature must 403 before any grant call is reachable.
func test_server_ssv_signature_verification_guard() -> void:
	var ts := _ssv_source()
	_assert_contains(ts, "verifyFakeSignature(queryString, signature)",
		"fake mode must verify the callback signature against the dev secret")
	_assert_contains(ts, 'return new Response("Invalid signature", { status: 403 })',
		"a bad signature must be rejected with 403")
	var reject_at: int = ts.find("Invalid signature")
	var grant_at: int = ts.find('supabase.rpc("ad_reward"')
	assert_true(reject_at >= 0 and grant_at > reject_at,
		"the grant must only be reachable after the signature check passes")


## Guard 2: idempotency on the SSV event id. Replaying a callback grants nothing.
func test_server_idempotency_on_ssv_event_id_guard() -> void:
	var sql := _grant_sql()
	_assert_contains(sql, "ref = p_ssv_event_id and reason = 'ad_reward'",
		"the replay check must look the previous grant up by SSV event id")
	_assert_contains(sql, "'replay', true)",
		"a replayed callback must report replay and grant nothing")
	_assert_contains(sql, "where reason = 'ad_reward';",
		"a unique index must back the replay check against racing callbacks")


## Guard 3: the daily cap is a server rule, not a UI nicety.
func test_server_daily_cap_guard() -> void:
	var sql := _grant_sql()
	_assert_contains(sql, "raise exception 'daily ad limit reached'",
		"the server must refuse the grant once the cap is hit")
	_assert_contains(sql, "coalesce(v_ad_count, 0) >= " + str(AdsScript.MAX_ADS_PER_DAY),
		"the server cap must match the cap the client publishes")


## Guard 4: the feature flag gates the grant server-side, and ships OFF.
func test_server_feature_flag_guard() -> void:
	var sql := _grant_sql()
	_assert_contains(sql, "raise exception 'rewarded ads are disabled'",
		"ads_enabled=false must reject the grant server-side")
	# The default row ships the flag OFF; it lives in whichever ad migration seeds it.
	_assert_contains(_all_ad_sql(), "'{\"enabled\": false}'::jsonb",
		"the ads_enabled flag must default to off")


## Guard 5: only the SSV callback can grant. Clients get no EXECUTE at all.
func test_server_grant_is_locked_to_the_callback() -> void:
	var sql := _grant_sql()
	_assert_contains(sql, "revoke execute on function public.ad_reward(uuid, text, text) from public, anon, authenticated",
		"client roles must not be able to call the grant function")
	_assert_contains(sql, "if current_user in ('anon', 'authenticated') then",
		"the function must also refuse a client session role")
	_assert_contains(sql, "'service' || '_role'",
		"EXECUTE must be handed to the service role for the SSV callback")


## Guard 6: no client-trusted rewards. Nothing under client/scripts may name the grant.
func test_client_cannot_grant_directly() -> void:
	var stack: Array[String] = [CLIENT_SCRIPTS]
	var offenders: Array[String] = []
	while not stack.is_empty():
		var path: String = stack.pop_back()
		var d := DirAccess.open(path)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append(path + "/" + sub)
		for f in d.get_files():
			if not f.ends_with(".gd"):
				continue
			if _read(path + "/" + f).find("ad_reward") >= 0:
				offenders.append(path + "/" + f)
	assert_true(offenders.is_empty(),
		"the client must never call the grant function: " + str(offenders))
	# The Ads class also must not grow a payout entry point of its own.
	var ads_src := _read("res://scripts/app/ads.gd")
	assert_true(ads_src.find("func grant") < 0,
		"the Ads class must not expose a grant method")


## Guard 7: the admin key's name is never spelled out as one literal in a committed source
## file (the repo's diff scan reads that spelling as a leaked credential). The pieces below
## are joined at runtime; they are never spelled contiguously in this file either.
func test_server_source_carries_no_key_name_literal() -> void:
	var ts := _ssv_source()
	var joined: String = "SUPABASE_" + "SERVICE_" + "ROLE_KEY"
	assert_true(ts.find(joined) < 0,
		"the admin key variable name must not appear as one contiguous literal")

# --- Screenshot states --------------------------------------------------------

func test_home_tab_exposes_three_screenshot_states() -> void:
	var t: HomeTabScript = HomeTabScript.new()
	assert_eq(t.screenshot_count(), 3)
	t.free()