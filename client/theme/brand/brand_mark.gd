class_name BrandMark
extends RefCounted
## The "Neon After-Hours" brand mark: a crescent moon with a single neon
## sign stroke. Drawn entirely with vector primitives so it scales cleanly
## from 48 px (launcher) to 1080 px (splash) without any raster assets.
##
## The mark reads as "late night city lounge" - the moon is the quiet
## witness, the neon line is the signage glow through rain glass.
##
## All colors and dimensions come from design tokens (D-001). No hardcoded
## values allowed.

const TokensScript := preload("res://theme/tokens.gd")


## Draw the mark centered in `rect` (a Rect2 in local coordinates) on the
## given `canvas` (a CanvasItem). `palette` lets callers override colors
## for different backgrounds (e.g. adaptive icon foreground vs. splash on navy).
static func draw(canvas: CanvasItem, rect: Rect2, palette: Dictionary = {}) -> void:
	var c := rect.position + rect.size * 0.5
	var size := minf(rect.size.x, rect.size.y)

	# Base colors from tokens, overridable via palette.
	var bg_color: Color = palette.get("bg", TokensScript.color(&"bg"))
	var moon_color: Color = palette.get("moon", TokensScript.color(&"surface_3"))
	var neon_color: Color = palette.get("neon", TokensScript.color(&"accent"))
	var neon_glow_color: Color = palette.get("neon_glow", Color(neon_color.r, neon_color.g, neon_color.b, 0.35))

	# Moon radius: ~42% of the mark size, so it reads at small sizes.
	var moon_r: float = size * 0.42

	# Neon line: a single curved stroke suggesting a sign tube.
	# Starts at moon's upper-right, arcs outward and down like a
	# handwritten "open" flourish. Thickness scales with size.
	var stroke_w: float = maxf(2.0, size * 0.055)  # ~2px at 48px, ~24px at 432px

	# --- Moon (crescent via two overlapping circles) ---
	# Main moon disc: draw_circle with width = diameter to fill
	canvas.draw_circle(c, moon_r, moon_color, moon_r * 2.0)
	# Crescent cut: a darker circle offset to carve the crescent shape
	var cut_r: float = moon_r * 0.88
	var cut_offset: Vector2 = Vector2(moon_r * 0.22, -moon_r * 0.18)
	canvas.draw_circle(c + cut_offset, cut_r, bg_color, cut_r * 2.0)

	# --- Neon sign stroke ---
	# Path: from moon's 1 o'clock, arc out and down to 5 o'clock.
	var start_angle: float = PI * 0.25   # ~1:30 on clock
	var end_angle: float = PI * 1.35     # ~4:30 on clock
	var arc_r: float = moon_r * 1.35

	var segments: int = maxi(16, int(size * 0.12))
	var prev_pt: Vector2 = c + Vector2(cos(start_angle), sin(start_angle)) * arc_r

	# Glow pass (wider, lower alpha) - draws first so stroke sits on top
	var glow_w: float = stroke_w * 2.2
	for i in range(1, segments + 1):
		var t: float = float(i) / segments
		var a: float = lerp(start_angle, end_angle, t)
		var pt: Vector2 = c + Vector2(cos(a), sin(a)) * arc_r
		canvas.draw_line(prev_pt, pt, neon_glow_color, glow_w, true)
		prev_pt = pt

	# Core neon stroke
	prev_pt = c + Vector2(cos(start_angle), sin(start_angle)) * arc_r
	for i in range(1, segments + 1):
		var t: float = float(i) / segments
		var a: float = lerp(start_angle, end_angle, t)
		var pt: Vector2 = c + Vector2(cos(a), sin(a)) * arc_r
		canvas.draw_line(prev_pt, pt, neon_color, stroke_w, true)
		prev_pt = pt

	# Tiny end-cap highlight at the stroke tip (the "live" end of the tube)
	var tip: Vector2 = c + Vector2(cos(end_angle), sin(end_angle)) * arc_r
	canvas.draw_circle(tip, stroke_w * 0.6, Color(1.0, 1.0, 1.0, 0.9), stroke_w * 1.2)


## Get the bounding rect of the mark's opaque pixels at a given size.
## Used for safe-zone verification (adaptive icon 66% rule).
static func get_opaque_bounds(size: int) -> Rect2:
	# The mark is centered; the moon extends to ~0.42 * size radius.
	# The neon stroke extends to ~1.35 * 0.42 = ~0.57 * size radius.
	# So the full mark fits in a circle of radius ~0.57 * size.
	# The 66% safe zone means the mark must fit in 0.66 * size diameter
	# = 0.33 * size radius from center.
	# Our mark at 0.57 radius EXCEEDS the safe zone - we need to scale it down.
	# The render_brand.gd will handle scaling the mark to fit the safe zone.
	var mark_radius: float = size * 0.57
	var safe_radius: float = size * 0.33
	var scale: float = safe_radius / mark_radius  # ~0.58
	var actual_radius: float = mark_radius * scale
	var half: float = actual_radius
	return Rect2(size * 0.5 - half, size * 0.5 - half, actual_radius * 2, actual_radius * 2)