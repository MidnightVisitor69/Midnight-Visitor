shader_type canvas_item;
render_mode blend_add, unshaded;
// Gold: a warm sheen plus sparse glints. The glint cells shift with tilt so the
// sparkle crawls across the foil, and each one twinkles on its own phase.

uniform vec2 tilt = vec2(0.0);
uniform sampler2D ramp : hint_default_black, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D depth_tex : hint_default_black, filter_linear;
uniform float depth_mask : hint_range(0.0, 1.0) = 0.6;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float near = texture(depth_tex, UV).r;
	float figure = clamp(1.0 - near * depth_mask, 0.0, 1.0);

	vec2 p = UV - vec2(0.5);
	float d = p.x * 0.7 + p.y * 0.7 - tilt.x * 0.50;
	float band = smoothstep(0.52, 0.0, abs(d));
	vec3 c = texture(ramp, vec2(clamp(0.5 + d * 1.8, 0.0, 1.0), 0.5)).rgb;

	// One candidate per cell; only the rare bright cell actually glints.
	vec2 cell = floor((UV + tilt * 0.15) * 28.0);
	float r = hash(cell);
	float glint = step(0.88, r) * (0.5 + 0.5 * sin(TIME * 2.2 + r * 40.0));

	vec3 col = c * band + vec3(1.0, 0.88, 0.55) * glint;
	float a = (band * 0.6 + glint * 0.8) * intensity * figure;
	COLOR = vec4(col * a, a);
}
