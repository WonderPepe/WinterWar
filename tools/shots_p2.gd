extends Node
## P2 screenshots: soldiers in different poses, impact sprays, gun smoke (not part of the game).
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_p2.gd [prefix]

var _walkers: Array = [] # [enemy, start, direction, speed]


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[1] if args.size() > 1 else "p2"
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	game.get_node("HUD").visible = false
	for i in 20:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.set_physics_process(false)
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	for vm in p.weapons._view_models:
		vm.visible = false
	p.weapons.set_process(false)

	var scene: PackedScene = load("res://scenes/enemies/soviet_rifleman.tscn")
	var enemies: Node = game.get_node("Enemies")
	# [x, state, kneeling, walking speed]
	var lineup := [[-4.0, Enemy.State.PATROL, false, 0.0], [-2.0, Enemy.State.PATROL, false, 1.4],
		[0.0, Enemy.State.ATTACK, false, 3.2], [2.0, Enemy.State.ATTACK, true, 0.0], [4.0, Enemy.State.ATTACK, false, 0.0]]
	var soldiers: Array[Enemy] = []
	for i in lineup.size():
		var e: Enemy = scene.instantiate()
		e.name = "Shot%d" % i
		enemies.add_child(e)
		e.set_physics_process(false)
		e.global_position = Vector3(lineup[i][0], 0.0, 20.0)
		e.rotation.y = deg_to_rad(160.0) # facing the camera
		e.state = lineup[i][1]
		e.is_kneeling = lineup[i][2]
		if lineup[i][3] > 0.0:
			_walkers.append([e, e.global_position, Vector3(0.34, 0, 0.94), lineup[i][3]])
		soldiers.append(e)
	p.global_position = Vector3(0, -0.5, 27.5)
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(-6.0)
	await _shot(prefix + "_lineup", 60)
	# Close-up of the kneeling one firing.
	p.global_position = Vector3(2.6, -0.6, 22.2)
	p.input.look_yaw = deg_to_rad(20.0)
	p.input.look_pitch = deg_to_rad(-10.0)
	soldiers[3].show_shot_effects(Vector3(2, 0, 30), Vector3.UP, "snow")
	await _shot(prefix + "_kneel_fire", 6)
	# Walking soldier from the side.
	p.global_position = Vector3(-5.5, -0.5, 22.0)
	p.input.look_yaw = deg_to_rad(-70.0)
	p.input.look_pitch = deg_to_rad(-5.0)
	await _shot(prefix + "_walk_side", 20)
	# Dead.
	soldiers[4].take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	p.global_position = Vector3(5.5, -0.3, 23.0)
	p.input.look_yaw = deg_to_rad(40.0)
	p.input.look_pitch = deg_to_rad(-25.0)
	await _shot(prefix + "_dead", 60)
	# Impact sprays and smoke.
	var fx: ImpactEffects = get_tree().get_first_node_in_group("impact_effects")
	p.global_position = Vector3(-10, -0.5, 30.0)
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(-12.0)
	for i in 30:
		await get_tree().process_frame
	fx.spawn_impact(Vector3(-10.5, terrain_h(-10.5, 26.0), 26.0), Vector3.UP, "snow")
	fx.spawn_impact(Vector3(-9.0, terrain_h(-9.0, 26.5), 26.5), Vector3(0.3, 0.9, 0.3).normalized(), "snow")
	fx.spawn_impact(Vector3(-11.5, 0.8, 27.0), Vector3(0, 0, 1), "wood")
	fx.spawn_smoke(Vector3(-11.5, 1.0, 27.8), Vector3(0.3, 0, -1))
	await _shot(prefix + "_impacts", 5)
	get_tree().quit()


func terrain_h(x: float, z: float) -> float:
	return (get_tree().get_first_node_in_group("terrain") as TerrainGenerator).get_height(x, z)


func _process(delta: float) -> void:
	for w in _walkers:
		var e: Enemy = w[0]
		if not is_instance_valid(e):
			continue
		var start: Vector3 = w[1]
		var offset: float = fmod((e.global_position.z - start.z) + w[3] * delta, 4.0)
		e.global_position = start + (w[2] as Vector3) * offset


func _shot(n: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/shots/%s.png" % n)
	print("saved ", n)
