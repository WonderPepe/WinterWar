extends Node
## Screenshots of the Soviets crouching in the trench (EC1, not part of the game). Saved in tools/shots/:
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_ec1.gd

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
	p.god_mode = true
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	game.get_node("HUD").day_screen.close_now()
	await get_tree().create_timer(3.0).timeout # shader warm-up

	# Three soldiers in the trench: standing, crouching still (aiming), crouch-walking.
	var men: Array[Enemy] = []
	for i in 3:
		var e: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
		e.name = "EC1Shot%d" % i
		e.position = Vector3(-33.0 - i * 2.2, -1.35, 61.0 + (i % 2) * 0.5)
		game.get_node("Enemies").add_child(e, true)
		e.set_physics_process(false)
		e.state = Enemy.State.ASSAULT
		e.rotation.y = -PI / 2.0 # facing +x, towards the camera
		men.append(e)
	men[1].is_crouching = true
	men[2].is_crouching = true

	# Along the trench floor: they come towards you.
	p.global_position = Vector3(-28.5, -1.4, 60.8)
	_look_at(p, Vector3(-35.0, -0.6, 61.0))
	for f in 60:
		men[2].global_position.x += 0.035 # walking (the visual takes his speed from his movement)
		await get_tree().process_frame
	await _shot("ec1_side")
	for f in 14:
		men[2].global_position.x += 0.035
		await get_tree().process_frame
	await _shot("ec1_side_step")

	# Pose check: the same three on open ground, seen from the side (own camera).
	var cam := Camera3D.new()
	game.add_child(cam)
	for i in 3:
		var y: float = terrain_y(-20.0 - i * 1.4, 30.0)
		men[i].global_position = Vector3(-20.0 - i * 1.4, y, 30.0)
	cam.global_position = Vector3(-22.0, terrain_y(-22.0, 34.5) + 1.0, 34.5)
	cam.look_at(Vector3(-21.4, terrain_y(-21.4, 30.0) + 0.8, 30.0))
	cam.make_current()
	for f in 30:
		men[2].global_position.x += 0.035
		men[2].global_position.y = terrain_y(men[2].global_position.x, 30.0)
		await get_tree().process_frame
	await _shot("ec1_pose_side")
	cam.queue_free()
	for i in 3:
		men[i].rotation.y = -PI / 2.0
		men[i].global_position = Vector3(-33.0 - i * 2.2, -1.35, 61.0 + (i % 2) * 0.5)
	p.camera.make_current() if "camera" in p else null
	await get_tree().process_frame

	# From the field in front of the trench: the crouching heads stay below the edge.
	p.global_position = Vector3(-35.0, terrain_y(-35.0, 50.0), 50.0)
	_look_at(p, Vector3(-35.0, -0.3, 61.0))
	await get_tree().create_timer(0.5).timeout
	await _shot("ec1_from_field")
	print("SHOTS DONE")
	get_tree().quit()


func terrain_y(x: float, z: float) -> float:
	return (get_tree().get_first_node_in_group("terrain") as TerrainGenerator).get_height(x, z)


func _look_at(p: Player, target: Vector3) -> void:
	var d: Vector3 = target - p.head.global_position
	p.input.look_yaw = atan2(-d.x, -d.z)
	p.input.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + file + ".png")
	print("saved ", file)
