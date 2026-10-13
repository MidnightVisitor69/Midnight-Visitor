extends "res://tests/test_case.gd"
## T-006: Home tab (daily claim + pack opening). PackMath is pure, so the odds
## and pity numbers are pinned directly; the view is built offline through
## set_preview_data, which is the same path the screenshot harness uses.
##
## The last two tests are the fault-injection guards the task demands:
##   - an off-by-one in the pity countdown must break the pity test
##   - hiding the odds row must break the visibility test

const PackMathScript := preload("res://scripts/app/pack_math.gd")
const HomeTabScript := preload("res://scripts/app/tabs/home_tab.gd")

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
		since_epic := 0, since_legendary := 0) -> Dictionary:
	return {
		"gems": gems,
		"pity": {"since_epic": since_epic, "since_legendary": since_legendary, "total_pulls": 0},
		"streak": {"current": 1, "best": 1, "freezes": 0, "claimed_today": claimed},
		"alpha_mode": alpha,
	}


func _banner() -> Dictionary:
	return BANNER.duplicate(true)


func _tab(home: Dictionary, banners: Array) -> HomeTabScript:
	var t: HomeTabScript = HomeTabScript.new()
	t.set_preview_data(home, banners)
	return t


# --- PackMath -----------------------------------------------------------------

func test_ramp_odds_at_base() -> void:
	var ramp := {"base": 0.05, "step": 0.004, "cap": 0.25}
	assert_almost(PackMathScript.ramp_odds(ramp, 0), 0.05, 0.000001, "zero pulls -> base")


func test_ramp_odds_climb_with_pity() -> void:
	var ramp := {"base": 0.05, "step": 0.004, "cap": 0.25}
	assert_almost(PackMathScript.ramp_odds(ramp, 10), 0.09, 0.000001, "10 pulls -> 9%")
	assert_true(PackMathScript.ramp_odds(ramp, 10) > PackMathScript.ramp_odds(ramp, 0),
			"odds must climb with pity")


func test_ramp_odds_cap_at_max() -> void:
	var ramp := {"base": 0.05, "step": 0.004, "cap": 0.25}
	assert_almost(PackMathScript.ramp_odds(ramp, 100000), 0.25, 0.000001, "odds cap")


func test_ramp_odds_clamp_a_negative_counter() -> void:
	var ramp := {"base": 0.05, "step": 0.004, "cap": 0.25}
	assert_almost(PackMathScript.ramp_odds(ramp, -3), 0.05, 0.000001, "negative since -> base")


func test_pity_text_reads_the_ramp_in_plain_language() -> void:
	var text := PackMathScript.pity_text(
		{"since_epic": 10, "since_legendary": 0},
		{"ramp": {
			"epic": {"base": 0.05, "step": 0.004, "cap": 0.25},
			"legendary": {"base": 0.01, "step": 0.0015, "cap": 0.10},
		}})
	assert_true(text.find("rise every pull since your last epic") >= 0, "plain language")
	assert_true(text.find("9.0% now") >= 0, "epic odds computed from server numbers")
	assert_true(text.find("up to 25.0%") >= 0, "epic cap from the server")
	assert_true(text.find("1.0% now") >= 0, "legendary odds")
	assert_true(text.find("up to 10.0%") >= 0, "legendary cap")


## Guard: the numbers are the server's. A client that hardcoded the ramp would
## ignore this injected payload.
func test_pity_text_follows_the_server_not_a_client_constant() -> void:
	var text := PackMathScript.pity_text(
		{"since_epic": 0, "since_legendary": 0},
		{"ramp": {
			"epic": {"base": 0.10, "step": 0.02, "cap": 0.40},
			"legendary": {"base": 0.02, "step": 0.01, "cap": 0.20},
		}})
	assert_true(text.find("10.0% now") >= 0, "epic base is the server's 10%")
	assert_true(text.find("up to 40.0%") >= 0, "epic cap is the server's 40%")
	assert_true(text.find("up to 20.0%") >= 0, "legendary cap is the server's 20%")


func test_missing_ramp_says_unavailable_rather_than_guessing() -> void:
	assert_eq(PackMathScript.pity_text({"since_epic": 3}, {}), "Pity odds unavailable.")


## Guard: pack_math.gd formats odds; a ramp step constant appearing there means
## the client started duplicating the server's tuning (T-013).
func test_pack_math_hardcodes_no_ramp_numbers() -> void:
	var f := FileAccess.open("res://scripts/app/pack_math.gd", FileAccess.READ)
	assert_true(f != null, "pack_math.gd must be readable")
	if f == null:
		return
	var src := f.get_as_text()
	for needle in ["0.004", "0.0015"]:
		assert_true(src.find(needle) < 0, "client must not hardcode ramp step " + needle)


func test_percent_format_has_one_decimal() -> void:
	assert_eq(PackMathScript.format_percent(0.015), "1.5%", "holo-ish odds")
	assert_eq(PackMathScript.format_percent(0.7), "70.0%", "common odds")


func test_cards_summary_lists_each_pull() -> void:
	var s := PackMathScript.cards_summary([
		{"card_id": "c1", "variant": "gold"},
		{"card_id": "c2", "variant": "none"},
	])
	assert_true(s.find("c1") >= 0, "first card listed")
	assert_true(s.find("gold") >= 0, "holo variant shown")
	assert_true(s.find("c2") >= 0, "second card listed")


# --- open-button gating -------------------------------------------------------

func test_open_buttons_disable_when_gems_are_short() -> void:
	var t := _tab(_home(100), [_banner()])
	var btns := t.open_buttons()
	assert_true(btns[0].disabled, "single (160) must be disabled with 100 gems")
	assert_true(btns[1].disabled, "ten (1600) must be disabled with 100 gems")
	t.free()


func test_open_buttons_enable_when_gems_cover_both() -> void:
	var t := _tab(_home(1600), [_banner()])
	var btns := t.open_buttons()
	assert_true(not btns[0].disabled, "single must be enabled with 1600 gems")
	assert_true(not btns[1].disabled, "ten must be enabled with 1600 gems")
	t.free()


func test_disabled_button_says_why() -> void:
	var t := _tab(_home(100), [_banner()])
	var btns := t.open_buttons()
	assert_true(btns[0].tooltip_text.find("160") >= 0, "tooltip names the cost")
	t.free()


# --- daily claim --------------------------------------------------------------

func test_claim_button_available_today() -> void:
	var t := _tab(_home(1600), [_banner()])
	assert_true(not t.claim_button().disabled, "claim available")
	assert_eq(t.claim_button().text, "Claim")
	t.free()


func test_claim_button_disabled_when_already_claimed() -> void:
	var t := _tab(_home(1600, true), [_banner()])
	assert_true(t.claim_button().disabled, "already claimed today")
	assert_eq(t.claim_button().text, "Claimed")
	t.free()


# --- alpha faucet -------------------------------------------------------------

func test_faucet_hidden_unless_alpha() -> void:
	var t := _tab(_home(1600, false, false), [_banner()])
	assert_true(not t.faucet_visible(), "faucet hidden when alpha_mode is false")
	t.free()


func test_faucet_visible_in_alpha_mode() -> void:
	var t := _tab(_home(1600, false, true), [_banner()])
	assert_true(t.faucet_visible(), "faucet visible when alpha_mode is true")
	t.free()


# --- odds + pity row ----------------------------------------------------------

func test_odds_and_pity_are_visible_by_default() -> void:
	var t := _tab(_home(), [_banner()])
	assert_true(t.info_row().visible, "info row must be visible, not behind a toggle")
	assert_true(t.odds_visible(), "odds row must be visible, not behind a toggle")
	assert_true(t.odds_text().find("Legendary") >= 0, "odds name every rarity")
	assert_true(t.odds_text().find("%") >= 0, "odds are percentages")
	assert_true(t.pity_text().find("rise every pull") >= 0, "ramp pity shown in plain language")
	assert_true(t.pity_text().find("25.0%") >= 0, "epic ramp cap shown")
	t.free()


func test_home_tab_says_pity_odds_unavailable_without_a_ramp() -> void:
	var banner := _banner()
	banner["pity"] = {}
	var t := _tab(_home(), [banner])
	assert_eq(t.pity_text(), "Pity odds unavailable.")
	t.free()


func test_holo_odds_expand_inline() -> void:
	var t := _tab(_home(), [_banner()])
	assert_true(not t.holo_label_visible(), "holo odds start collapsed")
	t.holo_toggle().button_pressed = true
	assert_true(t.holo_label_visible(), "tapping Holo odds expands it inline")
	assert_true(t.odds_text().find("Legendary") >= 0, "rarity odds stay visible")
	t.free()


# --- banners ------------------------------------------------------------------

func test_banner_arrows_appear_only_for_several_banners() -> void:
	var t := _tab(_home(), [_banner()])
	assert_true(not t.prev_button().visible, "no arrows for a single banner")
	t.free()


func test_arrows_cycle_banners() -> void:
	var second := _banner()
	second["id"] = "event"
	second["name"] = "Event"
	var t := _tab(_home(), [_banner(), second])
	assert_true(t.prev_button().visible, "arrows appear with several banners")
	assert_eq(t.banner_name_text(), "Standard")
	t.next_button().pressed.emit()
	assert_eq(t.banner_name_text(), "Event", "right arrow advances")
	t.free()


# --- screenshots --------------------------------------------------------------

func test_home_tab_exposes_three_screenshot_states() -> void:
	var t: HomeTabScript = HomeTabScript.new()
	assert_eq(t.screenshot_count(), 3)
	t.free()
