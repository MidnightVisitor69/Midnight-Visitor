extends Control
## Dev preview: one epic CardView cycling every non-none holo variant at two
## pinned tilts. 10 shots total, one per variant + tilt. screenshot.gd drives
## screenshot_setup(i) and saves a PNG named after the returned label.
## Dark navy base so the neon-after-hours palette is judged against the right
## background.

const CardViewScene := preload("res://scenes/card/card_view.tscn")
const PlaceholderArt := preload("res://scripts/card/placeholder_art.gd")

## "none" is deliberately excluded: there is nothing foil-shaped to look at.
const SHOWN: Array[String] = ["silver", "rainbow", "gold", "prism", "galaxy"]
const TILTS: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.7, 0.5)]
const CARD_SIZE := Vector2(400, 600)

var _card: CardView
var _art: Dictionary


func _ready() -> void:
	_build()


func screenshot_count() -> int:
	return SHOWN.size() * TILTS.size()


func screenshot_setup(i: int) -> String:
	# screenshot.gd calls this before _ready has necessarily run.
	_build()
	var v := i / TILTS.size()
	var t := i % TILTS.size()
	_configure(SHOWN[v], TILTS[t])
	return "%s_%s" % [SHOWN[v], "flat" if t == 0 else "tilted"]


func _build() -> void:
	if _card != null:
		return
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_card = CardViewScene.instantiate()
	_card.size = CARD_SIZE
	add_child(_card)
	_art = PlaceholderArt.build()
	_centre()


func _configure(variant: String, tilt: Vector2) -> void:
	# Epic carries depth + char/bg, the richest non-legendary tier, so the foil
	# is judged over the effect-heavy case.
	_card.set_card("epic", _art)
	_card.set_variant(variant)
	_card.use_tilt_override = true
	_card.tilt_override = tilt
	_centre()


func _centre() -> void:
	if _card == null:
		return
	# size can still be 0 before the first layout pass (screenshot_setup runs
	# before it); fall back to the project's design resolution.
	var extents := size
	if extents.x <= 0.0 or extents.y <= 0.0:
		extents = Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
			ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	_card.position = (extents - CARD_SIZE) * 0.5
