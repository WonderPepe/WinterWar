extends Node
## Screenshots for T3 (tanks in the battles; not part of the game). Saved in tools/shots/:
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_t3.gd

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

	# 1. From the trench: a wave tank comes out of its lane in the forest.
	p.global_position = Vector3(10, -1.3, 61)
	var tank: Tank = spawner.spawn_wave_tank()
	tank._distance = -6.0
	await get_tree().create_timer(1.0).timeout
	_look_at(p, tank.global_position + Vector3(0, 1.2, 0))
	await get_tree().create_timer(0.3).timeout
	await _shot("t3_from_forest")
	# 2. Closer: a free camera out on the field.
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.global_position = tank.global_position + Vector3(14, 3.0, 30)
	cam.look_at(tank.global_position + Vector3(0, 1.2, 0))
	cam.fov = 55
	cam.current = true
	await get_tree().create_timer(0.3).timeout
	await _shot("t3_lane")
	get_tree().quit()


func _look_at(p: Player, target: Vector3) -> void:
	var d: Vector3 = target - p.head.global_position
	p.input.look_yaw = atan2(-d.x, -d.z)
	p.input.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + file + ".png")
	print("saved ", file)
