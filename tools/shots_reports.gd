extends Node
## Screenshots of the front report after a wave and on the victory screen (not part of the game).
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_reports.gd

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
	var director: MatchDirector = get_tree().get_first_node_in_group("match_director")
	director.waves_cleared = 2
	await get_tree().create_timer(1.5).timeout
	await _shot("report_wave2")
	director.waves_cleared = director.waves_to_win
	director.end_match(MatchDirector.Result.VICTORY)
	await get_tree().create_timer(0.5).timeout
	await _shot("report_victory")
	get_tree().quit()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % file)
	print("saved ", file)
