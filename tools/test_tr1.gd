extends Node
## Automated test for TR1: the drawn ground is cut into tiles (not part of the game).
## Every 1 m point is still there at exactly the collision ground's height, tile edges match,
## no tile has simpler LOD versions, and the drawn surface between the points is the same
## surface the collision uses (so a soldier far away never looks sunk in or floating).
##   godot --headless --path . --script tools/run.gd -- tools/test_tr1.gd

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _ready() -> void:
	await get_tree().process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	for i in 10:
		await get_tree().physics_frame
	var terrain: TerrainGenerator = game.find_child("Terrain", true, false)
	check(terrain != null, "Terrain found")
	if terrain == null:
		get_tree().quit(1)
		return
	var n: int = terrain.size_m + 1
	var half: float = terrain.size_m / 2.0
	var count: int = terrain.tiles_per_side
	check(count == 4, "4 x 4 tiles (chosen from the measurements)")
	check(terrain.get_node_or_null("GroundMesh") == null, "the old single GroundMesh is gone")
	var tiles: Node3D = terrain.get_node_or_null("GroundTiles")
	check(tiles != null and tiles.get_child_count() == count * count, "GroundTiles has %d tiles" % (count * count))
	var shape: HeightMapShape3D = (terrain.get_node("GroundCollision") as CollisionShape3D).shape
	var heights: PackedFloat32Array = shape.map_data

	# Every grid point once per tile that holds it; same point in two tiles must be identical.
	var seen := {}   # grid index -> [position, normal, colour]
	var triangles: int = 0
	var height_ok := true
	var edge_ok := true
	var edge_points: int = 0
	var lod_free := true
	var no_shadow := true
	for mi: MeshInstance3D in tiles.get_children():
		var mesh: ArrayMesh = mi.mesh
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			no_shadow = false
		if mesh.get_surface_count() != 1:
			lod_free = false
		var surf: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
		if not (surf.get("lods", []) as Array).is_empty():
			lod_free = false
		var arr: Array = mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		triangles += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		for i in v.size():
			var ix: int = roundi(v[i].x + half)
			var iz: int = roundi(v[i].z + half)
			var gi: int = iz * n + ix
			if v[i].y != heights[gi] or absf(v[i].x - (ix - half)) > 0.0001:
				height_ok = false
			if seen.has(gi):
				edge_points += 1
				var s: Array = seen[gi]
				if s[0] != v[i] or s[1] != nr[i] or s[2] != c[i]:
					edge_ok = false
			else:
				seen[gi] = [v[i], nr[i], c[i]]
	check(seen.size() == n * n, "every 1 m point of the map is drawn (%d of %d)" % [seen.size(), n * n])
	check(triangles == terrain.size_m * terrain.size_m * 2, "same triangle count as before: %d" % triangles)
	check(height_ok, "every drawn point is at exactly the collision ground's height")
	check(edge_ok and edge_points > 0, "tile edges: shared points have the same position, normal, colour (%d)" % edge_points)
	check(lod_free, "no tile has LOD (simpler far-away) versions")
	check(no_shadow, "tiles cast no shadows (as the old ground)")

	# Between the points: the drawn triangle surface must be the collision surface. Rays straight
	# down at random spots inside cells, compared with the height of the drawn triangle there.
	var space := terrain.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 1940
	var worst: float = 0.0
	var rays: int = 0
	for k in 2000:
		var x: float = rng.randf_range(-half + 1.0, half - 1.0)
		var z: float = rng.randf_range(-half + 1.0, half - 1.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 100, z), Vector3(x, -100, z))
		q.collide_with_areas = false
		q.exclude = []
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty() or hit.collider != terrain:
			# Something else (trench slab, bunker, tree) is on top - try the ground only.
			q.collision_mask = terrain.collision_layer
			hit = space.intersect_ray(q)
			if hit.is_empty() or hit.collider != terrain:
				continue
		rays += 1
		worst = maxf(worst, absf(hit.position.y - _drawn_height(heights, n, half, x, z)))
	check(rays > 1500 and worst < 0.001,
		"drawn surface = collision surface between the points (%d rays, worst %.4f m)" % [rays, worst])

	# get_height() still gives the same heights the ground is built from.
	var gh_ok := true
	for k in 500:
		var ix: int = rng.randi_range(0, n - 1)
		var iz: int = rng.randi_range(0, n - 1)
		if absf(terrain.get_height(ix - half, iz - half) - heights[iz * n + ix]) > 0.00001:
			gh_ok = false
	check(gh_ok, "get_height() matches the ground's points")

	print("TR1 test: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


## Height of the drawn ground at x/z: the triangles a-b-c and b-d-c of each 1 m cell
## (a = top left, b = right of a, c = below a, d = below b; diagonal from b to c).
func _drawn_height(h: PackedFloat32Array, n: int, half: float, x: float, z: float) -> float:
	var gx: float = x + half
	var gz: float = z + half
	var ix: int = floori(gx)
	var iz: int = floori(gz)
	var fx: float = gx - ix
	var fz: float = gz - iz
	var a: float = h[iz * n + ix]
	var b: float = h[iz * n + ix + 1]
	var c: float = h[(iz + 1) * n + ix]
	var d: float = h[(iz + 1) * n + ix + 1]
	if fx + fz <= 1.0:
		return a + (b - a) * fx + (c - a) * fz
	return d + (c - d) * (1.0 - fx) + (b - d) * (1.0 - fz)
