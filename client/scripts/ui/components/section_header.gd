class_name SectionHeader
extends HBoxContainer
## Quiet section header: Title text left, optional trailing action right.
## One per section, never a second CTA (AGENTS.md: no competing CTAs).

var _title: Label
var _action: Label


func _ready() -> void:
	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = "Title"
	add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)
	_action = Label.new()
	_action.name = "Action"
	_action.theme_type_variation = "Caption"
	_action.add_theme_color_override("font_color", Tokens.color(&"accent_secondary"))
	_action.visible = false
	add_child(_action)
	if _title.text.is_empty():
		_title.text = "Section"


func setup(title: String, action := "") -> void:
	if _title == null:
		# Not in the tree yet: store in the label; _ready fills the rest.
		_pending_title = title
		_pending_action = action
		return
	_title.text = title
	_action.text = action
	_action.visible = not action.is_empty()


func title_text() -> String:
	return _title.text if _title != null else _pending_title


func action_text() -> String:
	return _action.text if _action != null and not _action.text.is_empty() else _pending_action


var _pending_title := ""
var _pending_action := ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY and not _pending_title.is_empty():
		setup(_pending_title, _pending_action)
		_pending_title = ""
		_pending_action = ""
