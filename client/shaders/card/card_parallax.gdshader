shader_type canvas_item;
// Depth parallax + idle breathing for rare and epic cards, combined in one
// pass: it is cheaper on mobile than stacking two shaders (one extra texture
// read, no SCREEN_TEXTURE, no loops).
//
// It also owns the CARD SILHOUETTE: every art layer is alpha-clipped to a
// rounded rect (radius = corner_radius of the whole card), so art can never
// poke past the frame's rounded corners. The frame band is drawn opaque on
// top of this layer, so the window is computed at the full card rect.

uniform sampler2D depth_tex : hint_default_black, filter_linear;
uniform vec2 tilt = vec2(0.0);
// How far the nearest layer can slide, in UV units.
uniform float parallax_strength : hint_range(0.0, 0.08) = 0.025;
// Idle "breathing" scale, weighted by depth so the background stays still.
uniform float breath_strength : hint_range(0.0, 0.02) = 0.004;
uniform float breath_speed : hint_range(0.0, 4.0) = 1.1;
// Card rect in px + corner radius in px. rect_size <= 1 means "not laid out
// yet" (unit tests) and skips the mask instead of erasing the art.
uniform vec2 rect_size = vec2(0.0);
uniform float corner_radius : hint_range(0.0, 40.0) = 0.0;
// 0 = reduced motion: kills the idle breath, tilt response stays (it is the
// user's own input, not autoplay).

uniform float motion = 1.0;

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
	centred *= 1.0 + sin(TIME * breath_speed) * breath_strength * depth * motion;
	uv = clamp(centred + vec2(0.5), vec2(0.0), vec2(1.0));

	vec4 c = texture(TEXTURE, uv);

	// Rounded card silhouette (signed distance to a rounded rect).
	float alpha = c.a;
	if (rect_size.x > 1.0 && corner_radius > 0.5) {
		vec2 half_size = rect_size * 0.5;
		vec2 q = abs(UV * rect_size - half_size)
				- max(half_size - vec2(corner_radius), vec2(0.0));
		float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;
		alpha *= 1.0 - smoothstep(-1.5, 0.0, d);
	}
	COLOR = vec4(c.rgb, alpha);
}
