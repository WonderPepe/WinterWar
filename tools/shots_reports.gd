extends Node
## Screenshots of the day screen (photo + front report) after waves and of the victory screen.
## Optional argument: the days to show, e.g. "2 7" (default 2 7).
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
	var days: Array[int] = [2, 7]
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		days.clear()
		for a in args.slice(1):
			days.append(int(a))
	var day: DayScreen = get_tree().get_first_node_in_group("game").get_node("HUD/DayScreen")
	for d in days:
		director.waves_cleared = d
		await get_tree().create_timer(1.0).timeout
		await _shot("day%d_completed" % d)
		await get_tree().create_timer(day.intro_delay + 2.2 - day._t - day.intro_delay).timeout
		await _shot("day%d_title" % d)
		await get_tree().create_timer(2.5).timeout
		await _shot("day%d_typing" % d)
		await get_tree().create_timer(day._total - day._t - 1.0).timeout
		await _shot("day%d_read" % d)
		day.close_now()
		await get_tree().create_timer(0.3).timeout
	director.waves_cleared = director.waves_to_win
	director.end_match(MatchDirector.Result.VICTORY)
	await get_tree().create_timer(0.5).timeout
	await _shot("report_victory")
	get_tree().quit()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % file)
	print("saved ", file)
