shader_type canvas_item;
render_mode blend_add, unshaded;
// Galaxy: deep nebula plus a parallaxing star field. The nebula drift and the
// star cells shift the other way as the card tilts. 4 value-noise octaves and a
// handful of hash cells keep it inside the mobile budget. motion=0 freezes the
// drift and twinkle for reduced-motion devices.

uniform vec2 tilt = vec2(0.0);
uniform sampler2D ramp : hint_default_black, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D depth_tex : hint_default_black, filter_linear;
uniform float depth_mask : hint_range(0.0, 1.0) = 0.6;
// Rounded card silhouette (keep in sync across shaders/holo/*.gdshader).
uniform vec2 rect_size = vec2(0.0);
uniform float corner_radius : hint_range(0.0, 40.0) = 0.0;
uniform float motion = 1.0;
uniform float grain : hint_range(0.0, 1.0) = 0.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

float window_mask(vec2 uv) {
	if (rect_size.x < 1.0 || corner_radius < 0.5) { return 1.0; }
	vec2 half_size = rect_size * 0.5;
	vec2 q = abs(uv * rect_size - half_size) - max(half_size - vec2(corner_radius), vec2(0.0));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;
	return 1.0 - smoothstep(-1.5, 0.0, d);
}

void fragment() {
	float near = texture(depth_tex, UV).r;
	float figure = clamp(1.0 - near * depth_mask, 0.0, 1.0);

	float n = fbm((UV + tilt * 0.05) * 3.0 + vec2(TIME * 0.018 * motion, TIME * 0.011 * motion));
	vec3 nebula = texture(ramp, vec2(clamp(n * 1.4, 0.0, 1.0), 0.5)).rgb * 0.7;

	// Stars on a ~9px grid scaled to the card rect, so they stay fine-grained
	// at inspection size instead of turning into blocks. Each star is a small
	// round glint inside its cell, not the whole square.
	vec2 grid = rect_size.x > 1.0 ? rect_size : vec2(540.0);
	vec2 star_px = UV * grid + tilt * 26.0;
	vec2 cell_id = floor(star_px / 9.0);
	vec2 cell_uv = fract(star_px / 9.0) - 0.5;
	float r = hash(cell_id);
	float star = step(0.965, r) * (1.0 - smoothstep(0.10, 0.32, length(cell_uv)));
	float twinkle = 0.5 + 0.5 * sin(TIME * 1.7 * motion + r * 50.0);

	// Fine facet grain over the nebula so the foil never reads as a flat wash.
	vec2 grain_px = rect_size.x > 1.0 ? UV * rect_size : UV * 480.0;
	float g = hash(floor((grain_px + tilt * 18.0) / 2.0));
	float sheen = 1.0 - grain + grain * (0.7 + 0.6 * g);

	vec3 col = nebula * sheen + vec3(0.90, 0.95, 1.0) * star * twinkle;
	float a = (0.30 + n * 0.35 + star * 0.55) * sheen * intensity * figure * window_mask(UV);
	COLOR = vec4(col * a, a);
}
