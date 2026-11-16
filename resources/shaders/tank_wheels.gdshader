shader_type spatial;
render_mode cull_disabled; // (the model's material is double-sided)
// T6: the T-26's running gear with wheels that turn. Used for the two "chassis" meshes; the
// TrackAnimator (scripts/enemies/track_animator.gd) gives each side its own copy.
//
// All the wheels of one side are welded into ONE mesh with the bogies and springs. So each
// vertex of a wheel carries its axle in the mesh's second UV channel (written once into the
// model by tools/import_weapons.py, `bake_t26_wheels`):
//     UV2.x = the axle's place along the tank (metres; mesh space: +y = towards the nose)
//     UV2.y = the axle's height (metres) + 2 × the wheel's kind
//             (1 = drive sprocket / idler, 2 = road wheel, 3 = return roller)
//     UV2 = (0, 0): not a wheel – it never moves.
// Here, on the graphics card, every wheel vertex is turned around its own axle. That costs no
// extra draw calls: the whole side is still drawn in one go.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable; // the model's own picture
// How far each kind of wheel has turned (radians, forwards = +): x = sprocket / idler,
// y = road wheels, z = return rollers. Small wheels turn faster for the same track speed.
uniform vec3 wheel_angles = vec3(0.0);
uniform float roughness = 0.8;

void vertex() {
	float kind = floor(UV2.y * 0.5 + 0.001);
	if (kind > 0.5) {
		vec2 axle = vec2(UV2.x, UV2.y - kind * 2.0);
		float angle = kind < 1.5 ? wheel_angles.x : (kind < 2.5 ? wheel_angles.y : wheel_angles.z);
		float s = sin(angle);
		float c = cos(angle);
		// Seen from the side (y = towards the nose, z = up): rolling forwards, the top of a
		// wheel moves towards the nose.
		vec2 p = VERTEX.yz - axle;
		VERTEX.yz = axle + vec2(p.x * c + p.y * s, p.y * c - p.x * s);
		vec2 n = NORMAL.yz;
		NORMAL.yz = vec2(n.x * c + n.y * s, n.y * c - n.x * s);
	}
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
