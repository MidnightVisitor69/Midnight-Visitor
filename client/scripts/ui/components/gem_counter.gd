class_name GemCounter
extends HBoxContainer
## The ONE currency display (AGENTS.md: gems only, never a second currency).
## An amber diamond (drawn, not an image - DESIGNER.md allows no PNG assets)
## plus the count in Unbounded. set_count animates the number so a grant or a
## spend reads as a change, not a flicker (motion with a job).

var _label: Label
var _shown := -1


func _ready() -> void:
	add_theme_constant_override("separation", Tokens.space(&"s8"))
	var icon := GemIcon.new()
	icon.name = "Gem"
	icon.custom_minimum_size = Vector2(28, 28)
	add_child(icon)
	_label = Label.new()
	_label.name = "Count"
	_label.theme_type_variation = "Display"
	_label.add_theme_font_size_override("font_size", Tokens.font_size(&"title"))
	_label.add_theme_color_override("font_color", Tokens.color(&"reward"))
	add_child(_label)
	if _shown >= 0:
		_label.text = str(_shown)
		return
	_shown = 0
	_label.text = "0"


func set_count(value: int) -> void:
	if _label == null:
		_shown = value
		return
	var from := int(_shown) if _shown >= 0 else 0
	_shown = value
	if not is_inside_tree() or from == value:
		_label.text = str(value)
		return
	# Count up over the standard duration; motion that confirms a change.
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_label.text = str(roundi(v)), float(from), float(value),
		Tokens.duration(&"standard") / 1000.0)


func count() -> int:
	return int(_shown)


## The gem: an amber diamond with a 2-px stroke, drawn in code (no PNGs).
class GemIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 2.0
		var pts := PackedVector2Array([
			Vector2(c.x, c.y - r), Vector2(c.x + r, c.y),
			Vector2(c.x, c.y + r), Vector2(c.x - r, c.y),
		])
		var fill := Tokens.color(&"reward")
		fill.a = 0.22
		draw_colored_polygon(pts, fill)
		var stroke := Tokens.color(&"reward")
		for i in 4:
			draw_line(pts[i], pts[(i + 1) % 4], stroke, 2.0, true)
