extends SceneTree
## Builds app_theme.tres from tokens.tres (D-001). Run headless after changing
## a token value; the OUTPUT IS COMMITTED so runtime never builds themes:
##   godot --headless --path client --script res://theme/build_theme.gd
##
## Godot themes cascade, so every screen that does not opt out inherits the
## look for free (task goal). Type variations carry the named styles:
##   Buttons: Button (primary), ButtonSecondary, ButtonGhost
##   Labels:  Display, Title, Body, Caption
## The base look: Manrope everywhere, Unbounded for Display/Title, navy
## surfaces, neon reserved for the primary edge and the active tab bar.

const SurfacesScript := preload("res://theme/surfaces.gd")

const OUT := "res://theme/app_theme.tres"


func _initialize() -> void:
	var t := Theme.new()

	t.default_font = Tokens.ui_font()
	t.default_font_size = Tokens.font_size(&"body")

	_button(t, "Button", SurfacesScript.button_primary(),
			SurfacesScript.button_primary_pressed(), SurfacesScript.button_disabled(),
			Tokens.color(&"text_primary"))
	t.set_type_variation("ButtonSecondary", "Button")
	_button(t, "ButtonSecondary", SurfacesScript.button_secondary(),
			SurfacesScript.button_secondary(), SurfacesScript.button_disabled(),
			Tokens.color(&"text_primary"))
	t.set_type_variation("ButtonGhost", "Button")
	_button(t, "ButtonGhost", SurfacesScript.button_ghost(),
			SurfacesScript.button_ghost(), SurfacesScript.button_disabled(),
			Tokens.color(&"accent_secondary"))
	for variant in ["Button", "ButtonSecondary", "ButtonGhost"]:
		t.set_font("font", variant, Tokens.ui_font(600))
		t.set_font_size("font_size", variant, Tokens.font_size(&"label"))
		# 48-dp tap targets (AGENTS.md thumb-first).
		var sb: StyleBoxFlat = t.get_stylebox("normal", variant)
		if sb != null and sb.content_margin_top + sb.content_margin_bottom < 24:
			sb.content_margin_top = Tokens.space(&"s16")
			sb.content_margin_bottom = Tokens.space(&"s16")

	_label_variant(t, "Display", Tokens.display_font(700), &"display_l", &"text_primary")
	_label_variant(t, "Title", Tokens.display_font(600), &"title", &"text_primary")
	_label_variant(t, "Body", Tokens.ui_font(), &"body", &"text_primary")
	_label_variant(t, "Caption", Tokens.ui_font(500), &"caption", &"text_secondary")

	t.set_stylebox("panel", "PanelContainer", SurfacesScript.panel(1))

	_bottom_tab_bar(t)

	_line_edit(t)

	# Toggle: label colours only; the knob draws from the engine default.
	t.set_color("font_color", "CheckButton", Tokens.color(&"text_primary"))
	t.set_color("font_pressed_color", "CheckButton", Tokens.color(&"text_primary"))

	_slider(t)

	_option_button(t)

	_scrollbars(t)

	t.set_stylebox("panel", "PopupPanel", SurfacesScript.panel(2))

	# Bottom sheets (task sheet component) rest on PopupPanel; keep tooltips
	# quiet: dark surface, caption text.
	var tip := SurfacesScript.panel(3, &"small")
	tip.bg_color = Tokens.color(&"surface_3")
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", Tokens.color(&"text_secondary"))
	t.set_font_size("font_size", "TooltipLabel", Tokens.font_size(&"caption"))

	var err := ResourceSaver.save(t, OUT)
	if err != OK:
		push_error("cannot save %s: %d" % [OUT, err])
		quit(1)
		return
	print("WROTE " + OUT)
	quit(0)


func _button(t: Theme, type_name: String, normal: StyleBox, pressed: StyleBox,
		disabled: StyleBox, font_color: Color) -> void:
	t.set_stylebox("normal", type_name, normal)
	t.set_stylebox("hover", type_name, normal)
	t.set_stylebox("pressed", type_name, pressed)
	t.set_stylebox("disabled", type_name, disabled)
	t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
	t.set_color("font_color", type_name, font_color)
	t.set_color("font_hover_color", type_name, font_color)
	t.set_color("font_pressed_color", type_name, font_color)
	t.set_color("font_disabled_color", type_name, Tokens.color(&"text_disabled"))


func _label_variant(t: Theme, type_name: String, font: Font, size: StringName,
		text_color: StringName) -> void:
	t.set_type_variation(type_name, "Label")
	t.set_font("font", type_name, font)
	t.set_font_size("font_size", type_name, Tokens.font_size(size))
	t.set_color("font_color", type_name, Tokens.color(text_color))


## The 4-tab bar: active tab gets the thin neon bar under its label, inactive
## tabs stay quiet (DESIGNER.md: neon is a precious resource).
func _bottom_tab_bar(t: Theme) -> void:
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(Tokens.color(&"surface_1"), 0.0)
	selected.border_color = Tokens.color(&"accent")
	selected.border_width_bottom = 3
	selected.content_margin_top = Tokens.space(&"s8")
	selected.content_margin_bottom = Tokens.space(&"s8")
	var unselected := StyleBoxFlat.new()
	unselected.bg_color = Color(Tokens.color(&"surface_1"), 0.0)
	unselected.content_margin_top = Tokens.space(&"s8")
	unselected.content_margin_bottom = Tokens.space(&"s8")
	t.set_stylebox("tab_selected", "TabBar", selected)
	t.set_stylebox("tab_unselected", "TabBar", unselected)
	t.set_color("font_selected_color", "TabBar", Tokens.color(&"text_primary"))
	t.set_color("font_color", "TabBar", Tokens.color(&"text_secondary"))
	t.set_font("font", "TabBar", Tokens.ui_font(600))
	t.set_font_size("font_size", "TabBar", Tokens.font_size(&"label"))


func _line_edit(t: Theme) -> void:
	var normal := SurfacesScript.panel(1, &"small")
	normal.content_margin_top = Tokens.space(&"s12")
	normal.content_margin_bottom = Tokens.space(&"s12")
	var focus: StyleBoxFlat = normal.duplicate()
	focus.border_color = Tokens.color(&"accent_secondary")
	focus.border_width_bottom = 2
	t.set_stylebox("normal", "LineEdit", normal)
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "LineEdit", Tokens.color(&"text_primary"))
	t.set_color("caret_color", "LineEdit", Tokens.color(&"accent_secondary"))
	t.set_color("font_placeholder_color", "LineEdit", Tokens.color(&"text_disabled"))


func _slider(t: Theme) -> void:
	var groove := StyleBoxFlat.new()
	groove.bg_color = Tokens.color(&"surface_3")
	groove.set_corner_radius_all(Tokens.radius(&"pill"))
	groove.content_margin_top = Tokens.space(&"s4")
	groove.content_margin_bottom = Tokens.space(&"s4")
	var filled: StyleBoxFlat = groove.duplicate()
	filled.bg_color = Tokens.color(&"accent")
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)


func _option_button(t: Theme) -> void:
	t.set_stylebox("normal", "OptionButton", SurfacesScript.button_secondary())
	t.set_stylebox("hover", "OptionButton", SurfacesScript.button_secondary())
	t.set_stylebox("pressed", "OptionButton", SurfacesScript.button_secondary())
	t.set_stylebox("disabled", "OptionButton", SurfacesScript.button_disabled())
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_color("font_color", "OptionButton", Tokens.color(&"text_primary"))
	t.set_font_size("font_size", "OptionButton", Tokens.font_size(&"label"))
	# The popup list mirrors the option button's surfaces.
	t.set_stylebox("panel", "PopupMenu", SurfacesScript.panel(2))
	t.set_color("font_color", "PopupMenu", Tokens.color(&"text_primary"))
	t.set_color("font_hover_color", "PopupMenu", Tokens.color(&"accent_secondary"))


func _scrollbars(t: Theme) -> void:
	for type_name in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(Tokens.color(&"surface_2"), 0.0)
		t.set_stylebox("scroll", type_name, track)
		t.set_stylebox("grabber", type_name, SurfacesScript.scrollbar_grabber())
		t.set_stylebox("grabber_highlight", type_name, SurfacesScript.scrollbar_grabber())
		t.set_stylebox("grabber_pressed", type_name, SurfacesScript.scrollbar_grabber())
