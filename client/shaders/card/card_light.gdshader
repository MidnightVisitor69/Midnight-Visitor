shader_type canvas_item;
render_mode blend_add, unshaded;
// Soft specular sweep for epic and legendary cards. Purely additive so it
// never darkens the art; position follows tilt. No loops, no SCREEN_TEXTURE.

uniform vec2 tilt = vec2(0.0);
uniform vec4 tint : source_color = vec4(1.0, 0.96, 0.90, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec2 p = UV - vec2(0.5) - tilt * 0.30;
	float glow = smoothstep(0.55, 0.0, length(p * vec2(1.0, 0.72)));
	float streak = smoothstep(0.12, 0.0, abs(p.x * 0.7 + p.y * 0.3));
	float a = (glow * 0.75 + streak * 0.25) * strength;
	COLOR = vec4(tint.rgb * a, a);
}
