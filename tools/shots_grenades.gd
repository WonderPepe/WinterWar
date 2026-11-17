extends Node
## Screenshots of the Soviet hand grenades (GR1, not part of the game). Saved in tools/shots/:
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_grenades.gd

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
	await get_tree().create_timer(3.0).timeout # shader warm-up
	var manager: GrenadeManager = get_tree().get_first_node_in_group("grenades")

	# 1. A soldier throwing, seen from the side (the player stands next to him in the open).
	var e: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
	e.name = "ShotThrower"
	var at := Vector3(8.0, terrain_y(8.0, 44.0) + 0.05, 44.0)
	e.position = at
	game.get_node("Enemies").add_child(e, true)
	e.set_physics_process(false)
	e.rotation.y = 0.0 # facing -z ... turn him to face the trench (+z)
	e.rotation.y = PI
	e.state = Enemy.State.ATTACK
	await get_tree().create_timer(0.5).timeout
	p.global_position = Vector3(4.6, terrain_y(4.6, 45.0), 45.0)
	_look_at(p, at + Vector3(0, 1.2, 0))
	await get_tree().create_timer(0.5).timeout
	e.is_throwing = true
	await get_tree().create_timer(0.32).timeout
	await _shot("gr1_throw_cocked")
	await get_tree().create_timer(0.25).timeout
	await _shot("gr1_throw_release")
	await get_tree().create_timer(0.25).timeout
	await _shot("gr1_throw_follow")
	e.is_throwing = false
	e.queue_free()

	# 2. From the trench: a grenade comes over the parapet and lands near you (+ the icon).
	p.global_position = Vector3(-31.0, -1.4, 61.0)
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(8.0)
	await get_tree().create_timer(0.3).timeout
	var origin := Vector3(-29.0, terrain_y(-29.0, 42.0) + 1.9, 42.0)
	var target := Vector3(-30.0, -1.4, 61.0)
	manager.throw(origin, manager.solve_throw(origin, target, 40.0), -1, false, 3.6)
	await get_tree().create_timer(1.0).timeout
	await _shot("gr1_incoming")
	await get_tree().create_timer(0.7).timeout
	_look_at(p, target)
	await get_tree().create_timer(0.3).timeout
	await _shot("gr1_landed_icon")
	p.input.look_yaw = PI # turned away: the icon sits at the screen edge with an arrow
	p.input.look_pitch = 0.0
	await get_tree().create_timer(0.3).timeout
	await _shot("gr1_icon_behind")
	p.global_position = Vector3(-31.0, -1.4, 68.0) # (a wall between – the burst can't reach)
	p.input.look_yaw = PI
	await get_tree().create_timer(0.2).timeout
	p.global_position = Vector3(-37.0, -1.4, 63.5)
	_look_at(p, target)
	await get_tree().create_timer(1.15).timeout
	await _shot("gr1_burst")

	# 3. Close-up of a grenade lying on the trench floor.
	p.global_position = Vector3(12.0, -1.4, 61.0)
	manager.throw(Vector3(12.8, -1.0, 61.2), Vector3.ZERO, -1, false, 4.0)
	await get_tree().create_timer(0.6).timeout
	_look_at(p, Vector3(12.8, -1.35, 61.2))
	p.is_crouching = true
	await get_tree().create_timer(0.6).timeout
	await _shot("gr1_closeup")

	# 4. GR2: the [F] key on the icon, then snatching it up and throwing it back.
	p.is_crouching = false
	await get_tree().create_timer(4.0).timeout # (the close-up grenade goes off first)
	p.global_position = Vector3(50.0, -1.4, 61.3)
	manager.throw(Vector3(50.0, -1.1, 60.4), Vector3.ZERO, -1, false, 3.5)
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(-35.0)
	await get_tree().create_timer(0.5).timeout
	await _shot("gr2_key")
	p.input.look_pitch = deg_to_rad(10.0)
	p.grab.try_grab()
	await get_tree().create_timer(0.2).timeout
	await _shot("gr2_cocked")
	await get_tree().create_timer(0.17).timeout
	await _shot("gr2_throw")
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
