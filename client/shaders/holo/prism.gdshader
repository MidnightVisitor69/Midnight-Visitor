shader_type canvas_item;
render_mode blend_add, unshaded;
// Prism: fine diffraction stripes. High frequency reads as a hard prismatic
// foil; the stripe angle and phase both shift with tilt.

uniform vec2 tilt = vec2(0.0);
uniform sampler2D ramp : hint_default_black, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D depth_tex : hint_default_black, filter_linear;
uniform float depth_mask : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	float near = texture(depth_tex, UV).r;
	float figure = clamp(1.0 - near * depth_mask, 0.0, 1.0);

	vec2 p = UV - vec2(0.5);
	float ang = 0.6 + tilt.x * 0.5;
	float s = p.x * cos(ang) + p.y * sin(ang);

	float stripe = 0.5 + 0.5 * sin(s * 95.0 + tilt.y * 4.0);
	float t = fract(s * 0.9 + tilt.y * 0.25 + 0.5);
	vec3 c = texture(ramp, vec2(t, 0.5)).rgb;
	float a = (0.25 + 0.75 * stripe) * intensity * figure;
	COLOR = vec4(c * a, a);
}
