shader_type canvas_item;
render_mode blend_add, unshaded;
// Galaxy: deep nebula plus a parallaxing star field. The nebula drift and the
// star cells shift the other way as the card tilts. 4 value-noise octaves and a
// handful of hash cells keep it inside the mobile budget.

uniform vec2 tilt = vec2(0.0);
uniform sampler2D ramp : hint_default_black, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D depth_tex : hint_default_black, filter_linear;
uniform float depth_mask : hint_range(0.0, 1.0) = 0.6;

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

void fragment() {
	float near = texture(depth_tex, UV).r;
	float figure = clamp(1.0 - near * depth_mask, 0.0, 1.0);

	float n = fbm((UV + tilt * 0.05) * 3.0 + vec2(TIME * 0.018, TIME * 0.011));
	vec3 nebula = texture(ramp, vec2(clamp(n * 1.4, 0.0, 1.0), 0.5)).rgb * 0.7;

	vec2 cell = floor((UV + tilt * 0.12) * 60.0);
	float r = hash(cell);
	float star = step(0.94, r);
	float twinkle = 0.5 + 0.5 * sin(TIME * 1.7 + r * 50.0);

	vec3 col = nebula + vec3(0.90, 0.95, 1.0) * star * twinkle;
	float a = (0.30 + n * 0.35 + star * 0.7) * intensity * figure;
	COLOR = vec4(col * a, a);
}
