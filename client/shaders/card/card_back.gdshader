shader_type canvas_item;
render_mode unshaded;
// Card back: "after hours" moon + neon sign line art on navy with a subtle
// foil pattern. Used face-down in pack opening and anywhere a card is hidden.
// All procedural - no image files.

uniform vec2 rect_size = vec2(0.0);
uniform float corner_radius : hint_range(0.0, 40.0) = 0.0;
uniform vec4 bg_color : source_color = vec4(0.027, 0.039, 0.071, 1.0); // navy base
uniform vec4 foil_color : source_color = vec4(0.216, 0.902, 1.0, 1.0); // cyan accent
uniform vec4 moon_color : source_color = vec4(1.0, 0.95, 0.85, 1.0); // warm moon
uniform vec4 neon_color : source_color = vec4(1.0, 0.239, 0.545, 1.0); // magenta neon
uniform float motion = 1.0;
uniform vec2 tilt = vec2(0.0);
uniform float time = 0.0;

// Foil pattern noise - subtle diagonal brush
float foil_pattern(vec2 p) {
    vec2 n = p * 0.008;
    float v = sin(n.x * 12.0 + n.y * 12.0) * 0.5;
    v += sin(n.x * 24.0 + n.y * 24.0 + 1.57) * 0.25;
    return fract(v * 43758.5453) * 0.5 + 0.5;
}

// Moon shape (crescent)
float moon_shape(vec2 p, float r) {
    float d = length(p);
    float moon = smoothstep(r * 0.95, r * 0.9, d);
    // Crescent cut
    float cut = smoothstep(r * 0.55, r * 0.5, length(p + vec2(r * 0.35, 0.0)));
    return moon * (1.0 - cut);
}

// Neon sign line art - "after hours" style horizontal lines
float neon_sign(vec2 p, float width, float height) {
    float lines = 0.0;
    // Three horizontal neon tubes
    for (int i = 0; i < 3; i++) {
        float y = -height * 0.15 + float(i) * height * 0.15;
        float tube = 1.0 - smoothstep(2.0, 0.5, abs(p.y - y));
        tube *= smoothstep(width * 0.45, 0.0, abs(p.x));
        // Flicker
        tube *= 0.85 + 0.15 * sin(time * 3.0 + float(i) * 2.0) * motion;
        lines += tube;
    }
    // Vertical end caps
    float cap = 1.0 - smoothstep(2.0, 0.5, abs(p.x - width * 0.43));
    cap *= smoothstep(height * 0.35, 0.0, abs(p.y));
    cap *= 0.85 + 0.15 * sin(time * 2.5 + 1.0) * motion;
    lines += cap;
    cap = 1.0 - smoothstep(2.0, 0.5, abs(p.x + width * 0.43));
    cap *= smoothstep(height * 0.35, 0.0, abs(p.y));
    cap *= 0.85 + 0.15 * sin(time * 2.5 + 2.0) * motion;
    lines += cap;
    return clamp(lines, 0.0, 1.0);
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
    
    // Center for emblem
    vec2 center = uv - vec2(0.5);
    vec2 center_px = center * rect_size;
    
    // Base navy with subtle foil pattern
    float foil = foil_pattern(uv * rect_size + tilt * 8.0);
    vec3 col = bg_color.rgb * (0.95 + 0.1 * foil);
    
    // Moon (top-left area)
    vec2 moon_pos = center_px + vec2(-rect_size.x * 0.25, -rect_size.y * 0.25);
    float moon_r = min(rect_size.x, rect_size.y) * 0.18;
    float moon = moon_shape(moon_pos, moon_r);
    col = mix(col, moon_color.rgb, moon * 0.9);
    
    // Moon glow
    float moon_glow = smoothstep(moon_r * 1.5, moon_r, length(moon_pos));
    col += moon_color.rgb * moon_glow * 0.15;
    
    // Neon sign (center-right area)
    vec2 sign_pos = center_px + vec2(rect_size.x * 0.15, rect_size.y * 0.1);
    float sign_w = rect_size.x * 0.35;
    float sign_h = rect_size.y * 0.25;
    float neon = neon_sign(sign_pos, sign_w, sign_h);
    col = mix(col, neon_color.rgb, neon * 0.8);
    
    // Neon glow
    float neon_glow = smoothstep(sign_w * 0.6, sign_w * 0.4, length(sign_pos));
    col += neon_color.rgb * neon_glow * 0.1;
    
    // Subtle specular sweep from tilt
    float sweep = 0.0;
    if (motion > 0.0) {
        vec2 p = center - tilt * 0.3;
        sweep = smoothstep(0.6, 0.0, length(p * vec2(1.0, 0.7)));
        sweep *= 0.05 * motion;
    }
    col += vec3(1.0, 1.0, 1.0) * sweep * mask;
    
    COLOR = vec4(col, mask);
}