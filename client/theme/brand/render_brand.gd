class_name RenderBrand
extends SceneTree
## Headless rasterizer for the brand mark. Runs via:
##   godot --headless --path client --script res://theme/brand/render_brand.gd
##
## Writes PNGs to client/theme/generated/:
##   - adaptive_foreground_432x432.png (mark scaled to 66% safe zone, transparent bg)
##   - adaptive_background_color.txt (hex color for adaptive icon background)
##   - legacy_icon_192x192.png (mark centered, navy bg)
##   - boot_splash_1080x2400.png (mark centered, navy bg)
##
## All output is procedural - no source PNGs required.
## Uses RenderingServer directly for headless offscreen rendering.

const TokensScript := preload("res://theme/tokens.gd")
const BrandMarkScript := preload("res://theme/brand/brand_mark.gd")

const OUT_DIR := "res://theme/generated/"

## Output sizes
const ADAPTIVE_FG_SIZE := 432
const LEGACY_ICON_SIZE := 192
const SPLASH_WIDTH := 1080
const SPLASH_HEIGHT := 2400

## The mark must fit inside 66% of the adaptive icon (Android spec).
## Our mark's natural radius is ~0.57 of canvas; safe zone radius is 0.33.
## Scale factor to fit:
const SAFE_ZONE_SCALE := 0.33 / 0.57  # ~0.5789

var _viewport_rid: RID
var _canvas_rid: RID
var _draw_list_rid: RID


func _initialize() -> void:
	_build_renderer()
	_generate_all()
	quit(0)


func _build_renderer() -> void:
	# Create a viewport on the rendering server
	_viewport_rid = RenderingServer.viewport_create()
	_canvas_rid = RenderingServer.canvas_create()
	RenderingServer.viewport_attach_canvas(_viewport_rid, _canvas_rid)
	RenderingServer.viewport_set_update_mode(_viewport_rid, RenderingServer.VIEWPORT_UPDATE_ONCE)
	RenderingServer.viewport_set_clear_mode(_viewport_rid, RenderingServer.VIEWPORT_CLEAR_ALWAYS)

	# Create a draw list for our drawing commands
	_draw_list_rid = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_draw_list_rid, _canvas_rid)


## Draw the brand mark centered in a virtual rect of given size.
func _draw_mark(size: Vector2, palette: Dictionary) -> void:
	RenderingServer.canvas_item_clear(_draw_list_rid)
	var rect := Rect2(Vector2.ZERO, size)
	_draw_mark_rs(rect, palette)


func _draw_mark_rs(rect: Rect2, palette: Dictionary) -> void:
	var c := rect.position + rect.size * 0.5
	var size := minf(rect.size.x, rect.size.y)

	var bg_color: Color = palette.get("bg", TokensScript.color(&"bg"))
	var moon_color: Color = palette.get("moon", TokensScript.color(&"surface_3"))
	var neon_color: Color = palette.get("neon", TokensScript.color(&"accent"))
	var neon_glow_color: Color = palette.get("neon_glow", Color(neon_color.r, neon_color.g, neon_color.b, 0.35))

	var moon_r: float = size * 0.42
	var stroke_w: float = maxf(2.0, size * 0.055)

	# --- Moon (crescent via two overlapping circles) ---
	# Main moon disc: draw_circle with width = diameter to fill
	RenderingServer.canvas_item_add_circle(_draw_list_rid, c, moon_r, moon_color)
	# Crescent cut: a darker circle offset to carve the crescent shape
	var cut_r: float = moon_r * 0.88
	var cut_offset: Vector2 = Vector2(moon_r * 0.22, -moon_r * 0.18)
	RenderingServer.canvas_item_add_circle(_draw_list_rid, c + cut_offset, cut_r, bg_color)

	# --- Neon sign stroke ---
	var start_angle: float = PI * 0.25
	var end_angle: float = PI * 1.35
	var arc_r: float = moon_r * 1.35

	var segments: int = maxi(16, int(size * 0.12))
	var prev_pt: Vector2 = c + Vector2(cos(start_angle), sin(start_angle)) * arc_r

	# Glow pass (wider, lower alpha)
	var glow_w: float = stroke_w * 2.2
	for i in range(1, segments + 1):
		var t: float = float(i) / segments
		var a: float = lerp(start_angle, end_angle, t)
		var pt: Vector2 = c + Vector2(cos(a), sin(a)) * arc_r
		RenderingServer.canvas_item_add_line(_draw_list_rid, prev_pt, pt, neon_glow_color, glow_w, true)
		prev_pt = pt

	# Core neon stroke
	prev_pt = c + Vector2(cos(start_angle), sin(start_angle)) * arc_r
	for i in range(1, segments + 1):
		var t: float = float(i) / segments
		var a: float = lerp(start_angle, end_angle, t)
		var pt: Vector2 = c + Vector2(cos(a), sin(a)) * arc_r
		RenderingServer.canvas_item_add_line(_draw_list_rid, prev_pt, pt, neon_color, stroke_w, true)
		prev_pt = pt

	# Tiny end-cap highlight at the stroke tip
	var tip: Vector2 = c + Vector2(cos(end_angle), sin(end_angle)) * arc_r
	RenderingServer.canvas_item_add_circle(_draw_list_rid, tip, stroke_w * 0.6, Color(1.0, 1.0, 1.0, 0.9))


## Rasterize current viewport to an Image.
func _capture(size: Vector2) -> Image:
	RenderingServer.viewport_set_size(_viewport_rid, int(size.x), int(size.y))
	RenderingServer.viewport_set_update_mode(_viewport_rid, RenderingServer.VIEWPORT_UPDATE_ONCE)
	# Force render
	RenderingServer.frame_post_draw()
	var tex_rid := RenderingServer.viewport_get_texture(_viewport_rid)
	var img: Image = RenderingServer.texture_2d_get(tex_rid)
	img.flip_y()
	return img


## Helper to resolve res:// paths for FileAccess (which needs absolute paths).
static func _resolve(path: String) -> String:
	return ProjectSettings.globalize_path(path)


## Save image to generated folder.
func _save(img: Image, name: String) -> void:
	var abs_dir := _resolve(OUT_DIR)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(abs_dir)
		dir = DirAccess.open(abs_dir)
	assert(dir != null, "cannot open output dir: " + abs_dir)
	var path := _resolve(OUT_DIR + name)
	img.save_png(path)
	print("WROTE " + path)


## Generate adaptive icon foreground: 432x432, transparent bg, mark scaled to 66% safe zone.
func _gen_adaptive_foreground() -> void:
	print("DEBUG: _gen_adaptive_foreground start")
	# Draw mark at virtual size (fitted to safe zone)
	var virtual_size := int(ADAPTIVE_FG_SIZE * SAFE_ZONE_SCALE)
	_draw_mark(Vector2(virtual_size, virtual_size), {
		"bg": Color(0, 0, 0, 0),
		"moon": TokensScript.color(&"surface_3"),
		"neon": TokensScript.color(&"accent"),
	})
	var mark_img := _capture(Vector2(virtual_size, virtual_size))
	print("DEBUG: captured mark_img size = ", mark_img.get_size(), " empty = ", mark_img.is_empty())

	# Compose into 432x432 transparent canvas
	var final_img := Image.create(ADAPTIVE_FG_SIZE, ADAPTIVE_FG_SIZE, false, Image.FORMAT_RGBA8)
	final_img.fill(Color(0, 0, 0, 0))
	var paste_x := int((ADAPTIVE_FG_SIZE - virtual_size) / 2)
	var paste_y := int((ADAPTIVE_FG_SIZE - virtual_size) / 2)
	final_img.blit_rect(mark_img, Rect2(Vector2.ZERO, mark_img.get_size()), Vector2(paste_x, paste_y))
	_save(final_img, "adaptive_foreground_432x432.png")
	print("DEBUG: _gen_adaptive_foreground done")


## Generate adaptive icon background color (just a text file with hex).
func _gen_adaptive_background() -> void:
	var bg := TokensScript.color(&"bg")
	var hex := "#%02x%02x%02x" % [int(bg.r * 255), int(bg.g * 255), int(bg.b * 255)]
	var abs_dir := _resolve(OUT_DIR)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var path := _resolve(OUT_DIR + "adaptive_background_color.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(hex)
	f.close()
	print("WROTE " + path + " -> " + hex)


## Generate legacy icon: 192x192, navy background, mark centered.
func _gen_legacy_icon() -> void:
	print("DEBUG: _gen_legacy_icon start")
	_draw_mark(Vector2(LEGACY_ICON_SIZE, LEGACY_ICON_SIZE), {
		"bg": TokensScript.color(&"bg"),
		"moon": TokensScript.color(&"surface_3"),
		"neon": TokensScript.color(&"accent"),
	})
	var img := _capture(Vector2(LEGACY_ICON_SIZE, LEGACY_ICON_SIZE))
	print("DEBUG: captured legacy img size = ", img.get_size(), " empty = ", img.is_empty())
	_save(img, "legacy_icon_192x192.png")
	print("DEBUG: _gen_legacy_icon done")


## Generate boot splash: 1080x2400, navy background, mark centered.
func _gen_boot_splash() -> void:
	print("DEBUG: _gen_boot_splash start")
	_draw_mark(Vector2(SPLASH_WIDTH, SPLASH_HEIGHT), {
		"bg": TokensScript.color(&"bg"),
		"moon": TokensScript.color(&"surface_3"),
		"neon": TokensScript.color(&"accent"),
	})
	var img := _capture(Vector2(SPLASH_WIDTH, SPLASH_HEIGHT))
	print("DEBUG: captured splash img size = ", img.get_size(), " empty = ", img.is_empty())
	_save(img, "boot_splash_1080x2400.png")
	print("DEBUG: _gen_boot_splash done")


func _generate_all() -> void:
	_gen_adaptive_foreground()
	_gen_adaptive_background()
	_gen_legacy_icon()
	_gen_boot_splash()
	print("DONE: all brand assets generated")


## --- Verification helpers (used by tests) ---

## Check that adaptive foreground mark fits in 66% safe zone.
## Returns (bool_ok, String_details).
static func verify_adaptive_safe_zone() -> Array:
	var path := _resolve(OUT_DIR + "adaptive_foreground_432x432.png")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return [false, "adaptive_foreground_432x432.png not found"]
	f.close()

	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return [false, "failed to load adaptive foreground"]

	# Find alpha bounds
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var max_x := 0
	var min_y := h
	var max_y := 0
	var found := false

	img.lock()
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			if c.a > 0.01:
				found = true
				if x < min_x: min_x = x
				if x > max_x: max_x = x
				if y < min_y: min_y = y
				if y > max_y: max_y = y
	img.unlock()

	if not found:
		return [false, "no opaque pixels found in adaptive foreground"]

	var mark_w := max_x - min_x + 1
	var mark_h := max_y - min_y + 1
	var mark_diameter := maxf(mark_w, mark_h)
	var safe_diameter := int(ADAPTIVE_FG_SIZE * 0.66)

	var ok := mark_diameter <= safe_diameter
	var details := "mark diameter: %d, safe zone diameter: %d (66%% of %d), fit: %s" % [
		mark_diameter, safe_diameter, ADAPTIVE_FG_SIZE, "YES" if ok else "NO"
	]
	return [ok, details]


## Verify all output files exist with correct dimensions.
static func verify_outputs() -> Array[Dictionary]:
	var results: Array[Dictionary] = []

	var checks := [
		{"path": "adaptive_foreground_432x432.png", "w": ADAPTIVE_FG_SIZE, "h": ADAPTIVE_FG_SIZE},
		{"path": "legacy_icon_192x192.png", "w": LEGACY_ICON_SIZE, "h": LEGACY_ICON_SIZE},
		{"path": "boot_splash_1080x2400.png", "w": SPLASH_WIDTH, "h": SPLASH_HEIGHT},
	]

	for c in checks:
		var path := _resolve(OUT_DIR + c["path"])
		var f := FileAccess.open(path, FileAccess.READ)
		var entry := {"file": c["path"], "exists": f != null}
		if f != null:
			f.close()
			var img := Image.load_from_file(path)
			if img != null and not img.is_empty():
				entry["width"] = img.get_width()
				entry["height"] = img.get_height()
				entry["size_ok"] = (img.get_width() == c["w"] and img.get_height() == c["h"])
			else:
				entry["size_ok"] = false
				entry["error"] = "failed to load or empty"
		else:
			entry["size_ok"] = false
		results.append(entry)

	# Background color file
	var bg_path := _resolve(OUT_DIR + "adaptive_background_color.txt")
	var f := FileAccess.open(bg_path, FileAccess.READ)
	var bg_entry := {"file": "adaptive_background_color.txt", "exists": f != null}
	if f != null:
		var content := f.get_line()
		f.close()
		bg_entry["content"] = content
		bg_entry["valid_hex"] = content.begins_with("#") and content.length() == 7
	else:
		bg_entry["valid_hex"] = false
	results.append(bg_entry)

	return results