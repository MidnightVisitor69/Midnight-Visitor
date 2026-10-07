extends "res://tests/test_case.gd"
## T-002: holo variant registry + CardView foil overlay. The variant list must
## track the DB enum, the rarity rule must hold on the client (commons never get
## a foil), and every non-none variant must resolve to a real shader and ramp.

const CardViewScript := preload("res://scripts/card/card_view.gd")
const HoloVariantsScript := preload("res://scripts/card/holo_variants.gd")

## public.holo_variant from migration 20261007063932. Written out longhand on
## purpose: if a migration reorders or renames a variant, this must break.
const DB_ENUM: Array[String] = ["none", "silver", "rainbow", "gold", "prism", "galaxy"]


func _tex() -> ImageTexture:
	var img := Image.create(4, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)


func _art() -> Dictionary:
	return {"base": _tex(), "depth": _tex(), "char": _tex(), "bg": _tex()}


func _view(rarity: String) -> CardView:
	var v: CardView = CardViewScript.new()
	v.set_card(rarity, _art())
	return v


func test_variants_match_db_enum_in_order() -> void:
	assert_eq(HoloVariantsScript.VARIANTS, DB_ENUM, "variant names/order must match DB")


func test_applies_to_only_rare_and_up() -> void:
	assert_true(HoloVariantsScript.applies_to("rare", "silver"), "rare silver")
	assert_true(HoloVariantsScript.applies_to("epic", "galaxy"), "epic galaxy")
	assert_true(HoloVariantsScript.applies_to("legendary", "prism"), "legendary prism")


func test_common_never_gets_holo() -> void:
	assert_true(not HoloVariantsScript.applies_to("common", "galaxy"), "common galaxy")
	assert_true(not HoloVariantsScript.applies_to("common", "silver"), "common silver")


func test_none_never_gets_holo_even_on_legendary() -> void:
	assert_true(not HoloVariantsScript.applies_to("legendary", "none"), "legendary none")
	assert_true(not HoloVariantsScript.applies_to("rare", "none"), "rare none")


func test_every_variant_resolves_shader_and_ramp() -> void:
	for v in HoloVariantsScript.VARIANTS:
		if v == "none":
			continue
		assert_true(HoloVariantsScript.shader_for(v) != null, "shader for %s" % v)
		assert_true(HoloVariantsScript.ramp_for(v) != null, "ramp for %s" % v)


func test_none_and_unknown_resolve_to_null() -> void:
	assert_true(HoloVariantsScript.shader_for("none") == null, "none shader")
	assert_true(HoloVariantsScript.ramp_for("none") == null, "none ramp")
	assert_true(HoloVariantsScript.shader_for("chrome") == null, "unknown shader")
	assert_true(HoloVariantsScript.ramp_for("chrome") == null, "unknown ramp")


func test_common_card_view_drops_requested_holo() -> void:
	var v := _view("common")
	v.set_variant("gold")
	assert_eq(v.layer_names(), PackedStringArray(["base"]), "common must stay plain")
	assert_eq(v.holo_shader_path(), "", "common must not foil")
	v.free()


func test_rare_card_view_gets_gold_holo() -> void:
	var v := _view("rare")
	v.set_variant("gold")
	assert_eq(v.layer_names(), PackedStringArray(["base", "depth", "holo"]), "rare layers")
	assert_eq(v.holo_shader_path(), HoloVariantsScript.SHADERS["gold"], "gold shader")
	v.free()


func test_none_variant_hides_overlay() -> void:
	var v := _view("legendary")
	v.set_variant("none")
	assert_eq(v.layer_names(),
			PackedStringArray(["bg", "char", "depth", "particles"]), "legendary plain")
	v.free()


func test_switching_variant_swaps_shader() -> void:
	var v := _view("epic")
	v.set_variant("silver")
	assert_eq(v.holo_shader_path(), HoloVariantsScript.SHADERS["silver"], "silver shader")
	v.set_variant("galaxy")
	assert_eq(v.holo_shader_path(), HoloVariantsScript.SHADERS["galaxy"], "galaxy shader")
	assert_eq(v.layer_names(),
			PackedStringArray(["bg", "char", "depth", "holo"]), "epic layers")
	v.free()


func test_holo_layer_is_inside_art_root_below_frame() -> void:
	# The foil must live in the art root (child 0); the frame is a later sibling,
	# so the border always draws on top of the foil.
	var v := _view("rare")
	v.set_variant("silver")
	var holo := _find_holo(v)
	assert_true(holo != null, "holo rect must exist for rare+silver")
	assert_eq(holo.get_parent(), v.get_child(0), "holo must live in the art root")
	assert_true(v.get_child(0).get_index() < v.get_child(1).get_index(),
			"art root (with the foil) must draw before the frame")
	v.free()


func _find_holo(v: CardView) -> ColorRect:
	for child in v.get_child(0).get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			if (child.material as ShaderMaterial).shader.resource_path == v.holo_shader_path():
				return child
	return null
