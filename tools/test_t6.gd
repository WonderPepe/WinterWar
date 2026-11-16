extends Node
## Test for T6 "running tracks" (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_t6.gd
## The TrackAnimator must work out both tracks' speeds from how the hull really moves (straight,
## reverse, bends, turning on the spot, standing, being put somewhere else) and pass them on to
## the track and wheel materials. The test moves a parked tank by hand to get every case.

var fails := 0
var step: float = 1.0 / 60.0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance


func _ready() -> void:
	await get_tree().process_frame
	run()


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Moves the tank by hand for `n` physics steps: `speed` m/s towards its nose (negative =
## backwards) while turning `turn_deg` degrees per second (positive = to the left).
func drive(tank: Tank, speed: float, turn_deg: float, n: int) -> void:
	for i in n:
		tank.rotation.y += deg_to_rad(turn_deg) * step
		tank.global_position += -tank.global_basis.z * speed * step
		await get_tree().physics_frame


func run() -> void:
	Settings.difficulty = 1
	step = 1.0 / Engine.physics_ticks_per_second
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await get_tree().create_timer(0.5).timeout
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.set_physics_process(false)
	p.health = 100000
	(get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner).set_process(false)
	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner

	# --- The model carries the wheel data (written by tools/import_weapons.py).
	var model: Node3D = load("res://assets/models/vehicles/t26/model.gltf").instantiate()
	var wheel_vertices: int = 0
	var chassis_meshes: int = 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not String(mi.name).to_lower().begins_with("chassis"):
			continue
		chassis_meshes += 1
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2] if arrays.size() > Mesh.ARRAY_TEX_UV2 else null
		if uv2 is PackedVector2Array:
			var axles: Dictionary = {}
			for v: Vector2 in uv2:
				var kind: int = floori(v.y * 0.5 + 0.001)
				if kind > 0:
					wheel_vertices += 1
					axles[Vector3i(roundi(v.x * 100.0), roundi((v.y - kind * 2.0) * 100.0), kind)] = true
			check(axles.size() == 14, "%s: 14 wheel axles in the model's UV2 (got %d)" % [mi.name, axles.size()])
	model.free()
	check(chassis_meshes == 2, "the model has two chassis meshes (got %d)" % chassis_meshes)
	check(wheel_vertices > 2500 and wheel_vertices < 3200, "about 2 900 wheel vertices carry an axle (got %d)" % wheel_vertices)

	# --- A real tank driving its route: the tracks run as far as the tank drives.
	var tank: Tank = spawner.spawn_tank(1)
	var anim := tank.get_node_or_null("TrackAnimator") as TrackAnimator
	check(anim != null, "the tank has a TrackAnimator")
	if anim == null:
		print("TEST T6 DONE: %d failure(s)" % fails)
		get_tree().quit(1)
		return
	await frames(5)
	check(absf(anim.left_travel) < 0.01 and absf(anim.right_travel) < 0.01, "being put on the route at the start moves no track")
	var from: Vector3 = tank.global_position
	var ran: float = (anim.left_travel + anim.right_travel) * 0.5
	await frames(240)
	var driven: float = tank.global_position.distance_to(from)
	ran = (anim.left_travel + anim.right_travel) * 0.5 - ran
	check(driven > 2.0, "the tank drove off (%.2f m in 4 s)" % driven)
	check(near(ran, driven, driven * 0.05 + 0.05), "its tracks ran as far as it drove (%.2f m of %.2f m)" % [ran, driven])
	check(near(anim.left_speed, tank.drive_speed, 0.45) and near(anim.right_speed, tank.drive_speed, 0.45),
			"track speeds follow the driving speed (%.2f / %.2f at %.2f m/s)" % [anim.left_speed, anim.right_speed, tank.drive_speed])

	# --- Materials: each belt and each side's wheels have their own.
	var tl: ShaderMaterial = anim.track_material(TrackAnimator.LEFT)
	var tr: ShaderMaterial = anim.track_material(TrackAnimator.RIGHT)
	var wl: ShaderMaterial = anim.wheel_material(TrackAnimator.LEFT)
	var wr: ShaderMaterial = anim.wheel_material(TrackAnimator.RIGHT)
	check(tl != null and tr != null and wl != null and wr != null, "two track materials and two wheel materials")
	if tl == null or tr == null or wl == null or wr == null:
		print("TEST T6 DONE: %d failure(s)" % fails)
		get_tree().quit(1)
		return
	check(tl != tr and wl != wr, "left and right are separate materials")
	check(tl.shader == TrackAnimator.TRACK_SHADER and wl.shader == TrackAnimator.WHEEL_SHADER, "they use the track / wheel shaders")
	check(tl.get_shader_parameter("albedo_tex") is Texture2D and wl.get_shader_parameter("albedo_tex") is Texture2D, "the model's own pictures are passed on")
	check(tl.get_shader_parameter("grime_tex") == TrackAnimator.grime_texture(), "the belts wear the shared snow-and-dirt picture")
	var grime: ImageTexture = TrackAnimator.grime_texture()
	check(grime.get_width() == TrackAnimator.GRIME_W and grime.get_height() == TrackAnimator.GRIME_H, "snow-and-dirt picture is %d × %d" % [TrackAnimator.GRIME_W, TrackAnimator.GRIME_H])
	check(not is_equal_approx(float(tl.get_shader_parameter("grime_shift")), float(tr.get_shader_parameter("grime_shift"))), "the two belts wear their snow in different places")
	var found_left: bool = false
	for node in tank.model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.get_surface_override_material(0) == tl:
			found_left = true
			var centre: Vector3 = (tank.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb().get_center()
			check(centre.x < -0.5, "the LEFT track material is on the left belt (x %.2f)" % centre.x)
	check(found_left, "the left track material is on a mesh of the model")
	check(near(float(tl.get_shader_parameter("scroll")), anim.scroll_of(TrackAnimator.LEFT), 0.001), "the belt's picture is slid by the distance run")

	# --- Parked by the test from here on: moved by hand on open ground.
	tank.set_physics_process(false)
	tank.global_position = Vector3(0.0, terrain.get_height(0.0, 10.0), 10.0)
	tank.rotation = Vector3.ZERO
	await frames(3)
	check(not anim.is_moving(), "put somewhere else and standing: the tracks stand")
	var l0: float = anim.left_travel
	var r0: float = anim.right_travel

	await drive(tank, 2.0, 0.0, 60)
	check(near(anim.left_speed, 2.0, 0.05) and near(anim.right_speed, 2.0, 0.05), "straight at 2 m/s: both tracks 2 m/s (%.2f / %.2f)" % [anim.left_speed, anim.right_speed])
	check(near(anim.left_travel - l0, 2.0, 0.05) and near(anim.right_travel - r0, 2.0, 0.05), "…and they ran 2 m in a second")
	var angles: Vector3 = wl.get_shader_parameter("wheel_angles")
	check(near(angles.x, fposmod(anim.left_travel / anim.sprocket_radius, TAU), 0.001), "the sprocket has turned travel ÷ radius")
	check(near(angles.y, fposmod(anim.left_travel / anim.road_wheel_radius, TAU), 0.001), "the road wheels turn faster (smaller radius)")

	await frames(3)
	check(anim.left_speed == 0.0 and anim.right_speed == 0.0 and not anim.is_moving(), "standing still: the tracks stop completely")
	var scroll_standing: float = float(tl.get_shader_parameter("scroll"))
	await frames(30)
	check(float(tl.get_shader_parameter("scroll")) == scroll_standing, "…and stay stopped")

	l0 = anim.left_travel
	await drive(tank, -1.2, 0.0, 30)
	check(near(anim.left_speed, -1.2, 0.05) and near(anim.right_speed, -1.2, 0.05), "reversing at 1.2 m/s: both tracks run backwards (%.2f / %.2f)" % [anim.left_speed, anim.right_speed])
	check(anim.left_travel < l0, "…the left track's travel went down")

	await drive(tank, 2.0, 22.0, 30)
	check(anim.left_speed < 1.75 and anim.right_speed > 2.25, "left bend: left track slower, right faster (%.2f / %.2f)" % [anim.left_speed, anim.right_speed])
	check(near((anim.left_speed + anim.right_speed) * 0.5, 2.0, 0.05), "…and their average is the driving speed")
	await drive(tank, 2.0, -22.0, 30)
	check(anim.right_speed < 1.75 and anim.left_speed > 2.25, "right bend: right track slower, left faster (%.2f / %.2f)" % [anim.left_speed, anim.right_speed])

	await drive(tank, 0.0, 22.0, 30)
	check(anim.left_speed < -0.3 and anim.right_speed > 0.3, "turning left on the spot: left track backwards, right forwards (%.2f / %.2f)" % [anim.left_speed, anim.right_speed])
	check(near(anim.left_speed, -anim.right_speed, 0.02), "…at the same speed")
	await drive(tank, 0.0, -22.0, 30)
	check(anim.left_speed > 0.3 and anim.right_speed < -0.3, "turning right on the spot: the other way round (%.2f / %.2f)" % [anim.left_speed, anim.right_speed])

	await frames(3)
	l0 = anim.left_travel
	tank.global_position += Vector3(0.0, 0.0, -30.0)
	await frames(3)
	check(anim.left_travel == l0 and not anim.is_moving(), "put 30 m away in one step: no track movement")

	l0 = anim.left_travel
	await drive(tank, 9.0, 0.0, 10)
	check(anim.left_speed <= anim.max_track_speed + 0.01, "a glitch of 9 m/s is capped at %.1f m/s (%.2f)" % [anim.max_track_speed, anim.left_speed])
	await drive(tank, 0.01, 0.0, 30)
	check(anim.left_speed == 0.0, "creeping at 1 cm/s counts as standing")

	# --- A second tank has its own materials (two tanks never share a track's movement).
	var t2: Tank = spawner.spawn_tank(0)
	t2.set_physics_process(false)
	var anim2 := t2.get_node("TrackAnimator") as TrackAnimator
	await frames(3)
	check(anim2.track_material(TrackAnimator.LEFT) != tl and anim2.wheel_material(TrackAnimator.LEFT) != wl, "a second tank has its own materials")
	check(anim2.track_material(TrackAnimator.LEFT).shader == tl.shader, "…with the same shader (compiled once)")

	# --- A wreck never moves its tracks again.
	tank.destroy()
	await frames(5)
	l0 = anim.left_travel
	await drive(tank, 2.0, 0.0, 10)
	check(anim.left_travel == l0 and not anim.is_physics_processing(), "a wreck's TrackAnimator is switched off")

	print("TEST T6 DONE: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)
