extends Node
## Automated test for L1: the new trench line (short legs, many corners) and the four protected
## firing positions with sandbags (not part of the game).
##   godot --headless --path . --script tools/run.gd -- tools/test_l1.gd

var game: Node
var p: Player
var fails := 0
var xz: Array = []   # TRENCH_XZ from the level builder
var posts: Array = []
var bay_depth := 0.0
var step_top := 0.0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func set_input(dir: Vector2, crouch := false) -> void:
	p.input.move_dir = dir
	p.input.crouch_held = crouch


func teleport(pos: Vector3, yaw := 0.0) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.input.look_yaw = yaw


func pt(i: int) -> Vector2:
	return Vector2(xz[i * 2], xz[i * 2 + 1])


## Distance from a point (x, z) to the trench centre line.
func dist_to_line(q: Vector2) -> float:
	var best := 1e9
	for i in xz.size() / 2 - 1:
		var a := pt(i)
		var d := pt(i + 1) - a
		var t := clampf((q - a).dot(d) / d.length_squared(), 0.0, 1.0)
		best = minf(best, q.distance_to(a + d * t))
	return best


func line_z(x: float) -> float:
	for i in xz.size() / 2 - 1:
		var a := pt(i)
		var b := pt(i + 1)
		if not is_equal_approx(a.x, b.x) and x >= minf(a.x, b.x) - 0.001 and x <= maxf(a.x, b.x) + 0.001:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return 0.0


func _ready() -> void:
	await get_tree().process_frame
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	run()


func run() -> void:
	await frames(5)
	p = get_tree().get_nodes_in_group("players")[0]
	p.input.set_process(false)
	await frames(60)
	var consts: Dictionary = (load("res://tools/build_scenes.gd") as GDScript).get_script_constant_map()
	xz = consts["TRENCH_XZ"]
	posts = consts["POST_X"]
	bay_depth = consts["POST_BAY_DEPTH"]
	step_top = consts["POST_STEP_TOP"]

	# --- The line: many short legs and corners, nothing long and straight ---
	var legs: int = xz.size() / 2 - 1
	var longest := 0.0
	var shortest := 1e9
	var corners := 0
	var length := 0.0
	var inside := true
	for i in legs:
		var l := (pt(i + 1) - pt(i)).length()
		longest = maxf(longest, l)
		shortest = minf(shortest, l)
		length += l
		if i > 0 and absf((pt(i + 1) - pt(i)).angle_to(pt(i) - pt(i - 1))) > deg_to_rad(25.0):
			corners += 1
		inside = inside and absf(pt(i).x) <= 100.0 and pt(i).y >= 55.0 and pt(i).y <= 66.0
	print("  legs %d, longest %.1f m, shortest %.1f m, corners >25 deg: %d, length %.0f m" % [legs, longest, shortest, corners, length])
	check(legs >= 40, "at least 40 legs (%d)" % legs)
	check(longest <= 12.5 and shortest >= 2.9, "legs are 3 ... 12 m long (the long one is the bunker front)")
	var over_8 := 0
	for i in legs:
		if (pt(i + 1) - pt(i)).length() > 9.0:
			over_8 += 1
	check(over_8 <= 1, "only the bunker front is longer than 9 m (%d)" % over_8)
	check(corners >= 35, "at least 35 real corners (%d)" % corners)
	check(inside, "the whole line lies inside the earth slab")

	# --- The trench is one connected, walkable corridor along the whole line ---
	var map: RID = p.get_world_3d().navigation_map
	var from := Vector3(pt(0).x + 2.0, -1.4, pt(0).y)
	var to := Vector3(pt(legs).x - 2.0, -1.4, pt(legs).y)
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	for i in 120:
		if path.size() > 1:
			break
		await get_tree().physics_frame
		path = NavigationServer3D.map_get_path(map, from, to, true)
	var plen := 0.0
	for i in range(1, path.size()):
		plen += path[i - 1].distance_to(path[i])
	check(path.size() > 1 and path[path.size() - 1].distance_to(to) < 1.5, "navigation path along the whole trench (%d points)" % path.size())
	check(plen > 0.0 and plen < length * 1.2, "the path follows the trench (%.0f m, line %.0f m)" % [plen, length])

	# --- Things that stand in the trench are really on the line ---
	var spawn_ok := true
	for m in get_tree().get_nodes_in_group("player_spawn"):
		spawn_ok = spawn_ok and dist_to_line(Vector2(m.global_position.x, m.global_position.z)) < 0.3
	check(spawn_ok and get_tree().get_nodes_in_group("player_spawn").size() == 4, "4 player spawns on the trench line")
	var crates_ok := true
	for g in ["ammo_crates", "molotov_crates"]:
		for c in get_tree().get_nodes_in_group(g):
			var d := dist_to_line(Vector2(c.global_position.x, c.global_position.z))
			# (the ammo crate in the bunker stands in the bunker; the niche crate 1.42 m off the line)
			if "Bunker" in c.name:
				continue
			if d > (1.6 if "AmmoCrate" in c.name else 1.1):
				crates_ok = false
				print("  crate ", c.name, " is ", d, " m from the line")
	check(crates_ok, "ammo and Molotov crates stand inside the trench")
	var entries := get_tree().get_nodes_in_group("trench_entry")
	var entry_ok := entries.size() == 10
	for e: NavigationLink3D in entries:
		var s: Vector3 = e.global_transform * e.start_position
		var t: Vector3 = e.global_transform * e.end_position
		entry_ok = entry_ok and dist_to_line(Vector2(t.x, t.z)) < 0.5 and dist_to_line(Vector2(s.x, s.z)) > 1.8
	check(entry_ok, "10 trench entries: they land on the line and start on solid ground")

	# --- Exits: the four ramps still lead out ---
	for x in [-80.0, -40.0, 40.0, 80.0]:
		teleport(Vector3(x, -1.3, 64.0), PI)
		await frames(20)
		set_input(Vector2(0, -1))
		await frames(240)
		check(p.global_position.z > 71.0, "exit ramp at x = %d leads out (z %.1f)" % [x, p.global_position.z])
		set_input(Vector2.ZERO)

	# --- The four firing positions ---
	var nodes := get_tree().get_nodes_in_group("fire_post")
	check(nodes.size() == 4, "4 firing positions (group fire_post)")
	var space := p.get_world_3d().direct_space_state
	for k in posts.size():
		var x: float = posts[k]
		var zc := line_z(x)
		var zf := zc - bay_depth
		var tag := "post %d (x = %.1f)" % [k + 1, x]
		# Eye heights: standing 1.6 m, crouching 0.95 m above the feet.
		var eye_stand := Vector3(x, step_top + 1.6, zf + 0.5)
		var eye_crouch := Vector3(x, step_top + 0.95, zf + 0.5)
		var eye_floor := Vector3(x, -1.4 + 1.6, zf + 2.5)
		var q := PhysicsRayQueryParameters3D.create(eye_stand, eye_stand + Vector3(0, 0, -12))
		q.collision_mask = 1
		check(space.intersect_ray(q).is_empty(), tag + ": standing on the step you see over the sandbags")
		q = PhysicsRayQueryParameters3D.create(eye_crouch, eye_crouch + Vector3(0, 0, -12))
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		check(not hit.is_empty() and hit.position.z > zf - 3.0, tag + ": crouching you are hidden behind the sandbags")
		q = PhysicsRayQueryParameters3D.create(eye_floor, eye_floor + Vector3(0, 0, -12))
		q.collision_mask = 1
		hit = space.intersect_ray(q)
		check(not hit.is_empty() and hit.position.z > zf - 3.0, tag + ": from the trench floor you see only earth")
		# Sideways: a ray along the front, level with the sandbags, is stopped by the flank wall.
		q = PhysicsRayQueryParameters3D.create(Vector3(x - 6.0, 0.3, zf - 0.3), Vector3(x + 6.0, 0.3, zf - 0.3))
		q.collision_mask = 1
		check(not space.intersect_ray(q).is_empty(), tag + ": a bullet along the sandbag wall is stopped")

		# Walk up the ramp onto the step and stop at the front wall.
		teleport(Vector3(x, -1.3, zc), 0.0)
		await frames(20)
		set_input(Vector2(0, -1))
		await frames(240)
		set_input(Vector2.ZERO)
		await frames(30)
		print("  ", tag, " player at ", p.global_position)
		check(absf(p.global_position.y - step_top) < 0.15 and p.global_position.z < zf + 1.4 and p.global_position.z > zf,
			tag + ": the player walks up onto the firing step (y %.2f z %.2f)" % [p.global_position.y, p.global_position.z])
		check(p.camera.global_position.y > 0.6, tag + ": standing, the eyes are above the sandbags (%.2f)" % p.camera.global_position.y)
		set_input(Vector2.ZERO, true)
		await frames(60)
		check(p.camera.global_position.y < 0.45, tag + ": crouching, the eyes are behind the sandbags (%.2f)" % p.camera.global_position.y)
		set_input(Vector2.ZERO, false)
		await frames(40)

		# Reachable for the Soviets who jump into the trench.
		var closest := NavigationServer3D.map_get_closest_point(map, Vector3(x, step_top, zf + 0.6))
		check(Vector2(closest.x, closest.z).distance_to(Vector2(x, zf + 0.6)) < 0.8, tag + ": the step is on the navigation mesh")

	print("RESULT: ", "OK (0 failures)" if fails == 0 else "FAILED (%d failures)" % fails)
	get_tree().quit(1 if fails > 0 else 0)
