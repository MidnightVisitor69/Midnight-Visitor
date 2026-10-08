class_name Toast
extends PanelContainer
## A short confirmation that slides up from the bottom and leaves by itself.
## Motion has one job here: confirm an action happened (AGENTS.md). One toast
## at a time; showing a new one replaces the old, it never stacks.

const SHOWN_MS := 2200

var _label: Label
var _tween: Tween


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", Surfaces.panel(3, &"pill"))
	_label = Label.new()
	_label.name = "Text"
	_label.theme_type_variation = "Body"
	_label.add_theme_color_override("font_color", Tokens.color(&"text_primary"))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)


func show_message(text: String) -> void:
	_label.text = text
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = true
	modulate.a = 0.0
	var t := Tokens.duration(&"standard") / 1000.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, t)
	_tween.tween_interval(SHOWN_MS / 1000.0)
	_tween.tween_property(self, "modulate:a", 0.0, t)
	_tween.tween_callback(func() -> void: visible = false)


func text() -> String:
	return _label.text if _label != null else ""
