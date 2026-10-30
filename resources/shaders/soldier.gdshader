shader_type spatial;
// Soviet soldier (SoldierMesh): colours come from the vertex colours.
// Vertex alpha: 1 = greatcoat (per-soldier tint + cloth grain), 0.5 = other cloth (grain),
// 0 = skin, leather, metal, wood. UV = rest position, so the grain stays on the cloth.

uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable; // snow_mask.png
uniform vec3 coat_tint : source_color = vec3(1.0); // Each soldier gets a slightly different coat.

void fragment() {
	vec3 col = COLOR.rgb;
	float cloth = step(0.25, COLOR.a);
	if (COLOR.a > 0.75) {
		col *= coat_tint;
	}
	float grain = texture(noise_texture, UV * 3.0).b;
	float wear = texture(noise_texture, UV * 0.5 + vec2(0.3, 0.1)).r;
	col *= mix(1.0, (0.85 + 0.3 * grain) * (0.88 + 0.24 * wear), cloth);
	// A little snow clinging to the lower coat and boots.
	float snow = smoothstep(0.55, 0.75, texture(noise_texture, UV * 1.7).r) * (1.0 - smoothstep(0.25, 0.6, UV.y)) * 0.6;
	col = mix(col, vec3(0.88, 0.91, 0.96), snow);
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.92, cloth);
	SPECULAR = mix(0.4, 0.2, cloth);
}
