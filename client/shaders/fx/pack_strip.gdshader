shader_type canvas_item;
render_mode blend_mix, unshaded;
// The strip that was just ripped off. Same skin as the body (shared include) and
// the same crimp phase, so the two halves of the wrapper stay visibly one piece
// as the strip tips away and drops.
#include "res://shaders/fx/pack_skin.gdshader"

uniform float fall : hint_range(0.0, 1.0) = 0.0;
// How much of the pack this strip covers, so the crimp lines land on the same
// UVs they had on the body.
uniform float slice : hint_range(0.05, 0.6) = 0.28;

void fragment() {
	vec3 foil = pack_surface(vec2(UV.x, UV.y * slice));
	// Backlit by the light coming out of the torn opening, strongest along the
	// cut edge at the bottom of the strip.
	float inner_glow = smoothstep(0.0, 0.55, 1.0 - UV.y) * 0.35;
	foil += vec3(1.0, 0.88, 0.62) * inner_glow;
	float a = pack_shape(vec2(UV.x, UV.y / slice), pack_radius) * (1.0 - fall);
	COLOR = vec4(foil, a);
}