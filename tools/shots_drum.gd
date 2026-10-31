extends Node
## Suomi drum screenshots: left hand on the drum (hip / ADS) and the drum change during a
## reload, each from first person and from cameras beside the player (not part of the game).
## Usage (needs xvfb): godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_drum.gd [prefix] [reload fractions, e.g. 0.2,0.5]
## Environment: FP_ONLY=1 = first-person pictures only.
var p: Player
var cam: Camera3D
var prefix := "drum"

func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	prefix = args[1] if args.size() > 1 else "drum"
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	p = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.set_physics_process(false)
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.02
	p.camera.add_child(cam)
	p.global_position = Vector3(-30, 0.0, 40.0)
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(1.0)
	p.weapons.current_slot = 1
	await _wait(0.8)
	var vm: ViewModel = p.weapons._view_models[1]
	var drum := vm.get_node("Model").find_child("SuomiKP31_Drum", true, false) as Node3D
	var mi := drum.get_child(0) as MeshInstance3D
	var aabb: AABB = mi.get_aabb()
	var model: Node3D = vm.get_node("Model")
	var to_model: Transform3D = model.global_transform.affine_inverse() * mi.global_transform
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in 8:
		var c: Vector3 = to_model * aabb.get_endpoint(i)
		lo = lo.min(c)
		hi = hi.max(c)
	print("DRUM in Model space: ", lo, " .. ", hi, " centre ", (lo + hi) / 2)
	print("drum node local xform ", drum.transform, " mesh xform ", mi.transform)
	for nm in ["SuomiKP31_MagLock", "SuomiKP31_Magazine", "SuomiKP31_Cover"]:
		var n := vm.get_node("Model/Mesh").find_child(nm, true, false) as Node3D
		print(nm, " origin in model ", model.global_transform.affine_inverse() * n.global_position)
	for aim in [false, true]:
		p.input.aim_held = aim
		await _wait(0.6)
		await _views("%s" % ("ads" if aim else "hip"))
	p.input.aim_held = false
	await _wait(0.6)
	var dur: float = 4.5
	var fs: Array = [0.12, 0.2, 0.25, 0.3, 0.38, 0.46, 0.55, 0.62, 0.7, 0.75, 0.88]
	if args.size() > 2:
		fs = Array(args[2].split(",")).map(func(x): return float(x))
	Engine.time_scale = 0.15 # pictures take long in xvfb: slow the game down
	for f in fs:
		# each picture from a fresh reload (taking the pictures takes time)
		vm.play_reload(dur)
		await _wait(dur * f)
		vm._tween.pause()
		vm._hand_tween.pause()
		await get_tree().process_frame
		await _views("reload%02d" % int(f * 100))
		vm._tween.kill()
		vm._hand_tween.kill()
		vm.play_raise(0.01)
		await _wait(0.2)
	await _wait(1.0)
	get_tree().quit()

func _wait(s: float) -> void:
	if s > 0:
		await get_tree().create_timer(s).timeout

func _views(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/shots/%s_%s.png" % [prefix, n])
	var poses := {
		"L": [Vector3(-0.7, -0.25, -0.3), Vector3(0.0, -0.2, -0.3)],
		"R": [Vector3(0.75, -0.15, -0.35), Vector3(0.05, -0.2, -0.3)],
		"B": [Vector3(-0.1, -0.75, -0.25), Vector3(0.0, -0.2, -0.3)],
	}
	var gl: Vector3 = p.camera.to_local(p.weapons._view_models[1].get_node("Model/GripL").global_position)
	poses["CL"] = [gl + Vector3(-0.3, 0.02, -0.05), gl]
	poses["CF"] = [gl + Vector3(0.05, 0.0, -0.35), gl]
	for k in poses:
		cam.position = poses[k][0]
		cam.look_at(p.camera.to_global(poses[k][1]))
		cam.current = true
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tools/shots/%s_%s_%s.png" % [prefix, n, k])
		cam.current = false
	await get_tree().process_frame
