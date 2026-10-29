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
	var chunk: MultiMeshInstance3D = null
	for c in forest.get_children():
		if c is MultiMeshInstance3D:
			chunk = c
			break

	check(game.get_node("Level/Trench") is StaticBody3D and game.get_node("Level/Bunker") is StaticBody3D, "level uses the baked trench and bunker (no CSG)")
	check(game.get_node("Level").find_children("*", "CSGShape3D", true, false).is_empty(), "no CSG nodes left in the level")

	Settings.set_quality(Settings.Quality.LOW)
	await get_tree().process_frame
	check(not sun.shadow_enabled, "Low: no shadows")
	check(is_equal_approx(chunk.visibility_range_end, 110.0), "Low: trees drawn to 110 m")
	check(p.snow_particles.amount == 250, "Low: less snow (%d)" % p.snow_particles.amount)
	check(is_equal_approx(get_tree().root.scaling_3d_scale, 0.75), "Low: 75 % render scale")
	check(is_equal_approx(env.fog_density, 0.009), "Low: denser fog hides the shorter view")

	Settings.set_quality(Settings.Quality.HIGH)
	await get_tree().process_frame
	check(sun.shadow_enabled and is_equal_approx(sun.directional_shadow_max_distance, 70.0), "High: shadows to 70 m")
	check(is_equal_approx(chunk.visibility_range_end, 190.0) and p.snow_particles.amount == 900, "High: trees to 190 m, full snow")

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
