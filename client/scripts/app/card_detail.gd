extends Control
## Card detail (T-008): the showpiece. One card, big, tiltable, nothing else -
## name, rarity, set, variant, how many you own, when you got it, one way out
## (close button top-left or swipe down). AGENTS.md: the pack opening and card
## detail views are the showpiece; every other screen stays quiet.
##
## Opened by the Collection tab as a full-screen overlay. Also loadable as its
## own scene, which is how the screenshot harness captures it.

const CardViewScene := preload("res://scenes/card/card_view.tscn")

const MIN_TAP_DP := 48.0
## Swipe-down-to-close: mostly-vertical fling of at least this many pixels.
const SWIPE_DOWN_PX := 140.0
const BG_COLOR := Color(0.031, 0.047, 0.118, 0.97)

signal closed

var _built := false
var _screenshot_mode := false
var _swipe_from := Vector2.ZERO
var _swiping := false

var _card: CardView
var _name_label: Label
var _rarity_label: Label
var _owned_label: Label
var _obtained_label: Label


func _ready() -> void:
	_ensure_built()


## group: one collection group as collection_tab.gd builds it
## (card_id, variant, name, rarity, set_id, art_path, copies, obtained_at).
func setup(group: Dictionary) -> void:
	_ensure_built()
	visible = true
	var rarity := str(group.get("rarity", "common"))
	_card.set_card(rarity, CardArt.textures_for(
			str(group.get("card_id", "")), rarity, str(group.get("art_path", ""))))
	_card.set_variant(str(group.get("variant", "none")))
	_name_label.text = str(group.get("name", group.get("card_id", "")))
	_rarity_label.text = "%s · %s%s" % [
		str(group.get("rarity", "")).capitalize(),
		str(group.get("set_id", "")),
		_variant_suffix(str(group.get("variant", "none"))),
	]
	_owned_label.text = "Owned x %d" % maxi(int(group.get("copies", 1)), 1)
	_obtained_label.text = _obtained_phrase(str(group.get("obtained_at", "")))


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
static func _variant_suffix(variant: String) -> String:
	# "none" is a real enum value, not an absence - it just has no display name.
	return "" if variant == "none" else " · %s" % variant.capitalize()
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
		return "Obtained %s %d" % [months[m - 1], day]
	return "Obtained %s" % iso


# --- construction ----------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	# Scrim behind everything: text never sits on busy art without one.
	var bg := ColorRect.new()
	bg.name = "Scrim"
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(MIN_TAP_DP * 2.0, MIN_TAP_DP)
	close_btn.pressed.connect(close)
	close_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	close_btn.offset_left = 12.0
	close_btn.offset_top = 12.0
	close_btn.offset_right = 12.0 + MIN_TAP_DP * 2.0
	close_btn.offset_bottom = 12.0 + MIN_TAP_DP
	add_child(close_btn)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(col)

	var card_holder := Control.new()
	card_holder.name = "CardHolder"
	card_holder.custom_minimum_size = Vector2(300.0, 450.0)
	card_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(card_holder)

	# Real tilt: device tilt on the phone, drag on the card in tests. No
	# override, because interacting with the card is the point of this screen.
	_card = CardViewScene.instantiate() as CardView
	_card.name = "Card"
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_holder.add_child(_card)

	_name_label = Label.new()
	_name_label.name = "Name"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_name_label)

	_rarity_label = Label.new()
	_rarity_label.name = "Rarity"
	_rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_rarity_label)

	_owned_label = Label.new()
	_owned_label.name = "Owned"
	_owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_owned_label)

	_obtained_label = Label.new()
	_obtained_label.name = "Obtained"
	_obtained_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obtained_label.visible = false
	col.add_child(_obtained_label)


# --- screenshots ----------------------------------------------------------------
## Two fixed poses, no randomness: a rare silver at rest, and a legendary
## galaxy tilted - the two ends of the holo showpiece.

static func demo_group() -> Dictionary:
	return {
		"card_id": "seraph-gold",
		"variant": "silver",
		"name": "Seraph Gold",
		"rarity": "rare",
		"set_id": "launch-01",
		"art_path": "placeholder/rare.png",
		"copies": 2,
		"obtained_at": "2026-10-03T21:14:00",
	}


static func demo_legendary() -> Dictionary:
	return {
		"card_id": "noir-ember",
		"variant": "galaxy",
		"name": "Noir Ember",
		"rarity": "legendary",
		"set_id": "noir",
		"art_path": "placeholder/legendary.png",
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
