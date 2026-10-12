class_name CardBack
extends Control
## Card back: "after hours" moon + neon sign line art on navy with a subtle
## foil pattern. Used face-down in pack opening and anywhere a card is hidden.
## All procedural - no image files.

const BACK_SHADER := preload("res://shaders/card/card_back.gdshader")

var _back: ColorRect
var _radius := 0.0
var _tilt_input: TiltInput

var tilt_override := Vector2.ZERO
var use_tilt_override := false


func _ready() -> void:
	_back = get_node("BackFace")
	_tilt_input = TiltInput.new()
	_tilt_input.name = "TiltInput"
	add_child(_tilt_input)
	resized.connect(_apply_layout)
	_apply_layout()


func _apply_layout() -> void:
	var w := size.x
	_radius = clampf(w * 0.05, 6.0, 18.0)
	if _back.material is ShaderMaterial:
		var mat := _back.material as ShaderMaterial
		mat.set_shader_parameter("rect_size", size)
		mat.set_shader_parameter("corner_radius", _radius)
		# Colors from tokens
		mat.set_shader_parameter("bg_color", Tokens.color(&"bg"))
		mat.set_shader_parameter("foil_color", Tokens.color(&"accent_secondary"))
		mat.set_shader_parameter("moon_color", Color(1.0, 0.95, 0.85))
		mat.set_shader_parameter("neon_color", Tokens.color(&"accent"))


func _process(_delta: float) -> void:
	_apply_tilt()


func _apply_tilt() -> void:
	if _back.material is ShaderMaterial:
		var mat := _back.material as ShaderMaterial
		var t := tilt_override if use_tilt_override else _tilt_input.tilt
		var motion := 0.0 if Motion.reduced else 1.0
		mat.set_shader_parameter("tilt", t)
		mat.set_shader_parameter("motion", motion)
		mat.set_shader_parameter("time", Time.get_ticks_msec() * 0.001)


func _gui_input(event: InputEvent) -> void:
	if use_tilt_override:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_tilt_input.begin_drag()
		else:
			_tilt_input.end_drag()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_tilt_input.add_drag(event.relative)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_tilt_input.begin_drag()
		else:
			_tilt_input.end_drag()
	elif event is InputEventScreenDrag:
		_tilt_input.add_drag(event.relative)