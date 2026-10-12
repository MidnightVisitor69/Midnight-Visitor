shader_type canvas_item;
render_mode unshaded;
// Epic: brushed metal. Anisotropic brushed streaks on the frame, a fine engraved
// line pattern (procedural guilloche), a specular highlight that slides along
// the frame with tilt.

uniform vec2 rect_size = vec2(0.0);
uniform float corner_radius : hint_range(0.0, 40.0) = 0.0;
uniform vec4 frame_color : source_color = vec4(0.65, 0.55, 0.98, 1.0); // violet enamel
uniform vec4 ink_color : source_color = vec4(0.055, 0.071, 0.145, 1.0); // card_ink
uniform float band_thickness : hint_range(0.0, 20.0) = 8.0;
uniform float motion = 1.0;
uniform vec2 tilt = vec2(0.0);

// Brushed metal: anisotropic streaks along the frame perimeter
float brushed(vec2 p, float dir) {
    // Rotate coordinate system to brush direction
    float c = cos(dir);
    float s = sin(dir);
    vec2 rot = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
    // Fine parallel lines
    float lines = sin(rot.y * 120.0) * 0.5;
    lines += sin(rot.y * 240.0 + 1.57) * 0.25;
    lines += sin(rot.y * 480.0) * 0.12;
    return fract(lines * 43758.5453);
}

// Guilloche pattern: engraved fine lines, rosette-like
float guilloche(vec2 p, float r) {
    float a = atan(p.y, p.x);
    float d = length(p);
    // Concentric waves modulated by angle
    float waves = sin(d * 80.0 + a * 12.0) * 0.5;
    waves += sin(d * 160.0 - a * 8.0 + 2.0) * 0.25;
    waves += sin(a * 24.0) * 0.15 * (1.0 - smoothstep(0.0, r, d));
    return fract(waves * 43758.5453);
}

// Rounded rect mask
float rounded_mask(vec2 uv) {
    if (rect_size.x < 1.0 || corner_radius < 0.5) { return 1.0; }
    vec2 half = rect_size * 0.5;
    vec2 q = abs(uv * rect_size - half) - max(half - vec2(corner_radius), vec2(0.0));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;
    return 1.0 - smoothstep(-1.5, 0.0, d);
}

// Distance to frame edge, signed (negative inside band)
float frame_sdf(vec2 uv) {
    vec2 half = rect_size * 0.5;
    vec2 q = abs(uv * rect_size - half);
    return min(half.x - q.x, half.y - q.y) - band_thickness;
}

void fragment() {
    vec2 uv = UV;
    float mask = rounded_mask(uv);
    
    // Base card stock
    vec3 col = ink_color.rgb;
    
    // Frame band SDF
    float sdf = frame_sdf(uv);
    float band = smoothstep(0.0, -2.0, sdf); // 1 inside band, 0 outside
    
    if (band > 0.001) {
        // Position along frame perimeter for brushing direction
        vec2 half = rect_size * 0.5;
        vec2 q = abs(uv * rect_size - half);
        vec2 corner = vec2(corner_radius);
        
        // Determine which edge we're on and brush direction
        float dir = 0.0;
        float edge_blend = 0.0;
        if (q.x > half.x - corner.x && q.y > half.y - corner.y) {
            // Corner: radial brush
            vec2 c = sign(uv * rect_size - half) * (half - corner);
            vec2 to_center = (uv * rect_size - c);
            dir = atan(to_center.y, to_center.x) + 1.5708;
        } else if (q.x > q.y) {
            // Left/right edges: vertical brush
            dir = 1.5708;
        } else {
            // Top/bottom edges: horizontal brush
            dir = 0.0;
        }
        
        // Brushed metal streaks
        vec2 local = (uv * rect_size) * 0.02;
        float brush = brushed(local, dir);
        vec3 metal_base = frame_color.rgb * (0.7 + 0.3 * brush);
        
        // Guilloche engraving (subtle, only on band)
        float guil = guilloche(uv * rect_size - half, band_thickness * 0.5);
        metal_base *= 0.95 + 0.1 * guil;
        
        // Specular highlight that slides with tilt
        float spec = 0.0;
        if (band > 0.1) {
            // Project tilt onto frame tangent
            float tilt_along = tilt.x * sin(dir) - tilt.y * cos(dir);
            float highlight_pos = 0.5 + tilt_along * 0.8;
            float dist_to_highlight = abs((sdf / band_thickness) - highlight_pos);
            spec = smoothstep(0.15, 0.0, dist_to_highlight) * 0.6;
        }
        
        col = mix(col, metal_base + vec3(1.0) * spec, band);
    }
    
    // Inner hairline (etched line)
    float hairline = smoothstep(band_thickness * 1.1, band_thickness * 1.0, -sdf);
    col += vec3(1.0, 0.95, 1.0) * hairline * 0.1 * mask;
    
    // Second etched line for epic
    float hairline2 = smoothstep(band_thickness * 1.5, band_thickness * 1.4, -sdf);
    col += vec3(0.9, 0.8, 1.0) * hairline2 * 0.06 * mask;
    
    COLOR = vec4(col, mask);
}