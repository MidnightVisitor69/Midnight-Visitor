shader_type canvas_item;
render_mode blend_add, unshaded;
// Soft specular sweep for epic and legendary cards. Purely additive so it
// never darkens the art; position follows tilt. No loops, no SCREEN_TEXTURE.
// Masked to the same rounded silhouette as the art layers.

uniform vec2 tilt = vec2(0.0);
uniform vec4 tint : source_color = vec4(1.0, 0.96, 0.90, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.35;
uniform vec2 rect_size = vec2(0.0);
uniform float corner_radius : hint_range(0.0, 40.0) = 0.0;
// Present for API parity with the other card shaders; this pass has no idle
// time term, so it is unused here.
uniform float motion = 1.0;

void fragment() {
	vec2 p = UV - vec2(0.5) - tilt * 0.30;
	float glow = smoothstep(0.55, 0.0, length(p * vec2(1.0, 0.72)));
	float streak = smoothstep(0.12, 0.0, abs(p.x * 0.7 + p.y * 0.3));
	float a = (glow * 0.75 + streak * 0.25) * strength;
	if (rect_size.x > 1.0 && corner_radius > 0.5) {
		vec2 half_size = rect_size * 0.5;
		vec2 q = abs(UV * rect_size - half_size)
				- max(half_size - vec2(corner_radius), vec2(0.0));
		float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;
		a *= 1.0 - smoothstep(-1.5, 0.0, d);
	}
	COLOR = vec4(tint.rgb * a, a);
}
