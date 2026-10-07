shader_type canvas_item;
render_mode blend_add, unshaded;
// Rainbow: hue bands from the ramp, the band angle following tilt like light
// bent through a grating. Additive keeps the art under it readable.

uniform vec2 tilt = vec2(0.0);
uniform sampler2D ramp : hint_default_black, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D depth_tex : hint_default_black, filter_linear;
uniform float depth_mask : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	float near = texture(depth_tex, UV).r;
	float figure = clamp(1.0 - near * depth_mask, 0.0, 1.0);

	vec2 p = UV - vec2(0.5);
	float ang = tilt.x * 0.9 + tilt.y * 0.5;
	float ca = cos(ang);
	float sa = sin(ang);
	float s = p.x * ca - p.y * sa;

	float t = fract(s * 1.3 + tilt.y * 0.30 + 0.5);
	vec3 c = texture(ramp, vec2(t, 0.5)).rgb;
	// Soften the band edges so it reads as a sheen, not stripes.
	float sheen = 0.55 + 0.45 * sin(t * 6.28318);
	float a = sheen * intensity * figure;
	COLOR = vec4(c * a, a);
}
