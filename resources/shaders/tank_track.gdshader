shader_type spatial;
render_mode cull_disabled; // (the model's track material is double-sided)
// T6: a tank track that runs. Used for the T-26's two track belts; the TrackAnimator
// (scripts/enemies/track_animator.gd) gives each belt its own copy of this material.
//
// The belt is ONE fixed mesh. Its link picture repeats `belt_repeats` times around the belt
// (UV.y counts the repeats). To make the track run, the picture is simply slid along the belt:
// `scroll` is how many repeats it has moved. No link is a mesh, nothing is rebuilt.
//
// On top of the links comes a little packed snow and frozen dirt (`grime_tex`, made in code by
// TrackAnimator.grime_texture()). That picture goes ONCE around the whole belt, so the twelve
// repeats no longer look the same, and it travels with the links. The snow is lit like any
// snow – it is what shows the track moving at dusk, when the bare steel is almost black.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable; // the model's own track picture
uniform sampler2D grime_tex : filter_linear_mipmap, repeat_enable; // R = snow patches, G = dirt, B = snow incl. the gaps between links
uniform float scroll = 0.0; // repeats the belt has run (TrackAnimator, every physics step it moves)
uniform float belt_repeats = 12.0; // link-picture repeats around the whole belt
uniform float grime_shift = 0.0; // 0..1: where on the belt the snow pattern starts (differs per tank and side)
uniform float snow_amount : hint_range(0.0, 1.0) = 0.6; // 0 = bare steel
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.45;
uniform vec3 snow_color : source_color = vec3(0.84, 0.87, 0.92);
uniform vec3 dirt_color : source_color = vec3(0.33, 0.27, 0.21);
uniform float steel_brightness = 1.5; // the model's steel is very dark; a little lift
uniform float roughness = 0.8;

void vertex() {
	UV.y += scroll; // the whole picture slides along the belt
}

void fragment() {
	vec3 steel = texture(albedo_tex, UV).rgb;
	// The darkest lines of the picture are the gaps between the links: snow packs in there first.
	float gap = 1.0 - smoothstep(0.004, 0.02, (steel.r + steel.g + steel.b) / 3.0);
	vec3 grime = texture(grime_tex, vec2(UV.x, UV.y / belt_repeats + grime_shift)).rgb;
	float snow = mix(grime.r, grime.b, gap) * snow_amount;
	float dirt = grime.g * dirt_amount;
	vec3 colour = mix(steel * steel_brightness, dirt_color, dirt);
	ALBEDO = mix(colour, snow_color, snow);
	ROUGHNESS = mix(roughness, 0.95, snow);
	METALLIC = 0.0;
}
