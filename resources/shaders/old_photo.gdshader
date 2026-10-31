// An old archive photograph on screen (day screen between waves): warm paper-grey tone,
// moving film grain, darker corners and a faint flicker of the brightness.
shader_type canvas_item;

uniform float grain : hint_range(0.0, 0.4) = 0.08;
uniform float vignette : hint_range(0.0, 1.0) = 0.5;
uniform float flicker : hint_range(0.0, 0.2) = 0.03;
uniform vec3 tone = vec3(1.0, 0.95, 0.85);
uniform float contrast = 1.08;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	g = (g - 0.5) * contrast + 0.5;
	float frame = floor(TIME * 18.0); // the grain changes 18 times a second, like film
	g += (hash(floor(UV * vec2(640.0, 450.0)) + frame * 1.37) - 0.5) * grain;
	g *= 1.0 + flicker * (hash(vec2(frame, 3.1)) - 0.5);
	vec2 d = (UV - 0.5) * vec2(1.0, 1.15);
	g *= 1.0 - vignette * smoothstep(0.3, 0.8, length(d));
	COLOR = vec4(clamp(g, 0.0, 1.0) * tone, COLOR.a);
}
