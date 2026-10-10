extends "res://tests/test_case.gd"
## The premium card object (redesign): the anchors-normalization guard that
## fixed the grid-overlap bug, the frame material tokens, the name plate, foil
## emphasis for the detail view, and the reduced-motion contract.
##
## These pin the regressions that actually shipped once: a scene-instantiated
## CardView keeping the .tscn's 400x600 offsets and rendering oversized over
## its neighbours.

const CardViewScene := preload("res://scenes/card/card_view.tscn")
const CardViewScript := preload("res://scripts/card/card_view.gd")
const TokensScript := preload("res://theme/tokens.gd")


func _tex() -> ImageTexture:
	var img := Image.create(4, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)


func _art() -> Dictionary:
	return {"base": _tex(), "depth": _tex(), "char": _tex(), "bg": _tex()}


# --- the anchors guard -------------------------------------------------------

func test_full_rect_anchors_set_before_add_are_normalized() -> void:
	# The exact call pattern collection/detail used: preset BEFORE add_child.
	var parent := Control.new()
	tree.root.add_child(parent)
	parent.size = Vector2(343.0, 514.0)
	var v: CardView = CardViewScene.instantiate()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)   # keeps 400x600 offsets
	# add_child fires _ready at runtime; the synchronous runner cannot reach
	# the tree, so the guard is invoked directly - same code, same order.
	parent.add_child(v)
	v.call("_ready")
	# The guard clears the stale scene offsets; with full-rect anchors and zero
	# offsets the rect IS the parent rect at the next layout pass (proven live
	# by the GPU probe: card size == tile size on every tile). Off-screen the
	# engine defers that pass, so the offsets are what is provable here.
	assert_almost(v.offset_left, 0.0, 0.01, "scene offsets cleared")
	assert_almost(v.offset_top, 0.0, 0.01, "scene offsets cleared")
	assert_almost(v.offset_right, 0.0, 0.01, "scene offsets cleared")
	assert_almost(v.offset_bottom, 0.0, 0.01, "scene offsets cleared")
	assert_true(v.anchor_right >= 1.0 and v.anchor_bottom >= 1.0,
			"anchors still full-rect")
	v.free()
	parent.free()


func test_explicit_size_is_not_clobbered_by_normalization() -> void:
	# Pack summary cells size the card themselves (anchors stay top-left).
	var parent := Control.new()
	tree.root.add_child(parent)
	parent.size = Vector2(400.0, 600.0)
	var v: CardView = CardViewScene.instantiate()
	v.size = Vector2(186.0, 279.0)
	parent.add_child(v)
	v.call("_ready")
	assert_almost(v.size.x, 186.0, 0.01, "caller-set size must survive _ready")
	assert_almost(v.size.y, 279.0, 0.01, "caller-set size must survive _ready")
	v.free()
	parent.free()


# --- frame materials from tokens ---------------------------------------------

func test_frame_metal_comes_from_the_rarity_token() -> void:
	for rarity in ["common", "rare", "epic", "legendary"]:
		var v: CardView = CardViewScript.new()
		v.set_card(rarity, _art())
		assert_eq(v._metal, TokensScript.color(StringName("frame_" + rarity)),
				"%s frame metal" % rarity)
		v.free()


func test_legendary_full_art_gets_the_hairline_band() -> void:
	var v: CardView = CardViewScript.new()
	v.set_card("legendary", _art())
	v.size = Vector2(343.0, 514.0)
	v._apply_layout()
	assert_true(v._full_art, "legendary with full art is full-bleed")
	assert_true(v._band < 5.0, "full art keeps only a hairline edge")
	v.free()


func test_legendary_without_layers_keeps_the_normal_frame() -> void:
	# Only base.png exists -> art tier falls back to common, and the card must
	# still present as a legendary OBJECT (gold band, not hairline).
	var v: CardView = CardViewScript.new()
	v.set_card("legendary", {"base": _tex()})
	v.size = Vector2(343.0, 514.0)
	v._apply_layout()
	assert_eq(v.active_tier(), "common", "tier falls back")
	assert_true(not v._full_art, "no full-art layout without full art")
	assert_true(v._band >= 5.0, "kept the normal metal band")
	assert_eq(v._metal, TokensScript.color(&"frame_legendary"), "still gold")
	v.free()


func test_geometry_scales_with_card_size() -> void:
	var v: CardView = CardViewScript.new()
	v.set_card("rare", _art())
	v.size = Vector2(343.0, 514.0)
	v._apply_layout()
	assert_almost(v._radius, clampf(343.0 * 0.05, 6.0, 18.0), 0.01, "corner radius")
	assert_almost(v._band, clampf(343.0 * 0.026, 5.0, 14.0), 0.01, "band thickness")
	assert_true(v._radius > 0.0 and v._band > 0.0 and v._band < v._radius,
			"band thinner than the corner radius")
	v.free()


# --- name plate ---------------------------------------------------------------

func _plate_sized_view() -> CardView:
	var v: CardView = CardViewScript.new()
	v.size = Vector2(343.0, 514.0)
	return v


func test_meta_names_the_card_and_foil() -> void:
	var v := _plate_sized_view()
	v.set_card("rare", _art(), {"name": "Seraph Gold", "set_id": "launch-01"})
	v.set_variant("silver")
	assert_true(v._plate.visible, "plate shows at grid size")
	assert_eq(v._name_label.text, "Seraph Gold", "name on the plate")
	assert_true(v._name_label.visible, "name shows when provided")
	assert_eq(v._meta_label.text, "RARE · LAUNCH-01", "meta line")
	assert_true(v._foil_label.visible, "foil badge shows for a variant")
	assert_eq(v._foil_label.text, "SILVER FOIL", "foil badge text")
	v.free()


func test_no_name_no_variant_plate_still_reads() -> void:
	var v := _plate_sized_view()
	v.set_card("common", _art())
	assert_true(not v._name_label.visible, "no invented name")
	assert_eq(v._meta_label.text, "COMMON", "rarity still reads")
	assert_true(not v._foil_label.visible, "no foil badge without a variant")
	v.free()


func test_plate_hidden_below_legible_width() -> void:
	var v: CardView = CardViewScript.new()
	v.set_card("common", _art(), {"name": "Tiny"})
	v.size = Vector2(100.0, 150.0)
	v._apply_layout()
	assert_true(not v._plate.visible, "no unreadable micro-text on tiny cards")
	v.free()


# --- foil emphasis + reduced motion -------------------------------------------

func test_foil_emphasis_raises_the_shader_intensity() -> void:
	var v: CardView = CardViewScript.new()
	v.set_card("rare", _art())
	v.set_variant("gold")
	var mat := v._holo.material as ShaderMaterial
	var rest := float(mat.get_shader_parameter("intensity"))
	v.set_foil_emphasis(1.18)
	var closeup := float(mat.get_shader_parameter("intensity"))
	assert_true(closeup > rest, "detail view foil beats grid foil")
	assert_true(closeup <= 1.0, "intensity stays clamped")
	v.free()


func test_reduced_motion_freezes_idle_shader_time_and_sparkles() -> void:
	var was := Motion.reduced
	Motion.reduced = true
	var v: CardView = CardViewScript.new()
	v.set_card("legendary", _art())
	v.set_variant("rainbow")
	var motion := float((v._holo.material as ShaderMaterial)
			.get_shader_parameter("motion"))
	assert_almost(motion, 0.0, 0.001, "foil time frozen under reduced motion")
	for mat in v._materials:
		assert_almost(float(mat.get_shader_parameter("motion")), 0.0, 0.001,
				"parallax breath frozen")
	assert_true(not v._particles.emitting, "legendary sparkles off")
	v._apply_tilt()
	assert_true(not v._particles.emitting, "stays off on the next frame too")
	v.free()
	Motion.reduced = was


func test_motion_on_keeps_the_effects() -> void:
	var was := Motion.reduced
	Motion.reduced = false
	var v: CardView = CardViewScript.new()
	v.set_card("legendary", _art())
	v.set_variant("rainbow")
	var motion := float((v._holo.material as ShaderMaterial)
			.get_shader_parameter("motion"))
	assert_almost(motion, 1.0, 0.001, "foil time runs")
	assert_true(v._particles.emitting, "legendary sparkles on")
	v.free()
	Motion.reduced = was
