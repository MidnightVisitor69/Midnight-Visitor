// Shared foil-pack surface, included (not compiled on its own) by
// pack_tear.gdshader and pack_strip.gdshader so a torn strip is pixel-identical
// to the body it came from. Nothing here reads TIME: a screenshot of a sealed
// pack has to land on the same pixels every run.
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec3 pack_top : source_color = vec3(0.086, 0.106, 0.243);
uniform vec3 pack_bottom : source_color = vec3(0.412, 0.082, 0.337);
uniform vec3 pack_foil : source_color = vec3(0.60, 0.86, 1.00);
// Ridge height of the crimp lines a real foil wrapper is creased into.
uniform float pack_crimp : hint_range(0.0, 0.4) = 0.10;
uniform float pack_radius : hint_range(0.0, 0.5) = 0.06;

// Rounded-rect coverage for UV, so the wrapper does not read as a plain
// rectangle. Returns alpha only; the caller owns the colour.
float pack_shape(vec2 uv, float radius) {
	vec2 d = abs(uv - vec2(0.5)) - vec2(0.5 - radius);
	float outside = length(max(d, 0.0)) - radius;
	return 1.0 - smoothstep(-0.002, 0.002, outside);
}

// Diagonal navy-to-magenta wash, vertical crimp ridges, and one soft sheen
// across the upper third (the foil catching the room light).
vec3 pack_surface(vec2 uv) {
	float t = clamp(uv.x * 0.30 + uv.y * 0.80, 0.0, 1.0);
	vec3 col = mix(pack_top, pack_bottom, t);

	float ridge = abs(fract(uv.x * 13.0) - 0.5) * 2.0;
	col += pack_foil * pack_crimp * ridge;
	col += vec3(0.16, 0.18, 0.24) * pack_crimp * (1.0 - ridge);

	col += vec3(1.0, 0.92, 0.98) * 0.07 * smoothstep(0.60, 0.0, abs(uv.y - 0.20));
	return col;
}