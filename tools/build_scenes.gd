extends SceneTree
## Helper (not part of the game): builds the .tscn scene files and material
## resources so they are written in Godot's own format.

const MAT_DIR := "res://resources/materials/"
const SHADER_DIR := "res://resources/shaders/"
const TEX_DIR := "res://assets/textures/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(MAT_DIR)
	var mats := _make_materials()
	DirAccess.make_dir_recursive_absolute("res://scenes/weapons")
	DirAccess.make_dir_recursive_absolute("res://resources/weapons")
	_save(_build_mosin_view(mats), "res://scenes/weapons/mosin_viewmodel.tscn")
	_save(_build_suomi_view(mats), "res://scenes/weapons/suomi_viewmodel.tscn")
	_make_weapon_data()
	_save(_build_target_dummy(mats), "res://scenes/props/target_dummy.tscn")
	_make_enemy_data()
	_make_difficulty_data()
	_make_front_reports()
	load("res://tools/make_weather.gd").write_all() # B3: the weather of the ten battles
	DirAccess.make_dir_recursive_absolute("res://scenes/props")
	_save(_build_ammo_crate(mats), "res://scenes/props/ammo_crate.tscn")
	_save(_build_molotov_crate(mats), "res://scenes/props/molotov_crate.tscn")
	_save(_build_enemy(mats), "res://scenes/enemies/soviet_rifleman.tscn")
	_save(_build_enemy(mats, "soviet_officer", "SovietOfficer"), "res://scenes/enemies/soviet_officer.tscn")
	_save(_build_enemy(mats, "soviet_mg_gunner", "SovietMGGunner"), "res://scenes/enemies/soviet_mg_gunner.tscn")
	_save(_build_player(mats), "res://scenes/player.tscn")
	_save(_build_maxim(mats), "res://scenes/weapons/maxim_mg.tscn")
	_save(_build_tank(), "res://scenes/enemies/soviet_tank.tscn")
	_save(_build_trench_source(mats), TRENCH_SOURCE)
	_save(_build_level(mats), "res://levels/test_level.tscn")
	DirAccess.make_dir_recursive_absolute("res://ui")
	var theme := _make_theme()
	_save(_build_hud(theme), "res://ui/hud.tscn")
	_save(_build_settings_menu(theme), "res://ui/settings_menu.tscn")
	_save(_build_controls_panel(theme), "res://ui/controls_panel.tscn")
	_save(_build_pause_menu(theme), "res://ui/pause_menu.tscn")
	_save(_build_main_menu(theme), "res://ui/main_menu.tscn")
	_save(_build_loading_screen(theme), "res://ui/loading_screen.tscn")
	_save(_build_game(), "res://scenes/game.tscn")
	_save(_build_benchmark(), "res://scenes/benchmark.tscn")
	print("ALL SCENES BUILT")
	quit()


# ---------------------------------------------------------------- helpers
func _own(node: Node, owner: Node) -> void:
	node.owner = owner
	if node.scene_file_path != "":
		return # an instanced scene: keep it as a link, don't copy its insides
	for c in node.get_children():
		_own(c, owner)


func _save(root: Node, path: String) -> void:
	for c in root.get_children():
		_own(c, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	assert(err == OK)
	err = ResourceSaver.save(ps, path)
	print("saved ", path, ": ", error_string(err))
	root.free()


func _add(parent: Node, child: Node, n: String) -> Node:
	child.name = n
	parent.add_child(child)
	return child


func _mat(file: String, color: Color, rough: float = 0.9, vertex_color := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.vertex_color_use_as_albedo = vertex_color
	m.vertex_color_is_srgb = vertex_color
	ResourceSaver.save(m, MAT_DIR + file)
	return load(MAT_DIR + file)


func _make_materials() -> Dictionary:
	var flake := StandardMaterial3D.new()
	flake.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flake.albedo_color = Color(0.95, 0.97, 1.0)
	ResourceSaver.save(flake, MAT_DIR + "snowflake.tres")
	return {
		"snow": _shader_mat("snow_ground.tres", "snow", {}),
		"drift": _shader_mat("snow_drift.tres", "snow", {"normal_strength": 0.35}),
		"trench_wall": _shader_mat("trench_wall_logs.tres", "log_wall", {
			"albedo_texture": load(TEX_DIR + "logs_albedo.png"), "normal_texture": load(TEX_DIR + "logs_normal.png"),
			"snow_band": true, "snow_line_y": 0.0, "tint": Color(0.95, 0.92, 0.9)}),
		"bunker_log": _shader_mat("bunker_logs.tres", "log_wall", {
			"albedo_texture": load(TEX_DIR + "logs_albedo.png"), "normal_texture": load(TEX_DIR + "logs_normal.png"),
			"snow_band": false, "log_top_snow": 0.0, "tile_size_m": Vector2(2.4, 1.2), "tint": Color(1.05, 0.98, 0.92)}),
		"nest_log": _shader_mat("nest_logs.tres", "log_wall", {
			"albedo_texture": load(TEX_DIR + "logs_albedo.png"), "normal_texture": load(TEX_DIR + "logs_normal.png"),
			"snow_band": false, "log_top_snow": 0.0, "top_snow": 0.0, "tile_size_m": Vector2(1.6, 0.8)}),
		"trunk": _shader_mat("tree_trunk.tres", "spruce", {"trunk": true, "bark_texture": load(TEX_DIR + "bark.png")}),
		"foliage": _shader_mat("tree_foliage.tres", "spruce", {}),
		"soldier": _shader_mat("soldier.tres", "soldier", {}),
		"tree_line": _shader_mat("tree_line.tres", "tree_line", {"silhouette": load(TEX_DIR + "treeline.png")}),
		"player_body": _mat("player_body.tres", Color(0.82, 0.83, 0.8)),
		"flake": load(MAT_DIR + "snowflake.tres"),
		"gun_wood": _mat("gun_wood.tres", Color(0.36, 0.22, 0.12), 0.6),
		"gun_metal": _metal("gun_metal.tres"),
		"target_wood": _mat("target_wood.tres", Color(0.55, 0.42, 0.28)),
		"target_cloth": _mat("target_soviet_cloth.tres", Color(0.3, 0.28, 0.2)),
		"muzzle_flash": _flash_mat("muzzle_flash.tres"),
		"crate_wood": _mat("crate_wood.tres", Color(0.33, 0.34, 0.26), 0.85),
		"tin_white": _mat("first_aid_white.tres", Color(0.86, 0.86, 0.82), 0.5),
		"cross_red": _mat("first_aid_red.tres", Color(0.62, 0.07, 0.06), 0.6),
		"bottle_glass": _mat("bottle_glass.tres", Color(0.16, 0.24, 0.13), 0.15),
		"rag_cloth": _mat("rag_cloth.tres", Color(0.78, 0.74, 0.62), 1.0),
		"sandbag": _mat("sandbag.tres", Color(0.6, 0.52, 0.38), 1.0),
		"sandbag_snow": _mat("sandbag_snow.tres", Color(0.74, 0.72, 0.66), 1.0),
	}


## A material using one of the shaders in resources/shaders/. The snow textures are
## given to every shader that has a slot for them.
func _shader_mat(file: String, shader: String, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_DIR + shader + ".gdshader")
	var defaults := {
		"snow_normal": load(TEX_DIR + "snow_normal.png"),
		"snow_mask": load(TEX_DIR + "snow_mask.png"),
		"noise_texture": load(TEX_DIR + "snow_mask.png"),
	}
	var names: Array = m.shader.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u.name)
	for key in defaults:
		if key in names:
			m.set_shader_parameter(key, defaults[key])
	for key in params:
		assert(key in names, "%s has no parameter %s" % [shader, key])
		m.set_shader_parameter(key, params[key])
	ResourceSaver.save(m, MAT_DIR + file)
	return load(MAT_DIR + file)


func _metal(file: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.11, 0.11, 0.12)
	m.metallic = 0.7
	m.roughness = 0.45
	ResourceSaver.save(m, MAT_DIR + file)
	return load(MAT_DIR + file)


func _flash_mat(file: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # normal blending: "add" is invisible against bright snow
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.78, 0.35)
	m.albedo_texture = ImpactEffects._make_round_texture()
	ResourceSaver.save(m, MAT_DIR + file)
	return load(MAT_DIR + file)


func _sync_config(props: Array) -> SceneReplicationConfig:
	# props: [[path, spawn, mode], ...]
	var cfg := SceneReplicationConfig.new()
	for p in props:
		var path := NodePath(p[0])
		cfg.add_property(path)
		cfg.property_set_spawn(path, p[1])
		cfg.property_set_replication_mode(path, p[2])
	return cfg


# ---------------------------------------------------------------- player
func _build_player(mats: Dictionary) -> Node:
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.set_script(load("res://scripts/player/player.gd"))
	p.collision_layer = 0b10      # layer 2: players
	p.collision_mask = 0b111      # world, players, enemies
	p.floor_max_angle = deg_to_rad(46.0)
	p.floor_snap_length = 0.3

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var cs: CollisionShape3D = _add(p, CollisionShape3D.new(), "CollisionShape3D")
	cs.shape = capsule
	cs.position.y = 0.9

	var body_mesh: MeshInstance3D = _add(p, MeshInstance3D.new(), "BodyMesh")
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.8
	cm.material = mats.player_body
	body_mesh.mesh = cm
	body_mesh.position.y = 0.9

	var head: Node3D = _add(p, Node3D.new(), "Head")
	head.position.y = 1.6
	var cam: Camera3D = _add(head, Camera3D.new(), "Camera3D")
	cam.fov = 75.0
	cam.near = 0.05
	cam.far = 600.0

	var holder: Node3D = _add(cam, Node3D.new(), "WeaponHolder")
	holder.position = Vector3(0.13, -0.17, -0.3)
	var arms: Node3D = _add(cam, Node3D.new(), "Arms") # snow-camo sleeves + mittens (W2)
	arms.set_script(load("res://scripts/player/fp_arms.gd"))
	var wall_check: RayCast3D = _add(cam, RayCast3D.new(), "WallCheck")
	wall_check.target_position = Vector3(0, 0, -0.9)
	wall_check.collision_mask = 0b1
	var remote_audio: AudioStreamPlayer3D = _add(head, AudioStreamPlayer3D.new(), "RemoteAudio")
	remote_audio.max_polyphony = 4
	remote_audio.unit_size = 25.0
	remote_audio.bus = &"SFX"
	remote_audio.attenuation_filter_cutoff_hz = 2500.0
	remote_audio.attenuation_filter_db = -30.0

	var wc: Node = _add(p, Node.new(), "WeaponController")
	wc.set_script(load("res://scripts/weapons/weapon_controller.gd"))
	var loadout: Array[WeaponData] = [load("res://resources/weapons/mosin_m28_30.tres"), load("res://resources/weapons/suomi_kp31.tres")]
	wc.set("loadout", loadout)
	var shot_audio: AudioStreamPlayer = _add(wc, AudioStreamPlayer.new(), "ShotAudio")
	shot_audio.max_polyphony = 4
	shot_audio.volume_db = -4.0
	shot_audio.bus = &"SFX"
	var mech_audio: AudioStreamPlayer = _add(wc, AudioStreamPlayer.new(), "MechAudio")
	mech_audio.volume_db = -6.0
	mech_audio.bus = &"SFX"
	var wsync: MultiplayerSynchronizer = _add(wc, MultiplayerSynchronizer.new(), "WeaponSync")
	wsync.root_path = NodePath("..")
	wsync.replication_config = _sync_config([
		[".:current_slot", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:mag_ammo", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:reserve_ammo", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:is_reloading", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:shots_fired", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:shots_hit", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
	])

	# T2: Molotov cocktails (G = in the hand, right mouse = light / aim, left mouse = throw).
	var mol: Node = _add(p, Node.new(), "Molotov")
	mol.set_script(load("res://scripts/player/molotov_handler.gd"))
	var mol_sync: MultiplayerSynchronizer = _add(mol, MultiplayerSynchronizer.new(), "MolotovSync")
	mol_sync.root_path = NodePath("..")
	mol_sync.replication_config = _sync_config([
		[".:count", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:phase", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
	])

	# Footsteps, breath vapour and drifting snow (made in code by player_fx.gd).
	var fx: Node3D = _add(p, Node3D.new(), "PlayerFX")
	fx.set_script(load("res://scripts/player/player_fx.gd"))

	var ceiling: ShapeCast3D = _add(p, ShapeCast3D.new(), "CeilingCheck")
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	ceiling.shape = sphere
	ceiling.position.y = 0.9
	ceiling.target_position = Vector3(0, 0.75, 0)
	ceiling.collision_mask = 0b1

	var snow: CPUParticles3D = _add(p, CPUParticles3D.new(), "SnowParticles")
	snow.position.y = 12.0
	snow.amount = 900
	snow.lifetime = 8.0
	snow.preprocess = 8.0
	snow.fixed_fps = 30
	snow.local_coords = false
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(22, 1, 22)
	snow.direction = Vector3(0, -1, 0)
	snow.spread = 20.0
	snow.gravity = Vector3(0.4, -1.0, 0.2)
	snow.initial_velocity_min = 0.3
	snow.initial_velocity_max = 0.8
	snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flake := QuadMesh.new()
	flake.size = Vector2(0.05, 0.05)
	flake.material = mats.flake
	snow.mesh = flake
	snow.emitting = false

	var pin: Node = _add(p, Node.new(), "PlayerInput")
	pin.set_script(load("res://scripts/player/player_input.gd"))
	var in_sync: MultiplayerSynchronizer = _add(pin, MultiplayerSynchronizer.new(), "InputSync")
	in_sync.root_path = NodePath("..")
	var ALWAYS := SceneReplicationConfig.REPLICATION_MODE_ALWAYS
	var ON_CHANGE := SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
	var NEVER := SceneReplicationConfig.REPLICATION_MODE_NEVER
	in_sync.replication_config = _sync_config([
		[".:move_dir", false, ALWAYS],
		[".:sprint_held", false, ON_CHANGE],
		[".:crouch_held", false, ON_CHANGE],
		[".:look_yaw", true, ALWAYS],
		[".:look_pitch", true, ALWAYS],
		[".:aim_held", false, ON_CHANGE],
	])

	var state_sync: MultiplayerSynchronizer = _add(p, MultiplayerSynchronizer.new(), "StateSync")
	state_sync.root_path = NodePath("..")
	state_sync.replication_config = _sync_config([
		[".:position", true, ALWAYS],
		[".:velocity", false, ALWAYS],
		[".:rotation", true, NEVER],
		[".:health", true, ON_CHANGE],
		[".:stamina", true, ON_CHANGE],
		[".:is_crouching", true, ON_CHANGE],
		[".:is_sprinting", true, ON_CHANGE],
		[".:god_mode", true, ON_CHANGE],
		[".:mounted_gun_path", true, ON_CHANGE],
		[".:is_dead", true, ON_CHANGE],
		[".:kills", true, ON_CHANGE],
		[".:deaths", true, ON_CHANGE],
		[".:bandages", true, ON_CHANGE],
		[".:is_bandaging", true, ON_CHANGE],
	])
	return p


# ---------------------------------------------------------------- level
const NAVMESH_PATH := "res://levels/test_level_navmesh.res"
## L1: the trench centre line as x, z pairs, west -> east (+z = towards the rear, -z = towards
## the enemy). Short legs (3-8 m) with many corners: bays and traverses like a real trench.
## The line deliberately passes the spots other code and the tests use: (-30, 61), (-10, 61),
## (10, 61), (50, 61), (70, 61), (90, 61), the bunker front (x = -6 ... 6, z = 64) and the
## exit spots (x = +-40 and +-80, z = 64).
const TRENCH_XZ := [
	-100, 61, -94, 61, -91, 58, -86, 58, -83, 61, -83, 64,
	-77, 64, -72, 59, -67, 60, -61, 60, -57, 63, -52, 63,
	-52, 59, -47, 59, -47, 63, -43, 64, -37, 64, -34, 61,
	-28, 61, -26, 58, -21, 58, -17, 61, -9, 61, -6, 64,
	6, 64, 9, 61, 16, 61, 21, 58, 28, 58, 31, 61,
	36, 64, 44, 64, 47, 61, 54, 61, 58, 59, 67, 59,
	70, 61, 74, 61, 77, 64, 84, 64, 87, 61, 94, 61,
	94, 58, 100, 58,
]
## L1: protected firing positions: x of each bay (a narrow slot, one soldier wide, that juts
## forward from the front of the line; in front of it a sandbag wall with a loophole, like
## the photo SA_Kuva_a_8).
const POST_X := [-64.0, -23.5, 24.0, 64.0]
const POST_BAY_W := 1.3      ## width of the bay (m): one soldier
const POST_BAY_DEPTH := 2.6  ## from the centre line to the front wall of the bay (m)
## The sandbag wall (local to the bay's front edge; -z = towards the enemy):
const POST_WALL_BACK := 0.02   ## rear face
const POST_WALL_FRONT := -0.6  ## front face (0.62 m thick)
const POST_WALL_HALF_W := 1.4  ## half width of the wall
const POST_WALL_TOP := 0.84    ## top (m above the ground)
const POST_HOLE_HALF_W := 0.4  ## the loophole is 0.8 m wide ...
const POST_HOLE_TOP := 0.42    ## ... and 0.42 m tall, starting at the ground
## L1: two short dead-end branches to the rear: x, z of the line they leave, length (m).
const SPURS := [Vector3(-54.5, 63.0, 5.0), Vector3(51.0, 61.0, 5.0)]
const TRENCH_WIDTH := 2.0
const DEPTH := 1.4
## L2: the log bunker faces the enemy (its front wall with the Maxim's hole is at z = BUNKER_Z - 2.75,
## open ground in front); the trench line runs behind it and a short stub of trench leads to the
## door in its back wall.
const BUNKER_Z := 59.5
const BUNKER_DOOR_X := 1.2
const BUNKER_DOOR_W := 1.4


func _tcount() -> int:
	return TRENCH_XZ.size() / 2 - 1  # number of legs


func _tp(i: int) -> Vector2:
	return Vector2(TRENCH_XZ[i * 2], TRENCH_XZ[i * 2 + 1])


func _leg_dir(i: int) -> Vector2:
	return (_tp(i + 1) - _tp(i)).normalized()


## The side of leg i that points to the rear of the trench (+z for a leg running west -> east).
func _leg_rear(i: int) -> Vector2:
	var d := _leg_dir(i)
	return Vector2(-d.y, d.x)


## z of the centre line at x (first leg that crosses x).
func _line_z(x: float) -> float:
	for i in _tcount():
		var a := _tp(i)
		var b := _tp(i + 1)
		if not is_equal_approx(a.x, b.x) and x >= minf(a.x, b.x) - 0.001 and x <= maxf(a.x, b.x) + 0.001:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return _tp(0).y


## Index of the straight east-west leg (constant z) that covers x, or -1.
func _flat_leg_at(x: float) -> int:
	for i in _tcount():
		var a := _tp(i)
		var b := _tp(i + 1)
		if is_equal_approx(a.y, b.y) and x >= a.x and x <= b.x:
			return i
	return -1


func _dist_to_leg(p: Vector2, j: int) -> float:
	var a := _tp(j)
	var b := _tp(j + 1)
	var d := b - a
	var t := clampf((p - a).dot(d) / d.length_squared(), 0.0, 1.0)
	return p.distance_to(a + d * t)


## Is the ground point p (in front of a leg) solid ground, i.e. not above another part of the
## trench, a bay or a branch?
func _front_clear(p: Vector2, leg: int) -> bool:
	if p.y < 52.6:
		return false
	for j in _tcount():
		if j != leg and _dist_to_leg(p, j) < TRENCH_WIDTH / 2.0 + 0.8:
			return false
	for x: float in POST_X:
		var zc := _line_z(x)
		if absf(p.x - x) < POST_BAY_W / 2.0 + 1.5 and p.y < zc and p.y > zc - POST_BAY_DEPTH - 3.0:
			return false
	for s: Vector3 in SPURS:
		if absf(p.x - s.x) < 2.5 and p.y > s.z - 1.0 and p.y < s.z + s.y + 1.5:
			return false
	return true


## G1/L1: the legs that get a trench entry (one per ~20 m): mostly east-west legs of at
## least 4 m with open ground in front.
func _entry_legs() -> Array[int]:
	var used: Array[int] = []
	for tx in range(-90, 91, 20):
		var best := -1
		var best_d := 1e9
		for i in _tcount():
			if i in used:
				continue
			var d := _tp(i + 1) - _tp(i)
			if d.length() < 4.0 or absf(d.y) > absf(d.x) * 0.8:
				continue
			var mid := (_tp(i) + _tp(i + 1)) / 2.0
			if not _front_clear(mid - _leg_rear(i) * (TRENCH_WIDTH / 2.0 + 1.3), i):
				continue
			if absf(mid.x - tx) < best_d:
				best_d = absf(mid.x - tx)
				best = i
		assert(best >= 0, "no trench entry leg near x = %d" % tx)
		used.append(best)
	return used


## G1: the ammo niche in the rear wall of the straight leg at x = -31 (next to the first
## player spawn). Returns [crate centre (x, z), yaw, rear direction].
func _ammo_niche() -> Array:
	var i := _flat_leg_at(-31.0)
	var rear := _leg_rear(i)
	var dir := _leg_dir(i)
	return [Vector2(-31.0, _tp(i).y) + rear * (TRENCH_WIDTH / 2.0 + 0.42), atan2(-dir.y, dir.x), rear]


func _csg_box(parent: Node, n: String, size: Vector3, pos: Vector3, mat: Material,
		op := CSGShape3D.OPERATION_UNION, rot := Vector3.ZERO) -> CSGBox3D:
	var b: CSGBox3D = _add(parent, CSGBox3D.new(), n)
	b.size = size
	b.position = pos
	b.rotation = rot
	b.material = mat
	b.operation = op
	return b


func _build_level(mats: Dictionary) -> Node:
	var root := Node3D.new()
	root.name = "TestLevel"

	# --- Atmosphere ---
	var we: WorldEnvironment = _add(root, WorldEnvironment.new(), "WorldEnvironment")
	var env := Environment.new()
	# Clear, freezing day: our own sky shader (resources/shaders/winter_sky.gdshader).
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load(SHADER_DIR + "winter_sky.gdshader")
	ResourceSaver.save(sky_mat, MAT_DIR + "winter_sky.tres")
	var sky := Sky.new()
	sky.sky_material = load(MAT_DIR + "winter_sky.tres")
	sky.radiance_size = Sky.RADIANCE_SIZE_64 # the sky is soft: a tiny reflection map is enough
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Shadows are lit only by the blue sky -> cold blue shadows next to warm sunlit snow.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.56, 0.68, 0.9)
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Linear tonemapping: in the Compatibility renderer "Filmic" looks different when the
	# render scale is below 100 %, which would make the quality presets change the colours.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.85
	# Light haze: distant things fade to pale blue (density is set by the quality preset).
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.81, 0.9)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.25
	env.fog_density = 0.003
	env.fog_sky_affect = 0.15
	env.fog_height = 0.5
	env.fog_height_density = 0.03
	we.environment = env
	we.add_to_group("world_environment", true)

	# Low winter sun in the south-west: warm light, long shadows towards the trench.
	var sun: DirectionalLight3D = _add(root, DirectionalLight3D.new(), "Sun")
	sun.rotation = Vector3(deg_to_rad(-13.0), deg_to_rad(-150.0), 0.0)
	sun.light_color = Color(1.0, 0.87, 0.72)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.add_to_group("sun", true)
	# The low winter sun hits the snow at a grazing angle: extra bias avoids striped "shadow acne".
	sun.shadow_bias = 0.2
	sun.shadow_normal_bias = 2.5

	# --- Ground ---
	var terrain: StaticBody3D = _add(root, StaticBody3D.new(), "Terrain")
	terrain.set_script(load("res://scripts/world/terrain_generator.gd"))
	terrain.add_to_group("terrain", true)
	terrain.add_to_group("navigation_source", true)
	var noise := FastNoiseLite.new()
	noise.seed = 1939
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	terrain.set("noise", noise)
	terrain.set("snow_material", mats.snow)

	# --- Invisible walls at the map border ---
	var bounds: StaticBody3D = _add(root, StaticBody3D.new(), "MapBounds")
	bounds.collision_layer = 0b1
	bounds.add_to_group("navigation_source", true)
	for side in [[Vector3(0, 10, -151), Vector3(304, 40, 2)], [Vector3(0, 10, 151), Vector3(304, 40, 2)],
			[Vector3(-151, 10, 0), Vector3(2, 40, 304)], [Vector3(151, 10, 0), Vector3(2, 40, 304)]]:
		var wall: CollisionShape3D = _add(bounds, CollisionShape3D.new(), "Wall")
		var box := BoxShape3D.new()
		box.size = side[1]
		wall.shape = box
		wall.position = side[0]

	# --- Forest ---
	var forest: Node3D = _add(root, Node3D.new(), "Forest")
	forest.set_script(load("res://scripts/world/forest_scatter.gd"))
	forest.add_to_group("navigation_source", true)
	forest.set("trunk_material", mats.trunk)
	forest.set("foliage_material", mats.foliage)
	forest.set("tree_line_material", mats.tree_line)

	# --- Trench and bunker ---
	# Edited as CSG in levels/source/trench_csg.tscn; tools/bake_csg.gd turns them into plain
	# meshes (much faster to load, especially in a browser). Until baked, the CSG is used.
	if ResourceLoader.exists(BAKED_DIR + "trench_mesh.res"):
		_baked_body(root, "Trench", Vector3.ZERO, "earthwork")
		_baked_body(root, "Bunker", Vector3(0, 0, BUNKER_Z), "wood")
	else:
		_add(root, load(TRENCH_SOURCE).instantiate(), "TrenchCSG")

	# --- Maxim machine gun in the bunker, firing through the slit ---
	var maxim: Node3D = _add(root, load("res://scenes/weapons/maxim_mg.tscn").instantiate(), "MaximMG")
	# L2: the turning point sits 0.6 m behind the outer face (the muzzle ends flush with the hole) of the front wall (z = BUNKER_Z - 2.75).
	maxim.position = Vector3(0.0, MAXIM_BARREL_Y - MAXIM_BARREL_HEIGHT, BUNKER_Z - 2.15)

	# --- L1: sandbag walls and earth banks in front of the four firing positions ---
	_build_fire_posts(root, mats)

	# --- Deep snow ---
	var zones: Node3D = _add(root, Node3D.new(), "DeepSnowZones")
	var zone_data := [
		[Vector3(-45, 0, -20), Vector3(26, 4, 14)],
		[Vector3(35, 0, -55), Vector3(30, 4, 16)],
		[Vector3(-80, 0, -85), Vector3(24, 4, 18)],
		[Vector3(75, 0, 5), Vector3(22, 4, 12)],
		[Vector3(0, 0, 32), Vector3(40, 4, 8)],
	]
	for i in zone_data.size():
		var z: Area3D = _add(zones, Area3D.new(), "DeepSnow%d" % (i + 1))
		z.set_script(load("res://scripts/world/deep_snow_zone.gd"))
		z.position = zone_data[i][0]
		z.set("size", zone_data[i][1])
		z.set("drift_material", mats.drift)

	# (The shooting-range practice targets were removed – owner. target_dummy.tscn stays for tests.)

	# --- Navigation map for the enemies (baked from the nodes in group "navigation_source") ---
	var nav: NavigationRegion3D = _add(root, NavigationRegion3D.new(), "Navigation")
	if ResourceLoader.exists(NAVMESH_PATH):
		nav.navigation_mesh = load(NAVMESH_PATH)
	else:
		var nm := NavigationMesh.new()
		nm.agent_radius = 0.5    # multiples of the 0.25 m cell size
		nm.agent_height = 2.0
		nm.agent_max_climb = 0.5
		nm.agent_max_slope = 40.0
		nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		nm.geometry_collision_mask = 0b1
		nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
		nm.geometry_source_group_name = &"navigation_source"
		nm.filter_baking_aabb = AABB(Vector3(-150, -10, -150), Vector3(300, 30, 225)) # enemy side only
		nav.navigation_mesh = nm

	# --- Enemy spawn points (southern forest edge) and attack points (in front of the trench) ---
	var enemy_spawns: Node3D = _add(root, Node3D.new(), "EnemySpawnPoints")
	for i in 6:
		var m: Marker3D = _add(enemy_spawns, Marker3D.new(), "EnemySpawn%d" % (i + 1))
		m.position = Vector3(-100 + i * 40, 0, -118)
		m.add_to_group("enemy_spawn", true)
	var attack_points: Node3D = _add(root, Node3D.new(), "AttackPoints")
	for i in 8:
		var m: Marker3D = _add(attack_points, Marker3D.new(), "AttackPoint%d" % (i + 1))
		m.position = Vector3(-84 + i * 24, 0, 38 + (i % 2) * 4)
		m.add_to_group("attack_point", true)

	# --- T1: tank routes from the southern forest to the edge of the trench ---
	var routes: Node3D = _add(root, Node3D.new(), "TankRoutes")
	for i in TANK_ROUTES.size():
		var path: Path3D = _add(routes, Path3D.new(), "TankRoute%d" % (i + 1))
		path.curve = _smooth_curve(TANK_ROUTES[i])
		path.add_to_group("tank_route", true)

	# --- G1: ammo crates (one in a niche of the trench, one in the bunker) ---
	var crate_scene: PackedScene = load("res://scenes/props/ammo_crate.tscn")
	var niche: Array = _ammo_niche()
	var crate1: Node3D = _add(root, crate_scene.instantiate(), "AmmoCrateTrench")
	crate1.position = Vector3(niche[0].x, -DEPTH, niche[0].y)
	crate1.rotation.y = niche[1]
	var crate2: Node3D = _add(root, crate_scene.instantiate(), "AmmoCrateBunker")
	crate2.position = Vector3(-1.9, -DEPTH, BUNKER_Z + 1.7)
	# T2: boxes of Molotov cocktails against the rear wall of two straight trench legs.
	var bottle_scene: PackedScene = load("res://scenes/props/molotov_crate.tscn")
	for spot: Array in [[-15.0, "MolotovCrateWest"], [12.5, "MolotovCrateCentre"]]:
		var li := _flat_leg_at(spot[0])
		var rear := _leg_rear(li)
		var at: Vector2 = Vector2(spot[0], _tp(li).y) + rear * (TRENCH_WIDTH / 2.0 - 0.28)
		var box: Node3D = _add(root, bottle_scene.instantiate(), spot[1])
		box.position = Vector3(at.x, -DEPTH, at.y)
		box.rotation.y = 0.0

	# --- G1/L1: trench entries: where the Soviets jump down into the trench (one per ~20 m).
	# A NavigationLink3D joins the walkable ground in front to the trench floor.
	var entries: Node3D = _add(root, Node3D.new(), "TrenchEntries")
	var entry_no := 1
	for i in _entry_legs():
		var rear := _leg_rear(i) # points back (+z), away from the enemy
		var mid := (_tp(i) + _tp(i + 1)) / 2.0
		var link: NavigationLink3D = _add(entries, NavigationLink3D.new(), "Entry%d" % entry_no)
		entry_no += 1
		var start := mid - rear * (TRENCH_WIDTH / 2.0 + 1.3)
		var land := mid - rear * 0.1
		link.start_position = Vector3(start.x, 0.0, start.y)
		link.end_position = Vector3(land.x, -DEPTH, land.y)
		link.bidirectional = false
		link.add_to_group("trench_entry", true)

	# --- Player spawn points inside the trench (facing the enemy, -z) ---
	var spawns: Node3D = _add(root, Node3D.new(), "PlayerSpawnPoints")
	var spawn_x := [-30.0, -10.0, 10.0, 33.0]
	for i in 4:
		var m: Marker3D = _add(spawns, Marker3D.new(), "Spawn%d" % (i + 1))
		m.position = Vector3(spawn_x[i], -DEPTH + 0.1, _line_z(spawn_x[i]))
		m.add_to_group("player_spawn", true)
	return root


# ---------------------------------------------------------------- T1: tank
## Tank routes (x, z): from the forest edge in the south to just in front of the trench
## (front edge at z ≈ 57; the last point is where the tank stops). Height comes from the terrain.
const TANK_ROUTES := [
	[Vector2(-68, -106), Vector2(-62, -60), Vector2(-54, -15), Vector2(-47, 25), Vector2(-44, 49)],
	[Vector2(6, -106), Vector2(-4, -64), Vector2(-6, -30), Vector2(3, 0), Vector2(4, 24), Vector2(6, 49)],
	[Vector2(74, -106), Vector2(69, -58), Vector2(58, -10), Vector2(49, 27), Vector2(46, 49)],
]
const T26_TURRET := Vector3(0.014, 1.5, 0.07)       # turret ring centre (model is in metres)
const T26_TRUNNION := Vector3(0.022, 1.888, -0.654) # where the gun turns up/down
const T26_MUZZLE := Vector3(0.028, 1.888, -2.508)


## A smooth Curve3D through the points (Catmull-Rom handles), lying on y = 0.
func _smooth_curve(points: Array) -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = 0.5
	for i in points.size():
		var p := Vector3(points[i].x, 0.0, points[i].y)
		var prev: Vector2 = points[maxi(i - 1, 0)]
		var next: Vector2 = points[mini(i + 1, points.size() - 1)]
		var tangent := Vector3(next.x - prev.x, 0.0, next.y - prev.y) / 6.0
		c.add_point(p, -tangent, tangent)
	return c


func _build_tank() -> Node:
	var t := AnimatableBody3D.new()
	t.name = "SovietTank"
	t.set_script(load("res://scripts/enemies/tank.gd"))
	t.collision_layer = 0b100 # layer 3: enemies (bullets hit it, players bump into it)
	t.collision_mask = 0
	t.sync_to_physics = false # the script places it every physics frame (with Jolt, "true" kept it at 0,0,0)
	t.set_meta("surface", "metal")
	var hull := BoxShape3D.new()
	hull.size = Vector3(2.35, 1.4, 4.65)
	var hs: CollisionShape3D = _add(t, CollisionShape3D.new(), "HullShape")
	hs.shape = hull
	hs.position = Vector3(0, 0.9, 0)
	var turret := CylinderShape3D.new()
	turret.radius = 0.78
	turret.height = 0.85
	var ts: CollisionShape3D = _add(t, CollisionShape3D.new(), "TurretShape")
	ts.shape = turret
	ts.position = T26_TURRET + Vector3(0, 0.45, 0)
	# "Т-26 SD" by MMD_SonicNewYear (Sketchfab), CC-BY 4.0. Already in metres, front = -z.
	_add(t, load("res://assets/models/vehicles/t26/model.gltf").instantiate(), "Model")

	var turret_pivot: Node3D = _add(t, Node3D.new(), "TurretPivot")
	turret_pivot.position = T26_TURRET
	var eye: Marker3D = _add(turret_pivot, Marker3D.new(), "Eye")
	eye.position = Vector3(0, 0.85, -0.2) # commander's hatch / periscope
	var gun_pivot: Node3D = _add(turret_pivot, Node3D.new(), "GunPivot")
	gun_pivot.position = T26_TRUNNION - T26_TURRET
	var muzzle: Marker3D = _add(gun_pivot, Marker3D.new(), "Muzzle")
	muzzle.position = T26_MUZZLE - T26_TRUNNION
	var dt: Marker3D = _add(gun_pivot, Marker3D.new(), "DtMuzzle")
	dt.position = Vector3(0.2, -0.02, -0.5) # coaxial DT, right of the gun
	var gun_sound: AudioStreamPlayer3D = _add(gun_pivot, AudioStreamPlayer3D.new(), "GunSound")
	gun_sound.bus = &"SFX"
	gun_sound.unit_size = 60.0
	gun_sound.max_polyphony = 2
	gun_sound.attenuation_filter_cutoff_hz = 4000.0
	gun_sound.position = muzzle.position
	var dt_sound: AudioStreamPlayer3D = _add(gun_pivot, AudioStreamPlayer3D.new(), "DtSound")
	dt_sound.bus = &"SFX"
	dt_sound.unit_size = 30.0
	dt_sound.max_polyphony = 4
	dt_sound.attenuation_filter_cutoff_hz = 2500.0
	dt_sound.attenuation_filter_db = -30.0
	dt_sound.position = dt.position

	# Engine + tracks (loop): heard from far away, before the tank comes out of the haze.
	var engine: AudioStreamPlayer3D = _add(t, AudioStreamPlayer3D.new(), "EngineSound")
	engine.bus = &"SFX"
	engine.unit_size = 18.0
	engine.max_distance = 450.0
	engine.attenuation_filter_cutoff_hz = 3000.0
	engine.attenuation_filter_db = -20.0
	engine.position = Vector3(0, 1.0, 1.2) # engine at the back

	var sync: MultiplayerSynchronizer = _add(t, MultiplayerSynchronizer.new(), "StateSync")
	sync.root_path = NodePath("..")
	var ALWAYS := SceneReplicationConfig.REPLICATION_MODE_ALWAYS
	var ON_CHANGE := SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
	sync.replication_config = _sync_config([
		[".:position", true, ALWAYS],
		[".:rotation", true, ALWAYS],
		[".:turret_yaw", true, ALWAYS],
		[".:gun_pitch", true, ALWAYS],
		[".:drive_speed", true, ON_CHANGE],
		[".:state", true, ON_CHANGE],
	])
	return t


# ---------------------------------------------------------------- game
## The bangs in assets/audio/artillery/barrage.ogg: [seconds], [loudness 0..1] (found with a
## simple onset detector in Python when the sound was converted).
const BARRAGE_SHELLS := [
	[0.98, 1.65, 2.14, 2.60, 3.84, 4.41, 4.78, 5.15, 5.68, 6.30, 7.36, 7.95, 8.66, 9.03, 9.59, 10.05,
	10.54, 10.98, 11.42, 11.84, 12.24, 12.69, 13.10, 13.73, 14.21, 14.78, 15.24, 15.71, 16.14, 16.53,
	16.97, 17.44, 18.49, 19.17, 19.57, 19.97, 20.82, 21.41, 22.06, 22.43, 22.88, 23.29, 23.68, 24.18,
	24.56, 24.94, 25.51],
	[0.18, 0.27, 0.24, 0.19, 0.14, 0.30, 0.59, 0.35, 0.52, 0.38, 0.41, 0.30, 0.57, 0.40, 0.22, 0.17,
	0.17, 0.12, 0.16, 0.19, 0.25, 0.19, 0.31, 0.22, 0.28, 0.58, 0.31, 0.16, 0.14, 0.25, 0.93, 0.64,
	0.40, 0.46, 0.36, 0.98, 0.65, 1.00, 0.89, 0.53, 0.28, 0.32, 0.25, 0.21, 0.14, 0.17, 0.16],
]


func _build_game() -> Node:
	var g := Node3D.new()
	g.name = "Game"
	g.set_script(load("res://scripts/game/game.gd"))
	var level: Node = load("res://levels/test_level.tscn").instantiate()
	_add(g, level, "Level")
	var players: Node3D = _add(g, Node3D.new(), "Players")
	var spawner: MultiplayerSpawner = _add(g, MultiplayerSpawner.new(), "PlayerSpawner")
	spawner.spawn_path = NodePath("../Players")
	spawner.add_spawnable_scene("res://scenes/player.tscn")
	g.set("players_root", players)

	var warm: CanvasLayer = _add(g, CanvasLayer.new(), "ShaderWarmup")
	warm.set_script(load("res://scripts/game/shader_warmup.gd"))
	var amb: Node = _add(g, Node.new(), "Ambience")
	amb.set_script(load("res://scripts/game/ambience.gd"))
	var qa: Node = _add(g, Node.new(), "QualityApplier")
	qa.set_script(load("res://scripts/game/quality_applier.gd"))
	var fx: Node3D = _add(g, Node3D.new(), "ImpactEffects")
	fx.set_script(load("res://scripts/weapons/impact_effects.gd"))

	var enemies: Node3D = _add(g, Node3D.new(), "Enemies")
	var enemy_spawner: MultiplayerSpawner = _add(g, MultiplayerSpawner.new(), "EnemySpawner")
	enemy_spawner.spawn_path = NodePath("../Enemies")
	enemy_spawner.add_spawnable_scene("res://scenes/enemies/soviet_rifleman.tscn")
	enemy_spawner.add_spawnable_scene("res://scenes/enemies/soviet_officer.tscn")
	enemy_spawner.add_spawnable_scene("res://scenes/enemies/soviet_mg_gunner.tscn")
	# T1: tanks (their own root + spawner, so they never count as soldiers of a wave).
	var tanks: Node3D = _add(g, Node3D.new(), "Tanks")
	var tank_node_spawner: MultiplayerSpawner = _add(g, MultiplayerSpawner.new(), "TankNodeSpawner")
	tank_node_spawner.spawn_path = NodePath("../Tanks")
	tank_node_spawner.add_spawnable_scene("res://scenes/enemies/soviet_tank.tscn")
	var tank_spawner: Node = _add(g, Node.new(), "TankSpawner")
	tank_spawner.set_script(load("res://scripts/enemies/tank_spawner.gd"))
	tank_spawner.set("tank_scene", load("res://scenes/enemies/soviet_tank.tscn"))
	tank_spawner.set("tanks_root", tanks)
	tank_spawner.set("crew_scene", load("res://scenes/enemies/soviet_rifleman.tscn"))
	tank_spawner.set("crew_root", enemies)
	# T2: flying Molotov cocktails and the fires they start.
	var molotovs: Node3D = _add(g, Node3D.new(), "Molotovs")
	molotovs.set_script(load("res://scripts/weapons/molotov_manager.gd"))
	var waves: Node = _add(g, Node.new(), "WaveSpawner")
	waves.set_script(load("res://scripts/enemies/wave_spawner.gd"))
	waves.set("enemy_scene", load("res://scenes/enemies/soviet_rifleman.tscn"))
	waves.set("officer_scene", load("res://scenes/enemies/soviet_officer.tscn"))
	waves.set("mg_gunner_scene", load("res://scenes/enemies/soviet_mg_gunner.tscn"))
	waves.set("enemies_root", enemies)
	var wave_sync: MultiplayerSynchronizer = _add(waves, MultiplayerSynchronizer.new(), "WaveSync")
	wave_sync.root_path = NodePath("..")
	wave_sync.replication_config = _sync_config([
		[".:wave_number", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:alive_count", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:wave_riflemen", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:wave_officers", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:wave_mg_teams", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:wave_tanks", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
	])

	# G1: the rules of the battle (difficulty, victory, defeat) and the evening light.
	var director: Node = _add(g, Node.new(), "MatchDirector")
	director.set_script(load("res://scripts/game/match_director.gd"))
	var diffs: Array[DifficultyData] = []
	for n in ["easy", "normal", "hard"]:
		diffs.append(load("res://resources/difficulty/%s.tres" % n))
	director.set("difficulties", diffs)
	var match_sync: MultiplayerSynchronizer = _add(director, MultiplayerSynchronizer.new(), "MatchSync")
	match_sync.root_path = NodePath("..")
	match_sync.delta_interval = 0.25
	var OC := SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
	match_sync.replication_config = _sync_config([
		[".:difficulty", true, OC], [".:waves_to_win", true, OC], [".:trench_limit", true, OC],
		[".:in_trench", true, OC], [".:waves_cleared", true, OC], [".:result", true, OC],
		[".:match_time", true, OC], [".:test_wave", true, OC],
	])
	var dusk: Node = _add(g, Node.new(), "Dusk")
	dusk.set_script(load("res://scripts/game/dusk.gd"))
	# Artillery barrage before some waves (WaveData.barrage). Recording: "Artillery Barrage" by
	# Mozfoo (original explosion by Steveygos93), CC-BY 4.0. A shell lands at every bang in it.
	var arty: Node3D = _add(g, Node3D.new(), "ArtilleryBarrage")
	arty.set_script(load("res://scripts/game/artillery_barrage.gd"))
	arty.set("sound", load("res://assets/audio/artillery/barrage.ogg"))
	arty.set("warning_sound", load("res://assets/audio/artillery/guns_distant.ogg"))
	arty.set("close_sound", load("res://assets/audio/artillery/shell_close.ogg"))
	arty.set("pool_size", 12) # air-raid bombs land in sticks: more blasts at once
	arty.set("shell_times", PackedFloat32Array(BARRAGE_SHELLS[0]))
	arty.set("shell_strengths", PackedFloat32Array(BARRAGE_SHELLS[1]))
	# Air raid (A1): three SB-2 bombers in waves 4 and 8. Sounds are found by the script itself
	# (recorded/raid_* or the placeholders in assets/audio/air_raid/, the engine is the plane recording).
	var raid: Node3D = _add(g, Node3D.new(), "AirRaid")
	raid.set_script(load("res://scripts/game/air_raid.gd"))
	raid.set("close_sound", load("res://assets/audio/artillery/shell_close.ogg"))
	# Background sounds: each flies over once per battle (a plane: YleArkisto, CC-BY 4.0).
	var bg: Node = _add(g, Node.new(), "BackgroundSounds")
	bg.set_script(load("res://scripts/game/background_sounds.gd"))
	var bg_sounds: Array[AudioStream] = [load("res://assets/audio/background/plane_flyover_viima.ogg")]
	bg.set("sounds", bg_sounds)
	var bg_over: Array[float] = [10.9] # the plane is loudest (right overhead) 10.9 s into the file
	bg.set("overhead_at", bg_over)

	_add(g, load("res://ui/hud.tscn").instantiate(), "HUD")
	_add(g, load("res://ui/pause_menu.tscn").instantiate(), "PauseMenu")
	var ui: CanvasLayer = _add(g, CanvasLayer.new(), "DebugUI")
	var label: Label = _add(ui, Label.new(), "DebugLabel")
	label.set_script(load("res://scripts/game/debug_overlay.gd"))
	label.position = Vector2(12, 10)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


# ---------------------------------------------------------------- weapons
func _part(parent: Node, n: String, mesh: PrimitiveMesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi: MeshInstance3D = _add(parent, MeshInstance3D.new(), n)
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(radius: float, length: float, sides := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = length
	c.radial_segments = sides
	c.rings = 0
	return c


const ALONG_Z := Vector3(PI / 2.0, 0, 0) # cylinders point along Y; rotate them to point along Z
const ALONG_X := Vector3(0, 0, PI / 2.0)


func _view_root(n: String, mats: Dictionary, muzzle: Vector3, aim: Vector3) -> Array:
	var root := Node3D.new()
	root.name = n
	root.set_script(load("res://scripts/weapons/view_model.gd"))
	var model: Node3D = _add(root, Node3D.new(), "Model")
	var aim_point: Marker3D = _add(model, Marker3D.new(), "AimPoint")
	aim_point.position = aim
	var m: Marker3D = _add(model, Marker3D.new(), "Muzzle")
	m.position = muzzle
	var flash := QuadMesh.new()
	flash.size = Vector2(0.24, 0.24)
	_part(m, "MuzzleFlash", flash, Vector3(0, 0, -0.06), mats.muzzle_flash)
	var side_flash := QuadMesh.new()
	side_flash.size = Vector2(0.06, 0.2)
	_part(m.get_node("MuzzleFlash"), "SideFlash", side_flash, Vector3(0, 0, -0.04), mats.muzzle_flash, Vector3(0, PI / 2.0, 0))
	var light: OmniLight3D = _add(m, OmniLight3D.new(), "FlashLight")
	light.light_color = Color(1.0, 0.75, 0.45)
	light.light_energy = 2.5
	light.omni_range = 6.0
	light.shadow_enabled = false
	return [root, model]


## Places an imported gun model (glTF) inside a view model's Model node.
## `rear_sight` / `muzzle` are points in the imported model's own coordinates; the model is
## turned (`yaw`) and scaled so that its rear sight lands exactly on the AimPoint.
## Returns the muzzle position in Model coordinates.
func _place_gun_mesh(model: Node3D, gltf: String, yaw: float, scale: float, rear_sight: Vector3, muzzle: Vector3) -> Vector3:
	var mesh: Node3D = load(gltf).instantiate()
	_add(model, mesh, "Mesh")
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	var aim: Vector3 = (model.get_node("AimPoint") as Node3D).position
	mesh.transform = Transform3D(basis, aim - basis * rear_sight)
	return mesh.transform * muzzle


## A hand position on a gun (FirstPersonArms puts a mitten there): `pos` = where the palm
## touches, `fingers` = the way the fingers point, `palm` = the way the palm faces.
## The marker's axes are the hand's own: fingers along -Y, thumb side -Z.
func _grip(parent: Node3D, n: String, pos: Vector3, fingers: Vector3, palm: Vector3, right: bool) -> Marker3D:
	var f: Vector3 = fingers.normalized()
	var p: Vector3 = (palm - f * f.dot(palm)).normalized()
	var x: Vector3 = -p if right else p
	var y: Vector3 = -f
	var m: Marker3D = _add(parent, Marker3D.new(), n)
	m.transform = Transform3D(Basis(x, y, x.cross(y)), pos)
	m.gizmo_extents = 0.03
	return m


## Mosin-Nagant M/28-30 view model: imported "Mosin Nagant M91" model (Doink, CC-BY 4.0).
func _build_mosin_view(mats: Dictionary) -> Node:
	var r := _view_root("MosinViewModel", mats, Vector3.ZERO, Vector3(0, 0.066, -0.16))
	var model: Node3D = r[1]
	# The model is 1.69 m long and points to +z: scale to the real 1.31 m and turn it around.
	var muzzle := _place_gun_mesh(model, "res://assets/models/weapons/mosin/model.gltf", PI, 0.774,
			Vector3(0.0, 0.0645, -0.06), Vector3(0.0, 0.034, 0.85))
	(model.get_node("Muzzle") as Node3D).position = muzzle
	r[0].set("bolt_part_names", PackedStringArray(["LP_BoltHandle", "LP_Bolt_Pigg", "LP_BoltCog", "LP_BoltHammer", "LP_BoltUnderside"]))
	r[0].set("hidden_part_names", PackedStringArray(["LP_Clip", "LP_BulletHolster", "LP_BulletHead"]))
	r[0].set("bolt_travel", 0.09)
	r[0].set("ads_eye_distance", 0.39) # (W1: 0.42; the bolt knob ends 0.31 behind the sight)
	r[0].set("reload_with_right_hand", true) # stripper clips from the pouch
	# Hands: right on the wrist of the stock (finger at the trigger), left under the fore-end,
	# BoltGrip = the bolt knob (the right hand goes there to work the bolt).
	_grip(model, "GripR", Vector3(0.017, -0.025, 0.19), Vector3(-0.3, -0.3, -0.9), Vector3(-1, 0, 0), true)
	_grip(model, "GripL", Vector3(0.0, -0.012, -0.27), Vector3(0.65, 0.3, -0.7), Vector3(0, 1, 0), false)
	_grip(model, "BoltGrip", Vector3(0.05, 0.045, 0.085), Vector3(-0.3, -0.3, -0.9), Vector3(-1, 0, 0), true)
	return r[0]


## Suomi KP/-31 view model: imported "Suomi KP-31" model (soidev, CC-BY 4.0).
func _build_suomi_view(mats: Dictionary) -> Node:
	var r := _view_root("SuomiViewModel", mats, Vector3.ZERO, Vector3(0, 0.076, -0.05))
	var model: Node3D = r[1]
	# The model is in centimetres (92 cm long, real gun 87 cm) and already points to -z.
	var muzzle := _place_gun_mesh(model, "res://assets/models/weapons/suomi/model.gltf", 0.0, 0.0094,
			Vector3(0.0, 9.65, 1.5), Vector3(0.0, 5.9, -46.8))
	(model.get_node("Muzzle") as Node3D).position = muzzle
	r[0].set("hidden_part_names", PackedStringArray(["SuomiKP31_Magazine", "9mm_Case"]))
	r[0].set("ads_eye_distance", 0.35) # (W1: 0.40)
	r[0].set("hip_offset", Vector3(0.0, -0.02, -0.08))
	# The drum: the left hand holds it, and a reload pulls it out, drops it and puts in a new
	# one. The gun is lifted and rolled to the left while reloading so you can see it happen.
	r[0].set("magazine_part_name", "SuomiKP31_Drum")
	r[0].set("reload_offset", Vector3(-0.1, -0.02, 0.0))
	r[0].set("reload_rotation_deg", Vector3(15.0, 10.0, -60.0))
	_grip(model, "GripR", Vector3(0.022, -0.04, 0.1), Vector3(-0.3, -0.3, -0.9), Vector3(-1, 0, 0), true)
	# Left hand under the drum (centre (0, -0.044, -0.145), radius ~0.077), palm up against
	# its rim, fingers forward-right around it.
	_grip(model, "GripL", Vector3(-0.023, -0.121, -0.145), Vector3(0.75, -0.2, -0.55), Vector3(0.3, 1, 0), false)
	return r[0]


func _make_weapon_data() -> void:
	var a := "res://assets/audio/"
	var mosin := WeaponData.new()
	mosin.display_name = "Mosin-Nagant M/28-30"
	mosin.view_model = load("res://scenes/weapons/mosin_viewmodel.tscn")
	mosin.fire_mode = WeaponData.FireMode.BOLT_ACTION
	mosin.bolt_cycle_time = 1.25
	mosin.damage = 100.0
	mosin.max_range_m = 800.0
	mosin.falloff_start_m = 400.0
	mosin.falloff_end_m = 800.0
	mosin.min_damage_multiplier = 0.7
	mosin.noise_radius_m = 150.0
	mosin.suppression = 0.45
	mosin.magazine_size = 5
	mosin.starting_reserve = 30
	mosin.reload_time = 3.0
	mosin.hip_spread_deg = 2.5
	mosin.ads_spread_deg = 0.08
	mosin.move_spread_deg = 3.0
	mosin.recoil_pitch_deg = 4.0
	mosin.recoil_yaw_deg = 0.8
	mosin.recoil_recovery = 0.6
	mosin.recoil_return_speed = 6.0
	mosin.kick_back_m = 0.09
	mosin.kick_rotation_deg = 8.0
	mosin.ads_fov = 45.0
	mosin.ads_time = 0.3
	mosin.ads_move_multiplier = 0.6
	mosin.ads_sensitivity_multiplier = 0.5
	mosin.fire_sound = load(a + "mosin_shot.wav")
	# (no cycle_sound: the generated bolt click was removed – owner. Real recording: bolt_mosin…)
	mosin.recording_name = "mosin" # reload sound: assets/audio/recorded/reload_mosin… (if any)
	mosin.empty_sound = load(a + "empty_click.wav")
	ResourceSaver.save(mosin, "res://resources/weapons/mosin_m28_30.tres")

	var suomi := WeaponData.new()
	suomi.display_name = "Suomi KP/-31"
	suomi.view_model = load("res://scenes/weapons/suomi_viewmodel.tscn")
	suomi.fire_mode = WeaponData.FireMode.FULL_AUTO
	suomi.rounds_per_minute = 850.0
	suomi.damage = 25.0
	suomi.max_range_m = 250.0
	suomi.falloff_start_m = 60.0
	suomi.falloff_end_m = 200.0
	suomi.min_damage_multiplier = 0.5
	suomi.noise_radius_m = 100.0
	suomi.suppression = 0.16
	suomi.magazine_size = 70
	suomi.starting_reserve = 140
	suomi.reload_time = 4.5
	suomi.hip_spread_deg = 3.0
	suomi.ads_spread_deg = 0.3
	suomi.move_spread_deg = 2.0
	suomi.bloom_per_shot_deg = 0.08
	suomi.max_bloom_deg = 1.2
	suomi.bloom_recovery_deg_per_s = 6.0
	suomi.recoil_pitch_deg = 0.9
	suomi.recoil_yaw_deg = 0.6
	suomi.recoil_recovery = 0.7
	suomi.recoil_return_speed = 10.0
	suomi.kick_back_m = 0.025
	suomi.kick_rotation_deg = 2.0
	suomi.ads_fov = 62.0
	suomi.ads_time = 0.2
	suomi.ads_move_multiplier = 0.75
	suomi.ads_sensitivity_multiplier = 0.75
	suomi.fire_sound = load(a + "suomi_shot.wav")
	suomi.recording_name = "suomi"
	suomi.empty_sound = load(a + "empty_click.wav")
	ResourceSaver.save(suomi, "res://resources/weapons/suomi_kp31.tres")

	var maxim := WeaponData.new()
	maxim.display_name = "Maxim M/09-21"
	maxim.fire_mode = WeaponData.FireMode.FULL_AUTO
	maxim.rounds_per_minute = 580.0
	maxim.damage = 100.0
	maxim.max_range_m = 1000.0
	maxim.falloff_start_m = 500.0
	maxim.falloff_end_m = 1000.0
	maxim.min_damage_multiplier = 0.8
	maxim.noise_radius_m = 250.0
	maxim.suppression = 0.3
	maxim.magazine_size = 250 # one cloth belt
	maxim.starting_reserve = 0
	maxim.reload_time = 6.0
	maxim.hip_spread_deg = 0.35
	maxim.ads_spread_deg = 0.2
	maxim.move_spread_deg = 0.0
	maxim.bloom_per_shot_deg = 0.02
	maxim.max_bloom_deg = 0.5
	maxim.bloom_recovery_deg_per_s = 2.0
	maxim.recoil_pitch_deg = 0.25
	maxim.recoil_yaw_deg = 0.15
	maxim.recoil_recovery = 0.9
	maxim.recoil_return_speed = 12.0
	maxim.ads_fov = 50.0
	maxim.ads_time = 0.25
	maxim.ads_sensitivity_multiplier = 0.5
	# Water jacket: ~120 rounds of non-stop fire make it steam, ~390 (two belts) boil it.
	# Short bursts never do (a hot gun cools faster).
	maxim.heat_per_shot = 0.0062
	maxim.cooling_rate = 0.09
	maxim.firing_cooling_multiplier = 0.4
	maxim.steam_heat = 0.6
	maxim.overheat_recover_heat = 0.5
	maxim.fire_sound = load(a + "maxim_shot.wav")
	maxim.recording_name = "maxim"
	maxim.empty_sound = load(a + "empty_click.wav")
	ResourceSaver.save(maxim, "res://resources/weapons/maxim_m09_21.tres")


# ---------------------------------------------------------------- Maxim
## Maxim M/09-21 on its wheeled mount, with a log platform and a step (a small gun nest).
## Imported model "Machine Gun Maxim" by jezusek (CC-BY 4.0), in model units (~1.35 cm).
## The scene origin is at the bottom of the mount; -z points down the barrel.
const MAXIM_SCALE := 0.0135
const MAXIM_MOUNT_BOTTOM := Vector3(0.0, -27.3, 33.0) # model units: under the turning point
const MAXIM_PIVOT := Vector3(0.0, -6.0, 33.0)         # model units: where the gun turns
const MAXIM_BARREL_HEIGHT := 0.338                    # barrel above the scene origin (m)
const MAXIM_BARREL_Y := 0.2                           # barrel height in the level (slit 0.1-0.6)
const MAXIM_EYE := Vector3(0.0, 0.52, 0.8)            # gunner's eye, scene coordinates


## A point given in the imported Maxim model's units → Pivot coordinates (metres).
func _maxim_pivot_point(model_units: Vector3) -> Vector3:
	return (model_units - MAXIM_PIVOT) * MAXIM_SCALE


func _build_maxim(mats: Dictionary) -> Node:
	var gun := StaticBody3D.new()
	gun.name = "MaximMG"
	gun.set_script(load("res://scripts/weapons/mounted_gun.gd"))
	gun.collision_layer = 0b1
	gun.set_meta("surface", "wood")
	gun.set("data", load("res://resources/weapons/maxim_m09_21.tres"))
	gun.set("traverse_left_deg", 21.0)  # L2: the narrow hole (1.1 m outside) allows about +-21 deg
	gun.set("traverse_right_deg", 21.0)
	gun.set("elevation_min_deg", -7.0)
	gun.set("elevation_max_deg", 4.0)
	gun.set("turning_part_names", PackedStringArray(["karabin_001_3", "Zapatka_4", "Cube_0",
		"pocisk_5", "pocisk_001_7", "pocisk_002_8", "pocisk_003_9", "pocisk_004_6", "pocisk_005_11",
		"pocisk_006_10", "pocisk_007_12", "pocisk_008_15", "pocisk_009_16", "pocisk_010_24",
		"pociskpusty_23", "pociskpusty_001_22", "pociskpusty_002_17", "pociskpusty_003_18",
		"pociskpusty_004_19", "pociskpusty_005_20", "pociskpusty_006_21"]))
	gun.set("hidden_part_names", PackedStringArray(["Cube_0"])) # the model's own muzzle flash

	var model: Node3D = _add(gun, load("res://assets/models/weapons/maxim/model.gltf").instantiate(), "Model")
	model.scale = Vector3.ONE * MAXIM_SCALE
	model.position = -MAXIM_MOUNT_BOTTOM * MAXIM_SCALE

	var pivot: Node3D = _add(gun, Node3D.new(), "Pivot")
	pivot.position = (MAXIM_PIVOT - MAXIM_MOUNT_BOTTOM) * MAXIM_SCALE
	var muzzle: Marker3D = _add(pivot, Marker3D.new(), "Muzzle")
	muzzle.position = Vector3(0.0, MAXIM_BARREL_HEIGHT - pivot.position.y, (-21.3 - MAXIM_PIVOT.z) * MAXIM_SCALE)
	var flash := QuadMesh.new()
	flash.size = Vector2(0.3, 0.3)
	_part(muzzle, "MuzzleFlash", flash, Vector3(0, 0, -0.06), mats.muzzle_flash)
	var side_flash := QuadMesh.new()
	side_flash.size = Vector2(0.08, 0.26)
	_part(muzzle.get_node("MuzzleFlash"), "SideFlash", side_flash, Vector3(0, 0, -0.05), mats.muzzle_flash, Vector3(0, PI / 2.0, 0))
	var light: OmniLight3D = _add(muzzle, OmniLight3D.new(), "FlashLight")
	light.light_color = Color(1.0, 0.75, 0.45)
	light.light_energy = 3.0
	light.omni_range = 7.0
	# W2: the eye position for aiming through the sights (on the line rear sight → front sight),
	# the hands on the spade grips, the right hand's place at the feed block (new belt), and
	# where steam leaves the water jacket.
	var eye: Marker3D = _add(pivot, Marker3D.new(), "SightEye")
	eye.position = _maxim_pivot_point(Vector3(0.0, 6.55, 84.0))
	_grip(pivot, "GripR", _maxim_pivot_point(Vector3(5.3, -2.0, 63.0)), Vector3(-0.3, -0.15, -0.95), Vector3(-1, 0, 0), true)
	_grip(pivot, "GripL", _maxim_pivot_point(Vector3(-5.3, -2.0, 63.0)), Vector3(0.3, -0.15, -0.95), Vector3(1, 0, 0), false)
	_grip(pivot, "BeltGrip", _maxim_pivot_point(Vector3(9.5, 3.0, 36.0)), Vector3(-0.4, -0.3, -0.85), Vector3(-1, 0, 0), true)
	var steam: Marker3D = _add(pivot, Marker3D.new(), "SteamPoint")
	steam.position = _maxim_pivot_point(Vector3(0.0, 2.2, 2.0))

	# Where the gunner stands (feet) and where they step off to.
	var seat: Marker3D = _add(gun, Marker3D.new(), "SeatPoint")
	seat.position = MAXIM_EYE - Vector3(0, 1.6, 0) # 1.6 m = standing eye height
	var exit: Marker3D = _add(gun, Marker3D.new(), "ExitPoint")
	var floor_y: float = -DEPTH - (MAXIM_BARREL_Y - MAXIM_BARREL_HEIGHT) # trench floor in scene coordinates
	exit.position = Vector3(1.1, floor_y + 0.05, 1.0)

	# Log platform under the gun and a low step for the gunner.
	_nest_box(gun, "Platform", Vector3(1.0, -floor_y, 1.2), Vector3(0.05, floor_y / 2.0, 0.0), mats.nest_log)
	var step_h: float = seat.position.y - floor_y
	_nest_box(gun, "Step", Vector3(0.8, step_h, 0.6), Vector3(0.0, floor_y + step_h / 2.0, seat.position.z), mats.nest_log)
	# The gun itself stops bullets (the shield!), roughly.
	var gun_shape: CollisionShape3D = _add(gun, CollisionShape3D.new(), "GunCollision")
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, 0.42, 1.1)
	gun_shape.shape = box
	gun_shape.position = Vector3(0.0, MAXIM_BARREL_HEIGHT, -0.05)

	var shot_audio: AudioStreamPlayer3D = _add(gun, AudioStreamPlayer3D.new(), "ShotAudio")
	shot_audio.position = muzzle.position
	shot_audio.max_polyphony = 6
	shot_audio.unit_size = 30.0
	shot_audio.bus = &"SFX"
	var mech_audio: AudioStreamPlayer3D = _add(gun, AudioStreamPlayer3D.new(), "MechAudio")
	mech_audio.unit_size = 6.0
	mech_audio.bus = &"SFX"
	var steam_audio: AudioStreamPlayer3D = _add(gun, AudioStreamPlayer3D.new(), "SteamAudio")
	steam_audio.stream = load("res://assets/audio/steam_hiss.wav")
	steam_audio.position = steam.position + pivot.position
	steam_audio.unit_size = 4.0
	steam_audio.bus = &"SFX"
	var sync: MultiplayerSynchronizer = _add(gun, MultiplayerSynchronizer.new(), "GunSync")
	sync.root_path = NodePath("..")
	sync.delta_interval = 0.1 # heat changes every frame: 10 updates a second are plenty
	sync.replication_config = _sync_config([
		[".:user_id", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:ammo", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:is_reloading", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:heat", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:is_overheated", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
	])
	return gun


## A log box (mesh + collision) for the gun nest.
func _nest_box(body: Node3D, n: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	_part(body, n + "Mesh", _box(size), pos, mat)
	var cs: CollisionShape3D = _add(body, CollisionShape3D.new(), n + "Collision")
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos


# ---------------------------------------------------------------- shooting range target
func _build_target_dummy(mats: Dictionary) -> Node:
	DirAccess.make_dir_recursive_absolute("res://scenes/props")
	var root := Node3D.new()
	root.name = "TargetDummy"
	root.set_script(load("res://scripts/world/target_dummy.gd"))
	_part(root, "Foot", _box(Vector3(0.9, 0.12, 0.18)), Vector3(0, 0.06, 0), mats.target_wood)
	var body: AnimatableBody3D = _add(root, AnimatableBody3D.new(), "Body")
	body.sync_to_physics = false
	body.collision_layer = 0b1
	body.set_meta("surface", "wood")
	body.set_meta("attach_holes", true) # bullet holes stay on it when it falls over
	_part(body, "Post", _box(Vector3(0.1, 1.0, 0.1)), Vector3(0, 0.5, 0), mats.target_wood)
	_part(body, "Torso", _box(Vector3(0.5, 0.65, 0.1)), Vector3(0, 1.25, 0), mats.target_cloth)
	_part(body, "Head", _box(Vector3(0.24, 0.26, 0.1)), Vector3(0, 1.73, 0), mats.target_cloth)
	for part in [[Vector3(0.1, 1.0, 0.1), Vector3(0, 0.5, 0)], [Vector3(0.5, 0.65, 0.1), Vector3(0, 1.25, 0)], [Vector3(0.24, 0.26, 0.1), Vector3(0, 1.73, 0)]]:
		var cs: CollisionShape3D = _add(body, CollisionShape3D.new(), "Shape")
		var box := BoxShape3D.new()
		box.size = part[0]
		cs.shape = box
		cs.position = part[1]
	var label: Label3D = _add(root, Label3D.new(), "DistanceLabel")
	label.text = "? m"
	label.position = Vector3(0, 2.3, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.01
	label.modulate = Color(0.15, 0.15, 0.15)
	label.outline_size = 0
	var sync: MultiplayerSynchronizer = _add(root, MultiplayerSynchronizer.new(), "DummySync")
	sync.root_path = NodePath("..")
	sync.replication_config = _sync_config([[".:is_down", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE]])
	return root


# ---------------------------------------------------------------- enemies
## G1: Easy / Normal / Hard (resources/difficulty/*.tres – tune them in the Inspector).
## Every difficulty has 10 waves (owner). What each wave is made of: [riflemen, officers,
## machine-gun teams, artillery barrage first (1/0)]. Barrage waves have an officer (he whistles
## when it lifts). Easy = Normal with fewer riflemen; officers, MG teams and barrages the same.
## [riflemen, officers, MG teams, barrage (1 = yes), tanks] per wave (T3: tanks owner's choice:
## one in battles 4–8, two in 9–10, the same on every difficulty).
const WAVE_LISTS := {
	"Easy": [[4, 0, 0, 0, 0], [4, 1, 0, 0, 0], [4, 0, 1, 0, 0], [5, 1, 1, 1, 1], [5, 1, 1, 0, 1], [5, 2, 1, 1, 1], [6, 1, 2, 0, 1], [6, 2, 2, 1, 1],
		[7, 2, 2, 0, 2], [7, 2, 2, 1, 2]],
	"Normal": [[6, 0, 0, 0, 0], [7, 1, 0, 0, 0], [7, 0, 1, 0, 0], [8, 1, 1, 1, 1], [9, 1, 1, 0, 1], [9, 2, 1, 1, 1], [10, 1, 2, 0, 1], [10, 2, 2, 1, 1],
		[11, 2, 2, 0, 2], [12, 2, 2, 1, 2]],
	"Hard": [[8, 0, 0, 0, 0], [9, 1, 0, 0, 0], [9, 1, 1, 1, 0], [10, 1, 1, 0, 1], [11, 2, 1, 1, 1], [11, 1, 2, 0, 1], [12, 2, 2, 1, 1], [13, 2, 2, 0, 1],
		[14, 2, 2, 1, 2], [15, 3, 3, 0, 2]],
}


func _make_difficulty_data() -> void:
	DirAccess.make_dir_recursive_absolute("res://resources/difficulty")
	# name, waves to win, trench limit, wave 1 size, added per wave, enemy spread ×, respawn s,
	# enemy damage ×
	for d in [["Easy", 10, 6, 4, 1, 1.4, 5.0, 0.6], ["Normal", 10, 4, 6, 2, 1.0, 5.0, 1.0],
			["Hard", 10, 3, 8, 2, 0.75, 10.0, 1.0]]:
		var r := DifficultyData.new()
		r.display_name = d[0]
		r.waves_to_win = d[1]
		r.trench_limit = d[2]
		r.base_enemies = d[3]
		r.enemies_added_per_wave = d[4]
		r.enemy_spread_multiplier = d[5]
		r.respawn_time = d[6]
		r.enemy_damage_multiplier = d[7]
		var waves: Array[WaveData] = []
		for w: Array in WAVE_LISTS[d[0]]:
			waves.append(WaveData.new().make(w[0], w[1], w[2], w[3] == 1, w[4]))
		r.waves = waves
		ResourceSaver.save(r, "res://resources/difficulty/%s.tres" % (d[0] as String).to_lower())


## The owner's ten Finnish front reports (21.12.1939 … 01.01.1940), shown after each cleared
## battle until B1. NOT shown any more (the battles now have real dates), kept here unchanged –
## never reword. [date, text, SA-kuva photo].
const OLD_FRONT_REPORTS := [
	["21.12.1939", "\"Täällä Kannaksen rintama. Summan suunnalla on havaittu vihollisen tiedustelu- ja jalkaväkiosastoja. Etumaastossa on käyty päivän aikana tulitaisteluita. Puolustusasemamme ovat säilyneet lujina.\"", "sa_kuva_144612"],
	["22.12.1939", "\"Täällä Kannaksen rintama. Summan lohkolla vihollinen on lisännyt hyökkäystoimintaansa ja tuonut uusia joukkoja etulinjaan. Useat etenemisyritykset on torjuttu. Joukkojen mieliala on hyvä.\"", "sa_kuva_117623"],
	["23.12.1939", "\"Rintamatiedotus Kannakselta. Summan suunnalla vihollinen on tukenut hyökkäyksiään voimakkaalla konekivääritulella. Kovista hyökkäyksistä huolimatta asemamme ovat edelleen hallussamme.\"", "sa_kuva_a_4"],
	["24.12.1939", "\"Täällä Kannaksen rintama. Vihollinen on valmistellut hyökkäyksiään voimakkaalla tykistötulella sekä konekivääriosastojen tukemana. Puolustajat jatkavat tehtävissään asemissaan.\"", "sa_kuva_a_511"],
	["25.12.1939", "\"Rintamatiedotus Summasta. Vihollinen jatkaa painostusta koko lohkolla. Konekiväärien tukemat hyökkäykset on torjuttu, eikä asemissamme ole tapahtunut muutoksia.\"", "sa_kuva_a_126"],
	["26.12.1939", "\"Täällä Kannaksen rintama. Vihollisen on havaittu keskittävän uusia joukkoja Summan eteen. Tykistötoiminta on jatkunut vilkkaana. Puolustusvalmisteluja jatketaan kaikilla osastoilla.\"", "sa_kuva_a_125"],
	["27.12.1939", "\"Rintamatiedotus Summan lohkolta. Vihollinen on lisännyt konekivääriosastojen käyttöä hyökkäystensä tukena. Päivän taistelut ovat päättyneet puolustajiemme onnistuneeseen torjuntaan.\"", "sa_kuva_a_8"],
	["28.12.1939", "\"Täällä Kannaksen rintama. Vihollinen on pyrkinyt murtamaan puolustusta voimakkaalla tykistötulella ja useilla jalkaväkihyökkäyksillä. Joukkomme pitävät edelleen asemansa.\"", "sa_kuva_a_123"],
	["31.12.1939", "\"Rintamatiedotus Summasta. Vihollinen jatkaa joukkojensa keskittämistä hyökkäysalueelle. Taistelutoiminta on ollut vilkasta, mutta puolustuslinjamme kestää edelleen.\"", "sa_kuva_144607"],
	["01.01.1940", "\"Täällä Kannaksen rintama. Vihollinen on tehostanut hyökkäyksiään Summan lohkolla tykistön ja suurten jalkaväkivoimien tukemana. Kaikista hyökkäyksistä huolimatta asemamme ovat säilyneet hallussamme. Puolustajien taistelutahto on horjumaton.\"", "sa_kuva_a_129"],
]


## The ten battles (B1): real dates, weather and the briefing, shown BEFORE each battle (loading
## screen for battle 1, the day screen after each cleared battle for the next one).
## [date, weather lines, briefing text, SA-kuva photo in assets/photos/ (CC BY 4.0)].
## Battle 9's text is a copy of battle 8's until the owner writes his own.
const MISSIONS := [
	["30 November 1939", "Weather: Light Snowfall",
		"Soviet forces have crossed the border. All units are ordered to battle stations. Prepare the defenses and repel enemy reconnaissance patrols.", "sa_kuva_144612"],
	["17 December 1939", "Weather: Heavy Snowfall\nVisibility: Poor",
		"After hours of artillery fire, Soviet infantry and tanks are advancing against the line. Hold your position at all costs.", "sa_kuva_117623"],
	["19 December 1939", "Weather: Clear and Bitterly Cold",
		"Enemy armor has broken through the obstacles. Finnish defenders must stop the tanks before the breach widens.", "sa_kuva_a_4"],
	["22 December 1939", "Weather: Clear Skies",
		"Days of relentless attacks have failed to break the line. One more assault is expected before the enemy withdraws.", "sa_kuva_a_511"],
	["1 February 1940", "Weather: Snow and Artillery Smoke",
		"The Soviet artillery barrage has begun. Shells rain down across the front as the enemy prepares a new offensive.", "sa_kuva_a_126"],
	["6 February 1940", "Weather: Overcast",
		"Enemy attacks continue day and night. Ammunition is running low and casualties are mounting.", "sa_kuva_a_125"],
	["11 February 1940", "Weather: Dense Fog\nTemperature: ~−20°C",
		"The largest offensive of the war has begun. Hundreds of guns support waves of infantry and tanks. Hold the line.", "sa_kuva_a_8"],
	["12 February 1940", "Weather: Fog Clearing",
		"Enemy forces have broken into key defensive positions. Delay the advance while neighboring units withdraw.", "sa_kuva_a_123"],
	["13 February 1940", "Weather: Low Cloud and Fog\nVisibility: Moderate",
		"Enemy forces have broken into key defensive positions. Delay the advance while neighboring units withdraw.", "sa_kuva_144607"],
	["15 February 1940", "Weather: Dusk",
		"Orders have arrived. Summa must be abandoned. Hold long enough for the remaining troops and wounded to escape.", "sa_kuva_a_129"],
]


func _make_front_reports() -> void:
	var r := FrontReports.new()
	var dates := PackedStringArray()
	var texts := PackedStringArray()
	var weathers := PackedStringArray()
	var photos := PackedStringArray()
	for m: Array in MISSIONS:
		dates.append(m[0])
		weathers.append(m[1])
		texts.append(m[2])
		photos.append("res://assets/photos/%s.jpg" % m[3] if m.size() > 3 else "")
	r.dates = dates
	r.texts = texts
	r.weathers = weathers
	r.photos = photos
	ResourceSaver.save(r, "res://resources/front_reports.tres")


## G1: two ammo boxes with a first-aid tin on top (F = refill spare ammo and bandages).
func _build_ammo_crate(mats: Dictionary) -> Node:
	var c := StaticBody3D.new()
	c.name = "AmmoCrate"
	c.set_script(load("res://scripts/world/ammo_crate.gd"))
	c.collision_layer = 0b1
	c.set_meta("surface", "wood")
	_part(c, "BoxLower", _box(Vector3(0.74, 0.3, 0.42)), Vector3(0, 0.15, 0), mats.crate_wood)
	_part(c, "BoxUpper", _box(Vector3(0.74, 0.3, 0.42)), Vector3(0.03, 0.455, -0.01), mats.crate_wood, Vector3(0, 0.12, 0))
	_part(c, "FirstAidTin", _box(Vector3(0.26, 0.11, 0.18)), Vector3(-0.12, 0.665, 0.0), mats.tin_white, Vector3(0, -0.2, 0))
	var cross: MeshInstance3D = _part(c.get_node("FirstAidTin"), "Cross", _box(Vector3(0.13, 0.004, 0.04)), Vector3(0, 0.056, 0), mats.cross_red)
	_part(cross, "Bar", _box(Vector3(0.04, 0.004, 0.13)), Vector3.ZERO, mats.cross_red)
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var cs: CollisionShape3D = _add(c, CollisionShape3D.new(), "CollisionShape3D")
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.78, 0.72, 0.46)
	cs.shape = shape
	cs.position = Vector3(0, 0.36, 0)
	return c


## T2: a wooden box with six Molotov cocktails (bottles with rags) standing in it.
## Three draw calls: the box, all bottles (one MultiMesh), all rags (one MultiMesh).
func _build_molotov_crate(mats: Dictionary) -> Node:
	var c := StaticBody3D.new()
	c.name = "MolotovCrate"
	c.set_script(load("res://scripts/world/molotov_crate.gd"))
	c.collision_layer = 0b1
	c.set_meta("surface", "wood")
	var box: MeshInstance3D = _part(c, "Box", _box(Vector3(0.62, 0.2, 0.4)), Vector3(0, 0.1, 0), mats.crate_wood)
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# One bottle mesh = body + neck (merged), the rag separately.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := _cyl(0.038, 0.19)
	st.append_from(body, 0, Transform3D(Basis(), Vector3(0, 0.095, 0)))
	var neck := _cyl(0.016, 0.1)
	st.append_from(neck, 0, Transform3D(Basis(), Vector3(0, 0.22, 0)))
	st.generate_normals()
	var bottle_mesh: ArrayMesh = st.commit()
	bottle_mesh.surface_set_material(0, mats.bottle_glass)
	var rag_mesh := _box(Vector3(0.035, 0.08, 0.02))
	rag_mesh.material = mats.rag_cloth
	var spots: Array[Transform3D] = []
	for i in 6:
		var x: float = -0.18 + (i % 3) * 0.18
		var z: float = -0.09 if i < 3 else 0.09
		spots.append(Transform3D(Basis(Vector3.UP, i * 1.3), Vector3(x, 0.06, z)))
	for part: Array in [["Bottles", bottle_mesh, Transform3D()],
			["Rags", rag_mesh, Transform3D(Basis(Vector3.BACK, -0.5), Vector3(0.012, 0.28, 0))]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[1]
		mm.instance_count = spots.size()
		for i in spots.size():
			mm.set_instance_transform(i, spots[i] * (part[2] as Transform3D))
		var mmi: MultiMeshInstance3D = _add(c, MultiMeshInstance3D.new(), part[0])
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for gi in c.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 70.0 # small: not drawn from far away
	var cs: CollisionShape3D = _add(c, CollisionShape3D.new(), "CollisionShape3D")
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.64, 0.42, 0.42)
	cs.shape = shape
	cs.position = Vector3(0, 0.21, 0)
	return c


func _make_enemy_data() -> void:
	DirAccess.make_dir_recursive_absolute("res://resources/enemies")
	var d := EnemyData.new() # defaults from enemy_data.gd
	ResourceSaver.save(d, "res://resources/enemies/soviet_rifleman.tres")

	# G2: the officer – TT pistol (only close up), steadier, whistles his men forward.
	var o := EnemyData.new()
	o.display_name = "Soviet officer"
	o.kind = EnemyData.Kind.OFFICER
	o.fire_sound = load("res://assets/audio/suomi_shot.wav")
	o.fire_sound_pitch = 1.3
	o.damage = 25.0
	o.max_fire_distance_m = 45.0
	o.fire_interval_min = 1.0
	o.fire_interval_max = 1.8
	o.trench_fire_interval_min = 0.8
	o.trench_fire_interval_max = 1.4
	o.base_spread_deg = 3.0
	o.spread_per_100m_deg = 6.0
	o.nerve = 0.7
	ResourceSaver.save(o, "res://resources/enemies/soviet_officer.tres")

	# G2: DP-27 gunner – lies down within range and fires bursts; never rushes the trench.
	var g := EnemyData.new()
	g.display_name = "Soviet machine-gunner (DP-27)"
	g.kind = EnemyData.Kind.MG_GUNNER
	g.fire_sound = load("res://assets/audio/maxim_shot.wav") # placeholder until a dp27… recording
	g.fire_sound_pitch = 1.12
	g.fire_sound_recording = "dp27"
	g.walk_speed = 2.2
	g.hurry_speed = 3.0
	g.damage = 30.0
	g.base_spread_deg = 1.6
	g.spread_per_100m_deg = 1.0
	g.moving_target_spread_deg = 1.0
	g.first_shot_multiplier = 1.5
	g.full_aim_time = 3.0
	g.reaction_time_min = 1.0
	g.reaction_time_max = 1.8
	g.shot_noise_radius_m = 200.0
	g.nerve = 0.85
	ResourceSaver.save(g, "res://resources/enemies/soviet_mg_gunner.tres")


func _build_enemy(mats: Dictionary, data_name := "soviet_rifleman", node_name := "SovietRifleman") -> Node:
	DirAccess.make_dir_recursive_absolute("res://scenes/enemies")
	var e := CharacterBody3D.new()
	e.name = node_name
	e.set_script(load("res://scripts/enemies/enemy.gd"))
	e.set("data", load("res://resources/enemies/%s.tres" % data_name))
	e.collision_layer = 0b100   # layer 3: enemies
	e.collision_mask = 0b011    # world + players (soldiers pass through each other)
	e.floor_max_angle = deg_to_rad(46.0)
	e.floor_snap_length = 0.4
	e.set_meta("surface", "cloth")

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.33
	capsule.height = 1.8
	var cs: CollisionShape3D = _add(e, CollisionShape3D.new(), "CollisionShape3D")
	cs.shape = capsule
	cs.position.y = 0.9

	# The body is built and animated in code (scripts/enemies/soldier_visual.gd + soldier_mesh.gd).
	var visual: Node3D = _add(e, Node3D.new(), "Visual")
	visual.set_script(load("res://scripts/enemies/soldier_visual.gd"))
	visual.set("material", mats.soldier)

	var eyes: Marker3D = _add(e, Marker3D.new(), "Eyes")
	eyes.position = Vector3(0, 1.6, -0.1)

	var agent: NavigationAgent3D = _add(e, NavigationAgent3D.new(), "NavigationAgent3D")
	agent.radius = 0.5
	agent.height = 2.0
	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.5
	agent.avoidance_enabled = false

	var audio: AudioStreamPlayer3D = _add(e, AudioStreamPlayer3D.new(), "ShotAudio")
	audio.stream = load("res://assets/audio/mosin_shot.wav")
	audio.bus = &"SFX"
	audio.unit_size = 30.0
	audio.volume_db = -2.0
	audio.max_polyphony = 2
	# Far-away shots lose their sharp high tones: you can hear roughly how far the shooter is.
	audio.attenuation_filter_cutoff_hz = 2500.0
	audio.attenuation_filter_db = -30.0
	audio.position = Vector3(0, 1.4, 0)

	var label: Label3D = _add(e, Label3D.new(), "DebugLabel")
	label.position = Vector3(0, 2.3, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.font_size = 32
	label.outline_size = 8
	label.no_depth_test = true
	label.visible = false

	var sync: MultiplayerSynchronizer = _add(e, MultiplayerSynchronizer.new(), "StateSync")
	sync.root_path = NodePath("..")
	var ALWAYS := SceneReplicationConfig.REPLICATION_MODE_ALWAYS
	var ON_CHANGE := SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
	sync.replication_config = _sync_config([
		[".:position", true, ALWAYS],
		[".:rotation", true, ALWAYS],
		[".:state", true, ON_CHANGE],
		[".:is_kneeling", true, ON_CHANGE],
		[".:is_prone", true, ON_CHANGE],
		[".:health", true, ON_CHANGE],
	])
	return e


# ---------------------------------------------------------------- UI
func _flat(bg: Color, border := Color(0, 0, 0, 0), border_w := 0, radius := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## A simple shared look for menus: dark translucent buttons with a thin frosty border.
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_stylebox("normal", "Button", _flat(Color(0.07, 0.09, 0.12, 0.78), Color(0.8, 0.86, 0.92, 0.45), 1))
	t.set_stylebox("hover", "Button", _flat(Color(0.16, 0.2, 0.26, 0.92), Color(1, 1, 1, 0.9), 1))
	t.set_stylebox("pressed", "Button", _flat(Color(0.25, 0.3, 0.37, 0.95), Color(1, 1, 1), 1))
	t.set_stylebox("disabled", "Button", _flat(Color(0.07, 0.09, 0.12, 0.4), Color(0.6, 0.65, 0.7, 0.25), 1))
	var focus := _flat(Color(0, 0, 0, 0), Color(1, 1, 1, 0.9), 2)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Color(0.93, 0.95, 0.98))
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.58, 0.62))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 4)
	t.set_stylebox("panel", "PanelContainer", _flat(Color(0.05, 0.07, 0.1, 0.88), Color(0.8, 0.86, 0.92, 0.35), 1, 4))
	ResourceSaver.save(t, "res://ui/winter_theme.tres")
	return load("res://ui/winter_theme.tres")


func _label(parent: Node, n: String, text: String, size: int, align := HORIZONTAL_ALIGNMENT_LEFT, color := Color(0.95, 0.97, 1.0)) -> Label:
	var l: Label = _add(parent, Label.new(), n)
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(size / 5, 3))
	return l


func _full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


func _bar(parent: Node, n: String, fill: Color, min_size: Vector2) -> ProgressBar:
	var b: ProgressBar = _add(parent, ProgressBar.new(), n)
	b.custom_minimum_size = min_size
	b.show_percentage = false
	b.max_value = 100
	b.value = 100
	var bg := _flat(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.25), 1, 2)
	bg.content_margin_left = 0
	bg.content_margin_right = 0
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
	var fg := _flat(fill, Color(0, 0, 0, 0), 0, 2)
	fg.content_margin_left = 0
	fg.content_margin_right = 0
	fg.content_margin_top = 0
	fg.content_margin_bottom = 0
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


## "A new day" between waves (DayScreen): black screen, an SA-kuva photo as an old print on the
## left, the date at the top and the front report as a TELEGRAM on the right (typewriter letters,
## FreeMono Bold, typed out one by one by the script), radio static at the start.
func _build_day_screen(hud: Node) -> void:
	var tele_font: Font = load("res://assets/fonts/FreeMonoBold.ttf")
	var ink := Color(0.16, 0.12, 0.09)
	var ds: Control = _add(hud, Control.new(), "DayScreen")
	ds.set_script(load("res://scripts/ui/day_screen.gd"))
	_full_rect(ds)
	ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var black: ColorRect = _add(ds, ColorRect.new(), "Black")
	black.color = Color(0.025, 0.025, 0.03, 1.0)
	_full_rect(black)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Everything else hangs from the screen centre, so a wider window only adds black at the sides.
	var content: Control = _add(ds, Control.new(), "Content")
	content.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title: VBoxContainer = _add(content, VBoxContainer.new(), "Title")
	title.position = Vector2(-500, -330)
	title.size = Vector2(1000, 90)
	title.add_theme_constant_override("separation", 2)
	var day := _label(title, "Day", "T A I S T E L U   1", 18, HORIZONTAL_ALIGNMENT_CENTER, Color(0.78, 0.74, 0.66))
	var date := _label(title, "Date", "21. joulukuuta 1939", 40, HORIZONTAL_ALIGNMENT_CENTER, Color(0.95, 0.92, 0.85))
	date.add_theme_font_override("font", tele_font)

	# The photo as an old print: off-white border, a shadow, laid down a little crooked.
	var pf: PanelContainer = _add(content, PanelContainer.new(), "PhotoFrame")
	var print_style := _flat(Color(0.88, 0.86, 0.8), Color(0, 0, 0, 0), 0, 1)
	for side in ["left", "right", "top", "bottom"]:
		print_style.set("content_margin_" + side, 12)
	print_style.shadow_color = Color(0, 0, 0, 0.6)
	print_style.shadow_size = 10
	print_style.shadow_offset = Vector2(4, 5)
	pf.add_theme_stylebox_override("panel", print_style)
	pf.rotation = deg_to_rad(0.7)
	pf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clip: Control = _add(pf, Control.new(), "Clip")
	clip.clip_contents = true # the slow zoom stays inside the print
	clip.custom_minimum_size = Vector2(600, 420)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var photo: TextureRect = _add(clip, TextureRect.new(), "Photo")
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_SCALE
	photo.size = Vector2(600, 420)
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var photo_mat := ShaderMaterial.new()
	photo_mat.shader = load("res://resources/shaders/old_photo.gdshader")
	photo.material = photo_mat
	var credit := _label(content, "Credit", "Kuva: SA-kuva", 14, HORIZONTAL_ALIGNMENT_LEFT, Color(0.62, 0.6, 0.56))
	credit.size = Vector2(600, 20)

	var fr: PanelContainer = _add(content, PanelContainer.new(), "Telegram")
	fr.position = Vector2(50, -140)
	fr.size = Vector2(530, 0)
	fr.pivot_offset = Vector2(265, 150)
	fr.rotation = deg_to_rad(-0.8)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := _flat(Color(0.93, 0.88, 0.74, 0.98), Color(0.55, 0.45, 0.3, 0.9), 1, 2)
	paper.content_margin_left = 28
	paper.content_margin_right = 28
	paper.content_margin_top = 16
	paper.content_margin_bottom = 20
	paper.shadow_color = Color(0, 0, 0, 0.5)
	paper.shadow_size = 8
	paper.shadow_offset = Vector2(3, 4)
	fr.add_theme_stylebox_override("panel", paper)
	var fr_v: VBoxContainer = _add(fr, VBoxContainer.new(), "VBox")
	fr_v.add_theme_constant_override("separation", 6)
	var head := _label(fr_v, "Header", "S Ä H K Ö S A N O M A", 24, HORIZONTAL_ALIGNMENT_CENTER, ink)
	var rule: ColorRect = _add(fr_v, ColorRect.new(), "Rule")
	rule.color = Color(ink, 0.7)
	rule.custom_minimum_size = Vector2(0, 2)
	var fr_d := _label(fr_v, "Date", "21.12.1939", 19, HORIZONTAL_ALIGNMENT_RIGHT, ink)
	var fr_t := _label(fr_v, "Text", "", 18, HORIZONTAL_ALIGNMENT_LEFT, ink)
	fr_t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fr_t.custom_minimum_size = Vector2(474, 0)
	for l: Label in [head, fr_d, fr_t]:
		l.add_theme_font_override("font", tele_font)
		l.add_theme_constant_override("outline_size", 0)
		# Letters appear one by one, but the lines are laid out for the whole text from the start.
		l.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	fr_t.add_theme_constant_override("line_spacing", 2)
	var tick_snd: AudioStreamPlayer = _add(fr, AudioStreamPlayer.new(), "TypeSound")
	tick_snd.bus = &"UI" # (no stream: a real recording assets/audio/recorded/telegraph…, if any)
	tick_snd.volume_db = -6.0

	var hint := _label(content, "Hint", "[Välilyönti] Jatka", 16, HORIZONTAL_ALIGNMENT_CENTER, Color(0.75, 0.73, 0.68))
	hint.position = Vector2(-300, 300)
	hint.size = Vector2(600, 24)
	var noise: AudioStreamPlayer = _add(ds, AudioStreamPlayer.new(), "Static")
	noise.bus = &"UI" # (no stream: a real recording assets/audio/recorded/radio_static…, if any)
	ds.visible = false


func _build_hud(theme: Theme) -> Node:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://scripts/ui/hud.gd"))

	var cross: Control = _add(hud, Control.new(), "Crosshair")
	cross.set_script(load("res://scripts/ui/crosshair.gd"))
	_full_rect(cross)
	var dmg: Control = _add(hud, Control.new(), "DamageIndicator")
	dmg.set_script(load("res://scripts/ui/damage_indicator.gd"))
	_full_rect(dmg)
	var marker: Control = _add(hud, Control.new(), "HitMarker")
	marker.set_script(load("res://scripts/ui/hit_marker.gd"))
	_full_rect(marker)

	# Red edges when hurt: a radial gradient, transparent in the middle.
	var flash: TextureRect = _add(hud, TextureRect.new(), "DamageFlash")
	_full_rect(flash)
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.6, 0.0, 0.0, 0.8))
	g.add_point(0.55, Color(0.6, 0.0, 0.0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 128
	gt.height = 128
	flash.texture = gt
	flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flash.stretch_mode = TextureRect.STRETCH_SCALE

	# Bottom left: health and stamina.
	var vitals: VBoxContainer = _add(hud, VBoxContainer.new(), "Vitals")
	vitals.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	vitals.offset_left = 24
	vitals.offset_top = -100
	vitals.offset_right = 304
	vitals.offset_bottom = -24
	vitals.add_theme_constant_override("separation", 6)
	_label(vitals, "HealthTitle", "HEALTH", 13, HORIZONTAL_ALIGNMENT_LEFT, Color(0.85, 0.88, 0.92))
	var hb := _bar(vitals, "HealthBar", Color(0.7, 0.13, 0.1, 0.95), Vector2(280, 24))
	var hv := _label(hb, "Value", "100", 16, HORIZONTAL_ALIGNMENT_CENTER)
	_full_rect(hv)
	hv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar(vitals, "StaminaBar", Color(0.78, 0.87, 0.96, 0.9), Vector2(280, 7))
	var bandages := _label(vitals, "Bandages", "Bandages: 2   [B]", 14, HORIZONTAL_ALIGNMENT_LEFT, Color(0.95, 0.88, 0.86))
	vitals.move_child(bandages, 0)

	# Bottom right: weapon and ammo.
	var wp: VBoxContainer = _add(hud, VBoxContainer.new(), "WeaponPanel")
	wp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	wp.offset_left = -344
	wp.offset_top = -140
	wp.offset_right = -24
	wp.offset_bottom = -24
	wp.alignment = BoxContainer.ALIGNMENT_END
	wp.add_theme_constant_override("separation", 0)
	_label(wp, "Reloading", "RELOADING", 16, HORIZONTAL_ALIGNMENT_RIGHT, Color(1.0, 0.8, 0.35))
	_label(wp, "Overheated", "OVERHEATED", 18, HORIZONTAL_ALIGNMENT_RIGHT, Color(1.0, 0.45, 0.3))
	_label(wp, "WeaponName", "Weapon", 18, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.88, 0.91, 0.95))
	_label(wp, "Ammo", "0 / 0", 36, HORIZONTAL_ALIGNMENT_RIGHT)
	# Maxim water-jacket heat (hidden for the hand weapons).
	var heat_row: HBoxContainer = _add(wp, HBoxContainer.new(), "HeatRow")
	heat_row.alignment = BoxContainer.ALIGNMENT_END
	_label(heat_row, "HeatTitle", "HEAT", 13, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.85, 0.88, 0.92))
	var heat_bar := _bar(heat_row, "HeatBar", Color(0.95, 0.95, 0.95, 0.9), Vector2(180, 8))
	heat_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heat_bar.max_value = 1.0
	heat_bar.step = 0.0
	heat_bar.value = 0.0

	# Top centre: wave information and score.
	var wv: VBoxContainer = _add(hud, VBoxContainer.new(), "WavePanel")
	wv.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	wv.offset_left = -220
	wv.offset_right = 220
	wv.offset_top = 14
	wv.offset_bottom = 150
	wv.add_theme_constant_override("separation", 0)
	_label(wv, "Wave", "Get ready", 24, HORIZONTAL_ALIGNMENT_CENTER)
	_label(wv, "Enemies", "Enemies: 0", 16, HORIZONTAL_ALIGNMENT_CENTER, Color(0.88, 0.91, 0.95))
	_label(wv, "NextWave", "", 16, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.85, 0.5))
	_label(wv, "Score", "Kills 0   Deaths 0", 14, HORIZONTAL_ALIGNMENT_CENTER, Color(0.8, 0.84, 0.9))
	var alert := _label(wv, "TrenchAlert", "", 20, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.42, 0.32))
	alert.visible = false
	var tag := _label(wv, "TestTag", "TEST MODE", 13, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.8, 0.3))
	tag.visible = false

	# Centre, below the crosshair: "[F] Use Maxim".
	var prompt := _label(hud, "InteractPrompt", "", 17, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.92, 0.7))
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.offset_top = 150
	prompt.offset_bottom = 180

	var banner := _label(hud, "WaveBanner", "BATTLE 1", 60, HORIZONTAL_ALIGNMENT_CENTER)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.offset_left = -300
	banner.offset_right = 300
	banner.offset_top = -170
	banner.offset_bottom = -90
	var sub := _label(hud, "WaveBannerSub", "", 24, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.92, 0.75))
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub.offset_left = -400
	sub.offset_right = 400
	sub.offset_top = -90
	sub.offset_bottom = -56

	# Artillery: "ARTILLERY! GET DOWN INTO THE TRENCH!" (top centre, read by hud.gd).
	var arty_l := _label(hud, "ArtilleryWarning", "", 30, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.45, 0.3))
	arty_l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	arty_l.offset_left = -450
	arty_l.offset_right = 450
	arty_l.offset_top = 128
	arty_l.offset_bottom = 172
	arty_l.add_theme_constant_override("outline_size", 6)
	arty_l.visible = false

	# The first battle with tanks (after its banner): where the Molotov cocktails are and how to use them (hud.gd).
	var tank_hint := _label(hud, "TankHint", "", 20, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.92, 0.75))
	tank_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	tank_hint.offset_left = -480 # where the BATTLE n banner was: it shows once the banner is gone
	tank_hint.offset_right = 480
	tank_hint.offset_top = -175
	tank_hint.offset_bottom = -40
	tank_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tank_hint.add_theme_constant_override("outline_size", 6)
	tank_hint.visible = false

	hud.set("front_reports", load("res://resources/front_reports.tres"))

	# Death screen.
	var ds: Control = _add(hud, Control.new(), "DeathScreen")
	_full_rect(ds)
	var dim: ColorRect = _add(ds, ColorRect.new(), "Dim")
	dim.color = Color(0.08, 0.0, 0.0, 0.55)
	_full_rect(dim)
	var died := _label(ds, "YouDied", "YOU DIED", 64, HORIZONTAL_ALIGNMENT_CENTER, Color(0.95, 0.85, 0.82))
	died.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	died.offset_left = -300
	died.offset_right = 300
	died.offset_top = -70
	died.offset_bottom = 10
	var rl := _label(ds, "Respawn", "Respawning in 5...", 24, HORIZONTAL_ALIGNMENT_CENTER)
	rl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rl.offset_left = -300
	rl.offset_right = 300
	rl.offset_top = 16
	rl.offset_bottom = 56

	_build_day_screen(hud)

	# (no HitSound: the generated hit tick was removed – owner's wish)
	var hurt: AudioStreamPlayer = _add(hud, AudioStreamPlayer.new(), "HurtSound")
	# (no stream: HUD picks a real recording, assets/audio/recorded/hurt…)
	hurt.volume_db = -4.0
	hurt.bus = &"UI"
	# G1: end of the battle (victory / defeat) with statistics.
	var es: Control = _add(hud, Control.new(), "EndScreen")
	es.set_script(load("res://scripts/ui/end_screen.gd"))
	es.theme = theme
	_full_rect(es)
	var es_dim: ColorRect = _add(es, ColorRect.new(), "Dim")
	es_dim.color = Color(0.03, 0.04, 0.07, 0.62)
	_full_rect(es_dim)
	var es_c: CenterContainer = _add(es, CenterContainer.new(), "Center")
	_full_rect(es_c)
	var es_p: PanelContainer = _add(es_c, PanelContainer.new(), "Panel")
	var es_v: VBoxContainer = _add(es_p, VBoxContainer.new(), "VBox")
	es_v.add_theme_constant_override("separation", 14)
	es_v.custom_minimum_size = Vector2(560, 0)
	_label(es_v, "Title", "THE LINE HELD", 46, HORIZONTAL_ALIGNMENT_CENTER)
	var es_sub := _label(es_v, "Subtitle", "", 18, HORIZONTAL_ALIGNMENT_CENTER, Color(0.88, 0.91, 0.95))
	es_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Victory: the front report of the last day held.
	var es_r := _label(es_v, "Report", "", 17, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.92, 0.75))
	es_r.add_theme_font_override("font", load("res://assets/fonts/FreeMonoBold.ttf"))
	es_r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	es_r.custom_minimum_size = Vector2(560, 0)
	_label(es_v, "Stats", "", 18, HORIZONTAL_ALIGNMENT_CENTER, Color(0.95, 0.96, 0.98))
	var es_b: HBoxContainer = _add(es_v, HBoxContainer.new(), "Buttons")
	es_b.alignment = BoxContainer.ALIGNMENT_CENTER
	es_b.add_theme_constant_override("separation", 16)
	for b in [["PlayAgainButton", "Play again"], ["MainMenuButton", "Main menu"]]:
		var btn: Button = _add(es_b, Button.new(), b[0])
		btn.text = b[1]
		btn.custom_minimum_size = Vector2(200, 44)
	_ignore_mouse(hud) # the HUD must never catch the mouse (see the M2 mouse-look bug)
	# ...except the end screen, which is used with the mouse.
	es.mouse_filter = Control.MOUSE_FILTER_STOP
	for btn in es_b.get_children():
		(btn as Control).mouse_filter = Control.MOUSE_FILTER_STOP
	return hud


func _build_pause_menu(theme: Theme) -> Node:
	var pm := CanvasLayer.new()
	pm.name = "PauseMenu"
	pm.layer = 20
	pm.set_script(load("res://scripts/ui/pause_menu.gd"))
	var root: Control = _add(pm, Control.new(), "Root")
	_full_rect(root)
	root.theme = theme
	var dim: ColorRect = _add(root, ColorRect.new(), "Dim")
	dim.color = Color(0.02, 0.03, 0.05, 0.55)
	_full_rect(dim)
	var panel: PanelContainer = _add(root, PanelContainer.new(), "Panel")
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var vb: VBoxContainer = _add(panel, VBoxContainer.new(), "VBox")
	vb.add_theme_constant_override("separation", 12)
	_label(vb, "Title", "PAUSED", 34, HORIZONTAL_ALIGNMENT_CENTER)
	_label(vb, "Hint", "Click Resume to play  (Esc opens this menu)", 15, HORIZONTAL_ALIGNMENT_CENTER, Color(0.8, 0.84, 0.9))
	for b in [["ResumeButton", "Resume"], ["SettingsButton", "Settings"], ["ControlsButton", "Controls"], ["MainMenuButton", "Main Menu"]]:
		var btn: Button = _add(vb, Button.new(), b[0])
		btn.text = b[1]
		btn.custom_minimum_size = Vector2(300, 46)
	var sm: Control = _add(root, load("res://ui/settings_menu.tscn").instantiate(), "SettingsMenu")
	sm.visible = false
	var cp: Control = _add(root, load("res://ui/controls_panel.tscn").instantiate(), "ControlsPanel")
	cp.visible = false
	return pm


## The "Controls" list (main menu + pause menu). The rows are filled by controls_panel.gd from
## the Input Map, so only the frame is built here.
func _build_controls_panel(theme: Theme) -> Node:
	var cp := Control.new()
	cp.name = "ControlsPanel"
	cp.set_script(load("res://scripts/ui/controls_panel.gd"))
	cp.theme = theme
	_full_rect(cp)
	var center: CenterContainer = _add(cp, CenterContainer.new(), "Center")
	_full_rect(center)
	var panel: PanelContainer = _add(center, PanelContainer.new(), "Panel")
	var vb: VBoxContainer = _add(panel, VBoxContainer.new(), "VBox")
	vb.add_theme_constant_override("separation", 14)
	_label(vb, "Title", "CONTROLS", 32, HORIZONTAL_ALIGNMENT_CENTER)
	# Taller than a small browser window: the list scrolls, Back stays visible.
	var scroll: ScrollContainer = _add(vb, ScrollContainer.new(), "Scroll")
	scroll.custom_minimum_size = Vector2(760, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid: GridContainer = _add(scroll, GridContainer.new(), "Grid")
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 4)
	var back: Button = _add(vb, Button.new(), "BackButton")
	back.text = "Back"
	back.custom_minimum_size = Vector2(200, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return cp


## Loading screen with a progress bar (main menu → battle). Same look as the main menu.
func _build_loading_screen(theme: Theme) -> Node:
	var ls := CanvasLayer.new()
	ls.name = "LoadingScreen"
	ls.set_script(load("res://scripts/ui/loading_screen.gd"))
	var root: Control = _add(ls, Control.new(), "Root")
	root.theme = theme
	_full_rect(root)
	var bg: TextureRect = _add(root, TextureRect.new(), "Background")
	_full_rect(bg)
	var g := Gradient.new()
	g.set_color(0, Color(0.13, 0.16, 0.21))
	g.set_color(1, Color(0.36, 0.41, 0.49))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	var center: CenterContainer = _add(root, CenterContainer.new(), "Center")
	_full_rect(center)
	var vb: VBoxContainer = _add(center, VBoxContainer.new(), "VBox")
	vb.add_theme_constant_override("separation", 14)
	_label(vb, "Title", "WINTER WAR: SUMMA", 44, HORIZONTAL_ALIGNMENT_CENTER)
	_label(vb, "Status", "Loading the battle...", 20, HORIZONTAL_ALIGNMENT_CENTER, Color(0.9, 0.93, 0.97))
	var bar := _bar(vb, "Bar", Color(0.4, 0.56, 0.76, 0.95), Vector2(560, 22))
	bar.show_percentage = true
	bar.add_theme_font_size_override("font_size", 14)
	bar.add_theme_color_override("font_color", Color(1, 1, 1))
	bar.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	bar.add_theme_constant_override("outline_size", 4)
	bar.value = 0
	var tip := _label(vb, "Tip", "", 16, HORIZONTAL_ALIGNMENT_CENTER, Color(0.8, 0.85, 0.92))
	tip.custom_minimum_size = Vector2(560, 0)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Browser only: one click locks the mouse to the game and starts the battle.
	var start := _label(vb, "ClickToStart", "CLICK TO START THE BATTLE", 30, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.93, 0.75))
	start.visible = false
	for c in ls.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE # the click is read in _input
	return ls


func _build_main_menu(theme: Theme) -> Node:
	var mm := Control.new()
	mm.name = "MainMenu"
	mm.set_script(load("res://scripts/ui/main_menu.gd"))
	mm.theme = theme
	_full_rect(mm)

	var bg: TextureRect = _add(mm, TextureRect.new(), "Background")
	_full_rect(bg)
	var g := Gradient.new()
	g.set_color(0, Color(0.13, 0.16, 0.21))
	g.set_color(1, Color(0.6, 0.65, 0.72))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE

	# A dark forest edge on the horizon and snowy ground (simple 2D shapes).
	var ground: ColorRect = _add(mm, ColorRect.new(), "Ground")
	ground.color = Color(0.82, 0.86, 0.91)
	ground.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	ground.offset_top = -150
	var trees: Control = _add(mm, Control.new(), "TreeLine")
	trees.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	trees.offset_top = -150
	trees.offset_bottom = -150
	var rng := RandomNumberGenerator.new()
	rng.seed = 1939
	var x := -20.0
	while x < 2000.0:
		var h := rng.randf_range(50, 130)
		var w := h * rng.randf_range(0.32, 0.42)
		var tree := Polygon2D.new()
		tree.color = Color(0.1, 0.13, 0.16).lerp(Color(0.3, 0.35, 0.42), rng.randf() * 0.5)
		tree.polygon = PackedVector2Array([Vector2(x - w, 4), Vector2(x, -h), Vector2(x + w, 4)])
		_add(trees, tree, "Tree")
		x += rng.randf_range(14, 40)

	var snow: CPUParticles2D = _add(mm, CPUParticles2D.new(), "SnowFall")
	snow.position = Vector2(960, -20)
	snow.amount = 260
	snow.lifetime = 14.0
	snow.preprocess = 14.0
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(1100, 10)
	snow.direction = Vector2(0.15, 1)
	snow.spread = 12.0
	snow.gravity = Vector2(4, 18)
	snow.initial_velocity_min = 20.0
	snow.initial_velocity_max = 45.0
	snow.scale_amount_min = 1.5
	snow.scale_amount_max = 3.5
	snow.color = Color(1, 1, 1, 0.85)

	var center: CenterContainer = _add(mm, CenterContainer.new(), "Center")
	_full_rect(center)
	center.offset_bottom = -120 # centre the menu in the sky, above the snowy ground
	var vb: VBoxContainer = _add(center, VBoxContainer.new(), "VBox")
	vb.add_theme_constant_override("separation", 9)
	_label(vb, "Kicker", "TALVISOTA", 18, HORIZONTAL_ALIGNMENT_CENTER, Color(0.85, 0.9, 0.97))
	_label(vb, "Title", "WINTER WAR: SUMMA", 64, HORIZONTAL_ALIGNMENT_CENTER)
	_label(vb, "Subtitle", "Battle of Summa  ·  Mannerheim Line  ·  1939–40", 20, HORIZONTAL_ALIGNMENT_CENTER, Color(0.88, 0.91, 0.95))
	var spacer: Control = _add(vb, Control.new(), "Spacer")
	spacer.custom_minimum_size = Vector2(0, 14)
	for b in [["SinglePlayerButton", "Single Player", ""],
			["TestModeButton", "Test Mode", "Start at any battle (only shown in the Godot editor)"], ["HostCoopButton", "Host Co-op", "Co-op is coming in a later version"],
			["JoinCoopButton", "Join Co-op", "Co-op is coming in a later version"], ["SettingsButton", "Settings", ""],
			["ControlsButton", "Controls", "Which key does what"], ["BenchmarkButton", "Benchmark", "A 60-second performance test"], ["CreditsButton", "Credits", ""],
			["QuitButton", "Quit", ""]]:
		var btn: Button = _add(vb, Button.new(), b[0])
		btn.text = b[1]
		btn.tooltip_text = b[2]
		btn.custom_minimum_size = Vector2(340, 44)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# G1: difficulty for single player (saved in Settings).
	var row: HBoxContainer = _add(vb, HBoxContainer.new(), "DifficultyRow")
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_label(row, "Label", "Difficulty", 18, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.92, 0.94, 0.97))
	var opt: OptionButton = _add(row, OptionButton.new(), "DifficultyOption")
	for n in ["Easy", "Normal", "Hard"]:
		opt.add_item(n)
	opt.select(1)
	opt.custom_minimum_size = Vector2(200, 40)
	opt.tooltip_text = "10 battles on every level.\nEasy: fewer riflemen, weaker enemy fire, the line breaks at 6 Soviets in the trench.\nNormal: 4 in the trench.\nHard: more soldiers, 3 in the trench, better enemy aim."
	vb.move_child(row, vb.get_node("SinglePlayerButton").get_index())
	vb.get_node("HostCoopButton").disabled = true
	vb.get_node("JoinCoopButton").disabled = true

	var sm: Control = _add(mm, load("res://ui/settings_menu.tscn").instantiate(), "SettingsMenu")
	sm.visible = false
	var cp: Control = _add(mm, load("res://ui/controls_panel.tscn").instantiate(), "ControlsPanel")
	cp.visible = false

	# Credits: the text of CREDITS.md (the models' licence requires naming their authors).
	var cc: CenterContainer = _add(mm, CenterContainer.new(), "Credits")
	_full_rect(cc)
	cc.visible = false
	var panel: PanelContainer = _add(cc, PanelContainer.new(), "Panel")
	var cvb: VBoxContainer = _add(panel, VBoxContainer.new(), "VBox")
	cvb.add_theme_constant_override("separation", 14)
	var credits_text: String = FileAccess.get_file_as_string("res://CREDITS.md").replace("# ", "").replace("#", "")
	# The list is taller than the screen: it scrolls (mouse wheel / scroll bar), Back stays visible.
	var scroll: ScrollContainer = _add(cvb, ScrollContainer.new(), "Scroll")
	scroll.custom_minimum_size = Vector2(790, 540)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var cl := _label(scroll, "Text", credits_text.strip_edges(), 15, HORIZONTAL_ALIGNMENT_LEFT, Color(0.92, 0.94, 0.97))
	cl.custom_minimum_size = Vector2(760, 0)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var back: Button = _add(cvb, Button.new(), "BackButton")
	back.text = "Back"
	back.custom_minimum_size = Vector2(200, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Test mode panel: pick the wave the battle starts at (MatchDirector.test_start_wave).
	var tc: CenterContainer = _add(mm, CenterContainer.new(), "TestMode")
	_full_rect(tc)
	tc.visible = false
	var tpanel: PanelContainer = _add(tc, PanelContainer.new(), "Panel")
	var tvb: VBoxContainer = _add(tpanel, VBoxContainer.new(), "VBox")
	tvb.add_theme_constant_override("separation", 14)
	_label(tvb, "Title", "TEST MODE", 32, HORIZONTAL_ALIGNMENT_CENTER)
	var trow: HBoxContainer = _add(tvb, HBoxContainer.new(), "WaveRow")
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	trow.add_theme_constant_override("separation", 12)
	_label(trow, "Label", "Start at battle", 18, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.92, 0.94, 0.97))
	var spin: SpinBox = _add(trow, SpinBox.new(), "WaveSpin")
	spin.min_value = 1
	spin.max_value = 10
	spin.step = 1
	spin.value = 1
	spin.custom_minimum_size = Vector2(120, 40)
	_label(tvb, "Info", "Difficulty: Normal", 15, HORIZONTAL_ALIGNMENT_CENTER, Color(0.8, 0.84, 0.9))
	for tb in [["StartButton", "Start"], ["BackButton", "Back"]]:
		var tbtn: Button = _add(tvb, Button.new(), tb[0])
		tbtn.text = tb[1]
		tbtn.custom_minimum_size = Vector2(240, 44)
		tbtn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var ver := _label(mm, "Version", "Prototype", 14, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.2, 0.24, 0.3))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -300
	ver.offset_top = -34
	ver.offset_right = -16
	ver.offset_bottom = -10
	ver.remove_theme_constant_override("outline_size")
	return mm


# ---------------------------------------------------------------- trench source (CSG) and baked version
const TRENCH_SOURCE := "res://levels/source/trench_csg.tscn"
const BAKED_DIR := "res://levels/baked/"


func _build_trench_source(mats: Dictionary) -> Node:
	DirAccess.make_dir_recursive_absolute("res://levels/source")
	var root := Node3D.new()
	root.name = "TrenchCSG"
	# --- Trench: a CSG earth slab with the trench line (TRENCH_XZ) and its bays cut out of it ---
	var trench: CSGCombiner3D = _add(root, CSGCombiner3D.new(), "Trench")
	trench.use_collision = true
	trench.collision_layer = 0b1
	trench.set_meta("surface", "earthwork")
	trench.add_to_group("navigation_source", true)
	_csg_box(trench, "EarthSlab", Vector3(210, 2.5, 18), Vector3(0, -1.25, 61), mats.snow)
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	for i in _tcount():
		var a := _tp(i)
		var b := _tp(i + 1)
		var d := b - a
		var length := d.length() + TRENCH_WIDTH  # overlap at the corners
		var mid := (a + b) / 2.0
		_csg_box(trench, "TrenchCut%d" % (i + 1), Vector3(length, 3.6, TRENCH_WIDTH),
			Vector3(mid.x, -0.8, mid.y), mats.trench_wall, SUB, Vector3(0, atan2(-d.y, d.x), 0))
	# L1: the bays of the four firing positions and two dead-end branches to the rear.
	for k in POST_X.size():
		var zc := _line_z(POST_X[k])
		var zf := zc - POST_BAY_DEPTH
		var z1 := zc + 0.5
		_csg_box(trench, "FirePostCut%d" % (k + 1), Vector3(POST_BAY_W, 3.6, z1 - zf),
			Vector3(POST_X[k], -0.8, (zf + z1) / 2.0), mats.trench_wall, SUB)
	for k in SPURS.size():
		var sp: Vector3 = SPURS[k]
		_csg_box(trench, "SpurCut%d" % (k + 1), Vector3(1.6, 3.6, sp.z),
			Vector3(sp.x, -0.8, sp.y + sp.z / 2.0), mats.trench_wall, SUB)

	# Exits: short cuts going back (+z) with a ramp up to ground level.
	# The ramp rises from the trench floor (z = 65) to just above ground level (z = 69.5),
	# then a flat landing continues past the end of the slab.
	var rise := DEPTH + 0.05
	var run := 4.5
	var slope := atan(rise / run)
	for x in [-80, -40, 40, 80]:
		_csg_box(trench, "ExitCut_x%d" % x, Vector3(1.6, 3.6, 7.0), Vector3(x, -0.8, 67.5),
			mats.trench_wall, SUB)
		var normal := Vector3(0, cos(slope), -sin(slope))
		var top_center := Vector3(x, -DEPTH + rise / 2.0, 65.0 + run / 2.0)
		_csg_box(trench, "ExitRamp_x%d" % x, Vector3(1.6, 0.6, sqrt(run * run + rise * rise) + 0.1),
			top_center - normal * 0.3, mats.snow, CSGShape3D.OPERATION_UNION, Vector3(-slope, 0, 0))
		_csg_box(trench, "ExitLanding_x%d" % x, Vector3(1.6, 0.4, 2.0), Vector3(x, -0.15, 70.4),
			mats.snow)

	# G1: a niche in the rear wall for the ammo crate.
	var niche: Array = _ammo_niche()
	var niche_c: Vector2 = niche[0] + (niche[2] as Vector2) * 0.05
	_csg_box(trench, "AmmoNiche", Vector3(1.6, 3.6, 1.0), Vector3(niche_c.x, -0.8, niche_c.y), mats.trench_wall, SUB,
		Vector3(0, niche[1], 0))

	# L2: the bunker room is dug into the slab (z = BUNKER_Z +- 2.25); the way in is a short open
	# stub of trench from the trench line behind it to the door in the back wall.
	_csg_box(trench, "BunkerRoomCut", Vector3(5, 2.62, 4.5), Vector3(0, -1.29, BUNKER_Z), mats.bunker_log, SUB)
	var stub_z0 := BUNKER_Z + 2.1
	var stub_z1 := _line_z(BUNKER_DOOR_X)
	_csg_box(trench, "BunkerDoorCut", Vector3(BUNKER_DOOR_W, 3.6, stub_z1 - stub_z0),
		Vector3(BUNKER_DOOR_X, -0.8, (stub_z0 + stub_z1) / 2.0), mats.trench_wall, SUB)

	# --- Log bunker (above-ground part) ---
	var bunker: CSGCombiner3D = _add(root, CSGCombiner3D.new(), "Bunker")
	bunker.use_collision = true
	bunker.collision_layer = 0b1
	bunker.set_meta("surface", "wood")
	bunker.add_to_group("navigation_source", true)
	bunker.position = Vector3(0, 0, BUNKER_Z)
	_csg_box(bunker, "Walls", Vector3(6, 1.0, 5.5), Vector3(0, 0.5, 0), mats.bunker_log)
	_csg_box(bunker, "Inside", Vector3(5, 1.2, 4.5), Vector3(0, 0.5, 0), mats.bunker_log, SUB)
	# L2: the firing hole in the front wall (wall z -2.75 ... -2.25): 1.1 m wide at the outside,
	# widening in three steps to 1.6 m inside (like a real machine-gun embrasure), 0.45 m tall
	# (y 0.1 ... 0.55). (A CSGPolygon3D did not subtract in the headless bake, so boxes.)
	_csg_box(bunker, "FiringHoleOuter", Vector3(1.1, 0.45, 0.35), Vector3(0, 0.325, -2.675), mats.bunker_log, SUB)
	_csg_box(bunker, "FiringHoleMid", Vector3(1.35, 0.45, 0.2), Vector3(0, 0.325, -2.4), mats.bunker_log, SUB)
	_csg_box(bunker, "FiringHoleInner", Vector3(1.6, 0.45, 0.25), Vector3(0, 0.325, -2.25), mats.bunker_log, SUB)
	# The door in the back wall (the trench stub leads to it).
	_csg_box(bunker, "BackDoor", Vector3(BUNKER_DOOR_W, 1.1, 0.8), Vector3(BUNKER_DOOR_X, 0.45, 2.5), mats.bunker_log, SUB)
	_csg_box(bunker, "Roof", Vector3(6.8, 0.5, 6.3), Vector3(0, 1.25, 0), mats.bunker_log)
	_csg_box(bunker, "RoofSnow", Vector3(6.6, 0.25, 6.1), Vector3(0, 1.62, 0), mats.drift)
	for i in 2: # two big logs along the front edge of the roof
		var log_node: CSGCylinder3D = _add(bunker, CSGCylinder3D.new(), "FrontLog%d" % (i + 1))
		log_node.radius = 0.17
		log_node.height = 7.0
		log_node.sides = 8
		log_node.rotation = Vector3(0, 0, deg_to_rad(90))
		log_node.position = Vector3(0, 1.12 + i * 0.32, -3.2)
		log_node.material = mats.bunker_log

	return root


## L1: what stands on the ground in front of each firing position (the narrow bay is part of the
## CSG trench): a wall of sandbags with a loophole at head height (0.8 x 0.42 m, starting at the
## ground) and an earth heap on each side, like the photo SA_Kuva_a_8. The collision is a few simple
## boxes with the hole left open, so the protection is real: a bullet only reaches the soldier
## through the hole. Standing on the trench floor his eyes (0.2 m above the ground) are at the
## hole; crouching, he is hidden. All sandbags of a post are one mesh (2 surfaces).
func _build_fire_posts(root: Node, mats: Dictionary) -> void:
	var posts: Node3D = _add(root, Node3D.new(), "FirePosts")
	var bag := SphereMesh.new()
	bag.radius = 0.5
	bag.height = 1.0
	bag.radial_segments = 8
	bag.rings = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 1940
	var thick: float = POST_WALL_BACK - POST_WALL_FRONT
	var zmid: float = (POST_WALL_BACK + POST_WALL_FRONT) / 2.0
	var hw := POST_WALL_HALF_W
	var hh := POST_HOLE_HALF_W
	for k in POST_X.size():
		var zf := _line_z(POST_X[k]) - POST_BAY_DEPTH
		var body: StaticBody3D = _add(posts, StaticBody3D.new(), "FirePost%d" % (k + 1))
		body.position = Vector3(POST_X[k], 0.0, zf)
		body.collision_layer = 0b1
		body.set_meta("surface", "earthwork")
		body.add_to_group("navigation_source", true)
		body.add_to_group("fire_post", true)

		# Collision: lintel above the hole and a jamb on each side of it.
		var lintel_h: float = POST_WALL_TOP - POST_HOLE_TOP
		for w: Array in [["LintelCollision", Vector3(hw * 2.0, lintel_h, thick), Vector3(0, POST_HOLE_TOP + lintel_h / 2.0, zmid)],
				["JambWestCollision", Vector3(hw - hh, POST_HOLE_TOP, thick), Vector3(-(hw + hh) / 2.0, POST_HOLE_TOP / 2.0, zmid)],
				["JambEastCollision", Vector3(hw - hh, POST_HOLE_TOP, thick), Vector3((hw + hh) / 2.0, POST_HOLE_TOP / 2.0, zmid)]]:
			var box := BoxShape3D.new()
			box.size = w[1]
			var cs: CollisionShape3D = _add(body, CollisionShape3D.new(), w[0])
			cs.shape = box
			cs.position = w[2]

		# Earth heaps on both sides of the wall (a triangular prism sloping down and away).
		for side in [-1.0, 1.0]:
			var heap := PrismMesh.new()
			heap.size = Vector3(1.3, POST_WALL_TOP, 1.0)
			heap.left_to_right = 1.0 if side < 0.0 else 0.0 # the steep side faces the wall
			var mi := MeshInstance3D.new()
			mi.mesh = heap
			mi.material_override = mats.snow
			_add(body, mi, "EarthHeapWest" if side < 0.0 else "EarthHeapEast")
			mi.position = Vector3(side * (hw + 0.65 - 0.05), POST_WALL_TOP / 2.0, zmid)
			var col: CollisionShape3D = _add(body, CollisionShape3D.new(), "EarthHeapWestCollision" if side < 0.0 else "EarthHeapEastCollision")
			col.shape = heap.create_convex_shape()
			col.position = mi.position

		# The sandbags: 4 layers of 0.21 m, 2 bags deep. The two lower layers leave the hole open.
		var plain: Array[Transform3D] = []
		var snowy: Array[Transform3D] = []
		for layer in 4:
			var y := 0.105 + layer * 0.21
			for row in 2:
				var z: float = POST_WALL_FRONT + 0.155 + row * 0.31
				var xs: Array[float] = []
				if y < POST_HOLE_TOP: # jambs: bags beside the hole
					for side in [-1.0, 1.0]:
						xs.append(side * (hh + 0.26))
						xs.append(side * (hh + 0.78))
				else: # full width above the hole
					var shift := 0.25 if (layer + row) % 2 == 1 else 0.0
					for c in 6:
						var x := -1.25 + c * 0.5 + shift
						if absf(x) <= hw - 0.1:
							xs.append(x)
				for x in xs:
					var t := _bag_transform(rng, Vector3(x, y, z), 0.0)
					(snowy if layer == 3 else plain).append(t)
		var bags := MeshInstance3D.new()
		bags.mesh = _bags_mesh(bag, plain, snowy, mats.sandbag, mats.sandbag_snow)
		_add(body, bags, "Sandbags")


func _bag_transform(rng: RandomNumberGenerator, pos: Vector3, yaw: float) -> Transform3D:
	var s := rng.randf_range(0.95, 1.05)
	var basis := Basis(Vector3.UP, yaw + rng.randf_range(-0.07, 0.07)) * Basis.from_scale(Vector3(0.52 * s, 0.21, 0.31 * s))
	return Transform3D(basis, pos + Vector3(rng.randf_range(-0.015, 0.015), 0.0, rng.randf_range(-0.015, 0.015)))


## Merges copies of `bag` (one per transform) into one mesh: surface 0 = plain, surface 1 = snowy.
func _bags_mesh(bag: Mesh, plain: Array[Transform3D], snowy: Array[Transform3D], mat_plain: Material, mat_snowy: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arr := bag.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for group: Array in [[plain, mat_plain], [snowy, mat_snowy]]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var base := 0
		for t: Transform3D in group[0]:
			var nb := t.basis.inverse().transposed()
			for i in verts.size():
				st.set_normal((nb * norms[i]).normalized())
				st.add_vertex(t * verts[i])
			for i in idx:
				st.add_index(base + i)
			base += verts.size()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, group[1])
	return mesh


## A StaticBody3D using the mesh and collision shape baked from the CSG combiner `n`.
func _baked_body(parent: Node, n: String, pos: Vector3, surface: String) -> void:
	var body: StaticBody3D = _add(parent, StaticBody3D.new(), n)
	body.position = pos
	body.collision_layer = 0b1
	body.set_meta("surface", surface)
	body.add_to_group("navigation_source", true)
	var mi: MeshInstance3D = _add(body, MeshInstance3D.new(), "Mesh")
	mi.mesh = load(BAKED_DIR + n.to_lower() + "_mesh.res")
	var cs: CollisionShape3D = _add(body, CollisionShape3D.new(), "Collision")
	cs.shape = load(BAKED_DIR + n.to_lower() + "_shape.res")


func _build_settings_menu(theme: Theme) -> Node:
	var sm := Control.new()
	sm.name = "SettingsMenu"
	sm.set_script(load("res://scripts/ui/settings_menu.gd"))
	sm.theme = theme
	_full_rect(sm)
	var panel: PanelContainer = _add(sm, PanelContainer.new(), "Panel")
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var vb: VBoxContainer = _add(panel, VBoxContainer.new(), "VBox")
	vb.add_theme_constant_override("separation", 14)
	_label(vb, "Title", "SETTINGS", 30, HORIZONTAL_ALIGNMENT_CENTER)
	var grid: GridContainer = _add(vb, GridContainer.new(), "Grid")
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)

	_label(grid, "QualityLabel", "Graphics quality", 18)
	var q: OptionButton = _add(grid, OptionButton.new(), "Quality")
	q.custom_minimum_size = Vector2(240, 40)
	_label(grid, "QualityHint", "", 14)

	_label(grid, "SensitivityLabel", "Mouse sensitivity", 18)
	var sens: HSlider = _add(grid, HSlider.new(), "Sensitivity")
	sens.min_value = 0.25
	sens.max_value = 3.0
	sens.step = 0.05
	sens.value = 1.0
	sens.custom_minimum_size = Vector2(240, 32)
	_label(grid, "SensitivityValue", "1.00×", 16)

	_label(grid, "VolumeLabel", "Volume", 18)
	var vol: HSlider = _add(grid, HSlider.new(), "Volume")
	vol.min_value = 0
	vol.max_value = 100
	vol.step = 1
	vol.value = 80
	vol.custom_minimum_size = Vector2(240, 32)
	_label(grid, "VolumeValue", "80 %", 16)

	_label(grid, "AmbienceLabel", "Wind and battle", 18)
	var amb: HSlider = _add(grid, HSlider.new(), "Ambience")
	amb.min_value = 0
	amb.max_value = 100
	amb.step = 1
	amb.value = 70
	amb.custom_minimum_size = Vector2(240, 32)
	_label(grid, "AmbienceValue", "70 %", 16)

	_label(grid, "BreathLabel", "Breath vapour", 18)
	var br: CheckButton = _add(grid, CheckButton.new(), "Breath")
	br.text = ""
	br.button_pressed = true
	_label(grid, "BreathHint", "", 14)

	_label(grid, "FullscreenLabel", "Fullscreen", 18)
	var fs: CheckButton = _add(grid, CheckButton.new(), "Fullscreen")
	fs.text = ""
	_label(grid, "FullscreenHint", "", 14)

	_label(vb, "Note", "Low: no shadows, shorter view, less snow - best for older laptops and browsers.", 14, HORIZONTAL_ALIGNMENT_CENTER, Color(0.8, 0.84, 0.9))
	var back: Button = _add(vb, Button.new(), "BackButton")
	back.text = "Back"
	back.custom_minimum_size = Vector2(240, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return sm


func _build_benchmark() -> Node:
	var b := Node.new()
	b.name = "Benchmark"
	b.set_script(load("res://scripts/game/benchmark.gd"))
	_add(b, load("res://scenes/game.tscn").instantiate(), "Game")
	return b
