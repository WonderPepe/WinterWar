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
	var t := Time.get_ticks_msec()
	region.bake_navigation_mesh(false)
	var nm := region.navigation_mesh
	print("baked in %d ms: %d vertices, %d polygons" % [Time.get_ticks_msec() - t, nm.get_vertices().size(), nm.get_polygon_count()])
	var err := ResourceSaver.save(nm, "res://levels/test_level_navmesh.res", ResourceSaver.FLAG_COMPRESS)
	print("navmesh saved: ", error_string(err))
	quit()
