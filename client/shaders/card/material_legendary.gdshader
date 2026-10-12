shader_type canvas_item;
render_mode unshaded;
// Legendary: frameless full art with a thin gold-leaf foil edge (crinkled-foil
// normal noise, sharp highlights on tilt), a glass laminate sheen sweeping
// across on tilt, and an embossed emblem stamp in a corner.

uniform vec2 rect_size = vec2(0.0);
uniform float corner_radius : hint_range(0.0, 40.0) = 0.0;
uniform vec4 frame_color : source_color = vec4(0.91, 0.72, 0.29, 1.0); // warm gold
uniform vec4 ink_color : source_color = vec4(0.055, 0.071, 0.145, 1.0); // card_ink
uniform float band_thickness : hint_range(0.0, 20.0) = 3.0; // thin gold edge
uniform float motion = 1.0;
uniform vec2 tilt = vec2(0.0);
uniform float time = 0.0;

// Gold foil crinkle noise - sharp facets that catch light
float foil_crinkle(vec2 p) {
    vec2 n = p * 0.006;
    float v = abs(sin(n.x * 19.0 + n.y * 29.0)) * 0.6;
    v += abs(sin(n.x * 37.0 + n.y * 17.0)) * 0.3;
    v += abs(sin(n.x * 11.0 + n.y * 43.0)) * 0.15;
    // Sharpen the facets
    v = smoothstep(0.3, 0.7, v);
    return v;
}

// Param names must not collide with uniform names - Godot's shader compiler
// rejects that as a redefinition, so the locals get a suffix.
float glass_sheen(vec2 uv, vec2 tilt_dir) {
    vec2 p = uv - vec2(0.5);
    // Sheen follows tilt direction, sweeps diagonally
    float d = p.x * 0.7 + p.y * 0.7 - tilt_dir.x * 0.6 - tilt_dir.y * 0.4;
    // Add slow auto-sweep when not tilting (motion=1)
    d += sin(time * 0.15) * 0.3 * motion;
    return smoothstep(0.35, 0.0, abs(d)) * 0.4;
}

// Embossed emblem stamp - raised gold seal
float emblem_stamp(vec2 uv, vec2 size) {
    // Position: bottom-right corner, inset
    vec2 half = size * 0.5;
    vec2 pos = uv * size - half;
    float inset = 28.0;
    pos.x = half.x - pos.x - inset; // flip to bottom-right
    pos.y = half.y - pos.y - inset;
    
    float r = length(pos);
    float emblem_r = 22.0;
    
    if (r > emblem_r) return 0.0;
    
    // Moon + neon sign line art (simplified procedural)
    float moon = smoothstep(emblem_r * 0.6, emblem_r * 0.55, r);
    // Crescent cut
    float crescent = smoothstep(emblem_r * 0.35, emblem_r * 0.3, length(pos + vec2(emblem_r * 0.25, 0.0)));
    moon *= 1.0 - crescent;
    
    // Neon line (horizontal)
    float line = 1.0 - smoothstep(1.5, 0.5, abs(pos.y));
    line *= smoothstep(emblem_r * 0.7, 0.0, abs(pos.x));
    
    return max(moon, line * 0.6);
}

// Rounded rect mask
float rounded_mask(vec2 uv) {
    if (rect_size.x < 1.0 || corner_radius < 0.5) { return 1.0; }
    vec2 half = rect_size * 0.5;
    vec2 q = abs(uv * rect_size - half) - max(half - vec2(corner_radius), vec2(0.0));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;
    return 1.0 - smoothstep(-1.5, 0.0, d);
}

// Distance to outer edge (for gold foil edge)
float edge_sdf(vec2 uv) {
    vec2 half = rect_size * 0.5;
    vec2 q = abs(uv * rect_size - half);
    return min(half.x - q.x, half.y - q.y);
}

void fragment() {
    vec2 uv = UV;
    float mask = rounded_mask(uv);
    
    // For legendary, the art bleeds to the edge (frameless).
    // This shader only draws the gold foil edge + glass laminate + emblem.
    // The base color is transparent - art shows through.
    vec3 col = vec3(0.0);
    float alpha = 0.0;
    
    // Gold foil edge (very thin)
    float dist = edge_sdf(uv);
    float edge_band = smoothstep(band_thickness, 0.0, dist);
    
    if (edge_band > 0.001) {
        // Crinkled gold foil
        float crinkle = foil_crinkle(uv * rect_size + tilt * 8.0);
        vec3 gold = frame_color.rgb * (0.6 + 0.8 * crinkle);
        
        // Sharp specular highlights on crinkle peaks
        float spec = smoothstep(0.7, 1.0, crinkle) * (0.5 + 0.5 * max(tilt.x, tilt.y) * 0.5 + 0.5);
        gold += vec3(1.0, 0.95, 0.7) * spec * 0.8;
        
        col = gold;
        alpha = edge_band;
    }
    
    // Glass laminate sheen (sweeps across entire card, very subtle)
    float sheen = glass_sheen(uv, tilt) * motion;
    col += vec3(1.0, 1.0, 1.0) * sheen * 0.15 * mask;
    alpha = max(alpha, sheen * 0.15);
    
    // Embossed emblem stamp
    float emblem = emblem_stamp(uv, rect_size);
    if (emblem > 0.0) {
        // Embossed gold: highlight on top-left, shadow on bottom-right
        vec2 half = rect_size * 0.5;
        vec2 pos = uv * rect_size - half;
        float inset = 28.0;
        pos.x = half.x - pos.x - inset;
        pos.y = half.y - pos.y - inset;
        float emboss_angle = atan(pos.y, pos.x);
        float emboss_shade = cos(emboss_angle - 0.785) * 0.3; // 45 deg light
        
        vec3 emblem_gold = frame_color.rgb * (0.8 + 0.4 * emboss_shade);
        emblem_gold += vec3(1.0, 0.95, 0.7) * max(emboss_shade, 0.0) * 0.6;
        
        col = mix(col, emblem_gold, emblem);
        alpha = max(alpha, emblem * 0.9);
    }
    
    COLOR = vec4(col, alpha * mask);
}