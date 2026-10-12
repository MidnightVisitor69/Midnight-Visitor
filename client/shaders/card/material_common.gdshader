shader_type canvas_item;
render_mode unshaded;
// Common: matte card stock. Fine paper fiber noise, printed ink border in the
// rarity color at low saturation, crisp name plate. No shine.
// The frame band + laminate are drawn in one pass. The art is rendered
// separately underneath (clipped to the same rounded rect).

uniform vec2 rect_size = vec2(0.0);
uniform float corner_radius : hint_range(0.0, 40.0) = 0.0;
uniform vec4 frame_color : source_color = vec4(0.37, 0.42, 0.52, 1.0); // gunmetal
uniform vec4 ink_color : source_color = vec4(0.055, 0.071, 0.145, 1.0); // card_ink
uniform float band_thickness : hint_range(0.0, 20.0) = 8.0;
uniform float motion = 1.0;
uniform vec2 tilt = vec2(0.0);

// Paper fiber noise - fine, static, no animation
float paper_noise(vec2 p) {
    vec2 n = p * 0.015;
    float v = 0.0;
    v += 0.50 * sin(n.x * 12.9898 + n.y * 78.233);
    v += 0.25 * sin(n.x * 39.346 + n.y * 11.135);
    v += 0.12 * sin(n.x * 11.135 + n.y * 39.346);
    return fract(v * 43758.5453);
}

// Rounded rect mask
float rounded_mask(vec2 uv) {
    if (rect_size.x < 1.0 || corner_radius < 0.5) { return 1.0; }
    vec2 half = rect_size * 0.5;
    vec2 q = abs(uv * rect_size - half) - max(half - vec2(corner_radius), vec2(0.0));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;
    return 1.0 - smoothstep(-1.5, 0.0, d);
}

void fragment() {
    vec2 uv = UV;
    float mask = rounded_mask(uv);
    
    // Base card stock color (ink plate)
    vec3 col = ink_color.rgb;
    
    // Fine paper fiber texture
    float fiber = paper_noise(uv * rect_size);
    col *= 0.98 + 0.04 * fiber;
    
    // Frame band: printed ink border at low saturation
    vec2 half = rect_size * 0.5;
    vec2 q = abs(uv * rect_size - half);
    float dist_to_edge = min(half.x - q.x, half.y - q.y);
    float band = smoothstep(band_thickness, 0.0, dist_to_edge);
    
    // Desaturated frame color for the printed border
    vec3 frame_desat = mix(frame_color.rgb, vec3(dot(frame_color.rgb, vec3(0.299, 0.587, 0.114))), 0.7);
    col = mix(col, frame_desat, band * 0.35);
    
    // Inner hairline highlight (subtle)
    float hairline = smoothstep(band_thickness * 1.15, band_thickness * 1.05, dist_to_edge);
    col += vec3(1.0, 1.0, 1.0) * hairline * 0.04 * mask;
    
    COLOR = vec4(col, mask);
}