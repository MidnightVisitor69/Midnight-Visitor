extends Control
## Collection tab (T-008): every card you own, grouped, filterable, sortable.
## One question per screen: "what do I have?" - no CTA competes with browsing.
##
## Data comes from GameState (the only cache that talks to the server); tests
## and the screenshot harness build the view offline through set_preview_data,
## the same seam the Home tab uses.
##
## Grouping rule (AGENTS.md): a card plus its holo variant is the collectible,
## so groups key on (card_id, variant) - two variants of one card are two tiles,
## three copies of one variant are one tile with an "x3" badge.
##
## Sort is rarity descending, then name; the filter chips and the set selector
## narrow before the sort. The counter only appears with a set selected and only
## when the server told us the set size, per the task.

const CardViewScene := preload("res://scenes/card/card_view.tscn")
const CardDetailScene := preload("res://scenes/app/card_detail.tscn")
## Preloaded (not the global class_name) so it resolves in the headless runner,
## whose global-class cache may not yet include CardCatalog.
const CardCatalogScript := preload("res://scripts/card/card_catalog.gd")

const MIN_TAP_DP := 48.0
const GRID_COLUMNS := 3
const TILE_SEPARATION := 10.0
const RANKS := {"common": 0, "rare": 1, "epic": 2, "legendary": 3}
## Chip order is display order, not rank order: All first, then low to high.
const FILTERS: Array[String] = ["all", "common", "rare", "epic", "legendary"]

signal detail_requested(group: Dictionary)

var _rows: Array = []
var _set_sizes: Dictionary = {}
var _preview := false
var _built := false

var _filter := "all"
var _set_id := ""   # "" = all sets

var _filter_row: HBoxContainer
var _set_selector: OptionButton
var _counter: Label
var _empty: Label
var _grid: GridContainer
var _scroll: ScrollContainer
var _detail: Control
var _filter_buttons: Array[Button] = []


func _ready() -> void:
	_ensure_built()
	if _preview:
		return
	var gs := get_node_or_null("/root/GameState") if is_inside_tree() else null
	if gs == null:
		return
	if not gs.collection_changed.is_connected(_on_collection_changed):
		gs.collection_changed.connect(_on_collection_changed)
	if (gs.collection as Array).size() > 0:
		_rows = gs.collection
		_rebuild()


## Offline seam for tests and screenshots: feed collection rows and optional
## set sizes (set_id -> total) exactly as parse_collection/parse_set_sizes
## produce them.
func set_preview_data(rows: Array, sizes: Dictionary = {}) -> void:
	_ensure_built()
	_preview = true
	_rows = rows
	_set_sizes = sizes
	_rebuild()


# --- accessors (tests) ----------------------------------------------------------

func tiles() -> Array[Control]:
	_ensure_built()
	var out: Array[Control] = []
	for child in _grid.get_children():
		out.append(child as Control)
	return out


func filter_buttons() -> Array[Button]:
	_ensure_built()
	return _filter_buttons


func set_selector() -> OptionButton:
	_ensure_built()
	return _set_selector


func counter_text() -> String:
	_ensure_built()
	return _counter.text


func counter_visible() -> bool:
	_ensure_built()
	return _counter.visible


func empty_visible() -> bool:
	_ensure_built()
	return _empty.visible


func detail_starts_closed() -> bool:
	_ensure_built()
	return _detail == null or not _detail.visible


func detail_view() -> Control:
	_ensure_built()
	return _detail


## The tile's group record, for tests that check what a tap would open.
static func group_key(row: Dictionary) -> String:
	return "%s|%s" % [str(row.get("card_id", "")), str(row.get("variant", "none"))]


# --- build ----------------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Same margin rhythm as the Home tab so sibling screens share one edge.
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Tokens.space(&"s16"))
	add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", Tokens.space(&"s16"))
	margin.add_child(col)

	_filter_row = HBoxContainer.new()
	_filter_row.name = "Filters"
	_filter_row.add_theme_constant_override("separation", Tokens.space(&"s8"))
	col.add_child(_filter_row)
	for f in FILTERS:
		# The shared Chip: 48dp pill, weight change marks the active filter.
		var b := Chip.new()
		b.name = "Filter_" + f
		b.text = f.capitalize()
		b.button_pressed = f == "all"
		b.pressed.connect(_select_filter.bind(f))
		_filter_row.add_child(b)
		_filter_buttons.append(b)

	_set_selector = OptionButton.new()
	_set_selector.name = "SetSelector"
	_set_selector.focus_mode = Control.FOCUS_NONE
	_set_selector.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_set_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_selector.item_selected.connect(_on_set_selected)
	col.add_child(_set_selector)

	_counter = Label.new()
	_counter.name = "Counter"
	_counter.theme_type_variation = "Caption"
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter.visible = false
	col.add_child(_counter)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", int(TILE_SEPARATION))
	_grid.add_theme_constant_override("v_separation", int(TILE_SEPARATION))
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)

	_empty = Label.new()
	_empty.name = "Empty"
	_empty.theme_type_variation = "Body"
	_empty.text = "No cards yet. Open packs on Home to start your collection."
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.visible = false
	col.add_child(_empty)

	resized.connect(_rebuild)


# --- data -> groups -------------------------------------------------------------

## One tile per (card_id, variant), with a copy count.
static func group_rows(rows: Array) -> Array[Dictionary]:
	var order: Array[String] = []
	var groups: Dictionary = {}
	for row in rows:
		if not (row is Dictionary):
			continue
		var key := group_key(row)
		if not groups.has(key):
			order.append(key)
			var first: Dictionary = row
			groups[key] = {
				"card_id": str(first.get("card_id", "")),
				"variant": str(first.get("variant", "none")),
				"name": str(first.get("name", "")),
				"rarity": str(first.get("rarity", "common")),
				"set_id": str(first.get("set_id", "")),
				"art_path": str(first.get("art_path", "")),
				"obtained_at": str(first.get("obtained_at", "")),
				"copies": 0,
			}
		groups[key]["copies"] = int(groups[key]["copies"]) + 1
	var out: Array[Dictionary] = []
	for key in order:
		out.append(groups[key])
	return out


static func _rank(rarity: String) -> int:
	return int(RANKS.get(rarity, 0))


static func _sorted(groups: Array[Dictionary]) -> Array[Dictionary]:
	var out := groups.duplicate(true)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := _rank(str(a["rarity"]))
		var rb := _rank(str(b["rarity"]))
		if ra != rb:
			return ra > rb
		var na := str(a["name"]).to_lower()
		var nb := str(b["name"]).to_lower()
		if na != nb:
			return na < nb
		return str(a["card_id"]) < str(b["card_id"]))
	return out


func _visible_groups() -> Array[Dictionary]:
	var groups := group_rows(_rows)
	var filtered: Array[Dictionary] = []
	for g in groups:
		if _filter != "all" and str(g["rarity"]) != _filter:
			continue
		if not _set_id.is_empty() and str(g["set_id"]) != _set_id:
			continue
		filtered.append(g)
	return _sorted(filtered)


# --- rebuild --------------------------------------------------------------------

func _on_collection_changed() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		_rows = gs.collection
		_rebuild()


func _select_filter(f: String) -> void:
	_filter = f
	for b in _filter_buttons:
		b.button_pressed = b.name == "Filter_" + f
	_rebuild()


func _on_set_selected(index: int) -> void:
	# Item 0 is always "All sets"; the rest are the distinct set_ids in order.
	_set_id = "" if index <= 0 else _set_selector.get_item_metadata(index)
	_rebuild()


func _distinct_sets() -> Array[String]:
	var out: Array[String] = []
	for row in _rows:
		if not (row is Dictionary):
			continue
		var sid := str(row.get("set_id", ""))
		if not sid.is_empty() and not out.has(sid):
			out.append(sid)
	out.sort()
	return out


func _sync_set_selector() -> void:
	_set_selector.clear()
	_set_selector.add_item("All sets")
	_set_selector.set_item_metadata(0, "")
	for sid in _distinct_sets():
		var idx := _set_selector.item_count
		_set_selector.add_item(sid)
		_set_selector.set_item_metadata(idx, sid)
	var keep := 0
	if not _set_id.is_empty():
		for i in _set_selector.item_count:
			if str(_set_selector.get_item_metadata(i)) == _set_id:
				keep = i
				break
	_set_selector.select(keep)


func _rebuild() -> void:
	_sync_set_selector()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	var groups := _visible_groups()
	_empty.visible = groups.is_empty()
	_scroll.visible = not groups.is_empty()

	# The counter shows only with a specific set selected, and only when the
	# server publishes that set's size (task: otherwise omit the total).
	var owned_in_set := 0
	var total := -1
	if not _set_id.is_empty():
		for g in group_rows(_rows):
			if str(g["set_id"]) == _set_id:
				owned_in_set += 1
		if _set_sizes.has(_set_id):
			total = int(_set_sizes[_set_id])
		_counter.visible = true
		_counter.text = ("%d/%d" % [owned_in_set, total]) if total >= 0 \
				else "%d owned" % owned_in_set
	else:
		_counter.visible = false

	var tile_size := _tile_size()
	for g in groups:
		_grid.add_child(_make_tile(g, tile_size))


func _tile_size() -> Vector2:
	# 2:3 portrait tiles in 3 columns that fit the width between the screen
	# margins (phone-first); the grid never overflows horizontally.
	var ext := size
	if ext.x <= 1.0:
		ext = Vector2(
				ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
				ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	var gutters := 2.0 * float(Tokens.space(&"s16"))
	var w := (ext.x - gutters - (GRID_COLUMNS - 1) * TILE_SEPARATION) / float(GRID_COLUMNS)
	return Vector2(w, w * 1.5)


func _make_tile(group: Dictionary, tile_size: Vector2) -> Control:
	var tile := Button.new()
	tile.name = "Tile_" + str(group["card_id"]) + "_" + str(group["variant"])
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = tile_size
	tile.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tile.pressed.connect(_open_detail.bind(group))
	# Flat look: the art is the tile, not a button.
	tile.flat = true
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		tile.add_theme_stylebox_override(state, empty)

	var view := CardViewScene.instantiate() as CardView
	view.name = "Card"
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.use_tilt_override = true
	view.tilt_override = Vector2(0.25, -0.15)
	tile.add_child(view)
	# add_child FIRST: a scene-instantiated CardView still carries the .tscn's
	# default offsets, and a preset applied before it has a parent keeps them
	# (that was the grid-overlap bug).
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_card(str(group["rarity"]), CardArt.textures_for(
			str(group["card_id"]), str(group["rarity"]), str(group["art_path"])), {
		"name": str(group.get("name", "")),
		"set_id": str(group.get("set_id", "")),
	})
	view.set_variant(str(group["variant"]))
	# Tap feedback: the card dips under the finger, nothing else moves.
	tile.button_down.connect(_dip.bind(view, true))
	tile.button_up.connect(_dip.bind(view, false))

	if int(group["copies"]) > 1:
		var badge := Badge.new()
		badge.name = "Count"
		badge.text = "x%d" % int(group["copies"])
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -Tokens.space(&"s40")
		badge.offset_top = Tokens.space(&"s8")
		badge.offset_right = -Tokens.space(&"s8")
		badge.offset_bottom = Tokens.space(&"s8") + Tokens.space(&"s24")
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(badge)
	return tile


## Pressed-state dip on the card itself (Motion.TAP_PRESS_SCALE).
func _dip(view: Control, down: bool) -> void:
	if not is_instance_valid(view):
		return
	var target := Motion.TAP_PRESS_SCALE if down else 1.0
	var tw := view.create_tween()
	tw.tween_property(view, "scale", Vector2.ONE * target,
			Motion.TAP_MS / 1000.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# --- detail ---------------------------------------------------------------------

func _open_detail(group: Dictionary) -> void:
	if _detail != null and is_instance_valid(_detail):
		_detail.queue_free()
	_detail = CardDetailScene.instantiate() as Control
	_detail.name = "CardDetail"
	_detail.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_detail)
	_detail.call("setup", group)
	# The detail renders above everything in this tab.
	_detail.move_to_front()


# --- screenshots ----------------------------------------------------------------
## Fixed fake data, no randomness and no network, so every capture is identical.

static func demo_rows() -> Array:
	var rows: Array = []
	var cards := CardCatalogScript.all()
	var i := 0
	for c in cards:
		var card_id := str(c["card_id"])
		var rarity := str(c["rarity"])
		# Deterministic copy counts so the xN badges and grouping have real work
		# to do; driven purely by catalog order, never randomness (screenshots
		# must be identical every capture).
		var copies := 1 + (i % 3)
		for copy in copies:
			var variant := "none"
			# The last copy of every fourth card is a holo variant so the grid
			# shows both plain and foil copies of the same real card.
			if copy == copies - 1 and i % 4 == 3:
				variant = "gold" if rarity in ["epic", "legendary"] else "silver"
			rows.append({
				"id": "demo-%d-%d" % [i, copy],
				"card_id": card_id,
				"variant": variant,
				"obtained_at": "2026-10-%02dT12:00:00" % ((i % 27) + 1),
				"name": str(c["name"]),
				"rarity": rarity,
				"set_id": str(c["set_id"]),
				"art_path": str(c["art_path"]),
			})
		i += 1
	return rows


func screenshot_count() -> int:
	return 2


func screenshot_setup(i: int) -> String:
	_ensure_built()
	set_preview_data(demo_rows(), {"kat-closet": 32, "kat-daily": 30})
	match i:
		0:
			_filter = "all"
			_set_id = ""
			_rebuild()
			return "collection_all"
		_:
			_filter = "epic"
			_set_id = ""
			for b in _filter_buttons:
				b.button_pressed = b.name == "Filter_epic"
			_rebuild()
			return "collection_epic"
