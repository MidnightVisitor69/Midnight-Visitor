extends Control
## Card detail pager (M-003): horizontal flick-through over the filtered collection.
## One card centered, neighbors peek 8% at the edges (scaled 0.92, dimmed).
## Drag follows the finger 1:1; release snaps with TRANS_BACK ease-out ~260 ms.
## Swipe-down to close stays (follow + fade). Tilt/holo works on the centered card.
##
## Opened by Collection tab as a full-screen overlay. Also loadable as its own
## scene for the screenshot harness.
##
## Interaction:
##   - Horizontal drag: pans the pager, cards follow finger exactly
##   - Release: velocity decides next/prev (threshold ~600 px/s or 35% width)
##   - Vertical swipe-down: closes with follow + fade
##   - Tap Close button: closes
##   - Drag on centered card: tilts the card (CardView reads its own drag)

const CardViewScene := preload("res://scenes/card/card_view.tscn")
const CardCatalogScript := preload("res://scripts/card/card_catalog.gd")
const PagerMathScript := preload("res://scripts/motion/pager_math.gd")

const MIN_TAP_DP := 48.0
## Swipe-down-to-close: mostly-vertical fling of at least this many pixels.
const SWIPE_DOWN_PX := 140.0
## Card sizing as fractions of the viewport.
const CARD_WIDTH_RATIO := 0.62
const CARD_WIDTH_MAX := 720.0
const CARD_HEIGHT_RATIO := 0.62
## The detail view is where the foil reads strongest (grid runs at 1.0).
const FOIL_EMPHASIS := 1.18

signal closed

var _built := false
var _screenshot_mode := false

# Pager state
var _groups: Array[Dictionary] = []
var _index := 0                    # centered card index
var _offset := 0.0                 # horizontal scroll offset (px), 0 = first card centered
var _velocity := 0.0               # current drag velocity (px/s)
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_start_offset := 0.0
var _drag_start_time := 0.0
var _last_drag_pos := Vector2.ZERO
var _last_drag_time := 0.0

# Swipe-down-to-close
var _swipe_down_active := false
var _swipe_down_start := Vector2.ZERO

# Animation
var _snap_tween: Tween
var _close_tween: Tween

# Card views (pooled: center, left neighbor, right neighbor)
var _card_views: Array[CardView] = []
var _card_holder: Control
var _panel: PanelContainer

# Info panel (updates per card)
var _name_label: Label
var _rarity_marker: RarityMarker
var _meta_label: Label
var _owned_value: Label
var _obtained_value: Label

# Layout
var _card_width := 0.0
var _card_height := 0.0

# Sound rate limiting
var _last_slide_sound_time := 0


func _ready() -> void:
	_ensure_built()


## groups: filtered collection array from CollectionTab._visible_groups()
## start_index: which group to center initially
func setup_pager(groups: Array[Dictionary], start_index: int) -> void:
	_ensure_built()
	_groups = groups
	_index = clampi(start_index, 0, maxi(_groups.size() - 1, 0))
	_offset = _index * _card_width
	_velocity = 0.0
	_dragging = false
	_swipe_down_active = false
	_last_slide_sound_time = 0
	visible = true
	_rebuild_cards()
	_update_info_panel()
	_layout()
	_play_entrance()


func close() -> void:
	if _close_tween != null and _close_tween.is_valid():
		return
	_close_tween = create_tween()
	_close_tween.set_parallel(true)
	var secs := Tokens.duration(&"quick") / 1000.0
	_close_tween.tween_property(_card_holder, "modulate:a", 0.0, secs) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_close_tween.tween_property(_card_holder, "position:y", _card_holder.position.y + 80.0, secs) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_close_tween.tween_property(_panel, "modulate:a", 0.0, secs) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_close_tween.finished.connect(_do_close)


func _do_close() -> void:
	visible = false
	_card_holder.modulate.a = 1.0
	_card_holder.position = Vector2.ZERO
	_panel.modulate.a = 1.0
	closed.emit()


func is_open() -> bool:
	_ensure_built()
	return visible


# --- input ----------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_begin_drag(t.position)
		else:
			_end_drag(t.position)
		accept_event()
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if m.button_index == MOUSE_BUTTON_LEFT:
			if m.pressed:
				_begin_drag(m.position)
			else:
				_end_drag(m.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_update_drag(mm.position)
			accept_event()
	elif event is InputEventScreenDrag:
		_update_drag(event.position)
		accept_event()


func _begin_drag(pos: Vector2) -> void:
	if _snap_tween != null and _snap_tween.is_valid():
		_snap_tween.kill()
	if _close_tween != null and _close_tween.is_valid():
		_close_tween.kill()
	_dragging = true
	_swipe_down_active = true
	_drag_start = pos
	_swipe_down_start = pos
	_drag_start_offset = _offset
	_drag_start_time = Time.get_ticks_msec()
	_last_drag_pos = pos
	_last_drag_time = _drag_start_time
	_velocity = 0.0


func _update_drag(pos: Vector2) -> void:
	if not _dragging:
		return
	var now := Time.get_ticks_msec()
	var dt := maxf(now - _last_drag_time, 1.0) / 1000.0
	var dx := pos.x - _last_drag_pos.x
	var dy := pos.y - _last_drag_pos.y
	
	# Update velocity (exponential moving average for stability)
	var instant_vel := dx / dt
	_velocity = lerpf(_velocity, instant_vel, 0.3)
	
	# Horizontal drag moves the pager
	var new_offset := _drag_start_offset - (pos.x - _drag_start.x)
	
	# Check for swipe-down (mostly vertical)
	var total_dy := pos.y - _swipe_down_start.y
	var total_dx := absf(pos.x - _swipe_down_start.x)
	if _swipe_down_active and total_dy >= SWIPE_DOWN_PX and total_dy > total_dx:
		_swipe_down_active = false
		# Let the swipe-down close happen on release
	
	# Apply rubber-band at edges
	new_offset = _apply_rubber_band(new_offset)
	
	_offset = new_offset
	_update_card_positions()
	
	_last_drag_pos = pos
	_last_drag_time = now


func _end_drag(pos: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	
	# Check for swipe-down-to-close
	var total_dy := pos.y - _swipe_down_start.y
	var total_dx := absf(pos.x - _swipe_down_start.x)
	if total_dy >= SWIPE_DOWN_PX and total_dy > total_dx:
		close()
		return
	
	# Decide target index from velocity and offset
	var count := _groups.size()
	if count <= 1:
		_snap_to_index(_index)
		return
	
	var target := PagerMath.target_index(_index, _offset, _velocity, count, _card_width)
	
	# Play slide sound if index actually changes
	if target != _index and PagerMathScript.can_play_slide_sound(_last_slide_sound_time, Time.get_ticks_msec()):
		Sfx.play("card_slide")
		_last_slide_sound_time = Time.get_ticks_msec()
	
	_snap_to_index(target)


func _apply_rubber_band(offset: float) -> float:
	var count := _groups.size()
	if count <= 1:
		return 0.0
	var min_offset := 0.0
	var max_offset := (count - 1) * _card_width
	if offset < min_offset:
		var overshoot := min_offset - offset
		return min_offset - PagerMath.rubber_band_offset(overshoot, _card_width)
	elif offset > max_offset:
		var overshoot := offset - max_offset
		return max_offset + PagerMath.rubber_band_offset(overshoot, _card_width)
	return offset


func _snap_to_index(target: int) -> void:
	target = clampi(target, 0, maxi(_groups.size() - 1, 0))
	if target == _index and absf(_offset - target * _card_width) < 1.0:
		return
	_index = target
	var target_offset := _index * _card_width
	var distance := absf(target_offset - _offset)
	var duration := PagerMathScript.SNAP_MS / 1000.0
	# Scale duration slightly by distance but cap it
	duration = clampf(duration * (distance / _card_width), PagerMathScript.SNAP_MS * 0.5 / 1000.0, PagerMathScript.SNAP_MS * 1.5 / 1000.0)
	
	_snap_tween = create_tween()
	_snap_tween.tween_property(self, "_offset", target_offset, duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_snap_tween.finished.connect(_on_snap_finished)


func _on_snap_finished() -> void:
	_update_info_panel()


func _update_card_positions() -> void:
	if _card_holder == null or _card_views.is_empty():
		return
	var count := _groups.size()
	var center_x := _card_holder.size.x * 0.5
	
	for i in range(_card_views.size()):
		var view := _card_views[i]
		if view == null:
			continue
		var card_index := _index + (i - 1)  # 0=left, 1=center, 2=right
		if card_index < 0 or card_index >= count:
			view.visible = false
			continue
		view.visible = true
		
		# Progress of this card relative to center (0 = centered, 1 = one card width away)
		var rel_offset := (card_index * _card_width) - _offset
		var progress := absf(rel_offset) / _card_width
		progress = clampf(progress, 0.0, 1.0)
		
		# Use PagerMath for transform
		var rel_index := card_index - _index
		var transform := PagerMath.card_transform(rel_index, progress, _card_width)
		
		view.position.x = center_x + transform.x
		view.scale = Vector2.ONE * transform.scale
		view.modulate.a = transform.modulate_alpha
		view.z_index = transform.z_index
		
		# Only the centered card gets tilt/holo emphasis
		view.set_foil_emphasis(FOIL_EMPHASIS if rel_index == 0 else 1.0)
		# Tilt input is handled by CardView itself via _gui_input


func _rebuild_cards() -> void:
	# Clear existing
	for view in _card_views:
		if view != null and is_instance_valid(view):
			view.queue_free()
	_card_views.clear()
	
	# Create 3 views: left neighbor, center, right neighbor
	for i in 3:
		var view := CardViewScene.instantiate() as CardView
		view.name = "CardView_%d" % i
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_holder.add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_card_views.append(view)
	
	# Load card data for visible indices
	_load_visible_cards()
	_update_card_positions()


func _load_visible_cards() -> void:
	var count := _groups.size()
	for i in range(_card_views.size()):
		var view := _card_views[i]
		if view == null:
			continue
		var card_index := _index + (i - 1)
		if card_index < 0 or card_index >= count:
			view.visible = false
			continue
		var group := _groups[card_index]
		var rarity := str(group.get("rarity", "common"))
		var set_id := str(group.get("set_id", ""))
		var variant := str(group.get("variant", "none"))
		view.set_card(rarity, CardArt.textures_for(
				str(group.get("card_id", "")), rarity, str(group.get("art_path", ""))), {
			"name": str(group.get("name", group.get("card_id", ""))),
			"set_id": set_id,
		})
		view.set_variant(variant)
		view.visible = true


func _update_info_panel() -> void:
	if _groups.is_empty() or _index >= _groups.size():
		return
	var group := _groups[_index]
	var rarity := str(group.get("rarity", "common"))
	var set_id := str(group.get("set_id", ""))
	var variant := str(group.get("variant", "none"))
	
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


# --- helpers --------------------------------------------------------------------


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
	_card_width = cw
	_card_height = ch
	
	_card_holder.custom_minimum_size = Vector2(cw * 3.0, ch)  # wide enough for 3 cards
	_panel.custom_minimum_size = Vector2(cw, 0.0)
	
	# Position card views
	for view in _card_views:
		if view != null:
			view.custom_minimum_size = Vector2(cw, ch)
	
	_update_card_positions()


## Entrance: the card settles in. Motion has a job (transition), nothing idles.
func _play_entrance() -> void:
	if _screenshot_mode or Motion.reduced or not is_inside_tree():
		return
	
	# Fade in the centered card
	var center_view := _card_views[1]
	if center_view != null:
		center_view.pivot_offset = center_view.size * 0.5
		center_view.scale = Vector2.ONE * 0.97
		center_view.modulate.a = 0.0
		var entrance := create_tween()
		entrance.set_parallel(true)
		var secs := Tokens.duration(&"standard") / 1000.0
		entrance.tween_property(center_view, "modulate:a", 1.0, secs) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		entrance.tween_property(center_view, "scale", Vector2.ONE, secs) \
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
	close_btn.button_down.connect(func() -> void:
		Motion.press(close_btn)
		Sfx.play("tap"))
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
	
	_card_holder = Control.new()
	_card_holder.name = "CardHolder"
	_card_holder.custom_minimum_size = Vector2(300.0, 450.0)
	_card_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_card_holder)
	
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
				Vector2(divider.size.x, divider.size.y * 0.5), c, 1.0))
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
	hint.text = "Drag to catch the light · Swipe to browse"
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
## Three fixed poses:
##   0: mid-drag between two cards (rare silver -> epic gold)
##   1: snapped on a card (legendary galaxy at rest)
##   2: swipe-down at 40% progress (card fading, moving down)

static func demo_groups() -> Array[Dictionary]:
	var c1 := CardCatalogScript.by_id("kat-daily-1735-day")   # rare "KaT · Golden Hour"
	var c2 := CardCatalogScript.by_id("kat-daily-2011-evening")  # epic "KaT · Game Night"
	var c3 := CardCatalogScript.by_id("kat-daily-2344-sleep") # legendary "KaT · Sweet Dreams"
	# Guard against missing catalog entries (should not happen in normal runs)
	if c1.is_empty() or c2.is_empty() or c3.is_empty():
		return []
	return [
		{
			"card_id": str(c1["card_id"]),
			"variant": "silver",
			"name": str(c1["name"]),
			"rarity": str(c1["rarity"]),
			"set_id": str(c1["set_id"]),
			"art_path": str(c1["art_path"]),
			"copies": 2,
			"obtained_at": "2026-10-03T21:14:00",
		},
		{
			"card_id": str(c2["card_id"]),
			"variant": "gold",
			"name": str(c2["name"]),
			"rarity": str(c2["rarity"]),
			"set_id": str(c2["set_id"]),
			"art_path": str(c2["art_path"]),
			"copies": 1,
			"obtained_at": "2026-10-04T18:22:00",
		},
		{
			"card_id": str(c3["card_id"]),
			"variant": "galaxy",
			"name": str(c3["name"]),
			"rarity": str(c3["rarity"]),
			"set_id": str(c3["set_id"]),
			"art_path": str(c3["art_path"]),
			"copies": 1,
			"obtained_at": "2026-10-05T23:41:00",
		},
	]


func screenshot_count() -> int:
	return 3


func screenshot_setup(i: int) -> String:
	_ensure_built()
	_screenshot_mode = true
	var groups := demo_groups()
	match i:
		0:
			# Mid-drag between card 0 (rare silver) and card 1 (epic gold)
			setup_pager(groups, 0)
			_offset = _card_width * 0.5  # halfway between index 0 and 1
			_update_card_positions()
			_card_views[1].use_tilt_override = true
			_card_views[1].tilt_override = Vector2(0.2, -0.1)
			_card_views[0].use_tilt_override = true
			_card_views[0].tilt_override = Vector2(0.2, -0.1)
			return "detail_pager_mid_drag"
		1:
			# Snapped on legendary galaxy
			setup_pager(groups, 2)
			_card_views[1].use_tilt_override = true
			_card_views[1].tilt_override = Vector2(0.5, -0.35)
			return "detail_pager_snapped_legendary"
		_:
			# Swipe-down at 40% progress (simulated via close tween at 0.4)
			setup_pager(groups, 0)
			# Manually set up close animation at 40%
			_card_holder.modulate.a = 0.6
			_card_holder.position.y = 32.0  # 40% of 80px
			_panel.modulate.a = 0.6
			return "detail_pager_swipe_down_40"