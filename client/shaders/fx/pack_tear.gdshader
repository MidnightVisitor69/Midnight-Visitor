shader_type canvas_item;
render_mode blend_mix, unshaded;
// The sealed wrapper plus the rip. The tear is a MASK, not a moving sprite: the
// line starts under the finger and races outward, jagging as it goes, and light
// in the best rarity's colour spills through the hole it leaves.
#include "res://shaders/fx/pack_skin.gdshader"

// 0 sealed, 1 torn all the way across. A jumpy value is fine; that is a finger
// ripping foil, not a progress bar.
uniform float tear : hint_range(0.0, 1.0) = 0.0;
// Where the player's finger crossed the top edge, in UV space.
uniform float rip_x : hint_range(0.0, 1.0) = 0.5;
// How ragged the torn edge is.
uniform float jag : hint_range(0.0, 0.2) = 0.055;
// Colour of the best rarity inside: common grey, rare blue, epic violet,
// legendary gold.
uniform vec3 inner_light : source_color = vec3(1.0, 0.80, 0.28);
uniform float burst : hint_range(0.0, 1.0) = 0.0;

// Height of the torn region at x. Two out-of-phase bands so the edge never
// reads as a sine wave, and the jag scales with tear so a sealed pack is
// perfectly clean.
float torn_height(float x) {
	float d = abs(x - rip_x);
	// The rip runs faster where it started, so it thins out toward the corners.
	float reach = tear * (0.20 + 0.80 * smoothstep(0.0, 0.62, d));
	float wobble = sin(x * 47.0) * 0.55 + sin(x * 19.0 + 1.9) * 0.45;
	return reach + wobble * jag * tear;
}

void fragment() {
	float line = torn_height(UV.x);
	float sealed = smoothstep(line - 0.004, line + 0.004, UV.y);

	vec3 foil = pack_surface(UV);
	vec3 col = mix(inner_light * (0.55 + 0.45 * burst), foil, sealed);

	// A hot rim right on the cut edge, brightest at the moment of the rip.
	float rim = smoothstep(0.05, 0.0, abs(UV.y - line)) * burst;
	col += inner_light * rim * 0.9;

	float a = pack_shape(UV, pack_radius);
	COLOR = vec4(col, a);
}