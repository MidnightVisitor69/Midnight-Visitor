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


## Set the displayed count. Any change tweens through Motion.count_up_value
## (clamped ease-out), so the counter never jumps and never overshoots; only
## an equal value or a detached label sets the text directly. `duration_ms`
## defaults to the standard duration token; the daily claim passes
## Motion.CLAIM_COUNT_UP_MS for its longer count-up.
func set_count(value: int, duration_ms: float = -1.0) -> void:
	if _label == null:
		_shown = value
		return
	var from := int(_shown) if _shown >= 0 else 0
	_shown = value
	if not is_inside_tree() or from == value:
		_label.text = str(value)
		return
	if duration_ms <= 0.0:
		duration_ms = Tokens.duration(&"standard")
	# Raw progress in, eased value out: the curve lives in Motion so every
	# counter in the game counts the same way (and is testable without a tree).
	var tw := create_tween()
	tw.tween_method(func(p: float) -> void:
		_label.text = str(roundi(Motion.count_up_value(float(from), float(value), p))),
		0.0, 1.0, duration_ms / 1000.0)


func count() -> int:
	# _shown is -1 until the first set_count; the counter reads as 0 until then.
	return int(_shown) if _shown >= 0 else 0


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
