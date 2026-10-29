extends SceneTree
## Renders screenshots of the level for a visual check (not part of the game).

func _initialize() -> void:
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	run()

func shot(p: Player, pos: Vector3, yaw_deg: float, pitch_deg: float, file: String) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.input.look_yaw = deg_to_rad(yaw_deg)
	p.input.look_pitch = deg_to_rad(pitch_deg)
	for i in 30:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://tools/shots/" + file)
	print("saved ", file)

func run() -> void:
	for i in 20:
		await process_frame
	var p: Player = get_nodes_in_group("players")[0]
	p.input.set_process(false)
	p.set_physics_process(false)
	p.head.position.y = 1.6
	await shot(p, Vector3(-30, -1.4, 61), 0, 2, "1_trench_view.png")
	await shot(p, Vector3(-6, 1.5, 76), 20, -12, "2_behind_trench.png")
	await shot(p, Vector3(0, 60, 150), 0, -28, "3_overview.png")
	await shot(p, Vector3(8, 0, 52), 140, -8, "4_bunker.png")
	await shot(p, Vector3(0, -1.4, 68.5), 0, 0, "5_inside_bunker.png")
	await shot(p, Vector3(10, 0, -60), 180, 0, "6_field_to_trench.png")
	quit()
