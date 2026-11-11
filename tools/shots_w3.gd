extends Node
## W3 screenshots: Suomi cocking handle at the end of a reload, empty cases flying out
## (not part of the game).
## Usage (needs xvfb): godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_w3.gd [prefix]

var p: Player
var side_cam: Camera3D
var prefix: String = "w3"


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	prefix = args[1] if args.size() > 1 else "w3"
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	p = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.set_physics_process(false)
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	side_cam = Camera3D.new()
	side_cam.fov = 40.0
	side_cam.near = 0.02
	p.camera.add_child(side_cam)
	p.global_position = Vector3(-30, 0.0, 40.0) # open snow in front of the trench
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(1.0)
	p.weapons.current_slot = 1
	await _wait(0.8)
	var vm: ViewModel = p.weapons._view_models[1]
	await _shot("rest")
	# Reload frozen at a few moments of the cocking (parts of the reload time).
	for u in [0.62, 0.755, 0.83, 0.867, 0.91]:
		vm.play_reload(4.5, true) # (an empty drum: the reload ends with cocking)
		await _wait(4.5 * u)
		vm._tween.pause()
		if vm._hand_tween:
			vm._hand_tween.pause()
		await _wait(0.1)
		await _shot("cock_%02d" % int(u * 100))
		vm._tween.kill()
		if vm._hand_tween:
			vm._hand_tween.kill()
		vm.play_raise(0.2)
		await _wait(0.4)
	# Firing: cases fly out of the port; time is stopped to catch them in the air.
	for aim in [false, true]:
		p.input.aim_held = aim
		await _wait(0.6)
		for i in 5:
			vm.play_fire(0.025, 2.0)
			await _wait(0.07)
		Engine.time_scale = 0.0
		await _shot("cases_%s" % ("ads" if aim else "hip"))
		Engine.time_scale = 1.0
	# Cases while the player runs to the right: they still fly out to the right.
	p.input.aim_held = false
	await _wait(0.6)
	for i in 5:
		vm.play_fire(0.025, 2.0)
		p.global_position += p.global_basis.x * 0.4 # ~6 m/s to the right
		await _wait(0.07)
	Engine.time_scale = 0.0
	await _shot("cases_moving_right")
	Engine.time_scale = 1.0
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


## The player's view, and one from beside the gun (right side).
func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/shots/%s_%s.png" % [prefix, n])
	side_cam.position = Vector3(0.55, 0.05, -0.15)
	side_cam.look_at(p.camera.to_global(Vector3(0.05, -0.15, -0.3)))
	side_cam.current = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/shots/%s_%s_side.png" % [prefix, n])
	side_cam.current = false
	await get_tree().process_frame
	print("saved ", n)
