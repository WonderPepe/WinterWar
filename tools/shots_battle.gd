extends Node
## Lets a wave attack for a while and takes screenshots from the trench (not part of the game).
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_battle.gd [prefix]

func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[1] if args.size() > 1 else "battle"
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 10:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.god_mode = true
	var waves := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	waves.first_wave_delay = 0.0
	waves._timer = 0.0
	waves.base_enemies = 10
	waves.group_size_min = 5
	waves.group_size_max = 5
	waves.time_between_groups = 0.0
	# Spawn closer so the shots don't take minutes on a software renderer.
	for m in get_tree().get_nodes_in_group("enemy_spawn"):
		(m as Node3D).position.z = -20.0
	p.global_position = Vector3(-20, -1.4, 59.0)
	p.input.look_yaw = deg_to_rad(5.0)
	p.input.look_pitch = deg_to_rad(1.0)
	p.weapons.current_slot = 1
	var n := 0
	for t in [12.0, 8.0, 8.0]:
		await get_tree().create_timer(t).timeout
		# Fire a burst at the nearest soldier for the screenshot.
		var target: Enemy = null
		for e in get_tree().get_nodes_in_group("enemies"):
			if (e as Enemy).state != Enemy.State.DEAD and (target == null or e.global_position.distance_to(p.global_position) < target.global_position.distance_to(p.global_position)):
				target = e
		if target:
			var d: Vector3 = target.global_position + Vector3(0, 1.2, 0) - p.camera.global_position
			p.input.look_yaw = atan2(-d.x, -d.z)
			p.input.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())
		p.input.aim_held = n == 1
		p.input.fire_held = true
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tools/shots/%s_%d.png" % [prefix, n])
		print("saved ", n, " enemies alive ", waves.alive_count)
		p.input.fire_held = false
		n += 1
	get_tree().quit()
