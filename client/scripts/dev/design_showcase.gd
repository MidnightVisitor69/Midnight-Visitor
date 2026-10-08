extends Control
## The design showcase (D-001): every token and component on one scrollable
## page, for the dev's phone review. Screenshot states: top, middle, bottom.

const COMPONENT_SCENES := {
	"gem_counter": preload("res://scenes/ui/components/gem_counter.tscn"),
	"chip": preload("res://scenes/ui/components/chip.tscn"),
	"badge": preload("res://scenes/ui/components/badge.tscn"),
	"toast": preload("res://scenes/ui/components/toast.tscn"),
	"sheet": preload("res://scenes/ui/components/sheet.tscn"),
	"section_header": preload("res://scenes/ui/components/section_header.tscn"),
	"rarity_marker": preload("res://scenes/ui/components/rarity_marker.tscn"),
}

var _scroll: ScrollContainer
var _built := false


func _ready() -> void:
	_build()


## Idempotent: the screenshot harness calls screenshot_setup(0) before the
## first frame processes _ready, so the page must be buildable on demand.
func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := AppBackground.new()
	add_child(bg)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	var page := VBoxContainer.new()
	page.name = "Page"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", Tokens.space(&"s16"))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", Tokens.space(&"s24"))
	margin.add_theme_constant_override("margin_right", Tokens.space(&"s24"))
	margin.add_theme_constant_override("margin_top", Tokens.space(&"s24"))
	margin.add_theme_constant_override("margin_bottom", Tokens.space(&"s48"))
	margin.add_child(page)
	_scroll.add_child(margin)

	_section(page, "Type scale")
	for size_name in [&"display_xl", &"display_l", &"display_m", &"title", &"body", &"caption"]:
		var l := Label.new()
		l.text = "Neon After-Hours %s" % size_name
		l.add_theme_font_size_override("font_size", Tokens.font_size(size_name))
		l.add_theme_font_override("font",
				Tokens.display_font(700) if String(size_name).begins_with("display")
				else Tokens.ui_font())
		l.add_theme_color_override("font_color",
				Tokens.color(&"text_primary") if not String(size_name).begins_with("caption")
				else Tokens.color(&"text_secondary"))
		page.add_child(l)

	_section(page, "Colors")
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", Tokens.space(&"s8"))
	for role in [&"surface_1", &"surface_2", &"surface_3", &"accent",
			&"accent_secondary", &"reward", &"success", &"danger"]:
		var sw := ColorRect.new()
		sw.color = Tokens.color(role)
		sw.custom_minimum_size = Vector2(48, 48)
		sw.tooltip_text = str(role)
		swatches.add_child(sw)
	page.add_child(swatches)

	_section(page, "Buttons")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.space(&"s12"))
	row.add_child(_button("Primary", ""))
	row.add_child(_button("Secondary", "ButtonSecondary"))
	row.add_child(_button("Ghost", "ButtonGhost"))
	page.add_child(row)

	_section(page, "Components")
	# Explicit configure-then-add: GDScript lambdas inside multi-line call
	# arguments parse unreliably, and plain statements read better anyway.
	var gems = COMPONENT_SCENES["gem_counter"].instantiate()
	gems.set_count(1600)
	page.add_child(gems)
	var chip_c = COMPONENT_SCENES["chip"].instantiate()
	chip_c.text = "Epic"
	page.add_child(chip_c)
	var badge_c = COMPONENT_SCENES["badge"].instantiate()
	badge_c.text = "x3"
	page.add_child(badge_c)
	var head = COMPONENT_SCENES["section_header"].instantiate()
	head.setup("Your collection", "view all")
	page.add_child(head)
	for rarity in ["common", "rare", "epic", "legendary"]:
		var marker = COMPONENT_SCENES["rarity_marker"].instantiate()
		marker.set_rarity(rarity)
		page.add_child(marker)
	var toast_c = COMPONENT_SCENES["toast"].instantiate()
	toast_c.show_message("Daily reward claimed - 40 gems")
	page.add_child(toast_c)
	var sheet_c = COMPONENT_SCENES["sheet"].instantiate()
	var sheet_label := Label.new()
	sheet_label.text = "Bottom sheet content"
	sheet_label.theme_type_variation = "Body"
	sheet_c.content().add_child(sheet_label)
	page.add_child(sheet_c)

	# Spacing steps, so the 8-px grid is inspectable on the phone.
	_section(page, "Spacing 4..48")
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", Tokens.space(&"s8"))
	for step in Tokens.tokens().spacing.values():
		var bar := ColorRect.new()
		bar.color = Tokens.color(&"outline")
		bar.custom_minimum_size = Vector2(maxi(4, int(step)), 24)
		sp.add_child(bar)
	page.add_child(sp)


func _section(page: VBoxContainer, title: String) -> void:
	var h := Label.new()
	h.text = title
	h.theme_type_variation = "Title"
	h.add_theme_color_override("font_color", Tokens.color(&"accent_secondary"))
	page.add_child(h)


func _button(text: String, variation: String) -> Button:
	var b := Button.new()
	b.text = text
	if not variation.is_empty():
		b.theme_type_variation = variation
	return b

func screenshot_count() -> int:
	return 3


func screenshot_setup(i: int) -> String:
	_build()
	if _scroll == null:
		return "showcase_%d" % i
	match i:
		0:
			_scroll.scroll_vertical = 0
			return "showcase_top"
		1:
			_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value * 0.5)
			return "showcase_middle"
		_:
			_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
			return "showcase_bottom"
