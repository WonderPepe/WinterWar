@tool
class_name TerrainGenerator
extends StaticBody3D
## Builds the snowy ground: one grid mesh for drawing and a HeightMapShape3D for collision.
##
## Heights come from noise for now. Later you can put an image made from real
## elevation data into `heightmap` and the same code will use it instead.
## "@tool" means this script also runs inside the editor, so you can see the terrain there.
## The generated nodes are NOT saved into the scene file (it would be huge); they are
## rebuilt every time the scene opens.

@export_tool_button("Rebuild terrain") var rebuild_action: Callable = build

@export var size_m: int = 300 ## Width and depth of the square map, in metres (1 vertex per metre).
@export var noise: FastNoiseLite ## Random "hilliness" pattern.
@export var noise_amplitude: float = 4.0 ## How high the hills are (metres up and down).
@export var finnish_side_rise: float = 2.0 ## Ground behind the trench rises gently by this much.
@export var snow_material: Material
@export var edge_height: float = -0.3 ## Height at the map border; a flat "horizon" ground continues from here.
@export var edge_falloff_m: float = 25.0 ## Hills fade out over this distance near the border.
@export var horizon_size_m: float = 1500.0 ## How far the flat horizon ground reaches (hidden by fog).

@export_group("Heightmap (real elevation data, later)")
@export var heightmap: Texture2D ## Grey image: black = lowest, white = highest. Leave empty to use noise.
@export var heightmap_min_m: float = 0.0
@export var heightmap_max_m: float = 20.0

@export_group("Frozen bog in front of the trench")
@export var bog_z_start: float = -120.0 ## Bog runs between these two Z values.
@export var bog_z_end: float = 40.0
@export var bog_flatness: float = 0.2 ## 0 = perfectly flat, 1 = as hilly as elsewhere.
@export var bog_height: float = -0.6 ## Bog sits a little lower than the trench line.

@export_group("Trench earthworks")
## Area (x, z, width, depth) covered by the CSG "earth slab" of the trench.
## Inside it the ground is lowered to become the trench floor.
@export var trench_area: Rect2 = Rect2(-105, 52, 210, 18)
@export var trench_depth: float = 1.4 ## Trench floor is this far below the ground level (y = 0).
@export var blend_margin: float = 14.0 ## Metres over which hills fade into the flat trench area.

var _image: Image


func _ready() -> void:
	build()


## Returns the ground height (y) at a world x/z position. Other scripts
## (forest, snow drifts, enemies later) use this to place things on the ground.
func get_height(x: float, z: float) -> float:
	var natural: float = _natural_height(x, z)
	var outside: float = _distance_outside(trench_area, x, z)
	if outside <= 0.0:
		# Inside the slab: lowered floor, except the outermost edge (hidden inside the slab walls).
		var inner: Rect2 = trench_area.grow(-0.5)
		return -trench_depth if inner.has_point(Vector2(x, z)) else 0.0
	var t: float = smoothstep(0.0, 1.0, outside / blend_margin)
	return lerpf(0.0, natural, t)


## Rebuilds the mesh and the collision shape.
func build() -> void:
	if noise == null:
		noise = FastNoiseLite.new()
	_image = null
	if heightmap != null:
		_image = heightmap.get_image()
		if _image.is_compressed():
			_image.decompress()

	# Remove what we generated last time.
	for child in get_children():
		if child.has_meta("generated"):
			child.free()

	var n: int = size_m + 1           # vertices per side
	var half: float = size_m / 2.0
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for iz in n:
		for ix in n:
			heights[iz * n + ix] = get_height(ix - half, iz - half)

	_add_mesh(heights, n, half)
	_add_collision(heights, n)
	_add_horizon(half)


func _natural_height(x: float, z: float) -> float:
	var h: float
	if _image != null:
		h = _sample_heightmap(x, z)
	else:
		h = noise.get_noise_2d(x, z) * noise_amplitude
	# Flatten the frozen bog.
	var bog_w: float = _bog_weight(z)
	h = lerpf(h, bog_height + h * bog_flatness, bog_w)
	# Finnish side (behind the trench, +z) rises a little.
	h += finnish_side_rise * smoothstep(trench_area.end.y, trench_area.end.y + 50.0, z)
	# Fade to a flat height at the border so the horizon ground fits seamlessly.
	var to_edge: float = size_m / 2.0 - maxf(absf(x), absf(z))
	return lerpf(edge_height, h, smoothstep(0.0, edge_falloff_m, to_edge))


func _bog_weight(z: float) -> float:
	return smoothstep(bog_z_start - 15.0, bog_z_start, z) * (1.0 - smoothstep(bog_z_end, bog_z_end + 15.0, z))


func _sample_heightmap(x: float, z: float) -> float:
	var u: float = clampf((x / size_m) + 0.5, 0.0, 1.0) * (_image.get_width() - 1)
	var v: float = clampf((z / size_m) + 0.5, 0.0, 1.0) * (_image.get_height() - 1)
	var value: float = _image.get_pixel(int(u), int(v)).r  # nearest pixel, good enough for now
	return lerpf(heightmap_min_m, heightmap_max_m, value)


func _distance_outside(r: Rect2, x: float, z: float) -> float:
	var dx: float = maxf(maxf(r.position.x - x, x - r.end.x), 0.0)
	var dz: float = maxf(maxf(r.position.y - z, z - r.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


func _add_mesh(heights: PackedFloat32Array, n: int, half: float) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	uvs.resize(n * n)
	var snow := Color(0.93, 0.95, 1.0)
	var ice := Color(0.72, 0.78, 0.86)
	for iz in n:
		for ix in n:
			var i: int = iz * n + ix
			var x: float = ix - half
			var z: float = iz - half
			verts[i] = Vector3(x, heights[i], z)
			# Normal from the height difference of the neighbours (2 m apart).
			var hl: float = heights[iz * n + maxi(ix - 1, 0)]
			var hr: float = heights[iz * n + mini(ix + 1, n - 1)]
			var hd: float = heights[maxi(iz - 1, 0) * n + ix]
			var hu: float = heights[mini(iz + 1, n - 1) * n + ix]
			normals[i] = Vector3(hl - hr, 2.0, hd - hu).normalized()
			# Icy grey-blue patches on the bog, white snow elsewhere.
			var patch: float = clampf(noise.get_noise_2d(x * 3.0 + 500.0, z * 3.0) * 2.0 + 0.3, 0.0, 1.0)
			colors[i] = snow.lerp(ice, patch * _bog_weight(z) * 0.6)
			uvs[i] = Vector2(x, z) * 0.25

	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var k: int = 0
	for iz in n - 1:
		for ix in n - 1:
			var a: int = iz * n + ix
			var b: int = a + 1
			var c: int = a + n
			var d: int = c + 1
			indices[k] = a; indices[k + 1] = b; indices[k + 2] = c
			indices[k + 3] = b; indices[k + 4] = d; indices[k + 5] = c
			k += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, snow_material)

	var mi := MeshInstance3D.new()
	mi.name = "GroundMesh"
	mi.mesh = mesh
	# The gentle ground hardly casts visible shadows, but drawing its 180 000 triangles
	# again into the shadow map is expensive - so it only receives shadows.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("generated", true)
	add_child(mi)


func _add_collision(heights: PackedFloat32Array, n: int) -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.name = "GroundCollision"
	cs.shape = shape
	cs.set_meta("generated", true)
	add_child(cs)


## A flat ring of snow around the map so you never see the edge of the world.
## It has no collision; invisible walls in the level keep players inside.
func _add_horizon(half: float) -> void:
	var far: float = horizon_size_m
	var y: float = edge_height
	# Four rectangles around the map: (min x, min z, max x, max z)
	var rects: Array[Rect2] = [
		Rect2(-far, -far, 2.0 * far, far - half),   # north strip
		Rect2(-far, half, 2.0 * far, far - half),   # south strip
		Rect2(-far, -half, far - half, 2.0 * half), # west strip
		Rect2(half, -half, far - half, 2.0 * half), # east strip
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.set_color(Color(0.93, 0.95, 1.0))
	for r in rects:
		var a := Vector3(r.position.x, y, r.position.y)
		var b := Vector3(r.end.x, y, r.position.y)
		var c := Vector3(r.position.x, y, r.end.y)
		var d := Vector3(r.end.x, y, r.end.y)
		for v in [a, b, c, b, d, c]:
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "HorizonMesh"
	mi.mesh = st.commit()
	mi.material_override = snow_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("generated", true)
	add_child(mi)
