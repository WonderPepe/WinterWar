extends Node
## NET2b screenshots: the Finnish soldier body the other players see, in its poses
## (not part of the game).
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_net2b.gd [prefix]

var _walkers: Array = [] # [player, start, direction, speed]


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[1] if args.size() > 1 else "net2b"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
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
	p.get_node("Head/Camera3D/Arms").set_process(false)
	p.get_node("Head/Camera3D/Arms").visible = false
	var dusk: DuskLight = game.get_node("Dusk")
	dusk.set_process(false)
	dusk._show_battle(int(args[2]) if args.size() > 2 else 3) # battle 3: daylight
	dusk._apply_blend(0.0)

	var scene: PackedScene = load("res://scenes/player.tscn")
	# [x, crouch, slot, aim, pitch deg, walk speed, sprint]
	var lineup := [[-5.0, false, 0, false, 0.0, 0.0, false], [-3.6, false, 0, false, 0.0, 1.6, false],
		[-1.0, true, 0, false, 0.0, 0.0, false], [1.0, false, 1, true, 15.0, 0.0, false],
		[3.0, false, 1, false, -10.0, 0.0, false], [5.0, true, 1, false, 0.0, 1.2, false]]
	var finns: Array[Player] = []
	for i in lineup.size():
		var f: Player = _add_finn(game, scene, "%d" % (2 + i), Vector3(lineup[i][0], 0.0, 20.0), 200.0)
		f.is_crouching = lineup[i][1]
		f.weapons.current_slot = lineup[i][2]
		f.input.aim_held = lineup[i][3]
		f.input.look_pitch = deg_to_rad(lineup[i][4])
		if lineup[i][5] > 0.0:
			_walkers.append([f, f.global_position, Vector3(1, 0, 0.0), lineup[i][5]])
		finns.append(f)
	p.global_position = Vector3(0, -0.5, 27.5)
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(-6.0)
	await _shot(prefix + "_lineup", 60)
	# Close-up: front three-quarter.
	p.global_position = Vector3(-4.0, -0.3, 23.0)
	p.input.look_yaw = deg_to_rad(-15.0)
	p.input.look_pitch = deg_to_rad(-12.0)
	await _shot(prefix + "_close", 20)
	for f in finns:
		print(f.name, " hands=", f.body._hands(), " speed=", f.body._speed, " sprint=", f.is_sprinting, " aim=", f.input.aim_held, " reload=", f.weapons.is_reloading, " slot=", f.weapons.current_slot)
	# Portrait from the front, 1.8 m away.
	var fwd: Vector3 = -finns[0].global_basis.z
	p.global_position = finns[0].global_position + fwd * 1.8 + Vector3.UP * -0.25
	p.input.look_yaw = finns[0].input.look_yaw + PI
	p.input.look_pitch = deg_to_rad(-8.0)
	await _shot(prefix + "_portrait", 20)
	# The same in sunlight: he turns round, the camera goes to his other side.
	finns[0].input.look_yaw += PI
	for i in 3:
		await get_tree().process_frame
	fwd = -finns[0].global_basis.z
	p.global_position = finns[0].global_position + fwd * 1.8 + finns[0].global_basis.x * 0.6 + Vector3.UP * -0.25
	p.input.look_yaw = finns[0].input.look_yaw + PI + 0.3
	await _shot(prefix + "_portrait_sun", 20)
	finns[0].input.look_yaw -= PI
	# From behind (the hood bunched at the neck) and the side.
	finns[0].input.look_yaw = deg_to_rad(20.0)
	p.global_position = Vector3(-4.7, -0.4, 21.9)
	p.input.look_yaw = deg_to_rad(-6.0)
	p.input.look_pitch = deg_to_rad(-14.0)
	await _shot(prefix + "_back", 30)
	finns[0].input.look_yaw = deg_to_rad(110.0)
	await _shot(prefix + "_side", 30)
	# Hands busy: Molotov lit, climbing, bandaging; then the Suomi firing.
	finns[2].is_crouching = false
	finns[2].molotov.count = 1
	finns[2].molotov.phase = MolotovHandler.Phase.LIT
	finns[3].is_bandaging = true
	finns[4].is_climbing = true
	p.global_position = Vector3(1.0, -0.5, 26.0)
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(-10.0)
	await _shot(prefix + "_busy", 40)
	finns[3].is_bandaging = false
	finns[4].is_climbing = false
	finns[4].input.look_pitch = 0.0
	finns[4].weapons._play_remote_fire_effects()
	p.global_position = Vector3(3.5, -0.3, 23.0)
	p.input.look_yaw = deg_to_rad(10.0)
	p.input.look_pitch = deg_to_rad(-10.0)
	await _shot(prefix + "_fire", 2)
	# Dead.
	finns[1].is_dead = true
	_walkers.clear()
	p.global_position = Vector3(-3.0, -0.3, 24.0)
	p.input.look_yaw = deg_to_rad(0.0)
	p.input.look_pitch = deg_to_rad(-25.0)
	await _shot(prefix + "_dead", 60)
	# On the Maxim in the bunker.
	var gun := get_tree().get_first_node_in_group("mounted_guns") as MountedGun
	if gun:
		var g: Player = finns[5]
		g.is_crouching = false
		g.global_position = gun.get_node("SeatPoint").global_position if gun.has_node("SeatPoint") else gun.global_position
		gun.mount(g)
		g.input.look_yaw = gun.get_base_yaw()
		for i in 5:
			await get_tree().process_frame
		var back: Vector3 = g.global_basis.z
		p.global_position = g.global_position + back * 1.6 + g.global_basis.x * 0.9 + Vector3.UP * -0.3
		p.input.look_yaw = g.input.look_yaw + deg_to_rad(25.0)
		p.input.look_pitch = deg_to_rad(-15.0)
		await _shot(prefix + "_maxim", 30)
	get_tree().quit()


func _add_finn(game: Node, scene: PackedScene, peer: String, at: Vector3, yaw_deg: float) -> Player:
	var f: Player = scene.instantiate()
	f.name = peer # not this computer's peer id: shown as another player
	var parent: Node = (get_tree().get_first_node_in_group("players") as Node).get_parent()
	parent.add_child(f)
	f.set_physics_process(false)
	f.input.set_process(false)
	f.weapons.set_process(false)
	f.weapons.holder.visible = false # (the game hides the other players' first-person guns itself)
	f.molotov.set_physics_process(false) # (its host rules would message a peer that does not exist)
	f.global_position = at
	f.input.look_yaw = deg_to_rad(yaw_deg)
	return f


func _process(delta: float) -> void:
	for w in _walkers:
		var f: Player = w[0]
		var start: Vector3 = w[1]
		var offset: float = fmod((f.global_position - start).length() + w[3] * delta, 4.0)
		f.global_position = start + (w[2] as Vector3) * offset
		f.input.look_yaw = atan2(-(w[2] as Vector3).x, -(w[2] as Vector3).z)


func _shot(n: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/shots/%s.png" % n)
	print("saved ", n)
