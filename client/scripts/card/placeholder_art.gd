class_name PlaceholderArt
extends RefCounted
## Procedural stand-in art so the card tiers can be built and reviewed before
## the image pipeline delivers approved PNGs. No image files, no randomness:
## every call returns identical pixels so screenshots and tests stay stable.
## (BLOCKED placeholder: this is our art, not generated character art.)

const WIDTH := 512
const HEIGHT := 768

const NAVY := Color(0.05, 0.07, 0.20)
const MAGENTA := Color(0.52, 0.09, 0.42)
const FIGURE := Color(0.86, 0.82, 0.97)
## Depth value of the background: far away, so parallax barely moves it.
const FAR := 0.16


## All four layer textures, matching the Handoff Contract art inputs.
static func build() -> Dictionary:
	return {
		"base": base_texture(),
		"depth": depth_texture(),
		"char": char_texture(),
		"bg": bg_texture(),
	}


static func base_texture() -> ImageTexture:
	var img := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in HEIGHT:
		for x in WIDTH:
			var bg := _gradient(float(x), float(y))
			var f := _figure_alpha(float(x), float(y))
			img.set_pixel(x, y, bg.lerp(FIGURE, f * 0.65))
	return ImageTexture.create_from_image(img)


static func depth_texture() -> ImageTexture:
	var img := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in HEIGHT:
		for x in WIDTH:
			var v := lerpf(FAR, 1.0, _figure_alpha(float(x), float(y)))
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)


static func char_texture() -> ImageTexture:
	var img := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in HEIGHT:
		for x in WIDTH:
			var a := _figure_alpha(float(x), float(y))
			img.set_pixel(x, y, Color(FIGURE.r, FIGURE.g, FIGURE.b, a))
	return ImageTexture.create_from_image(img)


static func bg_texture() -> ImageTexture:
	var img := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in HEIGHT:
		for x in WIDTH:
			img.set_pixel(x, y, _gradient(float(x), float(y)))
	return ImageTexture.create_from_image(img)


## Diagonal navy -> magenta wash plus a faint glow toward the figure.
static func _gradient(px: float, py: float) -> Color:
	var t := clampf((px / float(WIDTH) + py / float(HEIGHT)) * 0.5, 0.0, 1.0)
	var c := NAVY.lerp(MAGENTA, t)
	return c.lerp(FIGURE, 0.12 * smoothstep(0.9, 0.0, _figure_alpha(px, py)))


## Rounded head over a torso, union of two ellipses with a soft edge.
static func _figure_alpha(px: float, py: float) -> float:
	var head := _ellipse(px, py, WIDTH * 0.5, HEIGHT * 0.235,
			WIDTH * 0.115, HEIGHT * 0.095, 1.6)
	var torso := _ellipse(px, py, WIDTH * 0.5, HEIGHT * 0.60,
			WIDTH * 0.21, HEIGHT * 0.29, 1.6)
	return maxf(head, torso)


static func _ellipse(px: float, py: float, cx: float, cy: float,
		rx: float, ry: float, feather_px: float) -> float:
	var dx := (px - cx) / rx
	var dy := (py - cy) / ry
	var d := sqrt(dx * dx + dy * dy)
	# Convert the normalized distance back to pixels for a consistent edge.
	var edge_px := (d - 1.0) * minf(rx, ry)
	return clampf(0.5 - edge_px / feather_px, 0.0, 1.0)
