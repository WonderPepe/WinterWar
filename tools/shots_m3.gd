extends SceneTree
## Screenshots of the enemies for a visual check (not part of the game).
var p: Player

func _initialize() -> void:
	root.add_child(load("res://scenes/game.tscn").instantiate())
	root.get_node("Game/PauseMenu").free() # tests drive the game directly
	run()

func wait(n: int) -> void:
	for i in n:
		await process_frame

func snap(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://tools/shots/" + file)
	print("saved ", file)

func run() -> void:
	await wait(5)
	p = get_nodes_in_group("players")[0]
	p.input.set_process(false)
	p.god_mode = true
	var waves: WaveSpawner = get_first_node_in_group("wave_spawner")
	waves.first_wave_delay = 0.0
	waves._timer = 0.0
	waves.time_between_groups = 0.0
	Engine.time_scale = 20.0
	await create_timer(70.0).timeout # 3.5 s real time at 20x
	Engine.time_scale = 1.0
	Enemy.show_debug_labels = true
	p.global_position = Vector3(-10, -1.4, 61)
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(-1)
	await wait(20)
	await snap("m3_1_trench_view.png")
	# Close-up: one soldier kneeling, one dead
	var es: Array = get_nodes_in_group("enemies")
	var a: Enemy = es[0]
	var b: Enemy = es[1]
	for e: Enemy in es:
		e.set_physics_process(false)
	var base := Vector3(-20, 0, 0)
	var terrain: TerrainGenerator = get_first_node_in_group("terrain")
	a.global_position = Vector3(base.x - 1.5, terrain.get_height(base.x - 1.5, base.z), base.z)
	a.rotation.y = PI
	a.state = Enemy.State.ATTACK
	a.is_kneeling = true
	b.global_position = Vector3(base.x + 1.5, terrain.get_height(base.x + 1.5, base.z), base.z)
	b.rotation.y = PI - 0.4
	b.state = Enemy.State.PATROL
	var c: Enemy = es[2]
	c.global_position = Vector3(base.x + 4.5, terrain.get_height(base.x + 4.5, base.z - 2), base.z - 2)
	c.state = Enemy.State.DEAD
	p.global_position = Vector3(base.x, terrain.get_height(base.x, base.z + 7) , base.z + 7)
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(-6)
	await wait(60)
	await snap("m3_2_closeup.png")
	quit()
