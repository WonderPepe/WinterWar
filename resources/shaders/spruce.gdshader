shader_type spatial;
// Snow-laden spruce branches. Used by the forest's MultiMesh trees.
// Vertex colour: R = how much this part can hold snow (tops of the branch tiers),
//                G = ambient occlusion (darker deep inside / under the tiers).
// UV.x: 0 next to the trunk, 1 at the branch tips (snow collects more inside).
//                B, A = 1 (the MultiMesh instance colour puts per-tree values there:
//                B = how snowy this tree is, A = colour variation).

uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable; // snow_mask.png
uniform vec3 needle_color : source_color = vec3(0.08, 0.14, 0.09);
uniform vec3 needle_color_2 : source_color = vec3(0.12, 0.17, 0.09);
uniform vec3 snow_color : source_color = vec3(0.92, 0.95, 1.0);
uniform float snow_amount = 0.0; // Raise for heavier snow on all trees.

varying vec3 local_pos;
varying vec3 world_normal;

void vertex() {
	local_pos = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float clumps = (texture(noise_texture, local_pos.xz * 2.0).r + texture(noise_texture, vec2(local_pos.x + local_pos.z, local_pos.y) * 1.7).r) * 0.5;
	float n1 = texture(noise_texture, local_pos.xz * 0.9 + local_pos.y * 0.37).b;
	float n2 = texture(noise_texture, local_pos.xy * 0.23 + vec2(0.4, 0.1)).r;
	float facing_up = world_normal.y;
	float snow_level = facing_up * 0.7 + (clumps - 0.5) * 1.6 + (n1 - 0.5) * 0.15 + (COLOR.b - 0.4) * 0.3 + (0.75 - UV.x) * 0.6 + snow_amount;
	float snow = COLOR.r * smoothstep(0.44, 0.54, snow_level);
	vec3 needles = mix(needle_color, needle_color_2, clamp(n2 * 1.4 - 0.2 + COLOR.a * 0.6 - 0.3, 0.0, 1.0));
	needles *= 0.75 + 0.5 * n1;
	float ao = COLOR.g;
	ALBEDO = mix(needles, snow_color, snow) * mix(0.55, 1.0, ao);
	ROUGHNESS = mix(0.95, 0.85, snow);
	SPECULAR = mix(0.2, 0.4, snow);
}
