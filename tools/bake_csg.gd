extends SceneTree
## Bakes the CSG trench and bunker (levels/source/trench_csg.tscn) into plain meshes and
## collision shapes in levels/baked/. Run it after editing the CSG source, then rebuild the
## level and re-bake the navigation mesh:
##   godot --headless --path . --script tools/bake_csg.gd

func _initialize() -> void:
	run()

func run() -> void:
	var src: Node = load("res://levels/source/trench_csg.tscn").instantiate()
	root.add_child(src)
	for i in 3:
		await process_frame
	DirAccess.make_dir_recursive_absolute("res://levels/baked")
	for n in ["Trench", "Bunker"]:
		var csg := src.get_node(n) as CSGShape3D
		var mesh: ArrayMesh = csg.bake_static_mesh()
		var shape: ConcavePolygonShape3D = csg.bake_collision_shape()
		var tris: int = 0
		for s in mesh.get_surface_count():
			tris += mesh.surface_get_array_index_len(s) / 3 if mesh.surface_get_array_index_len(s) > 0 else mesh.surface_get_array_len(s) / 3
		ResourceSaver.save(mesh, "res://levels/baked/%s_mesh.res" % n.to_lower(), ResourceSaver.FLAG_COMPRESS)
		ResourceSaver.save(shape, "res://levels/baked/%s_shape.res" % n.to_lower(), ResourceSaver.FLAG_COMPRESS)
		print("%s: %d surfaces, %d triangles, %d collision faces" % [n, mesh.get_surface_count(), tris, shape.get_faces().size() / 3])
	quit()
