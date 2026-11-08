shader_type sky;
// Clear, freezing winter day: deep blue overhead, pale haze at the horizon,
// a low sun with a warm glow around it and a few thin high clouds.
// The sun's position comes from the Sun (DirectionalLight3D) in the level.

uniform vec3 zenith_color : source_color = vec3(0.24, 0.42, 0.70);
uniform vec3 horizon_color : source_color = vec3(0.78, 0.85, 0.92);
uniform vec3 ground_color : source_color = vec3(0.82, 0.86, 0.92);
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.80, 0.58);
uniform float horizon_softness = 0.4; // Bigger = the pale horizon reaches higher up.
uniform float glow_strength = 0.75;
uniform float sun_size_deg = 0.8;
uniform float sun_brightness = 12.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.35;
uniform vec3 cloud_color : source_color = vec3(1.0, 0.98, 0.96);
uniform float star_strength : hint_range(0.0, 1.0) = 0.0; // B3: a few stars on the night battles.

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += value_noise(p) * amp;
		p = p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sun_cos = dot(dir, sun_dir);
	float toward_sun = max(sun_cos, 0.0);

	// Blue gradient from the hazy horizon up to the deep blue zenith.
	float t = pow(clamp(h, 0.0, 1.0), horizon_softness);
	vec3 col = mix(horizon_color, zenith_color, t);

	// Warm glow around the low sun, strongest near the horizon.
	float near_horizon = 1.0 - clamp(h * 2.5, 0.0, 1.0);
	float glow = pow(toward_sun, 6.0) * 0.35 + pow(toward_sun, 48.0) * 0.6;
	col = mix(col, sun_glow_color, clamp(glow * glow_strength * (0.45 + 0.55 * near_horizon), 0.0, 1.0));

	// Thin high clouds (projected onto a flat "ceiling" far above).
	if (h > 0.0) {
		vec2 uv = dir.xz / (h + 0.12);
		float c = fbm(uv * vec2(0.9, 2.6) + vec2(13.0, 4.0));
		c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.3, c);
		c *= smoothstep(0.02, 0.25, h); // fade out towards the horizon haze
		vec3 lit = mix(cloud_color, sun_glow_color * 1.2, pow(toward_sun, 4.0) * 0.6);
		col = mix(col, lit, c * 0.75);
	} else {
		// Below the horizon (hidden by the ground and the fog, but never black).
		col = mix(horizon_color, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	}

	// Stars: tiny bright dots in the upper sky, hidden by clouds.
	if (star_strength > 0.0 && h > 0.05 && !AT_CUBEMAP_PASS) {
		vec2 sp = dir.xz / (h + 0.4) * 60.0;
		vec2 cell = floor(sp);
		float rnd = hash(cell + 7.0);
		vec2 off = vec2(hash(cell + 1.3), hash(cell + 5.1)) * 0.6 + 0.2;
		float d = length(fract(sp) - off);
		float star = step(0.93, rnd) * (1.0 - smoothstep(0.03, 0.09, d));
		col += vec3(0.85, 0.9, 1.0) * star * star_strength * smoothstep(0.05, 0.3, h) * (1.0 - clamp(cloud_cover, 0.0, 1.0) * 0.8);
	}

	// The sun disk itself (not in the reflection/ambient pass: it would make shiny spots).
	if (!AT_CUBEMAP_PASS && LIGHT0_ENABLED) {
		float angle = degrees(acos(clamp(sun_cos, -1.0, 1.0)));
		float disk = 1.0 - smoothstep(sun_size_deg * 0.7, sun_size_deg, angle);
		col += LIGHT0_COLOR * disk * sun_brightness;
	}
	COLOR = col;
}
