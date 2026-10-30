shader_type spatial;
// Snow-laden spruce (branches, or the trunk when `trunk` is on). Used by the forest's MultiMesh trees.
// Vertex colour: R = how much this part can hold snow (tops of the branch tiers),
//                G = ambient occlusion (darker deep inside / under the tiers),
//                B, A = 1 (the MultiMesh instance colour puts per-tree values there:
//                B = how snowy this tree is, A = colour variation).
// UV.x: 0 next to the trunk, 1 at the branch tips (snow collects more inside).
//
// Level of detail, decided for EACH TREE (not for a whole forest chunk), so trees switch
// one by one and softly: in the fade zone a tree "dissolves" pixel by pixel (dithering)
// while its other version appears in exactly the remaining pixels.
// The forest script sets `lod_camera` (the player's camera position) every frame.

uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable; // snow_mask.png
uniform vec3 needle_color : source_color = vec3(0.08, 0.14, 0.09);
uniform vec3 needle_color_2 : source_color = vec3(0.12, 0.17, 0.09);
uniform vec3 snow_color : source_color = vec3(0.92, 0.95, 1.0);
uniform float snow_amount = 0.0; // Raise for heavier snow on all trees.
uniform bool trunk = false; // true = this material is for the trunk (bark, no snow).
uniform sampler2D bark_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 bark_tint : source_color = vec3(0.85, 0.8, 0.78);

uniform int lod_mode = 0; // 0 = detailed tree (shown up close), 1 = simple tree (shown far away)
uniform vec3 lod_camera = vec3(0.0); // set by forest_scatter.gd
uniform float lod_distance = 70.0; // where the detailed tree changes into the simple one
uniform float view_distance = 220.0; // simple trees fade out here
uniform float fade_band = 10.0; // metres over which a tree dissolves

varying vec3 local_pos;
varying vec3 world_normal;
varying float tree_distance;

void vertex() {
	local_pos = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tree_distance = distance(MODEL_MATRIX[3].xyz, lod_camera); // tree's base, same for the whole tree
}

void fragment() {
	// Dithered level-of-detail fade (see the top of this file).
	float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float to_simple = smoothstep(lod_distance - fade_band, lod_distance, tree_distance);
	if (lod_mode == 0) {
		if (dither < to_simple) {
			discard;
		}
	} else {
		float gone = smoothstep(view_distance - fade_band * 2.0, view_distance, tree_distance);
		if (dither >= to_simple || dither < gone) {
			discard;
		}
	}

	if (trunk) {
		ALBEDO = texture(bark_texture, UV).rgb * bark_tint;
		ROUGHNESS = 0.95;
	} else {
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
}
