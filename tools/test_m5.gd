extends Node
## Automated test for Milestone 5: settings / quality presets and baked trench.

var fails := 0

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func _ready() -> void:
	await get_tree().process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await get_tree().create_timer(0.5).timeout
	var p: Player = get_tree().get_first_node_in_group("players")
	var sun: DirectionalLight3D = get_tree().get_first_node_in_group("sun")
	var forest: ForestScatter = get_tree().get_first_node_in_group("forest")
	var env: Environment = (get_tree().get_first_node_in_group("world_environment") as WorldEnvironment).environment
	var chunk: MultiMeshInstance3D = null # a far (simple trees) chunk
	var near_chunk: MultiMeshInstance3D = null # a near (detailed trees) chunk
	for c in forest.get_children():
		if c is MultiMeshInstance3D and c.name.begins_with("Far_") and chunk == null:
			chunk = c
		if c is MultiMeshInstance3D and c.name.begins_with("Near") and near_chunk == null:
			near_chunk = c

	check(game.get_node("Level/Trench") is StaticBody3D and game.get_node("Level/Bunker") is StaticBody3D, "level uses the baked trench and bunker (no CSG)")
	check(game.get_node("Level").find_children("*", "CSGShape3D", true, false).is_empty(), "no CSG nodes left in the level")

	Settings.set_quality(Settings.Quality.LOW)
	await get_tree().process_frame
	check(not sun.shadow_enabled, "Low: no shadows")
	var far_mat: ShaderMaterial = forest._far_materials[0]
	var near_mat: ShaderMaterial = forest._near_materials[0]
	check(is_equal_approx(far_mat.get_shader_parameter("view_distance"), 140.0) and chunk.visibility_range_end >= 140.0, "Low: trees drawn to 140 m")
	check(is_equal_approx(near_mat.get_shader_parameter("lod_distance"), 35.0) and near_chunk.visibility_range_end >= 35.0, "Low: detailed trees only to 35 m")
	check(p.snow_particles.amount == 250, "Low: less snow (%d)" % p.snow_particles.amount)
	check(is_equal_approx(get_tree().root.scaling_3d_scale, 0.75), "Low: 75 % render scale")
	check(is_equal_approx(env.fog_density, 0.006), "Low: denser fog hides the shorter view")

	Settings.set_quality(Settings.Quality.HIGH)
	await get_tree().process_frame
	check(sun.shadow_enabled and is_equal_approx(sun.directional_shadow_max_distance, 70.0), "High: shadows to 70 m")
	check(is_equal_approx(far_mat.get_shader_parameter("view_distance"), 220.0) and p.snow_particles.amount == 900, "High: trees to 220 m, full snow")
	check(is_equal_approx(near_mat.get_shader_parameter("lod_distance"), 70.0) and near_chunk.visibility_range_end >= 70.0, "High: detailed trees to 70 m")
	await get_tree().process_frame
	var cam_pos: Vector3 = get_viewport().get_camera_3d().global_position
	check(near_mat.get_shader_parameter("lod_camera").distance_to(cam_pos) < 0.5, "tree materials know where the camera is")
	check(forest.get_node_or_null("TreeLine") != null, "distant tree line exists")

	Settings.set_mouse_sensitivity(2.0)
	Settings.set_volume(0.5)
	var cfg := ConfigFile.new()
	check(cfg.load(Settings.SAVE_PATH) == OK and cfg.get_value("controls", "mouse_sensitivity") == 2.0, "settings saved to user://settings.cfg")
	check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.01, "volume applied to the audio bus")
	var yaw0: float = p.input.look_yaw
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var e := InputEventMouseMotion.new()
	e.screen_relative = Vector2(10, 0)
	p.input._input(e)
	var turned: float = absf(p.input.look_yaw - yaw0)
	check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or absf(turned - 10 * p.input.mouse_sensitivity * 2.0) < 0.0001, "mouse sensitivity multiplier used")
	# restore defaults for other tests
	Settings.set_mouse_sensitivity(1.0)
	Settings.set_volume(0.8)
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
