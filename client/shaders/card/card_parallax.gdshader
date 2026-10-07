shader_type canvas_item;
// Depth parallax + idle breathing for rare and epic cards, combined in one
// pass: it is cheaper on mobile than stacking two shaders (one extra texture
// read, no SCREEN_TEXTURE, no loops).

uniform sampler2D depth_tex : hint_default_black, filter_linear;
uniform vec2 tilt = vec2(0.0);
// How far the nearest layer can slide, in UV units.
uniform float parallax_strength : hint_range(0.0, 0.08) = 0.025;
// Idle "breathing" scale, weighted by depth so the background stays still.
uniform float breath_strength : hint_range(0.0, 0.02) = 0.004;
uniform float breath_speed : hint_range(0.0, 4.0) = 1.1;

void fragment() {
	float depth = clamp(texture(depth_tex, UV).r, 0.0, 1.0);

	// Inset the sampling window by the largest possible movement so parallax
	// can never reveal an edge of the art.
	float margin = parallax_strength + breath_strength + 0.002;
	vec2 uv = mix(vec2(margin), vec2(1.0 - margin), UV);

	// Near pixels (bright depth) slide the most, far pixels barely move.
	uv += tilt * parallax_strength * (depth - 0.5) * 2.0;

	// Breathing: gentle scale around the centre, scaled by depth.
	vec2 centred = uv - vec2(0.5);
	centred *= 1.0 + sin(TIME * breath_speed) * breath_strength * depth;
	uv = clamp(centred + vec2(0.5), vec2(0.0), vec2(1.0));

	COLOR = texture(TEXTURE, uv);
}
