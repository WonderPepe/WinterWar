extends Node
## W2 screenshots: first-person arms on each gun, bolt/reload hands, the Maxim's sights,
## hands on its grips, steam (not part of the game).
## Usage (needs xvfb): godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_w2.gd [prefix] [side]
## "side" also takes each shot from a camera beside the player (to check the grips).

var p: Player
var side_cam: Camera3D
var prefix: String = "w2"
var with_side: bool = false


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	prefix = args[1] if args.size() > 1 else "w2"
	with_side = args.size() > 2 and args[2] == "side"
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
	side_cam.fov = 50.0
	side_cam.near = 0.02
	p.camera.add_child(side_cam)
	p.global_position = Vector3(-30, 0.0, 40.0) # open snow in front of the trench
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(1.0)
	for slot in [0, 1]:
		p.weapons.current_slot = slot
		for aim in [false, true]:
			p.input.aim_held = aim
			await _wait(0.6)
			await _shot("slot%d_%s" % [slot, "ads" if aim else "hip"])
	p.input.aim_held = false
	# Mosin bolt cycle (right hand on the bolt) and reloads (a hand goes to the pouch).
	p.weapons.current_slot = 0
	await _wait(0.6)
	var vm: ViewModel = p.weapons._view_models[0]
	vm.play_bolt_cycle(1.2)
	await _wait(0.5)
	await _shot("mosin_bolt")
	await _wait(1.0)
	vm.play_reload(3.0)
	await _wait(0.6)
	await _shot("mosin_reload")
	await _wait(3.0)
	p.weapons.current_slot = 1
	await _wait(0.6)
	p.weapons._view_models[1].play_reload(3.0)
	await _wait(0.7)
	await _shot("suomi_reload")
	await _wait(3.0)
	await _maxim()
	get_tree().quit()


func _maxim() -> void:
	var gun: MountedGun = get_tree().get_first_node_in_group("mounted_guns")
	p.global_position = gun.exit_point.global_position
	p.set_physics_process(true)
	await get_tree().physics_frame
	p.input.request_interact()
	for i in 5:
		await get_tree().physics_frame
	p.set_physics_process(false)
	p.input.look_pitch = 0.0
	await _wait(0.5)
	await _shot("maxim_hip")
	p.input.aim_held = true
	await _wait(0.6)
	await _shot("maxim_ads")
	p.input.add_look(deg_to_rad(3.0), deg_to_rad(-25.0))
	await _wait(0.5)
	await _shot("maxim_ads_turned")
	p.input.aim_held = false
	p.input.look_pitch = 0.0
	p.input.look_yaw = gun.get_base_yaw()
	gun.heat = 0.95
	await _wait(1.5)
	await _shot("maxim_steam")
	gun.ammo = 100
	gun.start_reload()
	await _wait(1.5)
	await _shot("maxim_belt")
	gun._reload_timer = 0.0
	await _wait(0.2)
	# Belt animation: fire a few rounds and stop mid-way.
	p.input.fire_held = true
	await _wait(0.35)
	p.input.fire_held = false
	await _shot("maxim_fired")
	# The steaming gun from outside the bunker.
	p.input.aim_held = false
	side_cam.current = true
	side_cam.global_position = gun.global_position + Vector3(1.6, 0.6, -1.2)
	side_cam.look_at(gun.global_position + Vector3(0, 0.4, 0.0))
	await _wait(1.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/shots/%s_maxim_steam_outside.png" % prefix)
	side_cam.current = false


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/shots/%s_%s.png" % [prefix, n])
	print("saved ", n)
	if with_side:
		side_cam.position = Vector3(0.75, -0.15, -0.35)
		side_cam.look_at(p.camera.to_global(Vector3(0.05, -0.2, -0.3)))
		side_cam.current = true
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tools/shots/%s_%s_side.png" % [prefix, n])
		side_cam.current = false
		await get_tree().process_frame
