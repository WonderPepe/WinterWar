extends Node
## Screenshots of the L3 communication trenches (not part of the game). Saved in tools/shots/:
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_l3.gd

var _out: String
var _game: Node
var _cam: Camera3D


func _ready() -> void:
	await get_tree().process_frame
	_out = ProjectSettings.globalize_path("res://tools/shots/")
	DirAccess.make_dir_recursive_absolute(_out)
	_game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(_game)
	_game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.god_mode = true
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	await get_tree().create_timer(3.0).timeout # shader warm-up

	_cam = Camera3D.new()
	_game.add_child(_cam)
	_cam.current = true
	# 1. From above: both communication trenches leaving the line.
	await _view(Vector3(0, 95, 86), Vector3(0, 0, 86.5), "l3_top", 60.0, Vector3(0, 0, -1))
	await _view(Vector3(-40, 45, 88), Vector3(-40, 0, 88.5), "l3_top_west", 55.0, Vector3(0, 0, -1))
	# 2. From behind, looking at the line over the rear trench.
	await _view(Vector3(-30, 6, 118), Vector3(-40, -1, 90), "l3_rear_west")
	# 3. Player views: at a rear spawn, half way, at the junction with the line.
	_cam.current = false
	for spot: Array in [[Vector3(-40, -1.3, 105), 0.0, "l3_player_spawn"], [Vector3(-38, -1.3, 90), 0.0, "l3_player_mid"],
			[Vector3(-40, -1.3, 68), 0.0, "l3_player_junction"], [Vector3(-40, -1.3, 102.5), PI, "l3_player_ramp"]]:
		p.global_position = spot[0]
		p.input.look_yaw = spot[1]
		p.input.look_pitch = -0.05
		await get_tree().create_timer(0.8).timeout
		await _shot(spot[2])

	# 4. Battle 6: the Soviets holding the west half of the trench, seen from the junction.
	_game.queue_free()
	await get_tree().process_frame
	MatchDirector.test_start_wave = 6
	_game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(_game)
	_game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	p = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.god_mode = true
	await get_tree().create_timer(5.0).timeout # the battle starts, the Soviets are put in the trench
	await _shot("l3_b6_start")
	p.global_position = Vector3(-40, -1.3, 70)
	p.input.look_yaw = 0.0
	await get_tree().create_timer(1.0).timeout
	await _shot("l3_b6_junction")
	_cam = Camera3D.new()
	_game.add_child(_cam)
	await _view(Vector3(-50, 45, 75), Vector3(-50, -1, 61), "l3_b6_top", 70.0)
	MatchDirector.test_start_wave = 0
	get_tree().quit()


func _view(from: Vector3, to: Vector3, file: String, fov := 60.0, up := Vector3.UP) -> void:
	_cam.current = true
	_cam.fov = fov
	_cam.global_position = from
	_cam.look_at(to, up)
	await get_tree().create_timer(0.5).timeout
	await _shot(file)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + file + ".png")
	print("saved ", file)
