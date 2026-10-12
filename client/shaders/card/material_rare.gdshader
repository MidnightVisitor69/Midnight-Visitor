shader_type canvas_item;
render_mode unshaded;
// Rare: satin pearl. Pearlescent frame whose sheen shifts subtly (blue-violet-pink)
// with tilt; soft rounded inner bevel. Fine pearl grain on the band.

uniform vec2 rect_size = vec2(0.0);
uniform float corner_radius : hint_range(0.0, 40.0) = 0.0;
uniform vec4 frame_color : source_color = vec4(0.78, 0.82, 0.89, 1.0); // silver
uniform vec4 ink_color : source_color = vec4(0.055, 0.071, 0.145, 1.0); // card_ink
uniform float band_thickness : hint_range(0.0, 20.0) = 8.0;
uniform float motion = 1.0;
uniform vec2 tilt = vec2(0.0);

// Pearl iridescence - shifts with view angle (tilt)
vec3 pearl_shift(float angle, float depth) {
    // Base pearl color
    vec3 base = vec3(0.85, 0.88, 0.95);
    // Iridescent shift: blue -> violet -> pink as angle changes
    float shift = sin(angle * 3.0 + depth * 6.28) * 0.5 + 0.5;
    vec3 irid = mix(
        vec3(0.65, 0.75, 1.00),  // blue
        vec3(1.00, 0.70, 0.85),  // pink
        shift
    );
    // Violet midpoint
    irid = mix(irid, vec3(0.80, 0.65, 1.00), smoothstep(0.4, 0.6, shift));
    return mix(base, irid, 0.35 + 0.15 * depth);
}

// Fine pearl grain
float pearl_grain(vec2 p) {
    vec2 n = p * 0.008;
    float v = sin(n.x * 17.0 + n.y * 23.0) * 0.5;
    v += sin(n.x * 31.0 + n.y * 13.0) * 0.3;
    v += sin(n.x * 11.0 + n.y * 41.0) * 0.2;
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
    
    // Frame band only: the art window stays transparent so the art beneath
    // (child 0 of the CardView) remains the hero.
    vec2 half = rect_size * 0.5;
    vec2 q = abs(uv * rect_size - half);
    float dist_to_edge = min(half.x - q.x, half.y - q.y);
    float band = smoothstep(band_thickness, 0.0, dist_to_edge);
    
    // Pearl material on the frame band; the sheen shifts with tilt.
    float angle = atan(tilt.y, tilt.x);
    float depth = 1.0 - smoothstep(0.0, band_thickness, dist_to_edge);
    vec3 pearl = pearl_shift(angle, depth);
    
    // Pearl grain modulation
    float grain = pearl_grain(uv * rect_size + tilt * 12.0);
    pearl *= 0.92 + 0.16 * grain;
    
    // Soft inner bevel: highlight on top-left, shadow on bottom-right of band
    float bevel = 0.0;
    if (band > 0.0) {
        vec2 band_uv = (uv * rect_size - half + vec2(band_thickness)) / band_thickness;
        float bevel_angle = atan(band_uv.y, band_uv.x);
        bevel = cos(bevel_angle - 0.785) * 0.15 * band; // 45 deg light
    }
    
    vec3 col = pearl * frame_color.rgb + bevel * vec3(1.0, 1.0, 1.0);
    
    // Inner hairline where the satin meets the art window.
    float hairline = smoothstep(band_thickness * 1.12, band_thickness * 1.02, dist_to_edge);
    col += vec3(1.0, 1.0, 1.0) * hairline * 0.08;
    
    COLOR = vec4(col, band * mask);
}