shader_type spatial;
// Both sides are drawn: where a sleeve or mitten cuff is open you see its (shaded) inside, not
// a paper-thin edge. Cheap – the arms are a small mesh.
render_mode cull_disabled;
// First-person arms (FirstPersonArms, AR1): matte cloth from the vertex colours.
// Vertex alpha tells which cloth it is: 0.5 = cotton snow smock, 0.65 = grey wool tunic,
// 0.8 = knitted wool mitten. Dirt, wear and snow are already painted into the colours
// (FirstPersonArms._bake_wear). UV = rest position, so the grain stays on the cloth.

uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable; // snow_mask.png (r: blotches, b: grain)

void fragment() {
	vec3 col = COLOR.rgb;
	float wool = smoothstep(0.58, 0.72, COLOR.a); // tunic and mitten
	float knit = smoothstep(0.72, 0.86, COLOR.a); // mitten only
	// Smock: fine, low-contrast cotton grain. Wool: coarser and stronger, two sizes mixed.
	float fine = texture(noise_texture, UV * vec2(5.0, 6.0)).b;
	float coarse = texture(noise_texture, UV * vec2(9.0, 11.0) + vec2(0.37, 0.11)).b
			* 0.6 + texture(noise_texture, UV * 3.0 + vec2(0.71, 0.29)).b * 0.4;
	float grain = mix(fine, coarse, wool);
	float contrast = mix(0.14, 0.32, knit);
	col *= 1.0 - contrast * 0.5 + contrast * grain;
	// Broad, soft variation: the cloth is never one flat colour.
	float broad = texture(noise_texture, UV * 0.7 + vec2(0.3, 0.1)).r;
	col *= 0.92 + 0.14 * broad;
	if (!FRONT_FACING) {
		col *= 0.45; // the inside of the cloth is in shadow
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.97, wool); // never glossy
	SPECULAR = mix(0.2, 0.1, wool);
}
