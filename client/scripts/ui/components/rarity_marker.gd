class_name RarityMarker
extends HBoxContainer
## Rarity marker: shape + colour + text. Colourblind-safe by design (task):
## common circle, rare diamond, epic hexagon, legendary star - the shape
## carries the information, the tint only supports it (DESIGNER.md).

const SHAPES := {
	"common": "circle",
	"rare": "diamond",
	"epic": "hexagon",
	"legendary": "star",
}

var _shape: ShapeIcon
var _label: Label
var _rarity := "common"

## Injectable Settings (tests); null means the autoload.
var settings: Node = null


func _ready() -> void:
	add_theme_constant_override("separation", Tokens.space(&"s8"))
	_shape = ShapeIcon.new()
	_shape.name = "Shape"
	_shape.custom_minimum_size = Vector2(Tokens.space(&"s16") + Tokens.space(&"s4"), Tokens.space(&"s16") + Tokens.space(&"s4"))
	add_child(_shape)
	_label = Label.new()
	_label.name = "Text"
	_label.theme_type_variation = "Caption"
	add_child(_label)
	_apply()
	# The Colorblind-friendly rarity setting (D-003) decides whether the text
	# label rides along with the shape. Default on, so the safe form is what a
	# fresh install shows.
	var s := _settings_node()
	if s != null and not s.changed.is_connected(_on_setting_changed):
		s.changed.connect(_on_setting_changed)


func _settings_node() -> Node:
	if settings != null:
		return settings
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Settings")


func _on_setting_changed(key: String) -> void:
	if key == "colorblind_rarity":
		_apply()


## True when rarity must be legible without colour: shape plus label.
func colorblind_safe() -> bool:
	var s := _settings_node()
	return bool(s.get("colorblind_rarity")) if s != null else true


func set_rarity(rarity: String) -> void:
	_rarity = rarity
	if _shape != null:
		_apply()


func rarity() -> String:
	return _rarity


func _apply() -> void:
	_shape.shape = str(SHAPES.get(_rarity, "circle"))
	_shape.tint = Tokens.rarity_color(_rarity)
	_shape.queue_redraw()
	if _label != null:
		_label.text = _rarity.capitalize()
		_label.add_theme_color_override("font_color", Tokens.color(&"text_secondary"))
		# Off = the compact marker: shape only, no word.
		_label.visible = colorblind_safe()


## The shape glyphs, 2-px stroke (DESIGNER.md icon rule), drawn in code.
class ShapeIcon extends Control:
	var shape := "circle"
	var tint := Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 2.0
		var pts := PackedVector2Array()
		match shape:
			"circle":
				draw_arc(c, r, 0.0, TAU, 32, tint, 2.0, true)
				return
			"diamond":
				pts = PackedVector2Array([Vector2(c.x, c.y - r),
						Vector2(c.x + r, c.y), Vector2(c.x, c.y + r),
						Vector2(c.x - r, c.y)])
			"hexagon":
				for i in 6:
					var a := TAU * i / 6.0 - PI / 2.0
					pts.append(c + Vector2(cos(a), sin(a)) * r)
			"star":
				for i in 10:
					var a := TAU * i / 10.0 - PI / 2.0
					var rr := r if i % 2 == 0 else r * 0.45
					pts.append(c + Vector2(cos(a), sin(a)) * rr)
		if pts.size() >= 3:
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, tint, 2.0, true)
