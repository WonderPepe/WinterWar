extends Node
## Renders each imported weapon model from the side and top (not part of the game).
func _ready() -> void:
	await get_tree().process_frame
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.55, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(cam)
	var args := OS.get_cmdline_user_args()
	var names: Array = args.slice(1) if args.size() > 1 else ["mosin", "suomi", "maxim"]
	for n in names:
		var m: Node3D = load("res://assets/models/weapons/%s/model.gltf" % n).instantiate()
		add_child(m)
		await get_tree().process_frame
		var box := AABB()
		var first := true
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		print(n, " AABB ", box)
		var c := box.get_center()
		var views := {"side": [Vector3(1, 0, 0), maxf(box.size.z, box.size.y)], "top": [Vector3(0, 1, 0.001), maxf(box.size.z, box.size.x)], "front": [Vector3(0, 0, -1), maxf(box.size.x, box.size.y)], "back": [Vector3(0, 0, 1), maxf(box.size.x, box.size.y)]}
		for v in views:
			var dir: Vector3 = views[v][0]
			cam.size = views[v][1] * 1.1
			cam.near = 0.01
			cam.far = box.size.length() * 4.0
			cam.look_at_from_position(c + dir.normalized() * box.size.length() * 1.5, c, Vector3.UP if v != "top" else Vector3(0, 0, -1))
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tools/shots/model_%s_%s.png" % [n, v])
		m.queue_free()
	get_tree().quit()
