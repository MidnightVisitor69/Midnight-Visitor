shader_type canvas_item;
render_mode blend_add, unshaded;
// Gold: a warm sheen plus sparse glints. The glint cells shift with tilt so the
// sparkle crawls across the foil, and each one twinkles on its own phase
// (motion=0 freezes the twinkle, keeping the foil readable but still).

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
	float d = p.x * 0.7 + p.y * 0.7 - tilt.x * 0.50 - sin(TIME * 0.17) * 0.05 * motion;
	float band = smoothstep(0.52, 0.0, abs(d));
	float spec = smoothstep(0.05, 0.0, abs(d - 0.04));
	vec3 c = texture(ramp, vec2(clamp(0.5 + d * 1.8, 0.0, 1.0), 0.5)).rgb;

	// One candidate per cell; only the rare bright cell actually glints.
	vec2 cell = floor((UV * (rect_size.x > 1.0 ? rect_size : vec2(480.0))
			+ tilt * 30.0) / 4.0);
	float r = hash(cell);
	float glint = step(0.88, r) * (0.5 + 0.5 * sin(TIME * 2.2 * motion + r * 40.0));

	// Fine foil grain modulates the sheen so the metal never reads flat.
	vec2 grain_px = rect_size.x > 1.0 ? UV * rect_size : UV * 480.0;
	float g = hash(floor((grain_px + tilt * 18.0) / 2.0));
	band *= 1.0 - grain + grain * (0.7 + 0.6 * g);

	c = mix(c, vec3(1.0, 0.97, 0.88), spec * 0.6);
	vec3 col = c * band + vec3(1.0, 0.88, 0.55) * glint + vec3(1.0) * spec * 0.25;
	float a = (band * 0.6 + spec * 0.5 + glint * 0.8) * intensity * figure * window_mask(UV);
	COLOR = vec4(col * a, a);
}
