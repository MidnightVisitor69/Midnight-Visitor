shader_type canvas_item;
render_mode blend_add, unshaded;
// Legendary build-up: gold light rays fanning out from behind the card while the
// screen dims. Additive, slow and low-contrast, so it reads as light in a dark
// room rather than as a spinning graphic. Amount is driven by the reveal tween,
// never by TIME, so a screenshot can seek to a fixed frame.

uniform vec3 ray_color : source_color = vec3(1.0, 0.78, 0.32);
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float ray_count : hint_range(4.0, 24.0) = 11.0;
uniform float spin = 0.22;

void fragment() {
	vec2 p = UV - vec2(0.5);
	// Below the centre is where the card sits, so keep the fan behind it.
	if (p.y > 0.0) {
		COLOR = vec4(0.0);
	} else {
		float ang = atan(p.y, p.x) + TIME * spin;
		float d = abs(p.y) * 2.2;
		float rays = 0.5 + 0.5 * sin(ang * ray_count);
		rays = pow(rays, 3.0);
		// Fade toward the card and out at the top of the frame.
		float falloff = smoothstep(0.0, 0.9, d) * (1.0 - smoothstep(0.9, 1.6, d));
		float a = amount * rays * falloff;
		COLOR = vec4(ray_color * a, a);
	}
}