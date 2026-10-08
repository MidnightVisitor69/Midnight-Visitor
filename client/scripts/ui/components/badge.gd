class_name Badge
extends Label
## Small pill badge for counts on tiles ("x3", "NEW"). Reward amber on a dark
## surface so it never competes with the card art behind it.


func _init() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _ready() -> void:
	add_theme_font_size_override("font_size", Tokens.font_size(&"caption"))
	add_theme_color_override("font_color", Tokens.color(&"reward"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Tokens.color(&"surface_3"), 0.92)
	sb.set_corner_radius_all(Tokens.radius(&"pill"))
	sb.content_margin_left = Tokens.space(&"s8")
	sb.content_margin_right = Tokens.space(&"s8")
	sb.content_margin_top = Tokens.space(&"s4")
	sb.content_margin_bottom = Tokens.space(&"s4")
	add_theme_stylebox_override("normal", sb)
