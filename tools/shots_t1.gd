extends Node
## Screenshots of the T-26 tank (T1, not part of the game). Saved in tools/shots/:
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_t1.gd

var _out: String


func _ready() -> void:
	await get_tree().process_frame
	_out = ProjectSettings.globalize_path("res://tools/shots/")
	DirAccess.make_dir_recursive_absolute(_out)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.god_mode = true
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	await get_tree().create_timer(3.0).timeout # shader warm-up

	# 1. From the trench: the tank comes across the bog.
	p.global_position = Vector3(10, -1.3, 61)
	var tank: Tank = spawner.spawn_tank(1)
	tank._distance = 120.0
	Engine.time_scale = 1.0
	await get_tree().create_timer(1.0).timeout
	_look_at(p, tank.global_position + Vector3(0, 1.2, 0))
	await get_tree().create_timer(0.3).timeout
	await _shot("t1_approach")

	# 2. Side view (a free camera): turret turned towards a player standing out on the left.
	p.input.crouch_held = false
	p.global_position = tank.global_position + Vector3(-25, 0, 20)
	p.global_position.y = (get_tree().get_first_node_in_group("terrain") as TerrainGenerator).get_height(p.global_position.x, p.global_position.z) + 0.1
	await get_tree().create_timer(4.0).timeout
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.global_position = tank.global_position + Vector3(9, 2.5, -2)
	cam.look_at(tank.global_position + Vector3(0, 1.2, 0))
	cam.fov = 55
	cam.current = true
	await get_tree().create_timer(0.3).timeout
	await _shot("t1_side")
	cam.global_position = tank.global_position + Vector3(-5, 3.2, 8)
	cam.look_at(tank.global_position + Vector3(0, 1.4, 0))
	await get_tree().create_timer(0.2).timeout
	await _shot("t1_front")

	# 3. At the trench edge, seen from the trench.
	cam.current = false
	p.global_position = Vector3(10, -1.3, 61)
	p.input.crouch_held = false
	tank._distance = tank._route_length - 1.0
	await get_tree().create_timer(3.0).timeout
	_look_at(p, tank.global_position + Vector3(0, 1.4, 0))
	await get_tree().create_timer(0.4).timeout
	await _shot("t1_trench_edge")

	# 4. Knocked out: dark wreck, smoke.
	tank.destroy()
	p.global_position = Vector3(-10, -1.3, 61)
	await get_tree().create_timer(8.0).timeout
	_look_at(p, tank.global_position + Vector3(0, 3.0, 0))
	await get_tree().create_timer(0.3).timeout
	await _shot("t1_wreck")
	get_tree().quit()


func _look_at(p: Player, target: Vector3) -> void:
	var d: Vector3 = target - p.head.global_position
	p.input.look_yaw = atan2(-d.x, -d.z)
	p.input.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + file + ".png")
	print("saved ", file)
