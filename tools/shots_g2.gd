extends Node
## G2 screenshots: prone soldiers, the officer (also whistling), the DP-27 team (not part of the game).
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_g2.gd [prefix]


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[1] if args.size() > 1 else "g2"
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
	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")

	var enemies: Node = game.get_node("Enemies")
	# [scene, x, state, kneeling, prone, whistle]
	var lineup := [
		["soviet_officer", -5.0, Enemy.State.PATROL, false, false, false],
		["soviet_officer", -3.0, Enemy.State.ATTACK, false, false, true],
		["soviet_officer", -1.0, Enemy.State.ATTACK, false, false, false],
		["soviet_mg_gunner", 1.0, Enemy.State.PATROL, false, false, false],
		["soviet_rifleman", 3.0, Enemy.State.ATTACK, false, true, false],
		["soviet_mg_gunner", 5.0, Enemy.State.ATTACK, false, true, false],
		["soviet_officer", 7.5, Enemy.State.ATTACK, false, true, false],
	]
	var soldiers: Array[Enemy] = []
	for i in lineup.size():
		var e: Enemy = load("res://scenes/enemies/%s.tscn" % lineup[i][0]).instantiate()
		e.name = "Shot%d" % i
		enemies.add_child(e)
		e.set_physics_process(false)
		var x: float = lineup[i][1]
		e.global_position = Vector3(x, terrain.get_height(x, 20.0), 20.0)
		e.rotation.y = deg_to_rad(160.0) # facing the camera
		e.state = lineup[i][2]
		e.is_kneeling = lineup[i][3]
		e.is_prone = lineup[i][4]
		soldiers.append(e)
	await get_tree().create_timer(1.0).timeout
	soldiers[1].visual.play_whistle()
	p.global_position = Vector3(1.0, terrain.get_height(1, 28) + 0.2, 28.0)
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(-8.0)
	await _shot(prefix + "_lineup", 10)
	# Prone gunner close up from the front-left, and from the side.
	p.global_position = Vector3(4.0, terrain.get_height(4, 22.5) + 0.0, 22.5)
	p.input.look_yaw = deg_to_rad(10.0)
	p.input.look_pitch = deg_to_rad(-22.0)
	soldiers[5].show_shot_effects(Vector3(5, 0, 40), Vector3.UP, "snow")
	await _shot(prefix + "_gunner_front", 4)
	p.global_position = Vector3(8.5, terrain.get_height(8.5, 19.5) - 0.3, 19.0)
	p.input.look_yaw = deg_to_rad(80.0)
	p.input.look_pitch = deg_to_rad(-20.0)
	await _shot(prefix + "_prone_side", 10)
	# Officer whistling, close up.
	soldiers[1].visual.play_whistle()
	p.global_position = Vector3(-3.3, terrain.get_height(-3, 22) - 0.2, 22.3)
	p.input.look_yaw = deg_to_rad(-5.0)
	p.input.look_pitch = deg_to_rad(-2.0)
	await _shot(prefix + "_officer_whistle", 10)
	# Dead prone gunner.
	soldiers[5].take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	soldiers[4].take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	p.global_position = Vector3(4.0, terrain.get_height(4, 23) + 0.0, 23.5)
	p.input.look_yaw = deg_to_rad(5.0)
	p.input.look_pitch = deg_to_rad(-25.0)
	await _shot(prefix + "_dead_prone", 50)
	get_tree().quit()


func _shot(file: String, wait_frames: int) -> void:
	for i in wait_frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % file)
	print("saved ", OS.get_user_data_dir(), "/", file, ".png")
