shader_type canvas_item;
render_mode blend_add, unshaded;
// Silver: a cool white/grey sheen band. The band sweeps diagonally as the
// device tilts, with a thin specular line riding in front of it and a very
// slow time creep so the foil is never dead still (motion=0 kills the creep).
// Additive so the figure underneath is never darkened.

uniform vec2 tilt = vec2(0.0);
uniform sampler2D ramp : hint_default_black, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D depth_tex : hint_default_black, filter_linear;
// Near pixels (the figure) get less foil so the character stays readable.
uniform float depth_mask : hint_range(0.0, 1.0) = 0.6;
// Rounded card silhouette (keep in sync across shaders/holo/*.gdshader).
uniform vec2 rect_size = vec2(0.0);
uniform float corner_radius : hint_range(0.0, 40.0) = 0.0;
uniform float motion = 1.0;
// Fine foil grain: micro-facets that crawl as the card tilts.
uniform float grain : hint_range(0.0, 1.0) = 0.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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

	vec2 p = UV - vec2(0.5);
	float d = p.x * 0.8 + p.y * 0.6 - tilt.x * 0.45 + tilt.y * 0.30
			+ sin(TIME * 0.21) * 0.05 * motion;

	float band = smoothstep(0.42, 0.0, abs(d));
	float edge = smoothstep(0.07, 0.0, abs(d + 0.14));
	float spec = smoothstep(0.035, 0.0, abs(d - 0.06));
	float sheen = band * 0.6 + edge * 0.5 + spec * 0.55;

	vec2 grain_px = rect_size.x > 1.0 ? UV * rect_size : UV * 480.0;
	float g = hash(floor((grain_px + tilt * 18.0) / 2.0));
	sheen *= 1.0 - grain + grain * (0.7 + 0.6 * g);

	vec3 c = texture(ramp, vec2(clamp(0.5 + d * 1.6, 0.0, 1.0), 0.5)).rgb;
	c = mix(c, vec3(1.0), spec * 0.55);
	float a = sheen * intensity * figure * window_mask(UV);
	COLOR = vec4(c * a, a);
}
