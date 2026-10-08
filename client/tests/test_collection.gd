extends "res://tests/test_case.gd"
## T-008: Collection tab. The view is built offline through set_preview_data,
## the same seam the screenshot harness uses, so every test is synchronous and
## needs no server. Grouping, filtering, sorting, the set counter, the empty
## state, and the detail-overlay rule are pinned here; CardArt's LRU and
## placeholder fallback live in test_card_art.gd.
##
## The last test is the fault-injection guard: the real failures from T-008's
## blocked attempts were "detail starts closed" and "two variants of one card
## are two tiles" - both regressions must break here.

const CollectionTabScript := preload("res://scripts/app/tabs/collection_tab.gd")


func _row(id: String, card_id: String, name: String, rarity: String,
		set_id: String, variant := "none", art_path := "") -> Dictionary:
	return {
		"id": id,
		"card_id": card_id,
		"variant": variant,
		"obtained_at": "2026-10-01T12:00:00",
		"name": name,
		"rarity": rarity,
		"set_id": set_id,
		"art_path": art_path if not art_path.is_empty() else "placeholder/%s.png" % rarity,
	}


func _tab(rows: Array, sizes := {}) -> CollectionTabScript:
	var t: CollectionTabScript = CollectionTabScript.new()
	t.set_preview_data(rows, sizes)
	return t


## The set list is sorted alphabetically, so tests pick by set_id, not index.
func _select_set(t: CollectionTabScript, set_id: String) -> void:
	var sel := t.set_selector()
	for i in sel.item_count:
		if str(sel.get_item_metadata(i)) == set_id:
			sel.item_selected.emit(i)
			return


func _names(t: CollectionTabScript) -> Array[String]:
	var out: Array[String] = []
	for tile in t.tiles():
		out.append(str(tile.name))
	return out


# --- grouping ------------------------------------------------------------------

func test_three_copies_of_one_variant_are_one_tile_with_x3() -> void:
	var rows := [
		_row("a", "aurora", "Aurora", "common", "launch-01"),
		_row("b", "aurora", "Aurora", "common", "launch-01"),
		_row("c", "aurora", "Aurora", "common", "launch-01"),
	]
	var t := _tab(rows)
	var tiles := t.tiles()
	assert_eq(tiles.size(), 1, "same card + same variant = one tile")
	var badge := tiles[0].get_node_or_null("Count")
	assert_true(badge != null, "copy badge exists")
	if badge != null:
		assert_eq(badge.text, "x3", "badge counts copies")
	t.free()


func test_same_card_two_variants_are_two_tiles() -> void:
	var rows := [
		_row("a", "aurora", "Aurora", "rare", "launch-01"),
		_row("b", "aurora", "Aurora", "rare", "launch-01", "gold"),
	]
	var t := _tab(rows)
	assert_eq(t.tiles().size(), 2, "variant is part of the collectible")
	t.free()


func test_group_keys_split_on_variant() -> void:
	var a := _row("a", "aurora", "Aurora", "rare", "launch-01")
	var b := _row("b", "aurora", "Aurora", "rare", "launch-01", "gold")
	assert_true(CollectionTabScript.group_key(a) != CollectionTabScript.group_key(b),
			"different variants -> different keys")
	assert_true(CollectionTabScript.group_key(a) == CollectionTabScript.group_key(
			_row("c", "aurora", "Aurora", "rare", "launch-01")),
			"same card + variant -> same key")


func test_copies_sum_across_group() -> void:
	var rows := [
		_row("a", "aurora", "Aurora", "common", "launch-01"),
		_row("b", "aurora", "Aurora", "common", "launch-01", "none"),
	]
	var t := _tab(rows)
	var tiles := t.tiles()
	assert_eq(tiles.size(), 1, "variant none matches the default")
	var badge := tiles[0].get_node_or_null("Count")
	assert_eq(badge.text if badge != null else "", "x2")
	t.free()


# --- sorting -------------------------------------------------------------------

func test_sort_is_rarity_desc_then_name() -> void:
	var rows := [
		_row("1", "beta", "Beta", "common", "launch-01"),
		_row("2", "zeta", "Zeta", "epic", "launch-01"),
		_row("3", "alpha", "Alpha", "rare", "launch-01"),
		_row("4", "mid", "Mid", "rare", "launch-01"),
	]
	var t := _tab(rows)
	var names := _names(t)
	assert_true(names.size() == 4, "all tiles present")
	# Epic, then rare (Alpha < Mid), then common.
	assert_true(names[0].find("zeta") >= 0, "epic first")
	assert_true(names[1].find("alpha") >= 0, "alpha before mid within rare")
	assert_true(names[2].find("mid") >= 0, "mid before beta")
	assert_true(names[3].find("beta") >= 0, "common last")
	t.free()


# --- filtering -----------------------------------------------------------------

func test_filter_epic_shows_only_epics() -> void:
	var rows := [
		_row("1", "zeta", "Zeta", "epic", "launch-01"),
		_row("2", "alpha", "Alpha", "rare", "launch-01"),
		_row("3", "beta", "Beta", "common", "launch-01"),
	]
	var t := _tab(rows)
	for b in t.filter_buttons():
		if b.name == "Filter_epic":
			b.button_pressed = true
			b.pressed.emit()
	assert_eq(t.tiles().size(), 1, "only the epic survives the filter")
	t.free()


func test_filter_all_restores_every_group() -> void:
	var rows := [
		_row("1", "zeta", "Zeta", "epic", "launch-01"),
		_row("2", "alpha", "Alpha", "rare", "launch-01"),
	]
	var t := _tab(rows)
	for b in t.filter_buttons():
		if b.name == "Filter_epic":
			b.button_pressed = true
			b.pressed.emit()
	assert_eq(t.tiles().size(), 1)
	for b in t.filter_buttons():
		if b.name == "Filter_all":
			b.button_pressed = true
			b.pressed.emit()
	assert_eq(t.tiles().size(), 2, "All clears the rarity filter")
	t.free()


# --- set selector + counter ----------------------------------------------------

func test_set_selector_lists_all_sets_and_all_sets_entry() -> void:
	var rows := [
		_row("1", "a", "A", "common", "launch-01"),
		_row("2", "b", "B", "rare", "city-pop-93"),
	]
	var t := _tab(rows)
	var sel := t.set_selector()
	assert_eq(sel.item_count, 3, "All sets + two distinct set_ids")
	assert_eq(sel.get_item_text(0), "All sets")
	t.free()


func test_counter_shows_owned_over_total_for_selected_set() -> void:
	var rows := [
		_row("1", "a", "A", "common", "launch-01"),
		_row("2", "b", "B", "rare", "launch-01"),
		_row("3", "c", "C", "epic", "city-pop-93"),
	]
	var t := _tab(rows, {"launch-01": 16})
	_select_set(t, "launch-01")
	assert_true(t.counter_visible(), "counter visible with a set selected")
	assert_eq(t.counter_text(), "2/16", "owned groups over server total")
	t.free()


func test_counter_hidden_without_a_set() -> void:
	var rows := [_row("1", "a", "A", "common", "launch-01")]
	var t := _tab(rows, {"launch-01": 16})
	assert_true(not t.counter_visible(), "no set selected -> no counter")
	t.free()


func test_counter_without_server_total_says_owned_only() -> void:
	var rows := [_row("1", "a", "A", "common", "launch-01")]
	var t := _tab(rows, {})
	_select_set(t, "launch-01")
	assert_true(t.counter_visible())
	assert_eq(t.counter_text(), "1 owned", "no published size -> no fake total")
	t.free()


func test_counter_treats_two_variants_as_two_owned() -> void:
	var rows := [
		_row("1", "a", "A", "rare", "launch-01"),
		_row("2", "a", "A", "rare", "launch-01", "gold"),
		_row("3", "a", "A", "rare", "launch-01", "gold"),
	]
	var t := _tab(rows, {"launch-01": 8})
	_select_set(t, "launch-01")
	assert_eq(t.counter_text(), "2/8", "variants count once each, copies do not")
	t.free()


# --- empty state ----------------------------------------------------------------

func test_empty_state_visible_with_no_rows() -> void:
	var t := _tab([])
	assert_true(t.empty_visible(), "empty state must show when nothing is owned")
	assert_eq(t.tiles().size(), 0)
	t.free()


func test_empty_state_hidden_with_rows() -> void:
	var t := _tab([_row("1", "a", "A", "common", "launch-01")])
	assert_true(not t.empty_visible())
	t.free()


# --- detail overlay -------------------------------------------------------------

func test_detail_starts_closed() -> void:
	var t := _tab([_row("1", "a", "A", "common", "launch-01")])
	assert_true(t.detail_starts_closed(), "opening the tab must not open a detail")
	t.free()


func test_opening_a_tile_builds_the_detail_once() -> void:
	var t := _tab([_row("1", "a", "A", "common", "launch-01")])
	t.tiles()[0].pressed.emit()
	assert_true(t.detail_view() != null, "tap opens the detail overlay")
	t.free()


func test_demo_rows_group_cleanly() -> void:
	var rows := CollectionTabScript.demo_rows()
	var t := _tab(rows)
	assert_true(t.tiles().size() >= 8, "demo data renders a real grid")
	t.free()


# --- screenshot harness ----------------------------------------------------------

func test_collection_tab_exposes_two_screenshot_states() -> void:
	var t: CollectionTabScript = CollectionTabScript.new()
	assert_eq(t.screenshot_count(), 2)
	t.free()


# --- fault-injection guard --------------------------------------------------------
# The blocked attempts failed with "two variants grouped into one tile" and
# "detail opened on tab load". The tests above pin both; this one proves the
# grouping assertion actually bites by feeding the bug's signature input.

func test_grouping_assertion_bites_on_mixed_variants() -> void:
	var rows := [
		_row("1", "a", "A", "rare", "launch-01", "silver"),
		_row("2", "a", "A", "rare", "launch-01", "gold"),
		_row("3", "b", "B", "common", "launch-01"),
	]
	var t := _tab(rows)
	assert_eq(t.tiles().size(), 3, "2 variants of A + B must be 3 tiles, not 2")
	t.free()
