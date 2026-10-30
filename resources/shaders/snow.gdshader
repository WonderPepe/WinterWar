shader_type spatial;
// Snow for the ground, the trench parapet, drifts and the bunker roof.
// - Textures are placed by world position, so they line up across separate meshes.
// - Wind ripples (normal map) at two sizes, big soft brightness patches, glittering sparkles.
// - Terrain vertex colour: red < 1 = ice on the bog, green < 1 = trampled/dirty snow.
// - Custom light(): a little "wrap" lighting because snow scatters light inside itself.

uniform sampler2D snow_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_mask : filter_linear_mipmap, repeat_enable; // R big patches, G sparkles, B grain
uniform vec3 snow_color : source_color = vec3(0.9, 0.93, 0.97);
uniform vec3 snow_shade_color : source_color = vec3(0.8, 0.85, 0.93); // Colour of the darker snow patches.
uniform vec3 ice_color : source_color = vec3(0.60, 0.70, 0.80);
uniform vec3 dirt_color : source_color = vec3(0.5, 0.43, 0.36);
uniform float ripple_scale = 0.3; // How often the ripple texture repeats per metre.
uniform float patch_scale = 0.015;
uniform float normal_strength = 0.6;
uniform float wrap = 0.3; // 0 = normal lighting, higher = softer light/shadow edge.
uniform float sparkle_strength = 40.0;
uniform float sparkle_distance = 25.0; // Sparkles fade out by this distance (metres).
uniform float detail_distance = 90.0; // Ripples fade out by this distance.

varying vec3 world_pos;
varying vec3 world_normal;
varying float v_sparkle;
varying float v_ice;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 unpack_normal(vec4 t) {
	return t.xy * 2.0 - 1.0;
}

void fragment() {
	float dist = length(VERTEX);
	float detail = 1.0 - smoothstep(detail_distance * 0.4, detail_distance, dist);
	float ice = clamp(1.0 - COLOR.r, 0.0, 1.0);
	float dirt = clamp(1.0 - COLOR.g, 0.0, 1.0);
	vec2 uv = world_pos.xz * ripple_scale;

	// Ripples: two sizes, the second rotated, so the repetition is hard to see.
	vec2 n1 = unpack_normal(texture(snow_normal, uv));
	vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.37 + vec2(0.31, 0.77);
	vec2 n2 = unpack_normal(texture(snow_normal, uv2));
	vec2 bump = (n1 * 0.6 + n2) * normal_strength * detail * (1.0 - ice * 0.85);
	vec3 wn = normalize(world_normal + vec3(bump.x, 0.0, -bump.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// Colour: big soft patches, a fine grain, ice and trampled snow.
	vec4 big = texture(snow_mask, world_pos.xz * patch_scale);
	vec4 near = texture(snow_mask, uv);
	vec3 col = mix(snow_shade_color, snow_color, smoothstep(0.25, 0.75, big.r));
	col *= 0.97 + 0.06 * near.b;
	col = mix(col, ice_color * (0.9 + 0.2 * big.r), ice);
	col = mix(col, dirt_color * (0.8 + 0.4 * near.b), dirt);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.3, ice);
	SPECULAR = 0.3;

	// Sparkles: two dot patterns, one shifted by the camera position. They only line
	// up in a few places, and those places change as you move - the snow glitters.
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float s1 = texture(snow_mask, uv * 2.0).g;
	float s2 = texture(snow_mask, uv * 2.0 + cam.xz * 0.013 + cam.y * 0.021).g;
	float near_fade = 1.0 - smoothstep(sparkle_distance * 0.3, sparkle_distance, dist);
	v_sparkle = s1 * s2 * sparkle_strength * near_fade * (1.0 - dirt) * (1.0 - ice * 0.5);
	v_ice = ice;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diffuse = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += diffuse * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float shine = pow(ndh, mix(12.0, 120.0, v_ice)) * mix(0.04, 0.5, v_ice);
	float lit_side = step(0.0, ndl);
	SPECULAR_LIGHT += (shine + v_sparkle) * lit_side * ATTENUATION * LIGHT_COLOR / PI;
}
