extends Node
## Screenshots of the L1 trench line and firing positions (not part of the game). Saved in tools/shots/:
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_l1.gd

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
	_cam.fov = 60

	# 1. From above: the shape of the line (west half, east half).
	await _view(Vector3(-50, 70, 61), Vector3(-50, 0, 61.5), "l1_top_west", 55.0, Vector3(0, 0, -1))
	await _view(Vector3(50, 70, 61), Vector3(50, 0, 61.5), "l1_top_east", 55.0, Vector3(0, 0, -1))

	# 2. A firing position from the enemy side (x = -23.5), and from behind.
	await _view(Vector3(-21.0, 1.0, 44.0), Vector3(-23.5, 0.3, 55.0), "l1_post2_front")
	await _view(Vector3(-28, 1.7, 30), Vector3(-23.5, 0.2, 52.5), "l1_post2_far")
	await _view(Vector3(-23.5, 4.5, 64), Vector3(-23.5, -0.6, 55.5), "l1_post2_back")
	await _view(Vector3(64, 1.7, 33), Vector3(64, 0.2, 53.5), "l1_post4_front")
	await _view(Vector3(-64, 3.0, 62), Vector3(-64, -0.5, 55.5), "l1_post1_back")

	# 3. The player's view: standing on the step, then crouching behind the sandbags.
	_cam.current = false
	p.global_position = Vector3(-23.5, -1.3, 58.0)
	p.input.look_yaw = 0.0
	p.input.look_pitch = 0.0
	p.input.move_dir = Vector2(0, -1)
	await get_tree().create_timer(2.5).timeout
	p.input.move_dir = Vector2.ZERO
	await get_tree().create_timer(0.5).timeout
	await _shot("l1_player_standing")
	p.input.crouch_held = true
	await get_tree().create_timer(0.8).timeout
	await _shot("l1_player_crouching")
	p.input.crouch_held = false

	# 4. In the trench: corners.
	for spot: Array in [[Vector3(-34, -1.3, 61), PI * 0.5, "l1_trench_a"], [Vector3(-52, -1.3, 62.5), PI * 0.5, "l1_trench_b"],
			[Vector3(60, -1.3, 59), -PI * 0.5, "l1_trench_c"]]:
		p.global_position = spot[0]
		p.input.look_yaw = spot[1]
		p.input.look_pitch = -0.05
		await get_tree().create_timer(0.6).timeout
		await _shot(spot[2])
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
