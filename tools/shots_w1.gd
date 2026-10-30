extends Node
## Weapon screenshots: each gun from the hip and aimed (not part of the game).
## Usage (needs xvfb): godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_w1.gd [prefix]

func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[1] if args.size() > 1 else "w1"
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.set_physics_process(false)
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	p.global_position = Vector3(-30, -1.4, 59.4)
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(1.0)
	for slot in [0, 1]:
		p.weapons.current_slot = slot
		for aim in [false, true]:
			p.input.aim_held = aim
			for i in 40:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var file := "res://tools/shots/%s_slot%d_%s.png" % [prefix, slot, "ads" if aim else "hip"]
			get_viewport().get_texture().get_image().save_png(file)
			print("saved ", file)
	await _extra(p, prefix)
	get_tree().quit()


## The Maxim: on the gun (hip and aimed) and seen from inside and outside the bunker.
func _extra(p: Player, prefix: String) -> void:
	var gun: MountedGun = get_tree().get_first_node_in_group("mounted_guns")
	p.input.aim_held = false
	p.global_position = gun.exit_point.global_position
	p.input.look_yaw = deg_to_rad(150.0)
	p.input.look_pitch = deg_to_rad(-15.0)
	await _shot(prefix + "_maxim_inside")
	p.set_physics_process(true)
	p.input.request_interact()
	for i in 5:
		await get_tree().physics_frame
	p.set_physics_process(false)
	await _shot(prefix + "_maxim_on")
	p.input.aim_held = true
	await _shot(prefix + "_maxim_ads")
	p.input.add_look(0.0, deg_to_rad(-60.0)) # turned all the way right
	await _shot(prefix + "_maxim_right")
	# Outside, in front of the bunker.
	p.set_physics_process(true)
	p.input.request_interact()
	for i in 5:
		await get_tree().physics_frame
	p.set_physics_process(false)
	p.input.aim_held = false
	p.global_position = Vector3(2.5, 0.0, 60.0)
	p.input.look_yaw = deg_to_rad(150.0)
	p.input.look_pitch = deg_to_rad(-12.0)
	await _shot(prefix + "_maxim_outside")


func _shot(n: String) -> void:
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/shots/%s.png" % n)
	print("saved ", n)
