class_name Surfaces
extends RefCounted
## StyleBox factories for the layered navy surfaces (D-001, DESIGNER.md):
## "layered navy panels with a 1-px inner highlight on the top edge and a soft
## shadow". Everything reads tokens - no literal colors or px values here.

## Surface fill of the given depth (1..3) with top-edge highlight and shadow.
static func panel(depth := 1, radius_name := &"large") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tokens.color(StringName("surface_%d" % maxi(1, depth)))
	sb.set_corner_radius_all(Tokens.radius(radius_name))
	# 1-px inner highlight on the top edge: the light source is above.
	var lift := Tokens.color(&"text_primary")
	lift.a = 0.06
	sb.border_color = lift
	sb.border_width_top = 1
	# Soft shadow, drawn from the token palette (no hard-coded shadow color).
	var shadow := Color(0.0, 0.0, 0.0, 0.35)
	sb.shadow_color = shadow
	sb.shadow_size = Tokens.space(&"s8")
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_left = Tokens.space(&"s16")
	sb.content_margin_right = Tokens.space(&"s16")
	sb.content_margin_top = Tokens.space(&"s12")
	sb.content_margin_bottom = Tokens.space(&"s12")
	return sb


## The primary CTA: surface-dark fill, 1-px neon edge on the bottom - neon as
## a precious resource, an edge not a glow (DESIGNER.md).
static func button_primary() -> StyleBoxFlat:
	var sb := _button_base()
	sb.bg_color = Tokens.color(&"accent").darkened(0.72)
	sb.border_color = Tokens.color(&"accent")
	sb.border_width_bottom = 2
	return sb


static func button_primary_pressed() -> StyleBoxFlat:
	var sb := button_primary()
	sb.bg_color = Tokens.color(&"accent").darkened(0.82)
	return sb


static func button_secondary() -> StyleBoxFlat:
	var sb := _button_base()
	sb.bg_color = Tokens.color(&"surface_2")
	sb.border_color = Tokens.color(&"outline")
	sb.border_width_bottom = 1
	return sb


static func button_ghost() -> StyleBoxFlat:
	var sb := _button_base()
	sb.bg_color = Color(Tokens.color(&"surface_1"), 0.0)  # transparent fill
	sb.border_color = Color(Tokens.color(&"outline"), 0.0)
	sb.border_width_bottom = 0
	return sb


static func button_disabled() -> StyleBoxFlat:
	var sb := _button_base()
	sb.bg_color = Tokens.color(&"surface_2")
	sb.border_color = Color(Tokens.color(&"outline"), 0.5)
	sb.border_width_bottom = 0
	return sb


static func _button_base() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(Tokens.radius(&"small"))
	sb.content_margin_left = Tokens.space(&"s16")
	sb.content_margin_right = Tokens.space(&"s16")
	sb.content_margin_top = Tokens.space(&"s12")
	sb.content_margin_bottom = Tokens.space(&"s12")
	return sb


## Thin auto-hide-feeling scrollbar: 4-px wide thumb on the outline color.
static func scrollbar_grabber() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tokens.color(&"outline")
	sb.set_corner_radius_all(Tokens.radius(&"pill"))
	return sb
