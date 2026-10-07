class_name CardView
extends Control
## Renders one card at any rarity tier from the same art inputs. All motion is
## shader driven by a single tilt vector, so one piece of art gets every effect
## for free (AGENTS.md "Card visuals"). The node itself only swaps textures and
## sets a few uniforms per frame, which is what keeps it 60 fps on mid phones.

const PARALLAX_SHADER := preload("res://shaders/card/card_parallax.gdshader")
const LIGHT_SHADER := preload("res://shaders/card/card_light.gdshader")

const TIERS: Array[String] = ["common", "rare", "epic", "legendary"]

## Foil strength and how hard the depth map suppresses it over the figure.
const HOLO_INTENSITY := 1.0
const HOLO_DEPTH_MASK := 0.55

## Placeholder palette until client/theme/tokens.tres lands (AGENTS.md task 3).
const FRAME_COLORS := {
	"common": Color(0.42, 0.46, 0.58),
	"rare": Color(0.70, 0.76, 0.88),
	"epic": Color(0.62, 0.40, 0.95),
	"legendary": Color(1.0, 1.0, 1.0),
}
const FRAME_MARGIN := 8.0

var rarity := "common"
## Requested holo variant; only drawn when HoloVariants.applies_to() agrees.
var variant := "none"
## Pin the tilt for screenshots/tests; ignored unless use_tilt_override is on.
var tilt_override := Vector2.ZERO
var use_tilt_override := false

var _art: Dictionary = {}
var _tier := "common"

var _built := false
var _root: Control
var _frame: Panel
var _base: TextureRect
var _bg: TextureRect
var _char: TextureRect
var _light: ColorRect
var _holo: ColorRect
var _particles: CPUParticles2D
var _tilt_input: TiltInput
var _materials: Array[ShaderMaterial] = []


func _ready() -> void:
	_ensure_built()


## art keys: base / depth / char / bg, each a Texture2D or null.
func set_card(p_rarity: String, art: Dictionary) -> void:
	rarity = p_rarity
	_art = art
	_tier = _resolve_tier(p_rarity, art)
	_ensure_built()
	_apply_tier()


## The tier actually rendered after any fallback.
func active_tier() -> String:
	return _tier


## Request a foil. The rarity rule is re-checked here: a common drops it even if
## the server (or a bad payload) hands us "gold".
func set_variant(p_variant: String) -> void:
	variant = p_variant
	_ensure_built()
	_apply_holo()


## Resource path of the shader currently foiling the card, "" when none is.
func holo_shader_path() -> String:
	if _holo == null or not _holo.visible:
		return ""
	var mat := _holo.material as ShaderMaterial
	if mat == null or mat.shader == null:
		return ""
	return mat.shader.resource_path


## The art layers actually used, in draw order (plus depth / particle accents
## and the foil overlay when one is active).
func layer_names() -> PackedStringArray:
	var names: PackedStringArray
	match _tier:
		"rare":
			names = PackedStringArray(["base", "depth"])
		"epic":
			names = PackedStringArray(["bg", "char", "depth"])
		"legendary":
			names = PackedStringArray(["bg", "char", "depth", "particles"])
		_:
			names = PackedStringArray(["base"])
	if _holo != null and _holo.visible:
		names.append("holo")
	return names


func _process(_delta: float) -> void:
	_apply_tilt()


func _gui_input(event: InputEvent) -> void:
	# Desktop/editor alternative to the accelerometer: drag over the card.
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


# --- tier resolution -------------------------------------------------------

## Rank of the richest tier the supplied art can actually feed.
static func _supported_rank(art: Dictionary) -> int:
	if art.get("base") == null:
		return -1
	if art.get("depth") == null:
		return 0
	if art.get("char") == null or art.get("bg") == null:
		return 1
	return 3


func _resolve_tier(requested: String, art: Dictionary) -> String:
	var want := maxi(TIERS.find(requested), 0)
	var got := mini(want, _supported_rank(art))
	got = maxi(got, 0)
	if got != want:
		push_warning("CardView: '%s' needs layers this art lacks; using '%s'." %
				[requested, TIERS[got]])
	return TIERS[got]


# --- node construction -----------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_bg = _make_layer()
	_base = _make_layer()
	_char = _make_layer()

	_light = ColorRect.new()
	_light.set_anchors_preset(Control.PRESET_FULL_RECT)
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light.visible = false
	_root.add_child(_light)

	_particles = CPUParticles2D.new()
	_particles.amount = 12
	_particles.lifetime = 2.4
	_particles.one_shot = false
	_particles.emitting = false
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.direction = Vector2(0, -1)
	_particles.spread = 35.0
	_particles.gravity = Vector2(0, -9)
	_particles.initial_velocity_min = 6.0
	_particles.initial_velocity_max = 16.0
	_particles.scale_amount_min = 1.5
	_particles.scale_amount_max = 3.0
	_particles.color = Color(0.82, 0.86, 1.0, 0.75)
	_particles.visible = false
	_root.add_child(_particles)

	# Foil overlay: full-card additive sheen driven by the variant shader. It is
	# added after the art so it sits on top of it, but stays under the frame,
	# which is a child of CardView added later.
	_holo = ColorRect.new()
	_holo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_holo.color = Color.WHITE
	_holo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holo.visible = false
	_root.add_child(_holo)

	# Drawn last so the border sits on top of the art.
	_frame = Panel.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_tilt_input = TiltInput.new()
	_tilt_input.name = "TiltInput"
	add_child(_tilt_input)

	resized.connect(_apply_layout)


func _make_layer() -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.visible = false
	_root.add_child(t)
	return t


# --- tier application ------------------------------------------------------

func _apply_tier() -> void:
	_materials.clear()
	for t in [_base, _bg, _char]:
		t.texture = null
		t.material = null
		t.visible = false
	_light.material = null
	_light.visible = false
	_holo.material = null
	_holo.visible = false
	_particles.visible = false
	_particles.emitting = false

	match _tier:
		"common":
			_show(_base, "base")
		"rare":
			_show(_base, "base")
			_base.material = _parallax_material(_art.get("depth"), 1.0)
		"epic", "legendary":
			_show(_bg, "bg")
			_bg.material = _parallax_material(_art.get("depth"), 0.55)
			_show(_char, "char")
			_char.material = _parallax_material(_art.get("depth"), 1.25)
			_light.visible = true
			_light.material = _light_material()

	if _tier == "legendary":
		_particles.visible = true
		_particles.emitting = true

	_update_frame()
	_apply_layout()
	_apply_holo()
	_apply_tilt()


## Builds the foil material for the current variant, or hides the overlay when
## the variant does not apply to this rarity.
func _apply_holo() -> void:
	_holo.material = null
	_holo.visible = false
	if not HoloVariants.applies_to(rarity, variant):
		return
	var shader := HoloVariants.shader_for(variant)
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("ramp", HoloVariants.ramp_for(variant))
	mat.set_shader_parameter("intensity", HOLO_INTENSITY)
	# Rare and up always carry a depth map, so the figure can be spared.
	mat.set_shader_parameter("depth_tex", _art.get("depth"))
	mat.set_shader_parameter("depth_mask", HOLO_DEPTH_MASK)
	mat.set_shader_parameter("tilt", tilt_override if use_tilt_override else _tilt_input.tilt)
	_holo.material = mat
	_holo.visible = true


func _show(layer: TextureRect, key: String) -> void:
	layer.texture = _art.get(key)
	layer.visible = layer.texture != null


func _update_frame() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = FRAME_COLORS.get(rarity, FRAME_COLORS["common"])
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(16)
	_frame.add_theme_stylebox_override("panel", sb)
	_frame.visible = _tier != "legendary"


func _apply_layout() -> void:
	# Legendary is full-art frameless; other tiers keep a quiet placeholder frame.
	var m := 0.0 if _tier == "legendary" else FRAME_MARGIN
	_root.offset_left = m
	_root.offset_top = m
	_root.offset_right = -m
	_root.offset_bottom = -m
	_particles.position = _root.size * 0.5
	_particles.emission_rect_extents = _root.size * Vector2(0.34, 0.42)


func _apply_tilt() -> void:
	var t := tilt_override if use_tilt_override else _tilt_input.tilt
	for mat in _materials:
		mat.set_shader_parameter("tilt", t)
	if _light.material is ShaderMaterial:
		_light.material.set_shader_parameter("tilt", t)
	if _holo.material is ShaderMaterial:
		_holo.material.set_shader_parameter("tilt", t)


func _parallax_material(depth: Variant, strength: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PARALLAX_SHADER
	mat.set_shader_parameter("depth_tex", depth)
	mat.set_shader_parameter("parallax_strength", 0.022 * strength)
	mat.set_shader_parameter("breath_strength", 0.0035)
	mat.set_shader_parameter("tilt", tilt_override if use_tilt_override else Vector2.ZERO)
	_materials.append(mat)
	return mat


func _light_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = LIGHT_SHADER
	mat.set_shader_parameter("tilt", tilt_override if use_tilt_override else Vector2.ZERO)
	return mat
