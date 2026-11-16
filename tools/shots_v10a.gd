extends Node
## Pictures for V10a (spruce sway, cloud drift; not part of the game). Saved in tools/shots/:
##   xvfb-run godot --rendering-driver opengl3 --fixed-fps 20 --path . --script tools/run.gd -- tools/shots_v10a.gd [battle] [frames] [wind]
## (`wind` = try another wind strength with that battle's light, e.g. 1.6 in the daylight of battle 3.)
## Saves `frames` pictures in a row of trees near the camera (v10a_b<battle>_trees_NN.png) – with
## --fixed-fps 20 that is 20 pictures per second of game time – and two pictures of the sky
## 60 game seconds apart (v10a_b<battle>_sky_a / _b.png).

var _out: String
var _cam: Camera3D


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var battle: int = int(args[1]) if args.size() > 1 else 2
	var count: int = int(args[2]) if args.size() > 2 else 40
	_out = ProjectSettings.globalize_path("res://tools/shots/")
	DirAccess.make_dir_recursive_absolute(_out)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.god_mode = true
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	get_tree().get_first_node_in_group("match_director").set_process(false)
	game.get_node("HUD").visible = false
	var dusk := game.get_node("Dusk") as DuskLight
	dusk.wait_for_black = 1.0e9 # the script chooses the look (the clouds keep drifting)
	dusk._show_battle(battle)
	if args.size() > 3:
		dusk.look = dusk.look.duplicate()
		dusk.look.wind = float(args[3])
		(get_tree().get_first_node_in_group("forest") as ForestScatter).set_wind(dusk.look.wind, WeatherData.WIND_DIRECTION)
	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")
	_cam = Camera3D.new()
	game.add_child(_cam)
	_cam.fov = 60
	_cam.current = true
	# Behind the trench, looking at the edge of the northern forest.
	_cam.global_position = Vector3(-18, 2.2, 71)
	_cam.look_at(Vector3(-8, 4.5, 90))
	for i in 60:
		await get_tree().process_frame # shader warm-up
	var prefix: String = "v10a_b%d_" % battle
	if args.size() > 3:
		prefix += "w%s_" % args[3]
	for i in count:
		await _shot(prefix + "trees_%02d" % i)
	# The sky: looking up to the south-west, two pictures 60 game seconds apart.
	_cam.global_position = Vector3(0, terrain.get_height(0, 30) + 1.7, 30)
	_cam.look_at(_cam.global_position + Vector3(-0.5, 0.75, -1.0))
	await get_tree().create_timer(0.3).timeout
	await _shot(prefix + "sky_a")
	Engine.time_scale = 4.0
	await get_tree().create_timer(60.0).timeout
	Engine.time_scale = 1.0
	await _shot(prefix + "sky_b")
	print("clouds drifted to ", dusk.get_cloud_offset(), "  wind ", dusk.look.wind)
	get_tree().quit()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + file + ".png")
