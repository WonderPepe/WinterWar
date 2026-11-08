extends Node
## Screenshots of the air raid from the trench (not part of the game):
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_airraid.gd

func _ready() -> void:
	await get_tree().process_frame
	Settings.difficulty = 1
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.god_mode = true
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	p.global_position = Vector3(-30, 0.3, 52)
	p.input.look_yaw = deg_to_rad(0.0)
	p.input.look_pitch = deg_to_rad(12.0)
	var raid := game.get_node("AirRaid") as AirRaid
	raid.start(false)
	var clock := 0.0
	for t in [3.0, 6.0, 8.0, 9.5, 10.5, 11.5, 12.2, 13.0, 14.0, 15.5]:
		await get_tree().create_timer(t - clock).timeout
		clock = t
		# Look at the first plane (the second pair of shots look straight ahead).
		var d: Vector3 = raid.plane_position(0, raid.time) - p.global_position
		p.input.look_yaw = atan2(-d.x, -d.z)
		p.input.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())
		await _shot("raid_%04.1f" % raid.time)
	get_tree().quit()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/shots/%s.png" % file)
	print("saved ", file)
