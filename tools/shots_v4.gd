extends Node
## Screenshots for V4 (sandbags: burlap texture, sagging bags, no gaps to see through).
## Saved in tools/shots/ (not part of the game):
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_v4.gd
## Add a prefix to compare two versions: ... -- tools/shots_v4.gd before_

var _out: String
var _prefix := "v4_"
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
	var post: Node3D = get_tree().get_nodes_in_group("fire_post")[1]
	var o := post.global_position
	# From the enemy side: close, very close, from the side and from far away.
	await _view(o + Vector3(1.6, 0.9, -3.2), o + Vector3(0, 0.4, -0.3), "front_close")
	await _view(o + Vector3(0.9, 0.55, -1.5), o + Vector3(0.75, 0.3, -0.3), "front_jamb", 45.0)
	await _view(o + Vector3(-2.6, 1.0, -2.2), o + Vector3(0, 0.4, -0.3), "front_side")
	await _view(o + Vector3(2.5, 1.0, -11.0), o + Vector3(0, 0.3, 0.0), "front_far")
	# From the soldier's side: his eyes in the bay (0.2 m above the ground), straight and at the
	# jamb beside the hole (this is where daylight showed between the bags), and from above.
	await _view(o + Vector3(0, 0.2, 0.75), o + Vector3(0, 0.2, -10), "eye_view", 75.0)
	await _view(o + Vector3(0.1, 0.25, 0.9), o + Vector3(0.95, 0.25, -0.3), "eye_jamb", 60.0)
	await _view(o + Vector3(-0.1, 0.25, 0.9), o + Vector3(-0.95, 0.3, -0.3), "eye_jamb_west", 60.0)
	await _view(o + Vector3(0, 2.4, 2.6), o + Vector3(0, 0.3, -0.3), "back_above")
	dusk._show_battle(10) # dusk
	await get_tree().create_timer(1.0).timeout
	await _view(o + Vector3(1.6, 0.9, -3.2), o + Vector3(0, 0.4, -0.3), "dusk_front")
	get_tree().quit()


func _view(from: Vector3, to: Vector3, file: String, fov := 60.0) -> void:
	_cam.current = true
	_cam.fov = fov
	_cam.near = 0.03
	_cam.global_position = from
	_cam.look_at(to, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + _prefix + file + ".png")
	print("saved ", file)
