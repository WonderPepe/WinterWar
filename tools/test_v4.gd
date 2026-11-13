extends Node
## Automated test for V4: the sandbag walls of the firing positions (not part of the game).
## Nobody sees through the wall between the bags, the loophole stays open, nothing changed for
## bullets.
##   godot --headless --path . --script tools/run.gd -- tools/test_v4.gd

# The wall in the firing position's own coordinates (same numbers as tools/build_scenes.gd).
const WALL_BACK := 0.02
const WALL_FRONT := -0.6
const WALL_HALF_W := 1.4
const WALL_TOP := 0.84
const HOLE_HALF_W := 0.4
const HOLE_TOP := 0.42

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


## Does the line a→b pass through at least 10 cm of the box (given by two corners)? A line that
## only clips a corner of the wall - the rounded corner of one bag - is a look past the wall,
## not through it.
func _crosses_box(a: Vector3, b: Vector3, lo: Vector3, hi: Vector3) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	for k in 3:
		var d := b[k] - a[k]
		if absf(d) < 1e-9:
			if a[k] < lo[k] or a[k] > hi[k]:
				return false
			continue
		var u0 := (lo[k] - a[k]) / d
		var u1 := (hi[k] - a[k]) / d
		t0 = maxf(t0, minf(u0, u1))
		t1 = minf(t1, maxf(u0, u1))
	return (t1 - t0) * a.distance_to(b) > 0.1


func _ready() -> void:
	await get_tree().process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	for i in 10:
		await get_tree().physics_frame
	var posts := get_tree().get_nodes_in_group("fire_post")
	check(posts.size() == 4, "4 firing positions")

	# The solid parts of the wall, 5 cm smaller on every side (a line that only clips the very
	# edge of a bag does not count), and the middle of the loophole.
	var m := 0.05
	var solid: Array = [
		[Vector3(-WALL_HALF_W + m, HOLE_TOP + m, WALL_FRONT + m), Vector3(WALL_HALF_W - m, WALL_TOP - m, WALL_BACK - m)],
		[Vector3(-WALL_HALF_W + m, 0.0, WALL_FRONT + m), Vector3(-HOLE_HALF_W - m, HOLE_TOP + m, WALL_BACK - m)],
		[Vector3(HOLE_HALF_W + m, 0.0, WALL_FRONT + m), Vector3(WALL_HALF_W - m, HOLE_TOP + m, WALL_BACK - m)],
	]
	var hole_lo := Vector2(-HOLE_HALF_W + 0.06, 0.02)
	var hole_hi := Vector2(HOLE_HALF_W - 0.06, HOLE_TOP - 0.05)

	var total_tris := 0
	for post: Node3D in posts:
		var tag := String(post.name)
		var bags := post.get_node_or_null("Sandbags") as MeshInstance3D
		var core := post.get_node_or_null("SandbagCore") as MeshInstance3D
		check(bags != null and core != null, tag + ": has its sandbags and the dark filling")
		if bags == null or core == null:
			continue

		# Still one merged mesh with two surfaces (plain + snowy), now with the sackcloth material.
		check(bags.mesh is ArrayMesh and bags.mesh.get_surface_count() == 2, tag + ": the bags are one mesh with 2 surfaces")
		var cloth := true
		for s in bags.mesh.get_surface_count():
			var mat := bags.mesh.surface_get_material(s) as StandardMaterial3D
			cloth = cloth and mat != null and mat.albedo_texture != null and mat.normal_enabled and mat.normal_texture != null and mat.uv1_triplanar
		check(cloth, tag + ": both surfaces use the burlap texture and its normal map")

		# Smooth normals: neighbouring triangles share their corner points (a faceted mesh has
		# 3 separate points per triangle), and every normal has length 1.
		var tris := 0
		var points := 0
		var unit := true
		for s in bags.mesh.get_surface_count():
			var arr := bags.mesh.surface_get_arrays(s)
			tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			points += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			for n: Vector3 in arr[Mesh.ARRAY_NORMAL]:
				unit = unit and absf(n.length() - 1.0) < 0.01
		total_tris += tris
		check(points < tris and unit, tag + ": the bags have smooth normals (%d points for %d triangles)" % [points, tris])

		# Nothing changed for bullets and feet: the same 5 collision shapes, none on the new parts.
		var shapes := 0
		for c in post.get_children():
			if c is CollisionShape3D:
				shapes += 1
		check(shapes == 5 and bags.get_child_count() == 0 and core.get_child_count() == 0, tag + ": the collision is unchanged (5 shapes, none on the bags or the filling)")

		var bag_tm := bags.mesh.generate_triangle_mesh()
		var core_tm := core.mesh.generate_triangle_mesh()

		# 1. Lines straight through the wall, every 2 cm.
		var wall_lines := 0
		var see_through := 0
		var bag_miss := 0
		var hole_lines := 0
		var hole_blocked := 0
		var x := -WALL_HALF_W + 0.06
		while x < WALL_HALF_W - 0.05:
			var y := 0.02
			while y < WALL_TOP - 0.05:
				var a := Vector3(x, y, 0.8)
				var b := Vector3(x, y, -1.4)
				var hit_bag := bag_tm.intersect_segment(a, b).size() > 0
				var hit_core := core_tm.intersect_segment(a, b).size() > 0
				if absf(x) > HOLE_HALF_W + m or y > HOLE_TOP + m:
					wall_lines += 1
					if not hit_bag and not hit_core:
						see_through += 1
					if not hit_bag:
						bag_miss += 1
				elif x > hole_lo.x and x < hole_hi.x and y > hole_lo.y and y < hole_hi.y:
					hole_lines += 1
					if hit_bag or hit_core:
						hole_blocked += 1
				y += 0.02
			x += 0.02
		check(see_through == 0, tag + ": nobody sees straight through the wall (%d of %d lines pass)" % [see_through, wall_lines])
		check(bag_miss < wall_lines * 0.03, tag + ": the bags themselves close the wall (%.1f %% of the lines find only the dark filling)" % (100.0 * bag_miss / wall_lines))
		check(hole_lines > 400 and hole_blocked == 0, tag + ": the loophole is open (%d of %d lines blocked)" % [hole_blocked, hole_lines])

		# 2. Slanted lines: from where the soldier's eyes can be in the bay (standing, leaning,
		#    crouching) to points all over the field in front.
		var slant_wall := 0
		var slant_through := 0
		var slant_hole := 0
		var slant_blocked := 0
		for eye: Vector3 in [Vector3(0, 0.2, 0.75), Vector3(-0.45, 0.25, 0.6), Vector3(0.45, 0.25, 0.6),
				Vector3(0.3, 0.05, 1.2), Vector3(-0.2, 0.6, 0.5), Vector3(0, -0.3, 0.9)]:
			var tx := -6.0
			while tx <= 6.0:
				var ty := -0.5
				while ty <= 3.0:
					var target := Vector3(tx, ty, -4.0)
					var in_wall := false
					for box: Array in solid:
						in_wall = in_wall or _crosses_box(eye, target, box[0], box[1])
					var hit := bag_tm.intersect_segment(eye, target).size() > 0 or core_tm.intersect_segment(eye, target).size() > 0
					if in_wall:
						slant_wall += 1
						if not hit:
							slant_through += 1
							print("   passes: eye ", eye, " -> ", target, "  at the wall middle: ", eye.lerp(target, (-0.29 - eye.z) / (target.z - eye.z)))
					else:
						# Through the middle of the hole at both faces of the wall?
						var free := true
						for z: float in [WALL_BACK, WALL_FRONT]:
							var p := eye.lerp(target, (z - eye.z) / (target.z - eye.z))
							free = free and p.x > hole_lo.x and p.x < hole_hi.x and p.y > hole_lo.y and p.y < hole_hi.y
						if free:
							slant_hole += 1
							if hit:
								slant_blocked += 1
					ty += 0.07
				tx += 0.07
		check(slant_wall > 1000 and slant_through == 0, tag + ": no slanted view through the wall either (%d of %d lines pass)" % [slant_through, slant_wall])
		check(slant_hole > 200 and slant_blocked == 0, tag + ": the view out through the loophole is free (%d of %d lines blocked)" % [slant_blocked, slant_hole])

		# The filling stays hidden inside: it never reaches the wall's faces or the loophole.
		var inside := true
		for v: Vector3 in core.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			inside = inside and v.z < WALL_BACK - 0.05 and v.z > WALL_FRONT + 0.05 and v.y < WALL_TOP - 0.05
			inside = inside and (absf(v.x) > HOLE_HALF_W + 0.05 or v.y > HOLE_TOP + 0.05)
		check(inside, tag + ": the dark filling stays inside the wall")

	check(total_tris < 30000, "the bags stay cheap to draw (%d triangles in the 4 walls)" % total_tris)

	# A bullet through the loophole still flies free, one beside it is still stopped (physics).
	var space := get_viewport().get_world_3d().direct_space_state
	var o: Vector3 = (posts[1] as Node3D).global_position
	var through := PhysicsRayQueryParameters3D.create(o + Vector3(0, 0.2, 0.5), o + Vector3(0, 0.2, -3.0))
	check(space.intersect_ray(through).is_empty(), "a bullet through the loophole is not stopped")
	var beside := PhysicsRayQueryParameters3D.create(o + Vector3(0.8, 0.2, 0.5), o + Vector3(0.8, 0.2, -3.0))
	var hit_beside := space.intersect_ray(beside)
	check(not hit_beside.is_empty() and (hit_beside.collider as Node).is_in_group("fire_post"), "a bullet beside the loophole is stopped by the wall")

	print("RESULT: ", "OK (0 failures)" if fails == 0 else "FAILED (%d failures)" % fails)
	get_tree().quit(1 if fails > 0 else 0)
