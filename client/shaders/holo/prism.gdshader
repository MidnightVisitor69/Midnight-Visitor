shader_type canvas_item;
render_mode blend_add, unshaded;
// Prism: fine diffraction stripes. High frequency reads as a hard prismatic
// foil; the stripe angle and phase both shift with tilt, with a slow creep
// (motion=0 kills it) and a fine facet grain over the top.

uniform vec2 tilt = vec2(0.0);
uniform sampler2D ramp : hint_default_black, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D depth_tex : hint_default_black, filter_linear;
uniform float depth_mask : hint_range(0.0, 1.0) = 0.6;
// Rounded card silhouette (keep in sync across shaders/holo/*.gdshader).
uniform vec2 rect_size = vec2(0.0);
uniform float corner_radius : hint_range(0.0, 40.0) = 0.0;
uniform float motion = 1.0;
uniform float grain : hint_range(0.0, 1.0) = 0.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float window_mask(vec2 uv) {
	if (rect_size.x < 1.0 || corner_radius < 0.5) { return 1.0; }
	vec2 half_size = rect_size * 0.5;
	vec2 q = abs(uv * rect_size - half_size) - max(half_size - vec2(corner_radius), vec2(0.0));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;
	return 1.0 - smoothstep(-1.5, 0.0, d);
}

void fragment() {
	float near = texture(depth_tex, UV).r;
	float figure = clamp(1.0 - near * depth_mask, 0.0, 1.0);

	vec2 p = UV - vec2(0.5);
	float ang = 0.6 + tilt.x * 0.5 + sin(TIME * 0.11) * 0.06 * motion;
	float s = p.x * cos(ang) + p.y * sin(ang);

	float stripe = 0.5 + 0.5 * sin(s * 95.0 + tilt.y * 4.0 + TIME * 0.35 * motion);
	float t = fract(s * 0.9 + tilt.y * 0.25 + TIME * 0.01 * motion + 0.5);
	vec3 c = texture(ramp, vec2(t, 0.5)).rgb;

	// The brightest stripe cores read as the prism's specular flare.
	float spec = smoothstep(0.90, 1.0, stripe);

	vec2 grain_px = rect_size.x > 1.0 ? UV * rect_size : UV * 480.0;
	float g = hash(floor((grain_px + tilt * 18.0) / 2.0));
	stripe *= 1.0 - grain + grain * (0.7 + 0.6 * g);

	c = mix(c, vec3(1.0), spec * 0.4);
	float a = (0.25 + 0.75 * stripe + spec * 0.4) * intensity * figure * window_mask(UV);
	COLOR = vec4(c * a, a);
}
