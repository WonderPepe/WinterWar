shader_type spatial;
// Horizontal log walls (trench revetment, bunker) with snow on top surfaces.
// The texture is placed by world position along each wall, so it never stretches,
// whatever size the (CSG) wall pieces are. Upward-facing faces get snow; optionally
// a band of snow along a height (the lip at the top of the trench walls).

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable; // snow_mask.png
uniform vec2 tile_size_m = vec2(2.0, 1.0); // Wall size covered by one copy of the texture.
uniform vec3 tint : source_color = vec3(1.0);
uniform float normal_strength = 0.8;
uniform vec3 snow_color : source_color = vec3(0.93, 0.95, 1.0);
uniform bool snow_band = true; // Snow along `snow_line_y` (ground level).
uniform float snow_line_y = 0.0;
uniform float snow_band_width = 0.14;
uniform float top_snow = 1.0; // 1 = upward-facing faces are covered in snow.
uniform float log_top_snow = 0.55; // Snow resting on the upper side of each log.

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float up = smoothstep(0.55, 0.85, n.y);
	// Direction along the wall (horizontal, perpendicular to the normal).
	vec2 along = n.xz;
	along = length(along) > 0.001 ? normalize(vec2(-along.y, along.x)) : vec2(1.0, 0.0);
	vec2 uv_wall = vec2(dot(world_pos.xz, along), -world_pos.y) / tile_size_m;
	vec2 uv_top = world_pos.xz / tile_size_m;
	bool flat_face = abs(n.y) > 0.7; // floors, ceilings and tops use a flat (top-down) mapping
	vec2 uv = flat_face ? uv_top : uv_wall;

	vec3 col = texture(albedo_texture, uv).rgb * tint;
	vec2 nt = (texture(normal_texture, uv).xy * 2.0 - 1.0) * normal_strength;
	vec3 tangent = vec3(along.x, 0.0, along.y);
	vec3 wn = flat_face ? n : normalize(n + tangent * nt.x + vec3(0.0, 1.0, 0.0) * nt.y);

	// Snow: on top surfaces and (optionally) a ragged band at ground level.
	float noise = texture(noise_texture, (world_pos.xz + world_pos.y) * 2.5).r * 0.8 + texture(noise_texture, world_pos.xz * 0.3 + world_pos.y * 0.2).b * 0.2;
	float snow = up * top_snow;
	if (snow_band) {
		float d = abs(world_pos.y - snow_line_y) + (noise - 0.5) * 0.12;
		snow = max(snow, 1.0 - smoothstep(snow_band_width - 0.015, snow_band_width + 0.015, d));
	}
	// Snow sits on the upper side of each log too (where the normal map points up).
	snow = max(snow, smoothstep(0.35, 0.6, nt.y / max(normal_strength, 0.001) + noise * 0.3 - 0.15) * log_top_snow);
	snow = clamp(snow, 0.0, 1.0);
	col = mix(col, snow_color * (0.95 + 0.05 * noise), snow);
	wn = normalize(mix(wn, n, snow * 0.7));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.8, snow);
}
