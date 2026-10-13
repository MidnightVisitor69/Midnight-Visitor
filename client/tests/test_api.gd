extends "res://tests/test_case.gd"
## T-005: the API layer and Supabase auth timing. Parsing and the auth
## decisions are pure functions so recorded server JSON can be pinned without a
## network (builder rule: no network calls in tests).

const ApiScript := preload("res://scripts/app/api.gd")
const SupabaseClient := preload("res://scripts/supabase_client.gd")


# --- parse_home -------------------------------------------------------------

func test_parse_home_types_and_nesting() -> void:
	var d := ApiScript.parse_home({
		"gems": 1600,
		"pity": {"since_epic": 7, "since_legendary": 29, "total_pulls": 41},
		"streak": {"current": 3, "best": 9, "last_claim": "2026-10-06",
			"freezes": 1, "claimed_today": false},
		"total_spent_cents": 0,
		"alpha_mode": true,
		"created_at": "2026-10-01T00:00:00Z",
		"is_anonymous": true,
	})
	assert_eq(d["gems"], 1600)
	assert_eq(d["pity"]["since_epic"], 7)
	assert_eq(d["pity"]["since_legendary"], 29)
	assert_eq(d["pity"]["total_pulls"], 41)
	assert_eq(d["streak"]["current"], 3)
	assert_eq(d["streak"]["best"], 9)
	assert_eq(d["streak"]["claimed_today"], false)
	assert_eq(d["total_spent_cents"], 0)
	assert_eq(d["alpha_mode"], true)
	assert_eq(d["is_anonymous"], true)


func test_parse_home_survives_a_missing_payload() -> void:
	var d := ApiScript.parse_home(null)
	assert_eq(d["gems"], 0)
	assert_eq(d["pity"]["since_epic"], 0)
	assert_eq(d["streak"]["current"], 0)
	# Not knowing better, assume anonymous: it only hides account UI.
	assert_eq(d["is_anonymous"], true)


# --- parse_banners ----------------------------------------------------------

func test_parse_banners_rarity_odds_sum_to_one() -> void:
	var banners := ApiScript.parse_banners([{
		"id": "standard",
		"name": "Standard",
		"cost_single": 160,
		"cost_ten": 1600,
		"ends_at": "2027-01-01T00:00:00Z",
		"odds": {"common": 0.7, "rare": 0.2, "epic": 0.08, "legendary": 0.02},
		"pity": {"ramp": {
			"epic": {"base": 0.05, "step": 0.004, "cap": 0.25},
			"legendary": {"base": 0.01, "step": 0.0015, "cap": 0.10},
		}},
		"holo_odds": {"none": 0.85, "silver": 0.08, "rainbow": 0.04,
			"gold": 0.02, "prism": 0.008, "galaxy": 0.002},
	}])
	assert_eq(banners.size(), 1)
	var b: Dictionary = banners[0]
	assert_eq(b["id"], "standard")
	assert_eq(b["cost_single"], 160)
	assert_eq(b["cost_ten"], 1600)
	assert_almost(b["pity"]["ramp"]["epic"]["base"], 0.05, 0.000001, "epic base")
	assert_almost(b["pity"]["ramp"]["epic"]["step"], 0.004, 0.000001, "epic step")
	assert_almost(b["pity"]["ramp"]["epic"]["cap"], 0.25, 0.000001, "epic cap")
	assert_almost(b["pity"]["ramp"]["legendary"]["base"], 0.01, 0.000001, "legendary base")
	var total := 0.0
	for key in ApiScript.ODDS_KEYS:
		total += float(b["odds"][key])
	assert_almost(total, 1.0, 0.0001, "rarity odds must sum to 1")


## T-013: a banner with no ramp on the wire gets an empty ramp, never zeroed
## tiers the UI could mistake for real odds.
func test_parse_banners_never_invents_ramp_numbers() -> void:
	assert_eq(ApiScript.parse_banners([{"id": "standard"}])[0]["pity"]["ramp"], {})


func test_parse_banners_ramp_keeps_only_known_tiers() -> void:
	var banners := ApiScript.parse_banners([{
		"id": "standard",
		"pity": {"ramp": {
			"epic": {"base": 0.05, "step": 0.004, "cap": 0.25},
			"mythic": {"base": 0.5, "step": 0.5, "cap": 0.9},
		}},
	}])
	var ramp: Dictionary = banners[0]["pity"]["ramp"]
	assert_true(ramp.has("epic"), "epic parsed")
	assert_true(not ramp.has("mythic"), "unknown tier dropped, not rendered")


func test_parse_banners_holo_odds_sum_to_one() -> void:
	var banners := ApiScript.parse_banners([{
		"id": "standard",
		"holo_odds": {"none": 0.85, "silver": 0.08, "rainbow": 0.04,
			"gold": 0.02, "prism": 0.008, "galaxy": 0.002},
	}])
	var total := 0.0
	for key in ApiScript.HOLO_KEYS:
		total += float(banners[0]["holo_odds"][key])
	assert_almost(total, 1.0, 0.0001, "holo odds must sum to 1")


func test_parse_banners_ignores_non_array() -> void:
	assert_eq(ApiScript.parse_banners(null).size(), 0)


# --- parse_pull -------------------------------------------------------------

func test_parse_pull_cards_and_pity() -> void:
	var d := ApiScript.parse_pull({
		"cards": [
			{"user_card_id": "u1", "card_id": "c1", "rarity": "epic",
				"variant": "gold", "pity": 0},
			{"user_card_id": "u2", "card_id": "c2", "rarity": "rare",
				"variant": "none", "pity": 1},
		],
		"gems": 1440,
		"pity": {"since_epic": 0, "since_legendary": 1},
	})
	assert_eq(d["gems"], 1440)
	assert_eq(d["pity"]["since_epic"], 0)
	assert_eq(d["pity"]["since_legendary"], 1)
	assert_eq(d["cards"].size(), 2)
	assert_eq(d["cards"][0]["user_card_id"], "u1")
	assert_eq(d["cards"][0]["variant"], "gold")
	assert_eq(d["cards"][1]["rarity"], "rare")
	assert_eq(d["cards"][1]["pity"], 1)


# --- parse_collection -------------------------------------------------------

func test_parse_collection_flattens_the_joined_card() -> void:
	var rows := ApiScript.parse_collection([{
		"id": "u1",
		"card_id": "c1",
		"variant": "silver",
		"obtained_at": "2026-10-06T12:00:00Z",
		"cards": {"name": "Test Card", "rarity": "rare",
			"set_id": "test", "art_path": "test/c1/base.png"},
	}])
	assert_eq(rows.size(), 1)
	var r: Dictionary = rows[0]
	assert_eq(r["id"], "u1")
	assert_eq(r["variant"], "silver")
	assert_eq(r["obtained_at"], "2026-10-06T12:00:00Z")
	assert_eq(r["name"], "Test Card")
	assert_eq(r["rarity"], "rare")
	assert_eq(r["set_id"], "test")
	assert_eq(r["art_path"], "test/c1/base.png")


func test_parse_collection_tolerates_a_missing_join() -> void:
	var rows := ApiScript.parse_collection([{"id": "u1", "card_id": "c1"}])
	assert_eq(rows[0]["name"], "")
	assert_eq(rows[0]["variant"], "none")
	assert_eq(rows[0]["rarity"], "common")


# --- token timing -----------------------------------------------------------

func test_needs_refresh_inside_the_margin() -> void:
	assert_true(SupabaseClient.needs_refresh(1059.0, 1000.0), "59 s left: refresh")
	assert_true(SupabaseClient.needs_refresh(1060.0, 1000.0), "exactly 60 s left: refresh")
	assert_true(SupabaseClient.needs_refresh(1000.0, 1000.0), "expired: refresh")


func test_needs_refresh_outside_the_margin() -> void:
	assert_true(not SupabaseClient.needs_refresh(1061.0, 1000.0), "61 s left: wait")
	assert_true(not SupabaseClient.needs_refresh(9999.0, 1000.0), "far future: wait")


# --- 401 retry --------------------------------------------------------------

func test_should_retry_only_once_on_401() -> void:
	assert_true(SupabaseClient.should_retry(401, false), "first 401 retries")
	assert_true(not SupabaseClient.should_retry(401, true), "no second retry")
	assert_true(not SupabaseClient.should_retry(400, false), "400 is not an auth retry")
	assert_true(not SupabaseClient.should_retry(200, false), "200 never retries")


# --- idempotency wiring -----------------------------------------------------

func test_pull_args_carry_banner_count_and_key() -> void:
	var args := ApiScript.pull_args("standard", 10, "abc123")
	assert_eq(args["p_banner_id"], "standard")
	assert_eq(args["p_count"], 10)
	assert_eq(args["p_key"], "abc123")
