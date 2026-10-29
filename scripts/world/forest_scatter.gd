@tool
class_name ForestScatter
extends Node3D
## Scatters simple snowy spruce trees using MultiMeshInstance3D.
##
## A MultiMesh draws hundreds of copies of one mesh in a single draw call, which is
## much faster than hundreds of separate tree nodes (important for the web).
## Trees are grouped into square chunks; each chunk hides itself beyond
## `visibility_end` metres, so far-away chunks cost nothing to draw.

@export_tool_button("Rebuild forest") var rebuild_action: Callable = build

@export var terrain_path: NodePath = ^"../Terrain"
@export var random_seed: int = 1939
## Forest areas as (x, z, width, depth) rectangles.
@export var forest_areas: Array[Rect2] = [Rect2(-150, 80, 300, 70), Rect2(-150, -150, 300, 40)]
@export var trees_per_100m2: float = 4.0
@export var lone_trees: int = 30 ## A few single trees out on the open ground.
@export var lone_tree_area: Rect2 = Rect2(-140, -105, 280, 140)
## Areas where trees must never grow (trench earthworks + a little space around).
@export var keep_clear: Array[Rect2] = [Rect2(-110, 46, 220, 32)]
@export var min_scale: float = 1.0
@export var max_scale: float = 1.8
@export var chunk_size: float = 50.0
@export var visibility_end: float = 170.0 ## Chunks further away than this are not drawn.
@export var trunk_material: Material
@export var foliage_material: Material


func _ready() -> void:
	add_to_group("forest")
	build()


## Changes how far away trees are still drawn (used by the quality setting).
func set_visibility_end(distance: float) -> void:
	visibility_end = distance
	for child in get_children():
		if child is MultiMeshInstance3D:
			(child as MultiMeshInstance3D).visibility_range_end = distance


func build() -> void:
	for child in get_children():
		if child.has_meta("generated"):
			child.free()

	var terrain := get_node_or_null(terrain_path) as TerrainGenerator
	if terrain == null:
		push_warning("ForestScatter: terrain not found at %s" % terrain_path)
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var positions: Array[Vector2] = []
	for area in forest_areas:
		var count: int = int(area.get_area() / 100.0 * trees_per_100m2)
		for i in count:
			positions.append(Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y)))
	for i in lone_trees:
		positions.append(Vector2(rng.randf_range(lone_tree_area.position.x, lone_tree_area.end.x), rng.randf_range(lone_tree_area.position.y, lone_tree_area.end.y)))

	# Sort trees into chunks.
	var chunks: Dictionary = {}  # Vector2i -> Array of Transform3D
	for p in positions:
		if _is_kept_clear(p):
			continue
		var s: float = rng.randf_range(min_scale, max_scale)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s))
		var origin := Vector3(p.x, terrain.get_height(p.x, p.y) - 0.2, p.y)
		var key := Vector2i(floori(p.x / chunk_size), floori(p.y / chunk_size))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(Transform3D(basis, origin))

	var tree_mesh: ArrayMesh = _make_tree_mesh()
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.3
	trunk_shape.height = 4.0
	for key in chunks:
		_add_chunk(key, chunks[key], tree_mesh, trunk_shape)


func _is_kept_clear(p: Vector2) -> bool:
	for r in keep_clear:
		if r.has_point(p):
			return true
	return false


func _add_chunk(key: Vector2i, transforms: Array, mesh: ArrayMesh, trunk_shape: Shape3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Chunk_%d_%d" % [key.x, key.y]
	mmi.multimesh = mm
	mmi.visibility_range_end = visibility_end
	mmi.set_meta("generated", true)
	add_child(mmi)

	# Trunk collision (also created in the editor so "Bake NavigationMesh" sees the trees).
	var body := StaticBody3D.new()
	body.name = "Trunks_%d_%d" % [key.x, key.y]
	body.set_meta("surface", "wood") # bullets hitting trunks show wood splinters
	body.set_meta("generated", true)
	for t: Transform3D in transforms:
		var cs := CollisionShape3D.new()
		cs.shape = trunk_shape
		cs.position = t.origin + Vector3(0, trunk_shape.height / 2.0, 0)
		body.add_child(cs)
	add_child(body)


## Builds one tree: a trunk (surface 0) and two stacked cones of branches (surface 1).
func _make_tree_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.2
	trunk.height = 3.0
	trunk.radial_segments = 6
	trunk.rings = 0
	_add_part(mesh, [[trunk, Vector3(0, 1.5, 0)]], trunk_material, false)

	var lower := CylinderMesh.new()
	lower.top_radius = 0.0
	lower.bottom_radius = 1.7
	lower.height = 3.6
	lower.radial_segments = 8
	lower.rings = 0
	lower.cap_top = false
	var upper := CylinderMesh.new()
	upper.top_radius = 0.0
	upper.bottom_radius = 1.15
	upper.height = 3.0
	upper.radial_segments = 8
	upper.rings = 0
	upper.cap_top = false
	_add_part(mesh, [[lower, Vector3(0, 3.4, 0)], [upper, Vector3(0, 5.6, 0)]], foliage_material, true)
	return mesh


## Merges primitive meshes (each with an offset) into one new surface of `mesh`.
## If `snowy`, upward-facing parts get a white vertex colour = snow on the branches.
func _add_part(mesh: ArrayMesh, parts: Array, material: Material, snowy: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var prim: PrimitiveMesh = part[0]
		var offset: Vector3 = part[1]
		var arr: Array = prim.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in idx:
			var c := Color.WHITE
			if snowy:
				# Dark green at the bottom of each cone, snowier towards the top.
				# Faces pointing down (cone bottoms) get no snow.
				var height_factor: float = v[i].y / prim.get_aabb().size.y + 0.5
				var snow: float = 0.0 if nrm[i].y < -0.5 else pow(clampf(height_factor, 0.0, 1.0), 3.0) * 0.8
				c = Color(0.08, 0.14, 0.09).lerp(Color(0.88, 0.91, 0.96), snow)
			st.set_color(c)
			st.set_normal(nrm[i])
			st.add_vertex(v[i] + offset)
	st.set_material(material)
	st.commit(mesh)
