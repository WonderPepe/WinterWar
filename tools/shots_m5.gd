extends Node
## Screenshots of the three quality levels from the same spot (not part of the game).

func _ready() -> void:
	await get_tree().process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.global_position = Vector3(-6, 1.0, 76)
	p.set_physics_process(false)
	p.input.look_yaw = deg_to_rad(20)
	p.input.look_pitch = deg_to_rad(-10)
	for q in [Settings.Quality.LOW, Settings.Quality.MEDIUM, Settings.Quality.HIGH]:
		Settings.set_quality(q)
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_tree().root.get_viewport().get_texture().get_image().save_png("res://tools/shots/m5_%s.png" % Settings.Quality.keys()[q].to_lower())
		print("saved ", Settings.Quality.keys()[q])
	get_tree().quit()
