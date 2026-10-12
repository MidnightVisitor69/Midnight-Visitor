class_name Sheet
extends PanelContainer
## Bottom sheet with a grab handle (task D-001). It slides over the screen's
## bottom third and closes by handle tap, tap outside, or swipe down. Emits
## `closed` so the owning screen can restore its state. Never full-screen:
## the screen it interrupts must stay visible above the sheet.


signal closed

const MIN_HEIGHT := 240.0
## Swipe-down gesture: mostly-vertical drag of at least this many px.
const SWIPE_DOWN_PX := 120.0

var _handle: Control
var _content: VBoxContainer
var _press_at := Vector2.ZERO


func _init() -> void:
	# Build in _init so content()/configuration work before the node enters
	# the tree (the showcase and tests configure sheets off-tree).
	add_theme_stylebox_override("panel", Surfaces.panel(2))
	_handle = Control.new()
	_handle.name = "GrabHandle"
	_handle.custom_minimum_size = Vector2(0, Tokens.space(&"s24"))
	_handle.draw.connect(_draw_handle)
	_handle.gui_input.connect(_on_handle_input)
	add_child(_handle)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.add_theme_constant_override("separation", Tokens.space(&"s12"))
	add_child(_content)


## Add rows to the sheet through here; direct add_child lands on the panel.
func content() -> VBoxContainer:
	return _content


func _draw_handle() -> void:
	var w := _handle.size.x * 0.18
	var y := _handle.size.y * 0.5
	var from := Vector2(_handle.size.x * 0.5 - w * 0.5, y)
	var to := Vector2(_handle.size.x * 0.5 + w * 0.5, y)
	_handle.draw_line(from, to, Tokens.color(&"outline"), Tokens.space(&"s4"), true)


func _on_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_at = event.position
		elif _press_at.distance_to(event.position) < Tokens.space(&"s16"):
			close()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		# Swipe down: mostly-vertical, past the threshold -> close.
		var d: Vector2 = event.position - _press_at
		if d.y > SWIPE_DOWN_PX and absf(d.y) > absf(d.x) * 1.5:
			close()


func close() -> void:
	closed.emit()
	visible = false
