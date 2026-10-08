shader_type canvas_item;
// The app background: deep navy seen through rain-streaked glass, with the
// blurred glow of a city that is already closed for the night.
//
// STATIC ON PURPOSE. AGENTS.md bans idle motion on menus, and a fullscreen
// procedural pass every frame is the most expensive pixel in the game. The
// colours arrive as uniforms (set from tokens.tres) and AppBackground renders
// this exactly once into a SubViewport, then shows the result as a plain
// TextureRect. Nothing here reads TIME, so one frame is all it takes.

uniform vec3 base_color : source_color = vec3(0.027, 0.039, 0.071);
uniform vec3 haze_color : source_color = vec3(0.055, 0.078, 0.141);
uniform vec3 neon_a : source_color = vec3(1.0, 0.239, 0.545);
uniform vec3 neon_b : source_color = vec3(0.216, 0.902, 1.0);
uniform vec3 warm_color : source_color = vec3(1.0, 0.761, 0.294);
// Canvas width / height. Everything circular is corrected for it, or the beads
// come out as tall ellipses on a phone.
uniform float width_over_height = 0.5625;

uniform float bokeh_amount : hint_range(0.0, 1.0) = 0.6;
uniform float droplet_amount : hint_range(0.0, 1.0) = 0.9;
uniform float grain_amount : hint_range(0.0, 0.1) = 0.022;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	return vec2(hash21(p), hash21(p + 19.19));
}

vec2 square_uv(vec2 uv) {
	return vec2(uv.x * width_over_height, uv.y);
}

// Soft-edged disc: a defocused sign across the street.
float bokeh(vec2 p, vec2 centre, float radius, float squash) {
	return smoothstep(1.0, 0.0, length((p - centre) / vec2(radius, radius * squash)));
}

// One bead per sparse cell, plus the faint tail it leaves running down.
float droplets(vec2 uv) {
	vec2 grid = square_uv(uv) * 15.0;
	vec2 cell = floor(grid);
	float result = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 id = cell + vec2(float(x), float(y));
			vec2 jitter = hash22(id);
			// Rain is sparse: most cells stay empty or it reads as a screen door.
			if (jitter.x > 0.34) {
				continue;
			}
			vec2 centre = id + 0.5 + (jitter - 0.5) * 0.8;
			float size = 0.07 + pow(hash21(id + 7.3), 3.0) * 0.22;
			vec2 d = (grid - centre) / vec2(size, size * 0.86);
			float bead = smoothstep(1.05, 0.45, length(d));
			vec2 tail = (grid - vec2(centre.x, centre.y + 0.7)) / vec2(size * 0.26, size * 2.2);
			float streak = smoothstep(1.0, 0.0, length(tail)) * 0.16;
			// Light catches the top-left of every bead, as it does on a window.
			float lit = clamp(0.55 - 0.7 * (d.x + d.y), 0.0, 1.0);
			result += bead * mix(0.35, 1.0, lit) + streak;
		}
	}
	return result * droplet_amount * 0.42;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = square_uv(uv);

	// Deep navy, a touch lighter towards the middle of the window.
	vec3 col = mix(base_color, haze_color, smoothstep(0.0, 1.0, uv.y * 0.8 + 0.15) * 0.5);

	// Street level: a soft band of light below the rail, which is what makes the
	// glass read as a window instead of a wall.
	float street = exp(-abs(uv.y - 0.70) * 9.0);
	col += mix(neon_b, warm_color, 0.35) * street * 0.035;

	// Distant signage, scattered by hash so the city never repeats. Magenta and
	// cyan only, plus a few warm windows; heavy blur, so it stays behind the UI.
	vec3 tint = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float fi = float(i);
		vec2 seed = vec2(fi * 3.17, fi * 7.31);
		vec2 centre = vec2(0.06 + hash21(seed + 3.0) * 0.52, -0.05 + hash21(seed) * 0.62);
		float radius = 0.10 + hash21(seed + 11.0) * 0.22;
		float disc = bokeh(p, centre, radius, 0.55 + hash21(seed + 5.0) * 0.6);
		float pick = hash21(seed + 17.0);
		vec3 light = neon_a;
		if (pick > 0.60) {
			light = neon_b;
		} else if (pick > 0.42) {
			light = warm_color;
		}
		tint += disc * light * (0.5 + hash21(seed + 23.0) * 0.7);
	}
	col += tint * 0.16 * bokeh_amount;

	// The window itself: two verticals, one rail, all in the far dark.
	float rail = smoothstep(0.004, 0.0, abs(uv.y - 0.66));
	float mullion = smoothstep(0.0035, 0.0, abs(uv.x - 0.5) - 0.28);
	float frame = clamp(rail + mullion, 0.0, 1.0);
	col = mix(col, base_color * 0.55, frame * 0.65);
	col += neon_b * rail * 0.02;

	col += droplets(uv) * vec3(0.66, 0.78, 1.0);

	// Vignette: the light comes from the cards, so the edges fall away.
	col *= 1.0 - smoothstep(0.22, 0.62, length(p - vec2(width_over_height * 0.5, 0.5))) * 0.5;

	// Grain, so a flat fill never reads as plastic.
	col += (hash21(floor(uv * 2048.0)) - 0.5) * grain_amount;

	COLOR = vec4(col, 1.0);
}