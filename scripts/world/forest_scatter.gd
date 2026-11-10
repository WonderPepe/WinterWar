@tool
class_name ForestScatter
extends Node3D
## Scatters snowy spruce trees using MultiMeshInstance3D, and draws a far-away tree line.
##
## A MultiMesh draws hundreds of copies of one mesh in a single draw call, which is
## much faster than hundreds of separate tree nodes (important for the web).
## Trees have two "levels of detail" (LOD):
## - near (closer than `detail_distance`): detailed spruces, two different shapes,
## - far: a simple spruce with the same outline, fading out at `visibility_end`.
## The switch happens tree by tree in the spruce shader (a soft dissolve), using the camera
## position this script passes to the materials every frame. Trees are also grouped into
## square chunks, and whole chunks that are surely too far for a level are skipped
## (visibility ranges) so the graphics card has less to do.
## Shadows always use the simple tree (nobody notices, and it is much cheaper).

@export_tool_button("Rebuild forest") var rebuild_action: Callable = build

@export var terrain_path: NodePath = ^"../Terrain"
@export var random_seed: int = 1939
## Forest areas as (x, z, width, depth) rectangles.
@export var forest_areas: Array[Rect2] = [Rect2(-150, 80, 300, 70), Rect2(-150, -150, 300, 40)]
@export var trees_per_100m2: float = 4.0
@export var lone_trees: int = 30 ## A few single trees out on the open ground.
@export var lone_tree_area: Rect2 = Rect2(-140, -105, 280, 140)
## Areas where trees must never grow (trench earthworks + a little space around) and, T3, three
## lanes through the southern forest where the tanks drive out (x = start of TankRoute1..3 ± 6.5 m).
@export var keep_clear: Array[Rect2] = [Rect2(-110, 46, 220, 32), Rect2(-74.5, -151, 13, 47),
		Rect2(-0.5, -151, 13, 47), Rect2(67.5, -151, 13, 47),
		Rect2(-50, 64, 20, 54), Rect2(30, 64, 20, 54)] # L3: the two communication trenches
@export var min_scale: float = 1.0
@export var max_scale: float = 1.8
@export var chunk_size: float = 50.0
@export var visibility_end: float = 220.0 ## Chunks further away than this are not drawn.
@export var detail_distance: float = 70.0 ## Closer than this, chunks use the detailed trees.
@export var fade_band: float = 10.0 ## Metres over which one tree changes into the other.
@export var trunk_material: ShaderMaterial ## spruce.gdshader with `trunk` on
@export var foliage_material: ShaderMaterial ## spruce.gdshader

@export_group("Distant tree line")
@export var tree_line_material: Material
## Rings of tree silhouettes around the map: [radius m, height m, picture repeats].
@export var tree_line_rings: Array[Vector3] = [Vector3(330, 26, 10), Vector3(520, 38, 11)]

var _near_instances: Array[MultiMeshInstance3D] = []
var _far_instances: Array[MultiMeshInstance3D] = []
var _near_materials: Array[ShaderMaterial] = [] # detailed tree + shadow tree
var _far_materials: Array[ShaderMaterial] = []
var _last_camera_pos := Vector3(INF, INF, INF)


func _ready() -> void:
	add_to_group("forest")
	build()


## Every frame: tell the tree materials where the camera is (for the per-tree LOD).
func _process(_delta: float) -> void:
	var cam: Camera3D = _current_camera()
	if cam == null:
		return
	var pos: Vector3 = cam.global_position
	if pos.distance_squared_to(_last_camera_pos) < 0.04: # moved less than 20 cm
		return
	_last_camera_pos = pos
	for m in _near_materials + _far_materials:
		m.set_shader_parameter("lod_camera", pos)


## Changes how far away trees are still drawn (used by the quality setting).
func set_visibility_end(distance: float) -> void:
	visibility_end = distance
	_apply_ranges()


## Changes up to which distance the detailed trees are used (used by the quality setting).
func set_detail_distance(distance: float) -> void:
	detail_distance = distance
	_apply_ranges()


## Chunk ranges are wider than the tree ranges by the chunk's radius, so a chunk is
## never hidden while one of its trees should still be visible. The shader does the rest.
func _apply_ranges() -> void:
	var chunk_radius: float = chunk_size * 0.75
	for mmi in _near_instances:
		mmi.visibility_range_end = detail_distance + chunk_radius
	for mmi in _far_instances:
		mmi.visibility_range_begin = maxf(detail_distance - fade_band - chunk_radius, 0.0)
		mmi.visibility_range_end = visibility_end + chunk_radius
	for m in _near_materials + _far_materials:
		m.set_shader_parameter("lod_distance", detail_distance)
		m.set_shader_parameter("view_distance", visibility_end)
		m.set_shader_parameter("fade_band", fade_band)


func _current_camera() -> Camera3D:
	if Engine.is_editor_hint():
		if not Engine.has_singleton("EditorInterface"):
			return null
		var editor: Object = Engine.get_singleton("EditorInterface")
		var vp: SubViewport = editor.get_editor_viewport_3d(0)
		return vp.get_camera_3d() if vp else null
	return get_viewport().get_camera_3d()


func build() -> void:
	for child in get_children():
		if child.has_meta("generated"):
			child.free()
	_near_instances.clear()
	_far_instances.clear()
	_last_camera_pos = Vector3(INF, INF, INF)
	if foliage_material == null or trunk_material == null:
		push_warning("ForestScatter: trunk or foliage material missing")
		return
	# Copies of the tree materials: one set for the detailed trees, one for the simple ones.
	var near_foliage := _lod_material(foliage_material, 0)
	var near_trunk := _lod_material(trunk_material, 0)
	var far_foliage := _lod_material(foliage_material, 1)
	var far_trunk := _lod_material(trunk_material, 1)
	_near_materials = [near_foliage, near_trunk]
	_far_materials = [far_foliage, far_trunk]

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

	# Per-tree look (shape, snow, colour) uses its own random numbers, so the tree
	# positions stay exactly the same as before (the navigation mesh depends on them).
	var look_rng := RandomNumberGenerator.new()
	look_rng.seed = random_seed + 1

	# Sort trees into chunks.
	var chunks: Dictionary = {}  # Vector2i -> Array of [Transform3D, Color]
	for p in positions:
		if _is_kept_clear(p):
			continue
		var s: float = rng.randf_range(min_scale, max_scale)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s))
		var origin := Vector3(p.x, terrain.get_height(p.x, p.y) - 0.2, p.y)
		var key := Vector2i(floori(p.x / chunk_size), floori(p.y / chunk_size))
		if not chunks.has(key):
			chunks[key] = []
		# Per-tree values for the shader, sent as the instance colour: blue = snow, alpha = tint.
		var custom := Color(1.0, 1.0, look_rng.randf(), look_rng.randf())
		chunks[key].append([Transform3D(basis, origin), custom])

	var near_meshes: Array[ArrayMesh] = [
		_make_spruce(11, 7, 8, 7.4, 1.75, true, 6, near_trunk, near_foliage),  # tall and slender
		_make_spruce(23, 6, 9, 6.8, 2.1, true, 6, near_trunk, near_foliage),   # shorter and fuller
	]
	var far_mesh: ArrayMesh = _make_spruce(11, 4, 5, 7.2, 1.9, false, 4, far_trunk, far_foliage)
	# Same simple tree, but shown where the detailed trees are: it only casts their shadows.
	var shadow_mesh: ArrayMesh = _make_spruce(11, 4, 5, 7.2, 1.9, false, 4, near_trunk, near_foliage)
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.3
	trunk_shape.height = 4.0
	for key in chunks:
		_add_chunk(key, chunks[key], near_meshes, far_mesh, shadow_mesh, trunk_shape)
	_apply_ranges()
	_add_tree_line()


func _lod_material(base: ShaderMaterial, mode: int) -> ShaderMaterial:
	var m: ShaderMaterial = base.duplicate()
	m.set_shader_parameter("lod_mode", mode)
	return m


func _is_kept_clear(p: Vector2) -> bool:
	for r in keep_clear:
		if r.has_point(p):
			return true
	return false


func _make_multimesh(mesh: Mesh, trees: Array) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = trees.size()
	for i in trees.size():
		mm.set_instance_transform(i, trees[i][0])
		mm.set_instance_color(i, trees[i][1])
	return mm


func _add_mmi(n: String, mm: MultiMesh, shadow: GeometryInstance3D.ShadowCastingSetting) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.cast_shadow = shadow
	mmi.set_meta("generated", true)
	add_child(mmi)
	return mmi


func _add_chunk(key: Vector2i, trees: Array, near_meshes: Array[ArrayMesh], far_mesh: ArrayMesh,
		shadow_mesh: ArrayMesh, trunk_shape: Shape3D) -> void:
	var tag: String = "%d_%d" % [key.x, key.y]
	# Near: detailed trees. Neighbouring chunks use different tree shapes (one draw call
	# per chunk instead of two). No shadows (the "Shadow" one below casts them).
	var shape: int = posmod(key.x + key.y, near_meshes.size())
	var near := _add_mmi("Near%d_%s" % [shape, tag], _make_multimesh(near_meshes[shape], trees), GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_near_instances.append(near)
	var shadow := _add_mmi("Shadow_" + tag, _make_multimesh(shadow_mesh, trees), GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	_near_instances.append(shadow)
	# Far: the simple tree. No shadows: the sun's shadows end before the far trees start.
	var far := _add_mmi("Far_" + tag, _make_multimesh(far_mesh, trees), GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_far_instances.append(far)

	# Trunk collision (also created in the editor so "Bake NavigationMesh" sees the trees).
	var body := StaticBody3D.new()
	body.name = "Trunks_" + tag
	body.set_meta("surface", "wood") # bullets hitting trunks show wood splinters
	body.set_meta("generated", true)
	for t: Array in trees:
		var cs := CollisionShape3D.new()
		cs.shape = trunk_shape
		cs.position = (t[0] as Transform3D).origin + Vector3(0, trunk_shape.height / 2.0, 0)
		body.add_child(cs)
	add_child(body)


# ------------------------------------------------------------------ tree mesh
## Builds one spruce: a trunk (surface 0) and `tiers` layers of drooping branches (surface 1).
## Each layer is a jagged star: `points` branch tips with notches between them.
## `underside` adds the darker bottom of each layer (only needed close up).
func _make_spruce(shape_seed: int, tiers: int, points: int, height: float, max_radius: float,
		underside: bool, trunk_sides: int, trunk_mat: Material, foliage_mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed
	var mesh := ArrayMesh.new()

	# Trunk: a tapered cylinder, bark texture wrapped around it.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_h: float = height * 0.8
	for j in trunk_sides:
		var a0: float = TAU * j / trunk_sides
		var a1: float = TAU * (j + 1) / trunk_sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := d0 * 0.2
		var b1 := d1 * 0.2
		var t0 := d0 * 0.05 + Vector3.UP * trunk_h
		var t1 := d1 * 0.05 + Vector3.UP * trunk_h
		var u0: float = 2.0 * j / trunk_sides
		var u1: float = 2.0 * (j + 1) / trunk_sides
		var v_top: float = -trunk_h / 2.0
		_tri(st, [b0, b1, t1], [d0, d1, d1], [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, v_top)], (d0 + d1).normalized())
		_tri(st, [b0, t1, t0], [d0, d1, d0], [Vector2(u0, 0), Vector2(u1, v_top), Vector2(u0, v_top)], (d0 + d1).normalized())
	st.set_material(trunk_mat)
	st.commit(mesh)

	# Branch tiers, from the bottom up.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bottom: float = 1.2
	for t in tiers:
		var f: float = float(t) / tiers
		var radius: float = max_radius * pow(1.0 - f, 0.95) * rng.randf_range(0.92, 1.06) + 0.18
		var y: float = bottom + (height - bottom - 0.6) * f
		var apex_y: float = height if t == tiers - 1 else minf(y + radius * 1.25 + 0.3, height)
		var apex := Vector3(0, apex_y, 0)
		var inner := Vector3(0, y + (apex_y - y) * 0.25, 0)
		var twist: float = rng.randf() * TAU
		var ring: Array[Vector3] = []
		var ring_tip: Array[bool] = []
		for j in points * 2:
			var tip: bool = j % 2 == 0
			var ang: float = twist + TAU * j / (points * 2) + rng.randf_range(-0.08, 0.08)
			var r: float = radius * (rng.randf_range(0.9, 1.08) if tip else rng.randf_range(0.62, 0.72))
			var droop: float = radius * (0.28 if tip else 0.06)
			ring.append(Vector3(cos(ang) * r, y - droop, sin(ang) * r))
			ring_tip.append(tip)
		for j in ring.size():
			var a: Vector3 = ring[j]
			var b: Vector3 = ring[(j + 1) % ring.size()]
			var na: Vector3 = (Vector3(a.x, 0, a.z).normalized() * 0.85 + Vector3.UP * 0.75).normalized()
			var nb: Vector3 = (Vector3(b.x, 0, b.z).normalized() * 0.85 + Vector3.UP * 0.75).normalized()
			var mid_out: Vector3 = (na + nb).normalized()
			# Top side: holds snow (R = 1). Notches are darker (G). UV.x = 0 at the trunk, 1 at the tips.
			var ca := Color(1, 0.95 if ring_tip[j] else 0.6, 1)
			var cb := Color(1, 0.95 if ring_tip[(j + 1) % ring.size()] else 0.6, 1)
			_tri(st, [apex, a, b], [Vector3.UP, na, nb], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 0)], mid_out, [Color(1, 1, 1), ca, cb])
			if underside:
				var da: Vector3 = (Vector3(a.x, 0, a.z).normalized() * 0.5 + Vector3.DOWN * 0.85).normalized()
				var db: Vector3 = (Vector3(b.x, 0, b.z).normalized() * 0.5 + Vector3.DOWN * 0.85).normalized()
				var dark := Color(0, 0.55, 1)
				_tri(st, [inner, b, a], [Vector3.DOWN, db, da], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 0)], (da + db).normalized(), [Color(0, 0.35, 1), dark, dark])
	st.set_material(foliage_mat)
	st.commit(mesh)
	return mesh


## Adds one triangle facing `outward` (the vertex order is fixed automatically).
func _tri(st: SurfaceTool, v: Array, n: Array, uv: Array, outward: Vector3, col: Array = []) -> void:
	var order: Array[int] = [0, 1, 2]
	# Godot treats clockwise triangles (seen from the front) as the front side.
	if (v[1] - v[0]).cross(v[2] - v[0]).dot(outward) > 0.0:
		order = [0, 2, 1]
	for i in order:
		if not col.is_empty():
			st.set_color(col[i])
		if not uv.is_empty():
			st.set_uv(uv[i])
		st.set_normal(n[i])
		st.add_vertex(v[i])


# ------------------------------------------------------------------ tree line
## Rings of tree silhouettes far outside the map, so the horizon is a forest edge.
func _add_tree_line() -> void:
	if tree_line_material == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments: int = 96
	var base_y: float = -3.0
	for ring in tree_line_rings:
		var radius: float = ring.x
		var h: float = ring.y
		var repeats: float = ring.z
		for i in segments:
			var a0: float = TAU * i / segments
			var a1: float = TAU * (i + 1) / segments
			var p0 := Vector3(cos(a0) * radius, base_y, sin(a0) * radius)
			var p1 := Vector3(cos(a1) * radius, base_y, sin(a1) * radius)
			var up := Vector3.UP * h
			var u0: float = repeats * i / segments
			var u1: float = repeats * (i + 1) / segments
			var inward: Vector3 = -(p0 + p1).normalized()
			_tri(st, [p0, p1, p1 + up], [inward, inward, inward], [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0)], inward)
			_tri(st, [p0, p1 + up, p0 + up], [inward, inward, inward], [Vector2(u0, 1), Vector2(u1, 0), Vector2(u0, 0)], inward)
	var mi := MeshInstance3D.new()
	mi.name = "TreeLine"
	mi.mesh = st.commit()
	mi.material_override = tree_line_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("generated", true)
	add_child(mi)
