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

	var col := VBoxContainer.new()
	col.name = "Column"
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	_filter_row = HBoxContainer.new()
	_filter_row.name = "Filters"
	_filter_row.add_theme_constant_override("separation", 6)
	col.add_child(_filter_row)
	for f in FILTERS:
		var b := Button.new()
		b.name = "Filter_" + f
		b.text = f.capitalize()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
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
	_empty.text = "No cards here yet - pulls land on Home."
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
	# 2:3 portrait tiles in 3 columns that always fit the width (phone-first).
	var ext := size
	if ext.x <= 1.0:
		ext = Vector2(
				ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
				ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	var w := (ext.x - (GRID_COLUMNS - 1) * TILE_SEPARATION - 24.0) / float(GRID_COLUMNS)
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

	var view: Control = CardViewScene.instantiate()
	view.name = "Card"
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.use_tilt_override = true
	view.tilt_override = Vector2(0.25, -0.15)
	tile.add_child(view)
	view.set_card(str(group["rarity"]), CardArt.textures_for(
			str(group["card_id"]), str(group["rarity"]), str(group["art_path"])))
	view.set_variant(str(group["variant"]))

	if int(group["copies"]) > 1:
		var badge := Label.new()
		badge.name = "Count"
		badge.text = "x%d" % int(group["copies"])
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -56.0
		badge.offset_top = 4.0
		badge.offset_right = -6.0
		badge.offset_bottom = 30.0
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(badge)
	return tile


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
	var cards := [
		["aurora-late", "Aurora, Late", "common", "launch-01", 3],
		["neon-latte", "Neon Latte", "common", "launch-01", 1],
		["velvet-static", "Velvet Static", "common", "launch-01", 2],
		["harbor-lantern", "Harbor Lantern", "common", "con-weekend", 1],
		["sable-rain", "Sable Rain", "rare", "launch-01", 2],
		["mika-signal", "Mika Signal", "rare", "city-pop-93", 1],
		["opal-drive", "Opal Drive", "rare", "launch-01", 1],
		["yuki-ghost", "Yuki Ghost", "epic", "launch-01", 1],
		["rin-vending", "Rin, Vending Machine", "epic", "city-pop-93", 1],
		["seraph-gold", "Seraph Gold", "legendary", "launch-01", 1],
		["noir-ember", "Noir Ember", "legendary", "noir", 1],
		["ink-moth", "Ink Moth", "rare", "ink-ember", 1],
	]
	var variants := ["none", "none", "silver", "none", "gold"]
	var i := 0
	for c in cards:
		for copy in int(c[4]):
			var variant := "none"
			# Spread a second variant over the first two cards so grouping has
			# something real to do in the demo.
			if copy == int(c[4]) - 1 and i % 5 == 3:
				variant = variants[i % variants.size()]
			rows.append({
				"id": "demo-%d" % i,
				"card_id": c[0],
				"variant": variant,
				"obtained_at": "2026-10-0%dT12:00:00" % ((i % 7) + 1),
				"name": c[1],
				"rarity": c[2],
				"set_id": c[3],
				"art_path": "placeholder/%s.png" % c[2],
			})
			i += 1
	return rows


func screenshot_count() -> int:
	return 2


func screenshot_setup(i: int) -> String:
	_ensure_built()
	set_preview_data(demo_rows(), {"launch-01": 8, "con-weekend": 16})
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
