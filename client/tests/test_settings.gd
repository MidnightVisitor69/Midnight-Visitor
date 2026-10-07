extends "res://tests/test_case.gd"
## T-009: what the Trade tab and the (design-lane) Settings screen share.
##
## Settings itself is built by the design lane (D-003), so this task adds only
## its pure money helper, Format.cents_to_text, plus the app version tag. The
## tests that pin them live here so the trade placeholder and the money format
## are covered by one file.
##
## Fault-injection guards are marked "Guard:"; each one fails when its guard is
## removed:
##   - the modulo that carries the cents (integer division alone fails $1.99)
##   - the clamp on the pull progress (35 pulls would read 35/20)
##   - is_debug hiding the holo bench in a release build
##   - the tab shipping no button until Wonder Trade exists

const FormatScript := preload("res://scripts/app/format.gd")
const TradeTabScript := preload("res://scripts/app/tabs/trade_tab.gd")
const AppShellScript := preload("res://scripts/app/app_shell.gd")

const APP_VERSION := "0.1.0-alpha"
const HOLO_BUTTON := "TopBar/Row/HoloTestButton"


# --- money format ------------------------------------------------------------

func test_cents_format_as_dollars_and_cents() -> void:
	assert_eq(FormatScript.cents_to_text(0), "$0.00", "lifetime spend, nothing bought")
	assert_eq(FormatScript.cents_to_text(199), "$1.99", "one small purchase")
	assert_eq(FormatScript.cents_to_text(123456), "$1,234.56", "grouped thousands")


## Guard: the cents half. Integer division only would render $0.05 as $0.00 and
## $1.99 as $1.01, so both decimal cases must survive.
func test_cents_format_keeps_both_decimal_places() -> void:
	assert_eq(FormatScript.cents_to_text(5), "$0.05", "under a dollar")
	assert_eq(FormatScript.cents_to_text(100), "$1.00", "a round dollar still shows cents")
	assert_eq(FormatScript.cents_to_text(1005), "$10.05", "two digits carried")


# --- Trade tab: unlock progress ----------------------------------------------

func test_unlock_pull_progress_counts_up_to_the_gate() -> void:
	assert_eq(TradeTabScript.pulls_text(0), "Pulls: 0/20", "day-one account")
	assert_eq(TradeTabScript.pulls_text(19), "Pulls: 19/20", "one pull short")
	assert_eq(TradeTabScript.pulls_text(20), "Pulls: 20/20", "gate reached")


## Guard: the clamp. Without it a 35-pull account reads "Pulls: 35/20".
func test_unlock_pull_progress_stops_at_the_gate() -> void:
	assert_eq(TradeTabScript.pulls_text(35), "Pulls: 20/20", "progress, not a lifetime count")


func test_unlock_states_the_account_age_rule() -> void:
	assert_eq(TradeTabScript.age_text(), "Unlocks 3 days after sign-up")


func _home(total_pulls: int) -> Dictionary:
	# The shape get_home() returns for pity (Api.parse_home).
	return {
		"gems": 1600,
		"pity": {"since_epic": 3, "since_legendary": 40, "total_pulls": total_pulls},
		"streak": {"current": 1, "best": 1, "freezes": 0, "claimed_today": false},
	}


func _tab(home: Dictionary) -> TradeTabScript:
	var t: TradeTabScript = TradeTabScript.new()
	t.set_preview_data(home)
	return t


func test_trade_tab_reads_progress_from_the_home_cache() -> void:
	var t := _tab(_home(6))
	assert_eq(t.pulls_label_text(), "Pulls: 6/20", "pulls come from home.pity.total_pulls")
	assert_eq(t.age_label_text(), "Unlocks 3 days after sign-up")
	assert_true(t.explanation_text().find("same rarity") >= 0, "the rule is explained in one line")
	assert_true(t.rules_row().visible, "progress is on screen, not behind a tap")
	t.free()


func test_trade_tab_never_claims_a_progress_it_has_no_number_for() -> void:
	var t := _tab({"gems": 10})
	assert_eq(t.pulls_label_text(), "Pulls: 0/20", "no pity block reads as zero")
	t.free()


## Guard: no dead CTA. Wonder Trade itself is a later task; until it exists the
## tab must not offer a button that cannot do anything.
func test_trade_tab_offers_no_buttons_yet() -> void:
	var t := _tab(_home(6))
	assert_eq(_count_buttons(t), 0, "T-009 ships explanation and progress only")
	t.free()


func test_trade_tab_exposes_one_screenshot_state() -> void:
	var t: TradeTabScript = TradeTabScript.new()
	assert_eq(t.screenshot_count(), 1)
	t.free()


# --- debug-only holo bench ---------------------------------------------------

func test_holo_bench_hidden_when_not_debug() -> void:
	# Guard: is_debug, not OS.is_debug_build() read inside the build, so a
	# release build cannot pick up the shortcut by accident.
	var s: AppShellScript = AppShellScript.new()
	s.is_debug = false
	s.tab_buttons()
	assert_true(s.get_node_or_null(HOLO_BUTTON) == null,
		"a non-debug build must not ship the bench shortcut")
	s.free()


func test_holo_bench_reachable_when_debug() -> void:
	var s: AppShellScript = AppShellScript.new()
	s.is_debug = true
	s.tab_buttons()
	var holo := s.get_node_or_null(HOLO_BUTTON) as Button
	assert_true(holo != null, "devs keep the bench one tap away")
	assert_true(holo.custom_minimum_size.y >= 48.0, "48dp tap target")
	s.free()


# --- build metadata ----------------------------------------------------------

func test_project_carries_the_alpha_version_tag() -> void:
	assert_eq(str(ProjectSettings.get_setting("application/config/version")), APP_VERSION)


# --- helpers -----------------------------------------------------------------

func _count_buttons(node: Node) -> int:
	var found := 1 if node is BaseButton else 0
	for child in node.get_children():
		found += _count_buttons(child)
	return found