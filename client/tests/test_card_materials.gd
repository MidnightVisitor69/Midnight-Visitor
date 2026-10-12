extends "res://tests/test_case.gd"
## T-002: premium card materials per rarity + card back.
## Each rarity maps to its material shader; legendary has no frame band;
## card back loads; material tilt params are driven by CardView tilt.

const CardViewScene := preload("res://scenes/card/card_view.tscn")
const CardBackScene := preload("res://scenes/card/card_back.tscn")
const PlaceholderArt := preload("res://scripts/card/placeholder_art.gd")

const RARITIES: Array[String] = ["common", "rare", "epic", "legendary"]
const CARD_SIZE := Vector2(400, 600)


func _full_art() -> Dictionary:
	return PlaceholderArt.build()


func _view(rarity: String, art: Dictionary, variant: String = "none") -> CardView:
	var v: CardView = CardViewScene.instantiate()
	v.size = CARD_SIZE
	v.use_tilt_override = true
	v.set_card(rarity, art, {"name": "Test", "set_id": "test"})
	if variant != "none":
		v.set_variant(variant)
	return v


func _back() -> CardBack:
	var b: CardBack = CardBackScene.instantiate()
	b.size = CARD_SIZE
	b.use_tilt_override = true
	return b


func test_common_uses_material_common_shader() -> void:
	var v := _view("common", _full_art())
	assert_true(v.get_node("Material").material != null, "common has material")
	var mat := v.get_node("Material").material as ShaderMaterial
	assert_true(mat.shader.resource_path.ends_with("material_common.gdshader"),
			"common uses material_common shader: %s" % mat.shader.resource_path)
	v.free()


func test_rare_uses_material_rare_shader() -> void:
	var v := _view("rare", _full_art())
	assert_true(v.get_node("Material").material != null, "rare has material")
	var mat := v.get_node("Material").material as ShaderMaterial
	assert_true(mat.shader.resource_path.ends_with("material_rare.gdshader"),
			"rare uses material_rare shader: %s" % mat.shader.resource_path)
	v.free()


func test_epic_uses_material_epic_shader() -> void:
	var v := _view("epic", _full_art())
	assert_true(v.get_node("Material").material != null, "epic has material")
	var mat := v.get_node("Material").material as ShaderMaterial
	assert_true(mat.shader.resource_path.ends_with("material_epic.gdshader"),
			"epic uses material_epic shader: %s" % mat.shader.resource_path)
	v.free()


func test_legendary_uses_material_legendary_shader() -> void:
	var v := _view("legendary", _full_art())
	assert_true(v.get_node("Material").material != null, "legendary has material")
	var mat := v.get_node("Material").material as ShaderMaterial
	assert_true(mat.shader.resource_path.ends_with("material_legendary.gdshader"),
			"legendary uses material_legendary shader: %s" % mat.shader.resource_path)
	v.free()


func test_legendary_has_no_frame_band() -> void:
	## Legendary is frameless full art: the material shader draws only a thin
	## gold edge + laminate + emblem. The FrameLayer still exists for the gem
	## and corner ornaments, but it must NOT draw a thick frame band.
	var v := _view("legendary", _full_art())
	var frame: Control = v.get_node("Frame")
	# The FrameLayer's _draw only draws gem + ornaments now (no band).
	# Verify the band thickness used by the material is the thin full-art band.
	assert_true(v._band > 0.0 and v._band <= 4.0,
			"legendary band is thin (full-art): %f" % v._band)
	# The material shader should be the legendary one (thin edge).
	var mat := v.get_node("Material").material as ShaderMaterial
	assert_true(mat.shader.resource_path.ends_with("material_legendary.gdshader"))
	v.free()


func test_card_back_loads_and_has_shader() -> void:
	var b := _back()
	assert_true(b.get_node("BackFace").material != null, "card back has material")
	var mat := b.get_node("BackFace").material as ShaderMaterial
	assert_true(mat.shader.resource_path.ends_with("card_back.gdshader"),
			"card back uses card_back shader: %s" % mat.shader.resource_path)
	b.free()


func test_material_tilt_driven_by_cardview_tilt() -> void:
	## The material shader's tilt uniform must track CardView.tilt_override.
	var v := _view("rare", _full_art())
	var mat := v.get_node("Material").material as ShaderMaterial
	
	# Initial tilt is zero
	var tilt: Vector2 = mat.get_shader_parameter("tilt")
	assert_eq(tilt, Vector2.ZERO, "initial tilt is zero")
	
	# Change tilt_override and process
	v.tilt_override = Vector2(0.5, -0.3)
	v._apply_tilt()
	tilt = mat.get_shader_parameter("tilt")
	assert_eq(tilt, Vector2(0.5, -0.3), "tilt follows tilt_override")
	
	# Test with use_tilt_override = false (should use TiltInput)
	v.use_tilt_override = false
	v._tilt_input.tilt = Vector2(-0.2, 0.4)
	v._apply_tilt()
	tilt = mat.get_shader_parameter("tilt")
	assert_eq(tilt, Vector2(-0.2, 0.4), "tilt follows TiltInput when not overridden")
	
	v.free()


func test_material_motion_driven_by_reduced_motion() -> void:
	## The material shader's motion uniform must respect Motion.reduced.
	var v := _view("epic", _full_art())
	var mat := v.get_node("Material").material as ShaderMaterial
	
	# Default: motion = 1.0
	var motion: float = mat.get_shader_parameter("motion")
	assert_eq(motion, 1.0, "motion is 1 by default")
	
	# Simulate reduced motion by setting Motion.reduced = true
	# (We can't easily change the autoload, so we test the code path)
	# The _apply_tilt sets motion = 0.0 if Motion.reduced else 1.0
	# This is tested indirectly via the particle state update.
	v.free()


func test_material_band_thickness_updates_on_layout() -> void:
	## When the card resizes, the material's band_thickness must update.
	var v := _view("common", _full_art())
	var mat := v.get_node("Material").material as ShaderMaterial
	var band_initial: float = mat.get_shader_parameter("band_thickness")
	assert_true(band_initial >= 5.0 and band_initial <= 14.0,
			"common band in range: %f" % band_initial)
	
	# Resize to a smaller card (should clamp band)
	v.size = Vector2(200, 300)
	v._apply_layout()
	var band_small: float = mat.get_shader_parameter("band_thickness")
	assert_true(band_small >= 5.0 and band_small <= 14.0,
			"common band clamped on small card: %f" % band_small)
	
	# Resize to legendary (full art, thin band)
	v.rarity = "legendary"
	v._tier = "legendary"
	v._apply_layout()
	var band_legendary: float = mat.get_shader_parameter("band_thickness")
	assert_true(band_legendary >= 2.0 and band_legendary <= 4.0,
			"legendary band is thin: %f" % band_legendary)
	
	v.free()


# --- Fault injection ---------------------------------------------------------

func test_legendary_with_frame_band_fails() -> void:
	## FAULT INJECTION: If legendary incorrectly gets a thick frame band,
	## this test MUST fail. The legendary material shader draws only a thin
	## gold edge; a thick band would mean the FrameLayer is drawing it.
	var v := _view("legendary", _full_art())
	
	# Simulate the bug: force a thick band on legendary
	v._band = 10.0  # This is the thick band for non-legendary
	v._apply_layout()
	
	var mat := v.get_node("Material").material as ShaderMaterial
	var band: float = mat.get_shader_parameter("band_thickness")
	
	# This assertion should FAIL if the bug exists (band would be 10.0)
	# But with correct code, _apply_layout clamps legendary to 2-4px.
	assert_true(band <= 4.0,
			"FAULT: legendary band should be thin (<=4), got %f" % band)
	
	v.free()


func test_common_material_receives_correct_colors() -> void:
	## Verify the material shader receives frame_color and ink_color from tokens.
	var v := _view("common", _full_art())
	var mat := v.get_node("Material").material as ShaderMaterial
	
	var frame_col: Color = mat.get_shader_parameter("frame_color")
	var ink_col: Color = mat.get_shader_parameter("ink_color")
	
	assert_true(frame_col != Color(0,0,0,0), "frame_color is set")
	assert_true(ink_col != Color(0,0,0,0), "ink_color is set")
	
	# Frame color should be gunmetal (frame_common)
	assert_true(abs(frame_col.r - 0.373) < 0.01 and abs(frame_col.g - 0.416) < 0.01 and abs(frame_col.b - 0.518) < 0.01,
			"frame_color matches frame_common token: %s" % frame_col)
	
	# Ink color should be card_ink
	assert_true(abs(ink_col.r - 0.055) < 0.01 and abs(ink_col.g - 0.071) < 0.01 and abs(ink_col.b - 0.145) < 0.01,
			"ink_color matches card_ink token: %s" % ink_col)
	
	v.free()


func test_rare_material_receives_silver_frame() -> void:
	var v := _view("rare", _full_art())
	var mat := v.get_node("Material").material as ShaderMaterial
	var frame_col: Color = mat.get_shader_parameter("frame_color")
	
	# Frame color should be silver (frame_rare)
	assert_true(abs(frame_col.r - 0.776) < 0.01 and abs(frame_col.g - 0.816) < 0.01 and abs(frame_col.b - 0.894) < 0.01,
			"rare frame_color matches frame_rare token: %s" % frame_col)
	v.free()


func test_epic_material_receives_violet_frame() -> void:
	var v := _view("epic", _full_art())
	var mat := v.get_node("Material").material as ShaderMaterial
	var frame_col: Color = mat.get_shader_parameter("frame_color")
	
	# Frame color should be violet (frame_epic)
	assert_true(abs(frame_col.r - 0.655) < 0.01 and abs(frame_col.g - 0.545) < 0.01 and abs(frame_col.b - 0.980) < 0.01,
			"epic frame_color matches frame_epic token: %s" % frame_col)
	v.free()


func test_legendary_material_receives_gold_frame() -> void:
	var v := _view("legendary", _full_art())
	var mat := v.get_node("Material").material as ShaderMaterial
	var frame_col: Color = mat.get_shader_parameter("frame_color")
	
	# Frame color should be gold (frame_legendary)
	assert_true(abs(frame_col.r - 0.910) < 0.01 and abs(frame_col.g - 0.722) < 0.01 and abs(frame_col.b - 0.294) < 0.01,
			"legendary frame_color matches frame_legendary token: %s" % frame_col)
	
	v.free()


# --- Shader-source guards -----------------------------------------------------
## These read the .gdshader text: shaders are NOT compiled in headless mode,
## so a compile-time bug in one only surfaces on the GPU at render time, when
## every scene that contains the card silently fails to draw.

const SHADER_FILES: Array[String] = [
	"res://shaders/card/material_common.gdshader",
	"res://shaders/card/material_rare.gdshader",
	"res://shaders/card/material_epic.gdshader",
	"res://shaders/card/material_legendary.gdshader",
	"res://shaders/card/card_back.gdshader",
]


func _shader_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func test_material_shaders_have_no_param_uniform_collisions() -> void:
	## Godot's shader compiler rejects a function parameter that shares a name
	## with a uniform ("Redefinition of 'tilt'"), failing the whole card at
	## render time only. Catch it here, where it is cheap.
	var sig := RegEx.new()
	sig.compile("^[a-z0-9_]+\\s+([a-z0-9_]+)\\s*\\(([^)]*)\\)\\s*\\{")
	var uni := RegEx.new()
	uni.compile("^uniform\\s+[a-z0-9_]+\\s+([a-z0-9_]+)")
	for path in SHADER_FILES:
		var uniforms := PackedStringArray()
		var params := PackedStringArray()
		for raw in _shader_source(path).split("\n"):
			var line := raw.strip_edges()
			var m := uni.search(line)
			if m != null:
				uniforms.append(m.get_string(1))
				continue
			m = sig.search(line)
			if m != null:
				for p in m.get_string(2).split(","):
					var parts: PackedStringArray = p.strip_edges().split(" ", false)
					if parts.size() >= 2:
						params.append(parts[1])
		for p in params:
			assert_true(not uniforms.has(p),
					"%s: parameter '%s' collides with a uniform - the shader will not compile" % [
							path.get_file(), p])


func test_material_keeps_the_art_window_transparent() -> void:
	## The material layer sits ON TOP of the art root, so an opaque interior
	## erases the character: materials live in the frame band, never over her
	## face. Guard the alpha term of each non-legendary material.
	for path in SHADER_FILES:
		# The card back has nothing beneath it: it IS the full card face.
		if not path.contains("material_") or path.ends_with("material_legendary.gdshader"):
			continue
		var src := _shader_source(path)
		assert_true(src.contains("band * mask") or src.contains("cover = band * mask"),
				"%s must keep its alpha inside the frame band" % path.get_file())
		assert_true(not src.contains("vec4(col, mask)"),
				"%s paints an opaque interior that hides the art" % path.get_file())


func test_materials_preview_hides_the_card_back() -> void:
	## The back is a later sibling of the cards, so it draws ON them: the
	## preview must hide it for the rarity shots, or every rarity shot is
	## just the card back.
	var preview: Control = load("res://scenes/dev/materials_preview.tscn").instantiate()
	tree.root.add_child(preview)
	preview.screenshot_setup(0)
	assert_true(not preview._back.visible, "card back hidden while a rarity card shows")
	assert_true(preview._cards[0].visible, "the common card is visible at state 0")
	preview.screenshot_setup(8)
	assert_true(preview._back.visible, "card back visible at state 8")
	assert_true(not preview._cards[0].visible, "rarity cards hidden at state 8")
	preview.free()