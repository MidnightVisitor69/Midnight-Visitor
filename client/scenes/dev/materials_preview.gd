extends Control
## Dev preview: all four rarity materials at two tilts, card back, and
## legendary with gold holo. screenshot.gd drives screenshot_setup(i) and
## saves one PNG per call. Dark navy so the neon-after-hours palette is
## judged against the right base.

const CardViewScene := preload("res://scenes/card/card_view.tscn")
const CardBackScene := preload("res://scenes/card/card_back.tscn")
const PlaceholderArt := preload("res://scripts/card/placeholder_art.gd")

const RARITIES: Array[String] = ["common", "rare", "epic", "legendary"]
const TILTS: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.8, -0.6)]
const CARD_SIZE := Vector2(400, 600)

var _cards: Array[CardView] = []
var _back: CardBack
var _art: Dictionary


func _ready() -> void:
	_build()


func screenshot_count() -> int:
	return 10


func screenshot_setup(i: int) -> String:
	# screenshot.gd calls this before _ready has necessarily run.
	_build()
	match i:
		0, 1, 2, 3, 4, 5, 6, 7:
			# 0-7: four rarities × two tilts
			var r := i / 2
			var t := i % 2
			_configure_card(r, TILTS[t])
			return "%s_%s" % [RARITIES[r], "flat" if t == 0 else "tilted"]
		8:
			# 8: card back
			_configure_back()
			return "card_back"
		9:
			# 9: legendary with gold holo
			_configure_card(3, TILTS[1], "gold")
			return "legendary_gold_foil"
		_:
			return "unknown"


func _build() -> void:
	if _cards.size() > 0:
		return
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_art = PlaceholderArt.build()

	# Create 4 card views (one per rarity)
	for i in 4:
		var card = CardViewScene.instantiate()
		card.size = CARD_SIZE
		card.use_tilt_override = true
		add_child(card)
		_cards.append(card)

	# Card back
	_back = CardBackScene.instantiate()
	_back.size = CARD_SIZE
	_back.use_tilt_override = true
	add_child(_back)

	_centre_all()


func _configure_card(rarity_idx: int, tilt: Vector2, variant: String = "none") -> void:
	for i in _cards.size():
		_cards[i].visible = (i == rarity_idx)
		if i == rarity_idx:
			_cards[i].set_card(RARITIES[i], _art, {"name": "Test Character", "set_id": "test"})
			_cards[i].tilt_override = tilt
			_cards[i].set_variant(variant)
	_centre_all()


func _configure_back() -> void:
	for c in _cards:
		c.visible = false
	_back.visible = true
	_back.tilt_override = Vector2(0.8, -0.6)
	_centre_all()


func _centre_all() -> void:
	var extents := size
	if extents.x <= 0.0 or extents.y <= 0.0:
		extents = Vector2(
				ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
				ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	var pos := (extents - CARD_SIZE) * 0.5
	for c in _cards:
		c.position = pos
	_back.position = pos