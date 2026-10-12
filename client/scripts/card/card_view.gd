class_name CardView
extends Control
## Renders one card at any rarity tier from the same art inputs, as a premium
## collectible object. All motion is shader driven by a single tilt vector, so
## one piece of art gets every effect for free (AGENTS.md "Card visuals").
##
## The card is assembled in fixed z-order (draw order), all procedural - no
## image files (DESIGNER.md):
##   child 0  _root   art layers, specular sweep, foil overlay, particles
##            (clipped; the art shaders alpha-mask the rounded silhouette)
##   child 1  _frame  embossed metal band, etched hairlines, rarity gem,
##            corner ornaments - drawn opaque ON the art edge, so the frame
##            band and the art window meet exactly at radius - band
##   child 2  _plate  bottom scrim + name + meta + foil badge (always on top,
##            so text never sits under foil glare)
##   child 3  _tilt_input
##
## Geometry (corner radius, band thickness, plate type sizes) is derived from
## the card's pixel size and clamped to the design tokens, so the same script
## reads correctly at grid size in the collection and at inspection size in the
## detail view. Reduced motion (Motion.reduced) freezes idle shader time and
## particles; tilt response stays, because it is the user's own input.

const PARALLAX_SHADER := preload("res://shaders/card/card_parallax.gdshader")
const LIGHT_SHADER := preload("res://shaders/card/card_light.gdshader")
const MATERIAL_SHADERS := {
	"common": preload("res://shaders/card/material_common.gdshader"),
	"rare": preload("res://shaders/card/material_rare.gdshader"),
	"epic": preload("res://shaders/card/material_epic.gdshader"),
	"legendary": preload("res://shaders/card/material_legendary.gdshader"),
}

const TIERS: Array[String] = ["common", "rare", "epic", "legendary"]

## Foil strength at rest; the detail view multiplies it via foil_emphasis.
const HOLO_INTENSITY := 0.85
## Player's Holo intensity setting (D-003), 0..1. Settings owns it; a static
## here keeps the card lane free of autoload lookups (and deterministic in
## tests, which default it back to 1.0).
static var holo_scale := 1.0
## Battery saver (D-003) turns the particle accents off entirely.
static var particles_enabled := true
## Foil is held back over the figure so the character stays readable.
const HOLO_DEPTH_MASK := 0.55
## Below this width the plate text cannot be read: art only, no plate.
const PLATE_MIN_WIDTH := 132.0

## Geometry as fractions of card width, clamped to tokens at both ends.
const RADIUS_RATIO := 0.05
const FRAME_BAND_RATIO := 0.026
const FULL_ART_BAND_RATIO := 0.008
const NAME_RATIO := 0.062
const META_RATIO := 0.035
const PLATE_PAD_RATIO := 0.032

var rarity := "common"
## Requested holo variant; only drawn when HoloVariants.applies_to() agrees.
var variant := "none"
## Pin the tilt for screenshots/tests; ignored unless use_tilt_override is on.
var tilt_override := Vector2.ZERO
var use_tilt_override := false
## The detail view raises this so the foil reads stronger while inspecting.
var foil_emphasis := 1.0

var _art: Dictionary = {}
var _tier := "common"
var _card_name := ""
var _set_id := ""

# --- geometry (recomputed on layout) ---
var _radius := 0.0        # outer corner radius, px
var _band := 0.0          # frame band thickness, px
var _full_art := false    # legendary art tier: hairline edge, art bleeds out
var _metal := Color.GRAY  # rarity frame metal (for gem/ornaments)
var _plate_top := -1.0
var _plate_bottom := -1.0

var _built := false
var _root: Control
var _frame: FrameLayer
var _plate: PlateLayer
var _base: TextureRect
var _bg: TextureRect
var _char: TextureRect
var _light: ColorRect
var _holo: ColorRect
var _material: ColorRect
var _particles: CPUParticles2D
var _tilt_input: TiltInput
var _name_label: Label
var _meta_label: Label
var _foil_label: Label
var _materials: Array[ShaderMaterial] = []
var _last_motion := -1.0


## Frame ornaments only (gem + corner ornaments). The frame band + material
## effects are now drawn by the material shader on _material (child index 1).
## This layer sits ON the art edge, same as before (pinned by test_holo_variants).
class FrameLayer extends Control:
	var host: CardView

	func _draw() -> void:
		if host == null or size.x < 2.0 or size.y < 2.0:
			return
		_draw_gem()
		_draw_ornaments()

	## Top-centre rarity seal: dark disc + the rarity shape from RarityMarker,
	## so the silhouette language matches the collection's rarity markers.
	func _draw_gem() -> void:
		var r := clampf(host._band * 1.7, 10.0, 26.0)
		if host._full_art:
			r = clampf(size.x * 0.05, 10.0, 26.0)
		var c := Vector2(size.x * 0.5, r + 2.0)
		draw_circle(c, r, Color(Tokens.color(&"card_ink_deep"), 0.92))
		var shape: String = RarityMarker.SHAPES.get(host.rarity, "circle")
		_draw_shape(shape, c, r * 0.55, Tokens.rarity_color(host.rarity), 2.0)

	## Epic gets etched corner diamonds, legendary corner sparkles. Restrained
	## on purpose: the frame frames, it does not decorate itself.
	func _draw_ornaments() -> void:
		if host.rarity not in ["epic", "legendary"]:
			return
		var m := maxf(host._band, 4.0) * 0.78 + 1.0
		var pts := [Vector2(m, m), Vector2(size.x - m, m),
				Vector2(m, size.y - m), Vector2(size.x - m, size.y - m)]
		var ornament: String = "star" if host.rarity == "legendary" else "diamond"
		var color: Color = Tokens.color(&"frame_" + host.rarity).lightened(0.25)
		var r := maxf(host._band * 0.55, 3.0)
		for p in pts:
			_draw_shape(ornament, p, r, color, 1.6)

	func _draw_shape(shape: String, c: Vector2, r: float, color: Color, width: float) -> void:
		var pts := PackedVector2Array()
		match shape:
			"circle":
				draw_arc(c, r, 0.0, TAU, 24, color, width, true)
				return
			"diamond":
				pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0),
						c + Vector2(0, r), c + Vector2(-r, 0)])
			"hexagon":
				for i in 6:
					var a := TAU * i / 6.0 - PI / 2.0
					pts.append(c + Vector2(cos(a), sin(a)) * r)
			"star":
				for i in 10:
					var a := TAU * i / 10.0 - PI / 2.0
					var rr := r if i % 2 == 0 else r * 0.45
					pts.append(c + Vector2(cos(a), sin(a)) * rr)
			_:
				pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0),
						c + Vector2(0, r), c + Vector2(-r, 0)])
		if pts.size() >= 3:
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, color, width, true)


## Bottom scrim + hairline behind the plate text.
class PlateLayer extends Control:
	var host: CardView

	func _draw() -> void:
		if host == null or host._plate_top < 0.0 or size.x < 2.0:
			return
		var y0 := host._plate_top
		var h := host._plate_bottom - y0
		if h <= 0.0:
			return
		draw_texture_rect(CardView._scrim(), Rect2(0.0, y0, size.x, h), false)
		draw_line(Vector2(0.0, y0), Vector2(size.x, y0),
				Color(1.0, 1.0, 1.0, 0.10), 1.0)


static var _scrim_tex: GradientTexture2D


## The plate gradient: transparent -> ink, generated once, never a PNG.
static func _scrim() -> GradientTexture2D:
	if _scrim_tex == null:
		var base := Tokens.color(&"plate_scrim")
		var g := Gradient.new()
		g.set_color(0, Color(base.r, base.g, base.b, 0.0))
		g.set_color(1, Color(base.r, base.g, base.b, 0.94))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 4
		t.height = 512
		t.fill_from = Vector2(0.0, 0.0)
		t.fill_to = Vector2(0.0, 1.0)
		_scrim_tex = t
	return _scrim_tex


func _ready() -> void:
	_ensure_built()
	# A caller that set FULL_RECT anchors BEFORE add_child keeps the scene's
	# default offsets (400x600) and would render oversized - the grid-overlap
	# bug. Normalize any full-rect anchored instance once it has a parent.
	if anchor_left <= 0.0 and anchor_top <= 0.0 \
			and anchor_right >= 1.0 and anchor_bottom >= 1.0:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## art keys: base / depth / char / bg, each a Texture2D or null.
## meta (optional): { "name": String, "set_id": String } - presentation only.
func set_card(p_rarity: String, art: Dictionary, meta: Dictionary = {}) -> void:
	rarity = p_rarity
	_art = art
	_card_name = str(meta.get("name", ""))
	_set_id = str(meta.get("set_id", ""))
	_tier = _resolve_tier(p_rarity, art)
	_ensure_built()
	_apply_tier()
	_sync_plate_text()


## The tier actually rendered after any fallback.
func active_tier() -> String:
	return _tier


## Request a foil. The rarity rule is re-checked here: a common drops it even if
## the server (or a bad payload) hands us "gold".
func set_variant(p_variant: String) -> void:
	variant = p_variant
	_ensure_built()
	_apply_holo()
	_sync_plate_text()


## Raise foil strength (detail view). Rebuilds the foil material in place.
func set_foil_emphasis(emphasis: float) -> void:
	foil_emphasis = emphasis
	if _holo != null and _holo.material is ShaderMaterial:
		(_holo.material as ShaderMaterial).set_shader_parameter(
				"intensity", _foil_intensity())


func _foil_intensity() -> float:
	return clampf(HOLO_INTENSITY * foil_emphasis * holo_scale, 0.0, 1.0)


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
	_root.name = "ArtRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Everything in the art root clips to the card rect; the rounded silhouette
	# itself comes from the shaders' alpha mask.
	_root.clip_contents = true
	add_child(_root)

	_bg = _make_layer()
	_base = _make_layer()
	_char = _make_layer()

	_light = ColorRect.new()
	_light.name = "Sweep"
	_light.set_anchors_preset(Control.PRESET_FULL_RECT)
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light.visible = false
	_root.add_child(_light)

	# Foil overlay: full-card additive sheen driven by the variant shader, on
	# top of the art but under the frame and the plate (which are later siblings
	# of the art root - pinned by test_holo_variants).
	_holo = ColorRect.new()
	_holo.name = "Foil"
	_holo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_holo.color = Color.WHITE
	_holo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holo.visible = false
	_root.add_child(_holo)

	_particles = CPUParticles2D.new()
	_particles.name = "Sparkles"
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

	# Material shader: draws frame band + laminate effects in one pass.
	# Child index 1 (after _root), so it sits ON the art edge.
	_material = ColorRect.new()
	_material.name = "Material"
	_material.set_anchors_preset(Control.PRESET_FULL_RECT)
	_material.color = Color.WHITE
	_material.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_material)

	# Drawn after the material so ornaments sit on top (child index 2).
	_frame = FrameLayer.new()
	_frame.name = "Frame"
	_frame.host = self
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	# Last visual layer: text always wins over foil glare.
	_plate = PlateLayer.new()
	_plate.name = "Plate"
	_plate.host = self
	_plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)

	_name_label = Label.new()
	_name_label.name = "CardName"
	_name_label.clip_text = true
	_name_label.add_theme_font_override("font", Tokens.display_font(700))
	_name_label.add_theme_color_override("font_color", Tokens.color(&"text_primary"))
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_name_label)

	_meta_label = Label.new()
	_meta_label.name = "CardMeta"
	_meta_label.clip_text = true
	_meta_label.add_theme_font_override("font", Tokens.ui_font(600))
	_meta_label.add_theme_color_override("font_color", Tokens.color(&"text_secondary"))
	_meta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_meta_label)

	_foil_label = Label.new()
	_foil_label.name = "FoilBadge"
	_foil_label.clip_text = true
	_foil_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_foil_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_foil_label.add_theme_font_override("font", Tokens.ui_font(700))
	_foil_label.add_theme_color_override("font_color", Tokens.color(&"accent_secondary"))
	_foil_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foil_label.visible = false
	_plate.add_child(_foil_label)

	_tilt_input = TiltInput.new()
	_tilt_input.name = "TiltInput"
	add_child(_tilt_input)

	resized.connect(_apply_layout)
	_apply_layout()


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
	_material.material = null
	_material.visible = false

	match _tier:
		"common":
			# strength 0: the parallax shader only supplies the rounded
			# silhouette for commons, no movement.
			_show(_base, "base")
			_base.material = _parallax_material(_art.get("depth"), 0.0)
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

	# Material shader for frame + laminate (all tiers)
	_apply_material()
	
	_update_particle_state()
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
	mat.set_shader_parameter("intensity", _foil_intensity())
	# Rare and up always carry a depth map, so the figure can be spared.
	mat.set_shader_parameter("depth_tex", _art.get("depth"))
	mat.set_shader_parameter("depth_mask", HOLO_DEPTH_MASK)
	_push_window(mat)
	mat.set_shader_parameter("motion", 0.0 if Motion.reduced else 1.0)
	mat.set_shader_parameter("tilt", tilt_override if use_tilt_override else _tilt_input.tilt)
	_holo.material = mat
	_holo.visible = true


## Builds the material shader for the current rarity (frame + laminate).
func _apply_material() -> void:
	_material.material = null
	_material.visible = false
	var shader: Shader = MATERIAL_SHADERS.get(rarity)
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	# Frame color from tokens
	var frame_key := StringName("frame_" + rarity)
	var frame_col := Tokens.color(frame_key) if Tokens.tokens().colors.has(frame_key) else Tokens.color(&"frame_common")
	mat.set_shader_parameter("frame_color", frame_col)
	mat.set_shader_parameter("ink_color", Tokens.color(&"card_ink"))
	mat.set_shader_parameter("band_thickness", _band)
	_push_window(mat)
	mat.set_shader_parameter("motion", 0.0 if Motion.reduced else 1.0)
	mat.set_shader_parameter("tilt", tilt_override if use_tilt_override else _tilt_input.tilt)
	# Legendary shader needs time uniform
	if rarity == "legendary":
		mat.set_shader_parameter("time", 0.0)
	_material.material = mat
	_material.visible = true
	_materials.append(mat)


func _show(layer: TextureRect, key: String) -> void:
	layer.texture = _art.get(key)
	layer.visible = layer.texture != null


func _update_particle_state() -> void:
	if _particles == null:
		return
	var want := _tier == "legendary" and particles_enabled
	_particles.visible = want
	_particles.emitting = want and not Motion.reduced


# --- layout + frame ---------------------------------------------------------

func _apply_layout() -> void:
	var w := size.x
	_full_art = rarity == "legendary" and _tier == "legendary"
	_radius = clampf(w * RADIUS_RATIO, 6.0, 18.0)
	_band = (clampf(w * FULL_ART_BAND_RATIO, 2.0, 4.0) if _full_art
			else clampf(w * FRAME_BAND_RATIO, 5.0, 14.0))
	var key := StringName("frame_" + rarity)
	_metal = (Tokens.color(key) if Tokens.tokens().colors.has(key)
			else Tokens.color(&"frame_common"))
	for mat in _materials:
		_push_window(mat)
		mat.set_shader_parameter("band_thickness", _band)
	if _light.material is ShaderMaterial:
		_push_window(_light.material)
	if _holo.material is ShaderMaterial:
		_push_window(_holo.material)
	if _material.material is ShaderMaterial:
		_push_window(_material.material)
		(_material.material as ShaderMaterial).set_shader_parameter("band_thickness", _band)
	_layout_plate()
	if _frame != null:
		_frame.queue_redraw()
	if _particles != null:
		_particles.position = size * 0.5
		_particles.emission_rect_extents = size * Vector2(0.30, 0.36)


## Rounded-silhouette uniforms for one material.
func _push_window(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("rect_size", size)
	mat.set_shader_parameter("corner_radius", _radius)


## Plate geometry + type sizes, clamped to the design tokens.
func _layout_plate() -> void:
	if _plate == null:
		return
	var w := size.x
	var h := size.y
	var show := w >= PLATE_MIN_WIDTH and h >= 60.0
	_plate.visible = show
	_plate_top = -1.0
	if not show:
		return
	var pad := clampf(w * PLATE_PAD_RATIO, 5.0, 16.0)
	var meta_size := clampi(int(w * META_RATIO),
			Tokens.font_size(&"caption"), Tokens.font_size(&"label"))
	var name_size := clampi(int(w * NAME_RATIO),
			Tokens.font_size(&"label"), Tokens.font_size(&"display_m"))
	var meta_h := float(meta_size) * 1.35
	var name_h := float(name_size) * 1.35
	var bottom := h - _band
	var meta_y := bottom - pad - meta_h

	_meta_label.position = Vector2(pad, meta_y)
	_meta_label.size = Vector2(w * 0.62 - pad, meta_h)
	_meta_label.add_theme_font_size_override("font_size", meta_size)

	_foil_label.position = Vector2(w * 0.55, meta_y)
	_foil_label.size = Vector2(w * 0.45 - pad, meta_h)
	_foil_label.add_theme_font_size_override("font_size", meta_size)

	var has_name := not _card_name.is_empty()
	_name_label.visible = has_name
	if has_name:
		var name_y := meta_y - pad * 0.35 - name_h
		_name_label.position = Vector2(pad, name_y)
		_name_label.size = Vector2(w - 2.0 * pad, name_h)
		_name_label.add_theme_font_size_override("font_size", name_size)
		_plate_top = name_y - pad * 0.55
	else:
		_plate_top = meta_y - pad * 0.55
	_plate_bottom = bottom
	_plate.queue_redraw()


## Name / meta / foil text. Safe to call before the labels exist.
func _sync_plate_text() -> void:
	if _name_label == null:
		return
	_name_label.text = _card_name
	var meta := rarity.to_upper()
	if not _set_id.is_empty():
		meta += " · " + _set_id.to_upper()
	_meta_label.text = meta
	var foil := variant != "none"
	_foil_label.visible = foil and _plate != null and _plate.visible
	if foil:
		_foil_label.text = variant.to_upper() + " FOIL"


# --- tilt -------------------------------------------------------------------

func _apply_tilt() -> void:
	var t := tilt_override if use_tilt_override else _tilt_input.tilt
	var motion := 0.0 if Motion.reduced else 1.0
	# Uniform pushes are cheap but not free: only write when something moved.
	if motion != _last_motion:
		_last_motion = motion
		for mat in _materials:
			mat.set_shader_parameter("motion", motion)
		if _light.material is ShaderMaterial:
			(_light.material as ShaderMaterial).set_shader_parameter("motion", motion)
		if _holo.material is ShaderMaterial:
			(_holo.material as ShaderMaterial).set_shader_parameter("motion", motion)
		if _material.material is ShaderMaterial:
			(_material.material as ShaderMaterial).set_shader_parameter("motion", motion)
		_update_particle_state()
	for mat in _materials:
		mat.set_shader_parameter("tilt", t)
	if _light.material is ShaderMaterial:
		_light.material.set_shader_parameter("tilt", t)
	if _holo.material is ShaderMaterial:
		_holo.material.set_shader_parameter("tilt", t)
	if _material.material is ShaderMaterial:
		(_material.material as ShaderMaterial).set_shader_parameter("tilt", t)
	# Legendary material needs time for auto-sweep
	if _material.material is ShaderMaterial and rarity == "legendary":
		(_material.material as ShaderMaterial).set_shader_parameter("time", Time.get_ticks_msec() * 0.001)


func _parallax_material(depth: Variant, strength: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PARALLAX_SHADER
	mat.set_shader_parameter("depth_tex", depth)
	mat.set_shader_parameter("parallax_strength", 0.022 * strength)
	mat.set_shader_parameter("breath_strength", 0.0035 * strength)
	mat.set_shader_parameter("motion", 0.0 if Motion.reduced else 1.0)
	mat.set_shader_parameter("tilt", tilt_override if use_tilt_override else Vector2.ZERO)
	_push_window(mat)
	_materials.append(mat)
	return mat


func _light_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = LIGHT_SHADER
	mat.set_shader_parameter("tilt", tilt_override if use_tilt_override else Vector2.ZERO)
	_push_window(mat)
	return mat
