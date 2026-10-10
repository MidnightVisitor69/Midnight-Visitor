shader_type canvas_item;
render_mode blend_add, unshaded;
// Rainbow: hue bands from the ramp, the band angle following tilt like light
// bent through a grating, plus a fine foil grain and a slow phase creep
// (motion=0 kills the creep). Additive keeps the art under it readable.

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
	float ang = tilt.x * 0.9 + tilt.y * 0.5 + sin(TIME * 0.13) * 0.10 * motion;
	float ca = cos(ang);
	float sa = sin(ang);
	float s = p.x * ca - p.y * sa;

	float t = fract(s * 1.3 + tilt.y * 0.30 + TIME * 0.012 * motion + 0.5);
	vec3 c = texture(ramp, vec2(t, 0.5)).rgb;
	// Soften the band edges so it reads as a sheen, not stripes.
	float sheen = 0.55 + 0.45 * sin(t * 6.28318);
	// A restrained white specular where the sheen peaks.
	float spec = smoothstep(0.92, 1.0, sheen);

	vec2 grain_px = rect_size.x > 1.0 ? UV * rect_size : UV * 480.0;
	float g = hash(floor((grain_px + tilt * 18.0) / 2.0));
	sheen *= 1.0 - grain + grain * (0.7 + 0.6 * g);

	c = mix(c, vec3(1.0), spec * 0.35);
	float a = (sheen + spec * 0.35) * intensity * figure * window_mask(UV);
	COLOR = vec4(c * a, a);
}
