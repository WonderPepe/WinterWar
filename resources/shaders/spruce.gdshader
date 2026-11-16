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
// The detailed tree, the simple tree and the shadow tree all lean the same way in the wind
// (it only depends on the tree's place and the height on the tree), so they never come apart.

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

// V10a: wind. The whole tree leans with the gusts (the top most, the foot not at all) and the
// branch tips bob up and down. Gusts travel through the forest in the wind's direction, and
// every tree has its own rhythm. The forest script sets the two wind values from the battle's
// weather (WeatherData.wind). Done here in the vertex function = on the graphics card, for free.
uniform float wind_strength = 0.3; // 0 = still, 1 = a strong wind, 2 = a storm
uniform vec2 wind_direction = vec2(0.894, 0.447); // where the wind blows TO (world x, z), length 1
uniform float sway_top_m = 0.11; // how far the top of a tree leans at strength 1 (metres, tree scale 1)
uniform float sway_tip_m = 0.035; // how far a branch tip bobs at strength 1
uniform float sway_height = 7.0; // height of a tree before scaling

varying vec3 local_pos;
varying vec3 world_normal;
varying float tree_distance;

void vertex() {
	local_pos = VERTEX; // (before the wind moves it: the snow pattern stays on the branches)
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 tree_base = MODEL_MATRIX[3].xyz;
	tree_distance = distance(tree_base, lod_camera); // tree's base, same for the whole tree
	if (wind_strength > 0.0) {
		float along = dot(tree_base.xz, wind_direction); // metres downwind
		float own = fract(sin(dot(tree_base.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2832; // this tree's own rhythm
		// A slow gust wave rolling downwind + the tree's own quicker swing + a very slow swell.
		float gust = 0.55 * sin(TIME * 0.9 - along * 0.07 + own * 0.3) + 0.3 * sin(TIME * 2.1 + own)
				+ 0.35 * sin(TIME * 0.31 - along * 0.02);
		float up = clamp(local_pos.y / sway_height, 0.0, 1.2);
		float lean = wind_strength * sway_top_m * up * up * (0.5 + gust); // 0.5 = it leans with the wind on average
		// The wind's direction in the tree's own space (every tree is turned and scaled).
		vec3 wind_local = normalize((vec4(wind_direction.x, 0.0, wind_direction.y, 0.0) * MODEL_MATRIX).xyz);
		VERTEX += wind_local * lean;
		if (!trunk) {
			// Branch tips (UV.x = 1) bob; only on trees near the camera (far away nobody sees it).
			float near = 1.0 - smoothstep(lod_distance * 0.6, lod_distance - fade_band, tree_distance);
			VERTEX.y += wind_strength * sway_tip_m * UV.x * UV.x * near * sin(TIME * 1.7 + own + local_pos.y * 1.9 + along * 0.1);
		}
	}
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
