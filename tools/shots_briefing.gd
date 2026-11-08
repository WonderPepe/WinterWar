extends Node
## Screenshots of the loading screen with the briefing (B1), for battles 1, 7 (upright photo) and 9.
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_briefing.gd
## Pictures go to the user data folder (briefing_1.png …).

func _ready() -> void:
	await get_tree().process_frame
	for b in [1, 7, 9]:
		MatchDirector.test_start_wave = b if b > 1 else 0
		LoadingScreen.target_scene = "res://ui/controls_panel.tscn" # a tiny scene: only the briefing is photographed
		LoadingScreen.click_to_start = true
		var ls: Node = load("res://ui/loading_screen.tscn").instantiate()
		get_tree().root.add_child(ls)
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://briefing_%d.png" % b)
		ls.free()
	MatchDirector.test_start_wave = 0
	get_tree().quit()
