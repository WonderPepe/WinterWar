extends Node
## Screenshots of the L1 trench line and firing positions (not part of the game). Saved in tools/shots/:
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_l1.gd

var _out: String
var _game: Node
var _cam: Camera3D


func _ready() -> void:
	await get_tree().process_frame
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
	await get_tree().create_timer(3.0).timeout # shader warm-up

	_cam = Camera3D.new()
	_game.add_child(_cam)
	_cam.current = true
	_cam.fov = 60

	await _view(Vector3(0, 30, 59), Vector3(0, 0, 59.5), "l2_top", 50.0, Vector3(0, 0, -1))
	await _view(Vector3(-6, 1.7, 42), Vector3(0, 0.6, 56.5), "l2_front")
	await _view(Vector3(3, 1.5, 51), Vector3(0, 0.3, 56.8), "l2_hole_close")
	await _view(Vector3(6, 4.5, 68), Vector3(0.5, -1.0, 61), "l2_back")
	await _view(Vector3(1.2, 4.0, 66), Vector3(1.2, -1.3, 60), "l2_stub")
	_cam.current = false
	p.global_position = Vector3(1.2, -1.3, 64.5)
	p.input.look_yaw = 0.0
	p.input.look_pitch = -0.05
	p.input.move_dir = Vector2(0, -1)
	await get_tree().create_timer(1.2).timeout
	p.input.move_dir = Vector2.ZERO
	await get_tree().create_timer(0.4).timeout
	await _shot("l2_door_in")
	p.global_position = Vector3(-1.5, -1.3, 60.5)
	p.input.look_yaw = 0.0
	await get_tree().create_timer(0.4).timeout
	await _shot("l2_inside")
	var gun = get_tree().get_first_node_in_group("mounted_guns")
	p.global_position = gun.exit_point.global_position
	await get_tree().create_timer(0.3).timeout
	p.input.request_interact()
	await get_tree().create_timer(0.8).timeout
	await _shot("l2_gunner_0")
	p.input.add_look(deg_to_rad(40.0), 0.0)
	await get_tree().create_timer(0.3).timeout
	await _shot("l2_gunner_left")
	p.input.add_look(deg_to_rad(-90.0), 0.0)
	await get_tree().create_timer(0.3).timeout
	await _shot("l2_gunner_right")
	get_tree().quit()


func _view(from: Vector3, to: Vector3, file: String, fov := 60.0, up := Vector3.UP) -> void:
	_cam.current = true
	_cam.fov = fov
	_cam.global_position = from
	_cam.look_at(to, up)
	await get_tree().create_timer(0.5).timeout
	await _shot(file)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + file + ".png")
	print("saved ", file)
