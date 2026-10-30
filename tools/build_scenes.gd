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
	_save(_build_enemy(mats), "res://scenes/enemies/soviet_rifleman.tscn")
	_save(_build_player(mats), "res://scenes/player.tscn")
	_save(_build_maxim(mats), "res://scenes/weapons/maxim_mg.tscn")
	_save(_build_trench_source(mats), TRENCH_SOURCE)
	_save(_build_level(mats), "res://levels/test_level.tscn")
	DirAccess.make_dir_recursive_absolute("res://ui")
	var theme := _make_theme()
	_save(_build_hud(), "res://ui/hud.tscn")
	_save(_build_settings_menu(theme), "res://ui/settings_menu.tscn")
	_save(_build_pause_menu(theme), "res://ui/pause_menu.tscn")
	_save(_build_main_menu(theme), "res://ui/main_menu.tscn")
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
	])
	return p


# ---------------------------------------------------------------- level
const NAVMESH_PATH := "res://levels/test_level_navmesh.res"
const ZIG_X := [-100, -80, -60, -40, -20, 0, 20, 40, 60, 80, 100]
const ZIG_FRONT_Z := 58.0
const ZIG_REAR_Z := 64.0
const TRENCH_WIDTH := 2.0
const DEPTH := 1.4


func _zig_point(i: int) -> Vector2:
	return Vector2(ZIG_X[i], ZIG_FRONT_Z if i % 2 == 0 else ZIG_REAR_Z)


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
		_baked_body(root, "Bunker", Vector3(0, 0, 67.75), "wood")
	else:
		_add(root, load(TRENCH_SOURCE).instantiate(), "TrenchCSG")

	# --- Maxim machine gun in the bunker, firing through the slit ---
	var maxim: Node3D = _add(root, load("res://scenes/weapons/maxim_mg.tscn").instantiate(), "MaximMG")
	maxim.position = Vector3(-1.0, MAXIM_BARREL_Y - MAXIM_BARREL_HEIGHT, 65.88)

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

	# --- Shooting range: practice targets at known distances from the trench ---
	var range_root: Node3D = _add(root, Node3D.new(), "ShootingRange")
	range_root.add_to_group("navigation_source", true)
	var dummy_scene: PackedScene = load("res://scenes/props/target_dummy.tscn")
	for t in [[25, Vector3(32, 0, 36)], [50, Vector3(26, 0, 11)], [100, Vector3(16, 0, -39)], [150, Vector3(6, 0, -89)]]:
		var d: Node3D = dummy_scene.instantiate()
		_add(range_root, d, "Target_%dm" % t[0])
		d.position = t[1]
		d.set("label_text", "%d m" % t[0])

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

	# --- Player spawn points inside the trench (facing the enemy, -z) ---
	var spawns: Node3D = _add(root, Node3D.new(), "PlayerSpawnPoints")
	for i in 4:
		var m: Marker3D = _add(spawns, Marker3D.new(), "Spawn%d" % (i + 1))
		m.position = Vector3(-30 + i * 20, -DEPTH + 0.1, 61)
		m.add_to_group("player_spawn", true)
	return root


# ---------------------------------------------------------------- game
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
	var waves: Node = _add(g, Node.new(), "WaveSpawner")
	waves.set_script(load("res://scripts/enemies/wave_spawner.gd"))
	waves.set("enemy_scene", load("res://scenes/enemies/soviet_rifleman.tscn"))
	waves.set("enemies_root", enemies)
	var wave_sync: MultiplayerSynchronizer = _add(waves, MultiplayerSynchronizer.new(), "WaveSync")
	wave_sync.root_path = NodePath("..")
	wave_sync.replication_config = _sync_config([
		[".:wave_number", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:alive_count", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
	])

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
	r[0].set("ads_eye_distance", 0.42)
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
	r[0].set("ads_eye_distance", 0.4)
	r[0].set("hip_offset", Vector3(0.0, -0.02, -0.08))
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
	mosin.cycle_sound = load(a + "bolt_cycle.wav")
	mosin.reload_sound = load(a + "reload.wav")
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
	suomi.reload_sound = load(a + "reload.wav")
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
	maxim.fire_sound = load(a + "maxim_shot.wav")
	maxim.reload_sound = load(a + "belt_reload.wav")
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


func _build_maxim(mats: Dictionary) -> Node:
	var gun := StaticBody3D.new()
	gun.name = "MaximMG"
	gun.set_script(load("res://scripts/weapons/mounted_gun.gd"))
	gun.collision_layer = 0b1
	gun.set_meta("surface", "wood")
	gun.set("data", load("res://resources/weapons/maxim_m09_21.tres"))
	gun.set("traverse_left_deg", 14.0)  # the gun stands left of centre in the slit
	gun.set("traverse_right_deg", 40.0)
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
	var sync: MultiplayerSynchronizer = _add(gun, MultiplayerSynchronizer.new(), "GunSync")
	sync.root_path = NodePath("..")
	sync.replication_config = _sync_config([
		[".:user_id", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:ammo", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
		[".:is_reloading", true, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE],
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
func _make_enemy_data() -> void:
	DirAccess.make_dir_recursive_absolute("res://resources/enemies")
	var d := EnemyData.new() # defaults from enemy_data.gd
	ResourceSaver.save(d, "res://resources/enemies/soviet_rifleman.tres")


func _build_enemy(mats: Dictionary) -> Node:
	DirAccess.make_dir_recursive_absolute("res://scenes/enemies")
	var e := CharacterBody3D.new()
	e.name = "SovietRifleman"
	e.set_script(load("res://scripts/enemies/enemy.gd"))
	e.set("data", load("res://resources/enemies/soviet_rifleman.tres"))
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


func _build_hud() -> Node:
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
	vitals.offset_top = -78
	vitals.offset_right = 304
	vitals.offset_bottom = -24
	vitals.add_theme_constant_override("separation", 6)
	_label(vitals, "HealthTitle", "HEALTH", 13, HORIZONTAL_ALIGNMENT_LEFT, Color(0.85, 0.88, 0.92))
	var hb := _bar(vitals, "HealthBar", Color(0.7, 0.13, 0.1, 0.95), Vector2(280, 24))
	var hv := _label(hb, "Value", "100", 16, HORIZONTAL_ALIGNMENT_CENTER)
	_full_rect(hv)
	hv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar(vitals, "StaminaBar", Color(0.78, 0.87, 0.96, 0.9), Vector2(280, 7))

	# Bottom right: weapon and ammo.
	var wp: VBoxContainer = _add(hud, VBoxContainer.new(), "WeaponPanel")
	wp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	wp.offset_left = -344
	wp.offset_top = -110
	wp.offset_right = -24
	wp.offset_bottom = -24
	wp.alignment = BoxContainer.ALIGNMENT_END
	wp.add_theme_constant_override("separation", 0)
	_label(wp, "Reloading", "RELOADING", 16, HORIZONTAL_ALIGNMENT_RIGHT, Color(1.0, 0.8, 0.35))
	_label(wp, "WeaponName", "Weapon", 18, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.88, 0.91, 0.95))
	_label(wp, "Ammo", "0 / 0", 36, HORIZONTAL_ALIGNMENT_RIGHT)

	# Top centre: wave information and score.
	var wv: VBoxContainer = _add(hud, VBoxContainer.new(), "WavePanel")
	wv.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	wv.offset_left = -220
	wv.offset_right = 220
	wv.offset_top = 14
	wv.offset_bottom = 120
	wv.add_theme_constant_override("separation", 0)
	_label(wv, "Wave", "Get ready", 24, HORIZONTAL_ALIGNMENT_CENTER)
	_label(wv, "Enemies", "Enemies: 0", 16, HORIZONTAL_ALIGNMENT_CENTER, Color(0.88, 0.91, 0.95))
	_label(wv, "NextWave", "", 16, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.85, 0.5))
	_label(wv, "Score", "Kills 0   Deaths 0", 14, HORIZONTAL_ALIGNMENT_CENTER, Color(0.8, 0.84, 0.9))

	# Centre, below the crosshair: "[F] Use Maxim".
	var prompt := _label(hud, "InteractPrompt", "", 17, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.92, 0.7))
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.offset_top = 150
	prompt.offset_bottom = 180

	var banner := _label(hud, "WaveBanner", "WAVE 1", 60, HORIZONTAL_ALIGNMENT_CENTER)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.offset_left = -300
	banner.offset_right = 300
	banner.offset_top = -170
	banner.offset_bottom = -90

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

	var tick: AudioStreamPlayer = _add(hud, AudioStreamPlayer.new(), "HitSound")
	tick.stream = load("res://assets/audio/hit_tick.wav")
	tick.volume_db = -8.0
	tick.bus = &"UI"
	var hurt: AudioStreamPlayer = _add(hud, AudioStreamPlayer.new(), "HurtSound")
	hurt.stream = load("res://assets/audio/hurt_thump.wav")
	hurt.volume_db = -4.0
	hurt.bus = &"UI"
	_ignore_mouse(hud) # the HUD must never catch the mouse (see the M2 mouse-look bug)
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
	for b in [["ResumeButton", "Resume"], ["SettingsButton", "Settings"], ["MainMenuButton", "Main Menu"]]:
		var btn: Button = _add(vb, Button.new(), b[0])
		btn.text = b[1]
		btn.custom_minimum_size = Vector2(300, 46)
	var sm: Control = _add(root, load("res://ui/settings_menu.tscn").instantiate(), "SettingsMenu")
	sm.visible = false
	return pm


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
	for b in [["SinglePlayerButton", "Single Player", ""], ["HostCoopButton", "Host Co-op", "Co-op is coming in a later version"],
			["JoinCoopButton", "Join Co-op", "Co-op is coming in a later version"], ["SettingsButton", "Settings", ""],
			["BenchmarkButton", "Benchmark", "A 60-second performance test"], ["CreditsButton", "Credits", ""],
			["QuitButton", "Quit", ""]]:
		var btn: Button = _add(vb, Button.new(), b[0])
		btn.text = b[1]
		btn.tooltip_text = b[2]
		btn.custom_minimum_size = Vector2(340, 44)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.get_node("HostCoopButton").disabled = true
	vb.get_node("JoinCoopButton").disabled = true

	var sm: Control = _add(mm, load("res://ui/settings_menu.tscn").instantiate(), "SettingsMenu")
	sm.visible = false

	# Credits: the text of CREDITS.md (the models' licence requires naming their authors).
	var cc: CenterContainer = _add(mm, CenterContainer.new(), "Credits")
	_full_rect(cc)
	cc.visible = false
	var panel: PanelContainer = _add(cc, PanelContainer.new(), "Panel")
	var cvb: VBoxContainer = _add(panel, VBoxContainer.new(), "VBox")
	cvb.add_theme_constant_override("separation", 14)
	var credits_text: String = FileAccess.get_file_as_string("res://CREDITS.md").replace("# ", "").replace("#", "")
	var cl := _label(cvb, "Text", credits_text.strip_edges(), 15, HORIZONTAL_ALIGNMENT_LEFT, Color(0.92, 0.94, 0.97))
	cl.custom_minimum_size = Vector2(760, 0)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var back: Button = _add(cvb, Button.new(), "BackButton")
	back.text = "Back"
	back.custom_minimum_size = Vector2(200, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var ver := _label(mm, "Version", "Prototype · P2", 14, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.2, 0.24, 0.3))
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
	# --- Trench: a CSG earth slab with the zigzag trench cut out of it ---
	var trench: CSGCombiner3D = _add(root, CSGCombiner3D.new(), "Trench")
	trench.use_collision = true
	trench.collision_layer = 0b1
	trench.set_meta("surface", "earthwork")
	trench.add_to_group("navigation_source", true)
	_csg_box(trench, "EarthSlab", Vector3(210, 2.5, 18), Vector3(0, -1.25, 61), mats.snow)
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	for i in ZIG_X.size() - 1:
		var a := _zig_point(i)
		var b := _zig_point(i + 1)
		var d := b - a
		var length := d.length() + TRENCH_WIDTH  # overlap at the corners
		var mid := (a + b) / 2.0
		_csg_box(trench, "TrenchCut%d" % (i + 1), Vector3(length, 3.6, TRENCH_WIDTH),
			Vector3(mid.x, -0.8, mid.y), mats.trench_wall, SUB, Vector3(0, atan2(-d.y, d.x), 0))

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

	# Bunker room dug into the slab behind the trench at x = 0.
	_csg_box(trench, "BunkerRoomCut", Vector3(5, 2.62, 4.1), Vector3(0, -1.29, 66.95), mats.bunker_log, SUB)

	# --- Log bunker (above-ground part) ---
	var bunker: CSGCombiner3D = _add(root, CSGCombiner3D.new(), "Bunker")
	bunker.use_collision = true
	bunker.collision_layer = 0b1
	bunker.set_meta("surface", "wood")
	bunker.add_to_group("navigation_source", true)
	bunker.position = Vector3(0, 0, 67.75)
	_csg_box(bunker, "Walls", Vector3(6, 1.0, 5.5), Vector3(0, 0.5, 0), mats.bunker_log)
	_csg_box(bunker, "Inside", Vector3(5, 1.2, 4.5), Vector3(0, 0.5, 0), mats.bunker_log, SUB)
	# Firing slit: 3 m wide, 0.5 m tall (room for the Maxim and a view over its sights).
	_csg_box(bunker, "FiringSlit", Vector3(3.0, 0.5, 1.0), Vector3(0, 0.35, -2.5), mats.bunker_log, SUB)
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
