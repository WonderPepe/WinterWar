extends Node
## Graphics-polish screenshots from fixed views (not part of the game).
## Usage (needs a GL window, e.g. xvfb):
##   godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_p1.gd <prefix>

const VIEWS: Array = [
	# [name, position (feet), yaw deg, pitch deg]
	["trench", Vector3(-30, -1.4, 61), 0.0, 2.0],
	["trench_wall", Vector3(-22, -1.4, 59.5), 60.0, -8.0],
	["behind", Vector3(-6, 1.5, 76), 20.0, -12.0],
	["overview", Vector3(0, 60, 150), 0.0, -28.0],
	["bunker", Vector3(8, 0, 52), 140.0, -8.0],
	["field", Vector3(10, 0, -60), 180.0, 0.0],
	["forest", Vector3(-20, 0.5, 78), 160.0, 2.0],
	["sun", Vector3(-10, 0.0, 40), 30.0, 6.0],
	["bunker_near", Vector3(6, 0.3, 56), 150.0, -12.0],
	["bunker_inside", Vector3(0, -1.4, 68.8), 0.0, -3.0],
	["bog", Vector3(-20, 1.5, 10), 170.0, -14.0],
]


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[1] if args.size() > 1 else "shot"
	var only: String = args[2] if args.size() > 2 else "" # e.g. "forest,bunker"
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	game.get_node("HUD").visible = false
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.set_physics_process(false)
	p.weapons.set_process(false)
	for vm in p.weapons._view_models:
		vm.visible = false
	var waves := get_tree().get_first_node_in_group("wave_spawner")
	waves.set_process(false)
	for v in VIEWS:
		if only != "" and not (v[0] in only.split(",")):
			continue
		p.global_position = v[1]
		p.velocity = Vector3.ZERO
		p.input.look_yaw = deg_to_rad(v[2])
		p.input.look_pitch = deg_to_rad(v[3])
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_tree().root.get_viewport().get_texture().get_image()
		img.save_png("res://tools/shots/%s_%s.png" % [prefix, v[0]])
		print("saved ", v[0])
	get_tree().quit()
