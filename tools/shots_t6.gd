extends Node
## Pictures for T6 "running tracks" (not part of the game). Saved in tools/shots/:
##   xvfb-run godot --rendering-driver opengl3 --fixed-fps 30 --path . --script tools/run.gd -- tools/shots_t6.gd [battle]
## `battle` (1–10, default 2) chooses the light – use the darkest battle to check that the tracks
## can still be seen moving at dusk. A camera rides along beside the driving tank:
##   t6_b<battle>_side_0..5   the whole left side, six pictures in a row (one every 1/30 s of game
##                            time: flip through them – links, snow patches and wheels must move)
##   t6_b<battle>_sprocket_0..2  close-up of the drive sprocket and the first road wheels
##   t6_b<battle>_front       from the front quarter: both belts
##   t6_b<battle>_far_0..1   from 55 m: what a player in the trench sees (two pictures in a row)

var _out: String
var _cam: Camera3D
var _tank: Tank


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var battle: int = int(args[1]) if args.size() > 1 else 2
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
	dusk.wait_for_black = 1.0e9 # the script chooses the look
	dusk._show_battle(battle)
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	await get_tree().create_timer(3.0).timeout # shader warm-up
	_tank = spawner.spawn_tank(1)
	_cam = Camera3D.new()
	game.add_child(_cam)
	_cam.fov = 50
	_cam.current = true
	await get_tree().create_timer(6.0).timeout # it drives out onto the field, up to full speed
	var prefix: String = "t6_b%d_" % battle

	for i in 6:
		_place(Vector3(-6.0, 1.0, 0.0), Vector3(-1.0, 0.6, 0.0))
		await _shot(prefix + "side_%d" % i)
	_cam.fov = 30
	for i in 3:
		_place(Vector3(-3.2, 0.9, -1.6), Vector3(-1.0, 0.6, -1.5))
		await _shot(prefix + "sprocket_%d" % i)
	_cam.fov = 50
	_place(Vector3(-3.5, 1.2, -6.5), Vector3(0.0, 0.7, 0.0))
	await _shot(prefix + "front")
	_cam.fov = 75 # the player's view
	for i in 2: # (4 m to the side: from -25 m a lone spruce stood exactly in the way)
		_place(Vector3(4.0, 2.4, -55.0), Vector3(0.0, 1.0, 0.0))
		await _shot(prefix + "far_%d" % i)
	var anim := _tank.get_node("TrackAnimator") as TrackAnimator
	print("tracks: left %.2f m/s, right %.2f m/s, ran %.1f / %.1f m" % [anim.left_speed, anim.right_speed, anim.left_travel, anim.right_travel])
	get_tree().quit()


## Puts the camera at `from` and aims it at `at` – both in the tank's own space (x = right,
## y = up, -z = nose), so it rides along with the tank.
func _place(from: Vector3, at: Vector3) -> void:
	_cam.global_position = _tank.global_transform * from
	_cam.look_at(_tank.global_transform * at)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + file + ".png")
	print("saved ", file)
