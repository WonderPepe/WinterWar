extends Node
## Screenshots of the artillery barrage from the trench (not part of the game):
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_artillery.gd

func _ready() -> void:
	await get_tree().process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.god_mode = true
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	p.global_position = Vector3(-30, -1.3, 61)
	p.input.look_yaw = deg_to_rad(10.0)
	p.input.look_pitch = deg_to_rad(4.0)
	var arty := game.get_node("ArtilleryBarrage") as ArtilleryBarrage
	arty.start()
	await get_tree().create_timer(4.2).timeout
	for t in [5.0, 2.5, 6.0, 3.6]:
		await get_tree().create_timer(t).timeout
		await _shot("arty_%d" % arty.shells_fired)
	await get_tree().create_timer(12.0).timeout
	await _shot("arty_after")
	get_tree().quit()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % file)
	print("saved ", file)
