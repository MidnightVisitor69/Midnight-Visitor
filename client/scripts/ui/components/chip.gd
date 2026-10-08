class_name Chip
extends Button
## Filter chip (collection tab, trade filters): a pill that toggles. Selected
## state is a subtle surface lift plus the cyan text; never a glow.


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0.0, 48.0)


func _ready() -> void:
	theme_type_variation = "ButtonGhost"
	var on := StyleBoxFlat.new()
	on.bg_color = Tokens.color(&"surface_3")
	on.set_corner_radius_all(Tokens.radius(&"pill"))
	on.content_margin_left = Tokens.space(&"s16")
	on.content_margin_right = Tokens.space(&"s16")
	on.content_margin_top = Tokens.space(&"s8")
	on.content_margin_bottom = Tokens.space(&"s8")
	var off: StyleBoxFlat = on.duplicate()
	off.bg_color = Color(Tokens.color(&"surface_2"), 0.35)
	add_theme_stylebox_override("normal", off)
	add_theme_stylebox_override("hover", off)
	add_theme_stylebox_override("pressed", on)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_color_override("font_color", Tokens.color(&"text_secondary"))
	add_theme_color_override("font_pressed_color", Tokens.color(&"accent_secondary"))
	add_theme_font_size_override("font_size", Tokens.font_size(&"label"))
	toggled.connect(func(_on: bool) -> void: _sync_text())
	_sync_text()


func _sync_text() -> void:
	# Weight change reads without colour; text itself never changes.
	add_theme_font_override("font",
			Tokens.ui_font(700) if button_pressed else Tokens.ui_font(500))
