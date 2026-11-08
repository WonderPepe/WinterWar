extends Node
## Screenshots of every battle's weather (B3) from the first firing position, looking at the
## enemy side: weather_01.png … weather_10.png, plus weather_08_end.png and weather_10_end.png.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_weather.gd
## Pictures go to the user data folder.

func _ready() -> void:
	await get_tree().process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	var dusk: DuskLight = game.get_node("Dusk")
	dusk.set_process(false)
	var hud := game.get_node("HUD") as CanvasLayer
	hud.visible = false
	p.global_position = Vector3(-30, 0.0, 40) # in front of the trench, looking at the forest
	p.input.look_yaw = 0.0
	p.input.look_pitch = 0.03
	var steps: Array = [[1, 0.0, "01"], [2, 0.0, "02"], [3, 0.0, "03"], [4, 0.0, "04"], [5, 0.0, "05"], [6, 0.0, "06"],
			[7, 0.0, "07"], [8, 0.0, "08"], [8, 1.0, "08_end"], [9, 0.0, "09"], [10, 0.0, "10"], [10, 1.0, "10_end"]]
	for s in steps:
		dusk._show_battle(s[0])
		dusk._apply_blend(s[1])
		for i in 45:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://weather_%s.png" % s[2])
	get_tree().quit()
