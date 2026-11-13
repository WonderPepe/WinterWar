extends Node
## Screenshots for V2 (softer earthworks: snow lips, wall-foot drifts, rounded heaps, bunker snow).
## Saved in tools/shots/ (not part of the game):
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_v2.gd
## Add a prefix to compare two versions: ... -- tools/shots_v2.gd before_

var _out: String
var _prefix := "v2_"
var _game: Node
var _cam: Camera3D


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		_prefix = args[1]
	_out = ProjectSettings.globalize_path("res://tools/shots/")
	DirAccess.make_dir_recursive_absolute(_out)
	_game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(_game)
	_game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.god_mode = true
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	var dusk: DuskLight = _game.get_node("Dusk")
	dusk.set_process(false)
	(_game.get_node("HUD") as CanvasLayer).visible = false
	dusk._show_battle(3) # the clear freezing day
	await get_tree().create_timer(3.0).timeout # shader warm-up

	_cam = Camera3D.new()
	_game.add_child(_cam)
	_cam.current = true
	await _all_views("")
	dusk._show_battle(10) # dusk
	await get_tree().create_timer(1.0).timeout
	await _view(Vector3(-6, 1.7, 42), Vector3(0, 0.6, 56.5), "dusk_bunker")
	await _view(Vector3(-31, 0.3, 61), Vector3(-22, -1.2, 59.5), "dusk_trench")
	dusk._show_battle(2) # moonlit heavy snow
	await get_tree().create_timer(1.0).timeout
	await _view(Vector3(-21.0, 1.0, 44.0), Vector3(-23.5, 0.3, 55.0), "night_post")
	get_tree().quit()


func _all_views(tag: String) -> void:
	# Trench: from inside at eye height, from the edge looking along it, from above.
	await _view(Vector3(-33.5, 0.25, 61), Vector3(-22, -0.9, 59.0), tag + "trench_eye")
	await _view(Vector3(-12, -0.2, 61), Vector3(-20, -1.2, 59.5), tag + "trench_in")
	await _view(Vector3(-30, 2.2, 67), Vector3(-24, -1.0, 59.5), tag + "trench_rear")
	await _view(Vector3(12.5, 1.6, 66.5), Vector3(20, -1.2, 59.5), tag + "trench_corner")
	await _view(Vector3(-24, 14, 61), Vector3(-24, 0, 60), tag + "trench_top", 60.0, Vector3(0, 0, -1))
	# Firing position: from the enemy side, close and far, and from behind.
	await _view(Vector3(-21.0, 1.0, 51.0), Vector3(-23.5, 0.3, 55.0), tag + "post_close")
	await _view(Vector3(-21.0, 1.0, 44.0), Vector3(-23.5, 0.3, 55.0), tag + "post_front")
	await _view(Vector3(-23.5, 3.0, 62), Vector3(-23.5, -0.4, 55.5), tag + "post_back")
	# Bunker: from the enemy side, a corner, from behind.
	await _view(Vector3(-6, 1.7, 42), Vector3(0, 0.6, 56.5), tag + "bunker_front")
	await _view(Vector3(-7.5, 1.6, 53.5), Vector3(-1, 0.7, 58.5), tag + "bunker_corner")
	await _view(Vector3(6, 4.5, 68), Vector3(0.5, -1.0, 61), tag + "bunker_back")
	# Exit ramp and a communication trench.
	await _view(Vector3(-77, 2.0, 73), Vector3(-80, -0.8, 66), tag + "exit_ramp")
	await _view(Vector3(-36, 3.0, 78), Vector3(-42, -1.2, 88), tag + "comm_trench")
	await _view(Vector3(-40, 1.2, 116), Vector3(-40, -0.9, 106), tag + "comm_ramp")


func _view(from: Vector3, to: Vector3, file: String, fov := 60.0, up := Vector3.UP) -> void:
	_cam.current = true
	_cam.fov = fov
	_cam.global_position = from
	_cam.look_at(to, up)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + _prefix + file + ".png")
	print("saved ", file)
