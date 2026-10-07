extends "res://tests/test_case.gd"
## T-001: tier resolution and procedural placeholder art. A tier only renders
## when the art actually carries the layers it needs, otherwise it falls back
## instead of drawing a broken card.

const CardViewScript := preload("res://scripts/card/card_view.gd")
const PlaceholderArtScript := preload("res://scripts/card/placeholder_art.gd")


func _tex() -> ImageTexture:
	var img := Image.create(4, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)


func _full_art() -> Dictionary:
	return {"base": _tex(), "depth": _tex(), "char": _tex(), "bg": _tex()}


func _view(rarity: String, art: Dictionary) -> CardView:
	var v: CardView = CardViewScript.new()
	v.set_card(rarity, art)
	return v


func test_common_draws_only_base() -> void:
	var v := _view("common", _full_art())
	assert_eq(v.active_tier(), "common", "tier")
	assert_eq(v.layer_names(), PackedStringArray(["base"]), "layers")
	v.free()


func test_rare_draws_parallax_layers() -> void:
	var v := _view("rare", _full_art())
	assert_eq(v.active_tier(), "rare", "tier")
	assert_eq(v.layer_names(), PackedStringArray(["base", "depth"]), "layers")
	v.free()


func test_epic_draws_bg_char_layers() -> void:
	var v := _view("epic", _full_art())
	assert_eq(v.active_tier(), "epic", "tier")
	assert_eq(v.layer_names(), PackedStringArray(["bg", "char", "depth"]), "layers")
	v.free()


func test_legendary_draws_full_art_layers() -> void:
	var v := _view("legendary", _full_art())
	assert_eq(v.active_tier(), "legendary", "tier")
	assert_eq(v.layer_names(), PackedStringArray(["bg", "char", "depth", "particles"]), "layers")
	v.free()


func test_epic_without_char_bg_falls_back_to_rare() -> void:
	var art := {"base": _tex(), "depth": _tex()}
	var v := _view("epic", art)
	assert_eq(v.active_tier(), "rare", "missing char/bg must drop to rare")
	assert_eq(v.layer_names(), PackedStringArray(["base", "depth"]), "layers")
	v.free()


func test_rare_without_depth_falls_back_to_common() -> void:
	var art := {"base": _tex()}
	var v := _view("rare", art)
	assert_eq(v.active_tier(), "common", "missing depth must drop to common")
	assert_eq(v.layer_names(), PackedStringArray(["base"]), "layers")
	v.free()


func test_placeholder_layers_are_card_sized() -> void:
	var art := PlaceholderArtScript.build()
	for key in ["base", "depth", "char", "bg"]:
		var t: Texture2D = art[key]
		assert_true(t != null, "%s is null" % key)
		assert_eq(t.get_width(), 512, "%s width" % key)
		assert_eq(t.get_height(), 768, "%s height" % key)


func test_placeholder_char_has_transparent_corners() -> void:
	var img: Image = PlaceholderArtScript.char_texture().get_image()
	var corners := [Vector2i(0, 0), Vector2i(511, 0), Vector2i(0, 767), Vector2i(511, 767)]
	for p in corners:
		assert_true(img.get_pixelv(p).a < 0.05, "corner %s must be transparent" % p)


func test_placeholder_art_is_deterministic() -> void:
	var a: PackedByteArray = PlaceholderArtScript.base_texture().get_image().get_data()
	var b: PackedByteArray = PlaceholderArtScript.base_texture().get_image().get_data()
	assert_eq(a, b, "two calls must produce identical pixels")
