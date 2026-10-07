shader_type canvas_item;
render_mode blend_add, unshaded;
// Silver: a cool white/grey sheen band. The band sweeps diagonally as the
// device tilts, with a thinner highlight riding in front of it. Additive so the
// figure underneath is never darkened.

uniform vec2 tilt = vec2(0.0);
uniform sampler2D ramp : hint_default_black, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D depth_tex : hint_default_black, filter_linear;
// Near pixels (the figure) get less foil so the character stays readable.
uniform float depth_mask : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	float near = texture(depth_tex, UV).r;
	float figure = clamp(1.0 - near * depth_mask, 0.0, 1.0);

	vec2 p = UV - vec2(0.5);
	float d = p.x * 0.8 + p.y * 0.6 - tilt.x * 0.45 + tilt.y * 0.30;

	float band = smoothstep(0.42, 0.0, abs(d));
	float edge = smoothstep(0.07, 0.0, abs(d + 0.14));
	float sheen = band * 0.6 + edge * 0.5;

	vec3 c = texture(ramp, vec2(clamp(0.5 + d * 1.6, 0.0, 1.0), 0.5)).rgb;
	float a = sheen * intensity * figure;
	COLOR = vec4(c * a, a);
}
