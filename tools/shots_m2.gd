extends Node
## Screenshots of the weapons for a visual check (not part of the game).

var p: Player

func _ready() -> void:
	await get_tree().process_frame # the root can't take new children while it is adding us
	get_tree().root.add_child(load("res://scenes/game.tscn").instantiate())
	get_tree().root.get_node("Game/PauseMenu").free() # tests drive the game directly
	run()

func wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func snap(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_tree().root.get_viewport().get_texture().get_image().save_png("res://tools/shots/" + file)
	print("saved ", file)

func aim_at(point: Vector3) -> void:
	var d: Vector3 = point - p.camera.global_position
	p.input.look_yaw = atan2(-d.x, -d.z)
	p.input.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())

func run() -> void:
	await wait(10)
	p = get_tree().get_nodes_in_group("players")[0]
	p.input.set_process(false)
	for vm in p.weapons._view_models:
		vm.flash_duration = 5.0 # keep the flash visible for the slow software renderer
	var t25: Node3D = get_tree().root.get_node("Game/Level/ShootingRange/Target_25m")
	var torso: Vector3 = t25.get_node("Body/Torso").global_position
	p.global_position = Vector3(28, -1.4, 59.5)
	await wait(40)
	aim_at(torso + Vector3(0, 0.3, 0))
	await wait(40)
	await snap("m2_1_mosin_hip.png")
	p.input.aim_held = true
	await wait(40)
	aim_at(torso)
	await wait(5)
	await snap("m2_2_mosin_ads.png")
	p.input.fire_held = true
	await wait(1)
	await snap("m2_3_mosin_fire.png")
	p.input.fire_held = false
	p.input.aim_held = false
	await wait(30)
	p.input.request_switch(1)
	await wait(60)
	aim_at(torso + Vector3(0, 0.3, 0))
	await wait(5)
	await snap("m2_4_suomi_hip.png")
	p.input.aim_held = true
	await wait(40)
	aim_at(torso)
	await wait(3)
	await snap("m2_5_suomi_ads.png")
	# spray the trench wall and look at the holes
	p.input.aim_held = false
	p.global_position = Vector3(-30, -1.4, 61)
	await wait(10)
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(-15)
	p.input.fire_held = true
	await wait(25)
	p.input.fire_held = false
	await wait(20)
	p.input.look_pitch = deg_to_rad(-15)
	p.input.look_yaw = 0.0
	await wait(5)
	await snap("m2_6_wall_holes.png")
	get_tree().quit()
