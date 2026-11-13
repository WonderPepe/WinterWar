extends Node
## Automated test for V2: the soft snow on the earthworks is picture only (not part of the game).
##   godot --headless --path . --script tools/run.gd -- tools/test_v2.gd

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _verts(mi: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		out.append(mi.global_transform * v)
	return out


func _collisions(n: Node) -> int:
	var count := 1 if (n is CollisionObject3D or n is CollisionShape3D) else 0
	for c in n.get_children():
		count += _collisions(c)
	return count


func _ready() -> void:
	await get_tree().process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	for i in 10:
		await get_tree().physics_frame
	var level: Node = game.get_node("Level") if game.has_node("Level") else game.find_child("EarthworkSnow", true, false).get_parent()
	var snow: Node3D = level.get_node("EarthworkSnow")
	check(snow != null and snow.get_child_count() == 4, "EarthworkSnow has its 4 meshes (lips, drifts, ramp snow, bunker snow)")
	check(_collisions(snow) == 0, "the snow has no collision: bullets and feet pass through it")
	var in_nav := snow.is_in_group("navigation_source")
	for c in snow.get_children():
		in_nav = in_nav or c.is_in_group("navigation_source")
	check(not in_nav, "the snow is not part of the navigation mesh")

	var tris := 0
	for c: MeshInstance3D in snow.get_children():
		tris += c.mesh.surface_get_array_index_len(0) / 3
	var posts := get_tree().get_nodes_in_group("fire_post")
	for post: Node in posts:
		for side in ["West", "East"]:
			tris += (post.get_node("EarthHeap" + side) as MeshInstance3D).mesh.surface_get_array_index_len(0) / 3
	check(tris < 40000, "all the V2 snow together is under 40 000 triangles (%d)" % tris)

	# The lips are low: nothing a standing soldier's eyes (0.2 m above the ground) cannot see over.
	var top := -10.0
	for v in _verts(snow.get_node("TrenchLips")):
		top = maxf(top, v.y)
	check(top > 0.05 and top < 0.17, "the snow lips are low (highest point %.2f m above the ground)" % top)

	# The drifts stay at the foot of the walls.
	var floor_y := -1.4
	var drift_top := -10.0
	for v in _verts(snow.get_node("FloorDrifts")):
		drift_top = maxf(drift_top, v.y)
	check(drift_top - floor_y > 0.1 and drift_top - floor_y < 0.3, "the floor drifts are low (%.2f m above the floor)" % (drift_top - floor_y))

	# The loopholes of the firing positions stay open: no lip and no drift higher than a few cm
	# inside the hole (0.8 m wide, from the ground to 0.42 m, in the sandbag wall).
	check(posts.size() == 4, "4 firing positions")
	var lip_v := _verts(snow.get_node("TrenchLips"))
	for post: Node3D in posts:
		var o := post.global_position
		var worst := 0.0
		for v in lip_v:
			if absf(v.x - o.x) < 0.6 and v.z > o.z - 0.75 and v.z < o.z + 0.15:
				worst = maxf(worst, v.y)
		check(worst < 0.02, "%s: no snow lip in front of the loophole (%.3f)" % [post.name, worst])
		# The heaps: still the old wedge as collision, and the rounded heap covers it.
		for side in ["West", "East"]:
			var col := post.get_node("EarthHeap%sCollision" % side) as CollisionShape3D
			check(col != null and col.shape is ConvexPolygonShape3D, "%s %s heap: the collision wedge is unchanged" % [post.name, side])
			var heap := post.get_node("EarthHeap" + side) as MeshInstance3D
			var hv := _verts(heap)
			var poke := 0.0
			for cp: Vector3 in (col.shape as ConvexPolygonShape3D).points:
				var w := col.global_transform * cp
				if w.y < 0.05:
					continue
				# Height of the heap right above/below this corner of the wedge.
				var best := 1e9
				var hy := 0.0
				for v in hv:
					var d := Vector2(v.x - w.x, v.z - w.z).length()
					if d < best:
						best = d
						hy = v.y
				poke = maxf(poke, w.y - hy)
			check(poke < 0.12, "%s %s heap: it covers the wedge (a corner shows at most %.2f m)" % [post.name, side, poke])
		for v in _verts(post.get_node("EarthHeapWest")) + _verts(post.get_node("EarthHeapEast")):
			if absf(v.x - o.x) < 0.5 and v.y > 0.02:
				worst = 1.0
		check(worst < 0.5, "%s: the heaps stay clear of the loophole" % post.name)

	# Bunker: the cap hides the old flat slab (6.6 x 6.1 m, top at 1.745 m); the Maxim's hole is free.
	var bunker: Node3D = level.get_node("Bunker")
	var bz := bunker.global_position.z
	var cap := _verts(snow.get_node("BunkerSnow"))
	var covered := true
	for corner: Vector2 in [Vector2(-3.25, -3.0), Vector2(3.25, -3.0), Vector2(-3.25, 3.0), Vector2(3.25, 3.0), Vector2(0, 0)]:
		var best := 1e9
		var hy := 0.0
		for v in cap:
			if v.y < 1.2:
				continue
			var d := Vector2(v.x - corner.x, v.z - bz - corner.y).length()
			if d < best:
				best = d
				hy = v.y
		covered = covered and hy > 1.74
	check(covered, "the snow cap covers the old flat roof slab")
	var in_fire := 0.0
	for v in cap:
		if v.y < 1.2 and absf(v.x) < 1.4 and v.z < bz - 2.75:
			in_fire = maxf(in_fire, v.y)
	check(in_fire < 0.03, "no snow bank in front of the Maxim's hole (%.3f)" % in_fire)

	# Nothing changed for bullets: a ray along the ground just above a lip passes; the trench
	# body and the bunker still have their baked collision.
	var space := get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(-30, 0.06, 59.6), Vector3(-30, 0.06, 40))
	check(space.intersect_ray(q).is_empty() or absf(space.intersect_ray(q).position.z - 59.6) > 5.0, "a bullet skimming the trench edge is not stopped by the lip")
	check((level.get_node("Trench/Collision") as CollisionShape3D).shape is ConcavePolygonShape3D, "the trench keeps its baked collision")

	print("RESULT: ", "OK (0 failures)" if fails == 0 else "FAILED (%d failures)" % fails)
	get_tree().quit(1 if fails > 0 else 0)
