shader_type spatial;
// Soviet soldier (SoldierMesh): colours come from the vertex colours.
// Vertex alpha: 1 = greatcoat (per-soldier tint + cloth grain), 0.5 = other cloth (grain),
// 0 = skin, leather, metal, wood. UV = rest position, so the grain stays on the cloth.
// SV1: alpha 0.15 = the face – its UV is the front of the face, and the face texture
// (eyes, brows, mouth) is painted over the skin colour by the texture's own alpha.

uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable; // snow_mask.png
uniform sampler2D face_texture : source_color, filter_linear_mipmap, repeat_disable, hint_default_transparent; // soldier_face.png
uniform vec3 coat_tint : source_color = vec3(1.0); // Each soldier gets a slightly different coat.
// V10b: snow lying on a body left on the field over the night (0 = none, 1 = nearly covered).
// It settles on the parts that face up, in patches.
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;
// V10c: bodies baked together into one shape (BodyKeeper batch): each body's snow is in UV2.x,
// and the coat tint is already in the vertex colours.
uniform bool baked_snow = false;

void fragment() {
	vec3 col = COLOR.rgb;
	float cloth = step(0.25, COLOR.a);
	float face = step(0.1, COLOR.a) * (1.0 - cloth);
	if (face > 0.5) {
		vec4 paint = texture(face_texture, UV);
		col = mix(col, paint.rgb, paint.a);
	}
	if (COLOR.a > 0.75) {
		col *= coat_tint;
	}
	float grain = texture(noise_texture, UV * 3.0).b;
	float wear = texture(noise_texture, UV * 0.5 + vec2(0.3, 0.1)).r;
	col *= mix(1.0, (0.85 + 0.3 * grain) * (0.88 + 0.24 * wear), cloth);
	// A little snow clinging to the lower coat and boots.
	float snow = smoothstep(0.55, 0.75, texture(noise_texture, UV * 1.7).r) * (1.0 - smoothstep(0.25, 0.6, UV.y)) * 0.6 * (1.0 - face);
	col = mix(col, vec3(0.88, 0.91, 0.96), snow);
	float lying = 0.0;
	float cover = baked_snow ? UV2.x : snow_cover;
	if (cover > 0.0) {
		float facing_up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
		float patches = texture(noise_texture, UV * 2.3 + vec2(0.17, 0.61)).r;
		float level = facing_up * 0.6 + patches * 0.55 + cover * 0.9;
		lying = smoothstep(0.95, 1.15, level);
		col = mix(col, vec3(0.9, 0.93, 0.98), lying);
	}
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.55, 0.92, cloth), 0.9, lying);
	SPECULAR = mix(mix(0.4, 0.2, cloth), 0.35, lying);
}
