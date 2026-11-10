extends SceneTree
## Bakes the enemy navigation mesh for the test level and saves it to a file.
func _initialize() -> void:
	var level: Node = load("res://levels/test_level.tscn").instantiate()
	root.add_child(level)
	run(level)

func run(level: Node) -> void:
	for i in 5:
		await physics_frame
	var region: NavigationRegion3D = level.get_node("Navigation")
	# Enemy side + (L3) the communication trenches behind the line (same box as in build_scenes.gd).
	region.navigation_mesh.filter_baking_aabb = AABB(Vector3(-150, -10, -150), Vector3(300, 30, 268))
	var t := Time.get_ticks_msec()
	region.bake_navigation_mesh(false)
	var nm := region.navigation_mesh
	print("baked in %d ms: %d vertices, %d polygons" % [Time.get_ticks_msec() - t, nm.get_vertices().size(), nm.get_polygon_count()])
	var err := ResourceSaver.save(nm, "res://levels/test_level_navmesh.res", ResourceSaver.FLAG_COMPRESS)
	print("navmesh saved: ", error_string(err))
	quit()
