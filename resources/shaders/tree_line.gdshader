shader_type spatial;
// The far-away forest on the horizon: a ring of tree silhouettes (one picture, one draw call).
// Unshaded, because at that distance you only see a flat dark outline softened by the haze.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D silhouette : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float brightness = 1.6;

void fragment() {
	vec4 c = texture(silhouette, UV);
	ALBEDO = c.rgb * tint * brightness;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
