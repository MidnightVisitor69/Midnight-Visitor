extends Control
## Card detail (T-008, visual redesign): the showpiece. One card, big,
## tiltable, and the one screen where the foil is allowed to show off
## (foil_emphasis raises the foil above grid strength). Under it: a quiet
## info panel that answers "what is this and what do I own" with real data
## from the collection row - no invented stats.
##
## Opened by the Collection tab as a full-screen overlay. Also loadable as its
## own scene, which is how the screenshot harness captures it.
##
## Interaction: tap Close or swipe down to leave; drag anywhere on the screen
## tilts the card (the drag feeds both the close gesture and CardView).

const CardViewScene := preload("res://scenes/card/card_view.tscn")
## Preloaded (not the global class_name) so it resolves in the headless runner,
## whose global-class cache may not yet include CardCatalog.
const CardCatalogScript := preload("res://scripts/card/card_catalog.gd")

const MIN_TAP_DP := 48.0
## Swipe-down-to-close: mostly-vertical fling of at least this many pixels.
const SWIPE_DOWN_PX := 140.0
## Card sizing as fractions of the viewport, so the showpiece survives narrow
## and short screens without covering the info panel.
const CARD_WIDTH_RATIO := 0.62
const CARD_WIDTH_MAX := 720.0
const CARD_HEIGHT_RATIO := 0.62
## The detail view is where the foil reads strongest (grid runs at 1.0).
const FOIL_EMPHASIS := 1.18

signal closed

var _built := false
var _screenshot_mode := false
var _swipe_from := Vector2.ZERO
var _swiping := false
var _entrance: Tween

var _card: CardView
var _holder: Control
var _panel: PanelContainer
var _name_label: Label
var _rarity_marker: RarityMarker
var _meta_label: Label
var _owned_value: Label
var _obtained_value: Label


func _ready() -> void:
	_ensure_built()


## group: one collection group as collection_tab.gd builds it
## (card_id, variant, name, rarity, set_id, art_path, copies, obtained_at).
func setup(group: Dictionary) -> void:
	_ensure_built()
	visible = true
	var rarity := str(group.get("rarity", "common"))
	var set_id := str(group.get("set_id", ""))
	var variant := str(group.get("variant", "none"))
	_card.set_card(rarity, CardArt.textures_for(
			str(group.get("card_id", "")), rarity, str(group.get("art_path", ""))), {
		"name": str(group.get("name", group.get("card_id", ""))),
		"set_id": set_id,
	})
	_card.set_variant(variant)
	_card.set_foil_emphasis(FOIL_EMPHASIS)

	_name_label.text = str(group.get("name", group.get("card_id", "")))
	_rarity_marker.set_rarity(rarity)
	var parts: Array[String] = []
	if not set_id.is_empty():
		parts.append(set_id.to_upper())
	if variant != "none":
		parts.append(variant.to_upper() + " FOIL")
	_meta_label.text = " · ".join(parts)
	_meta_label.visible = not parts.is_empty()
	_owned_value.text = "x %d" % maxi(int(group.get("copies", 1)), 1)
	_obtained_value.text = _obtained_phrase(str(group.get("obtained_at", "")))

	_layout()
	_play_entrance()


func close() -> void:
	visible = false
	closed.emit()


func is_open() -> bool:
	_ensure_built()
	return visible


# --- input ----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_swiping = true
			_swipe_from = t.position
		else:
			_finish_swipe(t.position)
		accept_event()
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if m.button_index == MOUSE_BUTTON_LEFT:
			if m.pressed:
				_swiping = true
				_swipe_from = m.position
			else:
				_finish_swipe(m.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# A mostly-vertical drag ALSO tilts the card: the drag feeds both the
		# close gesture and the card (CardView reads its own drag events). The
		# gesture wins only when it becomes unmistakably a swipe-down.
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			accept_event()


func _finish_swipe(pos: Vector2) -> void:
	if not _swiping:
		return
	_swiping = false
	var d := pos - _swipe_from
	if d.y >= SWIPE_DOWN_PX and d.y > absf(d.x):
		close()


# --- helpers --------------------------------------------------------------------

## "Obtained Oct 3" from an ISO timestamp; falls back to the raw string.
static func _obtained_phrase(iso: String) -> String:
	if iso.is_empty():
		return ""
	var parsed := Time.get_datetime_dict_from_datetime_string(
			iso, true) if iso.contains("T") else {}
	if parsed.is_empty():
		return "Obtained %s" % iso
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
			"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var m := int(parsed.get("month", 1))
	var day := int(parsed.get("day", 1))
	if m >= 1 and m <= 12:
		return "%s %d" % [months[m - 1], day]
	return iso


# --- layout + motion -------------------------------------------------------------

## Card + panel width follow the viewport, so the pair always fits and stays
## aligned to one column.
func _layout() -> void:
	var ext := size
	if ext.x <= 1.0 or ext.y <= 1.0:
		ext = Vector2(
				ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
				ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	var cw := clampf(ext.x * CARD_WIDTH_RATIO, 240.0, CARD_WIDTH_MAX)
	var ch := cw * 1.5
	var max_h := ext.y * CARD_HEIGHT_RATIO
	if ch > max_h:
		ch = max_h
		cw = ch / 1.5
	_holder.custom_minimum_size = Vector2(cw, ch)
	_holder.pivot_offset = Vector2(cw, ch) * 0.5
	_panel.custom_minimum_size = Vector2(cw, 0.0)


## Entrance: the card settles in. Motion has a job (transition), nothing idles.
func _play_entrance() -> void:
	if _screenshot_mode or Motion.reduced or not is_inside_tree():
		return
	if _entrance != null and _entrance.is_valid():
		_entrance.kill()
	_card.pivot_offset = _holder.size * 0.5
	_card.scale = Vector2.ONE * 0.97
	_card.modulate.a = 0.0
	_entrance = create_tween()
	_entrance.set_parallel(true)
	var secs := Tokens.duration(&"standard") / 1000.0
	_entrance.tween_property(_card, "modulate:a", 1.0, secs) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_entrance.tween_property(_card, "scale", Vector2.ONE, secs) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# --- construction ----------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	resized.connect(_layout)

	# Scrim behind everything: text never sits on busy art without one.
	var bg := ColorRect.new()
	bg.name = "Scrim"
	bg.color = Color(Tokens.color(&"bg"), 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close"
	close_btn.theme_type_variation = "ButtonGhost"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(MIN_TAP_DP * 2.0, MIN_TAP_DP)
	close_btn.add_theme_font_override("font", Tokens.ui_font(500))
	close_btn.add_theme_font_size_override("font_size", Tokens.font_size(&"body"))
	close_btn.add_theme_color_override("font_color", Tokens.color(&"text_primary"))
	close_btn.add_theme_color_override("font_hover_color", Tokens.color(&"text_primary"))
	close_btn.add_theme_color_override("font_pressed_color", Tokens.color(&"accent"))
	close_btn.pressed.connect(close)
	add_child(close_btn)
	close_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	close_btn.offset_left = Tokens.space(&"s12")
	close_btn.offset_top = Tokens.space(&"s12")
	close_btn.offset_right = Tokens.space(&"s12") + MIN_TAP_DP * 2.0
	close_btn.offset_bottom = Tokens.space(&"s12") + MIN_TAP_DP

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", Tokens.space(&"s16"))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(col)

	_holder = Control.new()
	_holder.name = "CardHolder"
	_holder.custom_minimum_size = Vector2(300.0, 450.0)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_holder)

	# Real tilt: device tilt on the phone, drag on the card in tests. No
	# override, because interacting with the card is the point of this screen.
	_card = CardViewScene.instantiate() as CardView
	_card.name = "Card"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.name = "Info"
	_panel.add_theme_stylebox_override("panel", Surfaces.panel(1))
	col.add_child(_panel)

	var info := VBoxContainer.new()
	info.name = "InfoColumn"
	info.add_theme_constant_override("separation", Tokens.space(&"s8"))
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(info)

	_name_label = Label.new()
	_name_label.name = "Name"
	_name_label.theme_type_variation = "Display"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_name_label)

	_rarity_marker = RarityMarker.new()
	_rarity_marker.name = "Rarity"
	var rarity_row := CenterContainer.new()
	rarity_row.name = "RarityRow"
	rarity_row.add_child(_rarity_marker)
	info.add_child(rarity_row)

	_meta_label = Label.new()
	_meta_label.name = "Meta"
	_meta_label.theme_type_variation = "Caption"
	_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_meta_label)

	var divider := Control.new()
	divider.name = "Divider"
	divider.custom_minimum_size = Vector2(0.0, Tokens.space(&"s4"))
	divider.draw.connect(func() -> void:
		var c := Tokens.color(&"outline")
		divider.draw_line(Vector2(0.0, divider.size.y * 0.5),
				Vector2(divider.size.x, divider.size.y * 0.5), c, 1.0)
	)
	info.add_child(divider)

	var stats := HBoxContainer.new()
	stats.name = "Stats"
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", Tokens.space(&"s48"))
	info.add_child(stats)

	var owned := _stat_column("Owned")
	_owned_value = owned["value"]
	stats.add_child(owned["column"])

	var obtained := _stat_column("Obtained")
	_obtained_value = obtained["value"]
	stats.add_child(obtained["column"])

	var hint := Label.new()
	hint.name = "TiltHint"
	hint.theme_type_variation = "Caption"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "Drag to catch the light"
	info.add_child(hint)


## One "label over value" stat block, centred.
func _stat_column(label_text: String) -> Dictionary:
	var column := VBoxContainer.new()
	column.name = label_text + "Column"
	column.add_theme_constant_override("separation", Tokens.space(&"s4"))
	column.alignment = BoxContainer.ALIGNMENT_CENTER

	var label := Label.new()
	label.name = "Label"
	label.theme_type_variation = "Caption"
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)

	var value := Label.new()
	value.name = "Value"
	value.theme_type_variation = "Body"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(value)
	return {"column": column, "value": value}


# --- screenshots ----------------------------------------------------------------
## Two fixed poses, no randomness: a rare silver at rest, and a legendary
## galaxy tilted - the two ends of the holo showpiece.

static func demo_group() -> Dictionary:
	var c := CardCatalogScript.by_id("kat-daily-1735-day")   # rare "KaT · Golden Hour"
	return {
		"card_id": str(c["card_id"]),
		"variant": "silver",
		"name": str(c["name"]),
		"rarity": str(c["rarity"]),
		"set_id": str(c["set_id"]),
		"art_path": str(c["art_path"]),
		"copies": 2,
		"obtained_at": "2026-10-03T21:14:00",
	}


static func demo_legendary() -> Dictionary:
	var c := CardCatalogScript.by_id("kat-daily-2344-sleep")   # legendary "KaT · Sweet Dreams"
	return {
		"card_id": str(c["card_id"]),
		"variant": "galaxy",
		"name": str(c["name"]),
		"rarity": str(c["rarity"]),
		"set_id": str(c["set_id"]),
		"art_path": str(c["art_path"]),
		"copies": 1,
		"obtained_at": "2026-10-05T23:41:00",
	}


func screenshot_count() -> int:
	return 2


func screenshot_setup(i: int) -> String:
	_ensure_built()
	_screenshot_mode = true
	match i:
		0:
			setup(demo_group())
			_card.use_tilt_override = true
			_card.tilt_override = Vector2.ZERO
			return "detail_rare_silver"
		_:
			setup(demo_legendary())
			_card.use_tilt_override = true
			_card.tilt_override = Vector2(0.5, -0.35)
			return "detail_legendary_galaxy"
