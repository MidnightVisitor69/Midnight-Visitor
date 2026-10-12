class_name AppBackground
extends TextureRect
## The app background, drawn once (task D-001).
##
## background.gdshader is a static procedural: no TIME, no loop, no animation.
## Even so, running it per frame would be the most expensive pixel in the game,
## so the shader is rendered into a SubViewport with UPDATE_ONCE and this node
## only ever shows the resulting texture. A resize (rotation, window drag)
## re-arms a single re-render.
##
## It sits behind everything and swallows no input: the tab bar and every screen
## above it must keep their taps.

const SHADER := preload("res://theme/background.gdshader")

var _viewport: SubViewport
var _source: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_build()
	resized.connect(_arm_rerender)
	_arm_rerender()


func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "BackgroundRender"
	# Never let the offscreen pass react to a touch meant for the screen above.
	_viewport.disable_3d = true
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.transparent_bg = false
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	# ONE frame. The shader is static, so nothing after this would change a pixel.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	_source = ColorRect.new()
	_source.name = "RainOnGlass"
	_source.set_anchors_preset(Control.PRESET_FULL_RECT)
	_source.color = Tokens.color(&"bg")
	_source.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("base_color", Tokens.color(&"bg"))
	material.set_shader_parameter("haze_color", Tokens.color(&"surface_1"))
	material.set_shader_parameter("neon_a", Tokens.color(&"accent"))
	material.set_shader_parameter("neon_b", Tokens.color(&"accent_secondary"))
	material.set_shader_parameter("warm_color", Tokens.color(&"reward"))
	_source.material = material
	_viewport.add_child(_source)

	texture = _viewport.get_texture()


## The offscreen buffer follows the canvas, not the window: with canvas_items
## stretch the canvas is always the base viewport size, so the render is the same
## on every device and can never be soft.
func _arm_rerender() -> void:
	if _viewport == null:
		return
	var wanted: Vector2i = _canvas_size()
	if wanted.x <= 0 or wanted.y <= 0:
		return
	if _viewport.size != wanted:
		_viewport.size = wanted
	# _source uses PRESET_FULL_RECT anchors, so it fills the viewport automatically.
	# Beads and bokeh are circles, so the shader needs the buffer's shape.
	var material := _source.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("width_over_height", float(wanted.x) / float(wanted.y))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _canvas_size() -> Vector2i:
	var viewport := get_viewport()
	var size: Vector2i = Vector2i.ZERO
	if viewport != null:
		size = viewport.get_visible_rect().size
	if size.x <= 0 or size.y <= 0:
		size = Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
			ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	return Vector2i(maxi(2, size.x), maxi(2, size.y))