extends RefCounted
## V2 (helper of tools/build_scenes.gd, not part of the game): the soft snow that hides the
## box edges of the earthworks. Everything here is PICTURE ONLY - no collision, not part of the
## navigation mesh - so cover, sight lines and movement are exactly as before.
##   - TrenchLips:  a rounded lip of snow along every edge of the trenches
##   - FloorDrifts: low drifts where the trench walls meet the floor
##   - BunkerSnow:  a domed snow cap on the bunker roof + low banks against its side walls
##   - Aprons:      snow that smooths the landings at the top of the four exit ramps
##   - heap_mesh(): the rounded earth heaps beside the sandbag walls (firing positions)
## All meshes use the snow shader. Vertex colour green < 1 = trampled / earthy snow.

const STEP := 0.6 ## longest piece of a trench edge (m); shorter = smoother but more triangles


## Collects grids of points into one mesh with smooth normals.
class Builder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	## `rows`: Array of PackedVector3Array (all the same length), `cols`: matching colours.
	## `closed`: the last row joins the first. `skip`: per row, 1 = no quads from this row to the
	## next. `up_cols`: columns whose normal is forced straight up (they melt into flat ground).
	## `ref`: roughly where the surface faces (decides which side is the front).
	func add_grid(rows: Array, cols: Array, closed: bool, skip := PackedByteArray(),
			up_cols: Array = [], ref := Vector3.UP) -> void:
		var nr := rows.size()
		if nr < 2:
			return
		var nc: int = rows[0].size()
		var base := verts.size()
		var ns := PackedVector3Array()
		ns.resize(nr * nc)
		var facing := 0.0
		for r in nr:
			var r0: int = (r - 1 + nr) % nr if closed else maxi(r - 1, 0)
			var r1: int = (r + 1) % nr if closed else mini(r + 1, nr - 1)
			for c in nc:
				var dc: Vector3 = rows[r][mini(c + 1, nc - 1)] - rows[r][maxi(c - 1, 0)]
				var dr: Vector3 = rows[r1][c] - rows[r0][c]
				var n := dc.cross(dr)
				n = n.normalized() if n.length_squared() > 1e-12 else Vector3.ZERO
				ns[r * nc + c] = n
				facing += n.dot(ref)
		var sgn := -1.0 if facing < 0.0 else 1.0
		for r in nr:
			for c in nc:
				var n: Vector3 = ns[r * nc + c] * sgn
				if n == Vector3.ZERO or c in up_cols:
					n = Vector3.UP
				verts.append(rows[r][c])
				normals.append(n)
				colors.append(cols[r][c])
		var last := nr if closed else nr - 1
		for r in last:
			if not skip.is_empty() and skip[r] == 1:
				continue
			var rn := (r + 1) % nr
			for c in nc - 1:
				_tri(base + r * nc + c, base + r * nc + c + 1, base + rn * nc + c)
				_tri(base + r * nc + c + 1, base + rn * nc + c + 1, base + rn * nc + c)

	## Adds a triangle, wound so that its front is on the side of the vertex normals.
	func _tri(a: int, b: int, c: int) -> void:
		var g := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		if g.length_squared() < 1e-14:
			return # zero area
		if g.dot(normals[a] + normals[b] + normals[c]) > 0.0: # Godot: front = clockwise
			indices.append_array([a, c, b])
		else:
			indices.append_array([a, b, c])

	func triangles() -> int:
		return indices.size() / 3

	func mesh(mat: Material) -> ArrayMesh:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_INDEX] = indices
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat)
		return m


static func _noise(noise_seed: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 2
	return n


## 0 … 1 from a noise value.
static func _n01(n: FastNoiseLite, x: float, z: float) -> float:
	return clampf(n.get_noise_2d(x, z) * 0.75 + 0.5, 0.0, 1.0)


static func _outside(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


# ------------------------------------------------------------------ the outline of the trenches
## The floor plan of everything dug to full depth: one or more polygons (x, z), read from the
## CSG source (every box that is subtracted over the full height of the earth slab).
static func footprint(trench_csg: Node) -> Array[PackedVector2Array]:
	var polys: Array[PackedVector2Array] = []
	for c in trench_csg.get_children():
		var box := c as CSGBox3D
		if box == null or box.operation != CSGShape3D.OPERATION_SUBTRACTION or box.size.y < 3.5:
			continue
		var rect := PackedVector2Array()
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p: Vector3 = box.transform * Vector3(corner.x * box.size.x / 2.0, 0.0, corner.y * box.size.z / 2.0)
			rect.append(Vector2(p.x, p.z))
		# Join it with every polygon it touches.
		var rest: Array[PackedVector2Array] = []
		for q in polys:
			var merged := Geometry2D.merge_polygons(rect, q)
			var outer: Array[PackedVector2Array] = []
			for m in merged:
				if not Geometry2D.is_polygon_clockwise(m):
					outer.append(m)
			if outer.size() == 1:
				if merged.size() > 1:
					push_warning("EarthworkSnow: the trench plan has an island - its edge gets no snow lip")
				rect = outer[0]
			else:
				rest.append(q)
		rest.append(rect)
		polys = rest
	return polys


## Cuts a polygon's edges into pieces of at most STEP m. Returns [points, outward normals]:
## the normal points away from the trench; at corners it is the mitre of the two walls.
static func _contour(poly: PackedVector2Array) -> Array:
	var n := poly.size()
	var edge_n: Array[Vector2] = []
	for i in n:
		var d := (poly[(i + 1) % n] - poly[i]).normalized()
		edge_n.append(Vector2(d.y, -d.x))
	# Which side is outside? Test a point just beside the middle of the first edge.
	var mid := (poly[0] + poly[1]) / 2.0
	if Geometry2D.is_point_in_polygon(mid + edge_n[0] * 0.05, poly):
		for i in n:
			edge_n[i] = -edge_n[i]
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var prev := edge_n[(i - 1 + n) % n]
		var m := prev + edge_n[i]
		m = m.normalized() if m.length() > 0.01 else edge_n[i]
		pts.append(a)
		nrm.append(m * minf(1.0 / maxf(m.dot(edge_n[i]), 0.05), 1.8))
		var pieces := int(ceil(a.distance_to(b) / STEP))
		for k in range(1, pieces):
			pts.append(a.lerp(b, float(k) / pieces))
			nrm.append(edge_n[i])
	return [pts, nrm]


# ------------------------------------------------------------------ lips and drifts
## `ramps`: Array of Dictionary {x, z0 (ramp starts), z1 (ramp reaches the ground), land_end}.
## `no_lip`: rectangles where no lip may stand (sandbag walls with their loopholes, the bunker).
static func build_lips_and_drifts(polys: Array[PackedVector2Array], depth: float, ramps: Array,
		no_lip: Array[Rect2], mat: Material) -> Array:
	var lips := Builder.new()
	var drifts := Builder.new()
	var n_h := _noise(41, 0.55)
	var n_w := _noise(42, 0.35)
	for poly in polys:
		var con: Array = _contour(poly)
		var pts: PackedVector2Array = con[0]
		var nrm: PackedVector2Array = con[1]
		var lip_rows: Array = []
		var lip_cols: Array = []
		var lip_skip := PackedByteArray()
		var dr_rows: Array = []
		var dr_cols: Array = []
		var dr_skip := PackedByteArray()
		var lip_f := PackedFloat32Array()
		var dr_f := PackedFloat32Array()
		for i in pts.size():
			var p := pts[i]
			var nv := nrm[i]
			var unit := nv.normalized()
			# How much lip / drift here: none on the ramps, none where the sandbags stand.
			var fl := 1.0
			var fd := 1.0
			for r: Dictionary in ramps:
				if absf(p.x - r.x) < 1.3 and p.y > r.z0 - 0.6:
					fl = minf(fl, 1.0 - smoothstep(r.z1 - 1.8, r.z1 - 0.5, p.y))
					fd = minf(fd, 1.0 - smoothstep(r.z0 - 0.6, r.z0 - 0.1, p.y))
			for r in no_lip:
				fl = minf(fl, smoothstep(0.0, 0.3, _outside(r, p)))
			lip_f.append(fl)
			dr_f.append(fd)

			# --- the lip: from the flat ground up over a rounded top, curling over the wall ---
			# The side behind the men (rear, +z) is piled a little higher than the front.
			var rear := smoothstep(-0.3, 0.3, unit.y)
			var h := lerpf(0.04, lerpf(0.09, 0.15, rear), _n01(n_h, p.x, p.y)) * fl
			var w := lerpf(0.32, 0.62, _n01(n_w, p.x, p.y)) * fl
			var row := PackedVector3Array()
			var col := PackedColorArray()
			for q: Vector2 in [Vector2(w, -0.02), Vector2(0.52 * w, 0.48 * h), Vector2(0.2 * w, 0.92 * h),
					Vector2(0.03 * fl, h), Vector2(-0.05 * fl, 0.6 * h), Vector2(-0.04 * fl, 0.0), Vector2(0.0, -0.06)]:
				var o := p + (nv if q.x > 0.0 else unit) * q.x
				row.append(Vector3(o.x, q.y, o.y))
				col.append(Color.WHITE)
			lip_rows.append(row)
			lip_cols.append(col)

			# --- the drift at the foot of the wall: clean snow at the wall, trampled further in ---
			var hd := lerpf(0.07, 0.24, _n01(n_h, p.x + 300.0, p.y)) * fd
			var wd := lerpf(0.28, 0.5, _n01(n_w, p.x + 300.0, p.y)) * fd
			row = PackedVector3Array()
			col = PackedColorArray()
			var prof: Array = [Vector3(-0.02, hd, 1.0), Vector3(0.2 * wd, 0.65 * hd, 1.0), Vector3(0.55 * wd, 0.2 * hd, 0.7),
					Vector3(wd, -0.02, 0.3)]
			for q: Vector3 in prof:
				var o := p - nv * q.x
				row.append(Vector3(o.x, -depth + q.y, o.y))
				col.append(Color(1.0, q.z, 1.0))
			dr_rows.append(row)
			dr_cols.append(col)
		for i in pts.size():
			var j := (i + 1) % pts.size()
			lip_skip.append(1 if lip_f[i] < 0.01 and lip_f[j] < 0.01 else 0)
			dr_skip.append(1 if dr_f[i] < 0.01 and dr_f[j] < 0.01 else 0)
		lips.add_grid(lip_rows, lip_cols, true, lip_skip, [0])
		drifts.add_grid(dr_rows, dr_cols, true, dr_skip, [3])
	return [lips, drifts]


# ------------------------------------------------------------------ height-field patches
## A patch of snow over the rectangle `area` (x, z): `height.call(x, z)` gives [y, green] or
## null where there is no snow.
static func _patch(b: Builder, area: Rect2, cell: float, height: Callable) -> void:
	var nx := int(ceil(area.size.x / cell)) + 1
	var nz := int(ceil(area.size.y / cell)) + 1
	var rows: Array = []
	var cols: Array = []
	var has: Array = []
	for iz in nz:
		var row := PackedVector3Array()
		var col := PackedColorArray()
		var hrow := PackedByteArray()
		for ix in nx:
			var x := area.position.x + area.size.x * ix / (nx - 1)
			var z := area.position.y + area.size.y * iz / (nz - 1)
			var v: Variant = height.call(x, z)
			hrow.append(0 if v == null else 1)
			row.append(Vector3(x, -0.03 if v == null else float(v[0]), z))
			col.append(Color(1.0, 1.0 if v == null else float(v[1]), 1.0))
		rows.append(row)
		cols.append(col)
		has.append(hrow)
	# One strip at a time, so empty parts can be left out.
	for iz in nz - 1:
		var ix := 0
		while ix < nx - 1:
			if has[iz][ix] + has[iz][ix + 1] + has[iz + 1][ix] + has[iz + 1][ix + 1] == 0:
				ix += 1
				continue
			var end := ix
			while end < nx - 1 and has[iz][end] + has[iz][end + 1] + has[iz + 1][end] + has[iz + 1][end + 1] > 0:
				end += 1
			b.add_grid([rows[iz].slice(ix, end + 1), rows[iz + 1].slice(ix, end + 1)],
				[cols[iz].slice(ix, end + 1), cols[iz + 1].slice(ix, end + 1)], false)
			ix = end
	# (Each strip computes its own normals from two rows only; smooth them over the whole patch.)


## Normals of a height-field mesh from its own triangles, shared between touching strips.
static func _smooth(b: Builder, from_vertex: int) -> void:
	var acc := {}
	for i in range(0, b.indices.size(), 3):
		var a := b.indices[i]
		if a < from_vertex:
			continue
		var c := b.indices[i + 1]
		var d := b.indices[i + 2]
		var g := (b.verts[d] - b.verts[a]).cross(b.verts[c] - b.verts[a]) # area-weighted, front side
		for v: int in [a, c, d]:
			var key := b.verts[v].snapped(Vector3(0.001, 0.001, 0.001))
			acc[key] = acc.get(key, Vector3.ZERO) + g
	for v in range(from_vertex, b.verts.size()):
		var key := b.verts[v].snapped(Vector3(0.001, 0.001, 0.001))
		var n: Vector3 = acc.get(key, Vector3.UP)
		b.normals[v] = n.normalized() if n.length_squared() > 1e-14 else Vector3.UP


## The rounded earth heap beside a sandbag wall, in the firing position's own coordinates.
## `side`: -1 = west of the wall, +1 = east. It covers the old wedge (still the collision shape):
## full height against the end of the wall, sloping out and down, round to the front and back.
static func heap_mesh(side: float, wall_half_w: float, wall_top: float, zmid: float, mat: Material) -> ArrayMesh:
	var b := Builder.new()
	var n_a := _noise(7 if side < 0.0 else 8, 0.9)
	var n_b := _noise(9 if side < 0.0 else 10, 2.2)
	var x0 := wall_half_w - 0.45
	var x1 := wall_half_w + 2.15
	var area := Rect2(minf(side * x0, side * x1), zmid - 1.3, x1 - x0, 2.6)
	var height := func(x: float, z: float) -> Variant:
		var u := side * x - wall_half_w # metres out from the end of the wall
		var dz := absf(z - zmid)
		var across := 1.0 - smoothstep(0.38, 1.2, dz)
		var along := 1.0 - smoothstep(0.0, 1.95, u)
		if u < 0.0:
			along = 1.0 - smoothstep(0.15, 0.42, -u) # ends inside the sandbags
		var lumps := 1.0 + 0.09 * n_a.get_noise_2d(x, z) + 0.035 * n_b.get_noise_2d(x, z)
		var h := (wall_top + 0.03) * across * along * lumps
		# A little dark earth shows through on the steep upper part.
		var earth := smoothstep(0.1, 0.5, n_a.get_noise_2d(x + 40.0, z * 1.7)) * smoothstep(0.25, 0.6, h) * 0.55
		return [h - 0.025, 1.0 - earth]
	_patch(b, area, 0.2, height)
	_smooth(b, 0)
	return b.mesh(mat)


## Distance from (x, z) to a rectangle centred on the origin with rounded corners
## (negative inside).
static func _round_rect(x: float, z: float, hx: float, hz: float, radius: float) -> float:
	var qx := absf(x) - hx + radius
	var qz := absf(z) - hz + radius
	return Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length() + minf(maxf(qx, qz), 0.0) - radius


## Grid lines from -half to +half: close together at the rounded rim, wide in the middle.
static func _rim_coords(half: float) -> PackedFloat32Array:
	var side: Array[float] = [0.0, 0.05, 0.12, 0.22, 0.4]
	var out := PackedFloat32Array()
	for s in side:
		out.append(-half + s)
	var inner := half - 0.4
	var n := int(ceil(inner * 2.0 / 0.32))
	for i in range(1, n):
		out.append(-inner + 2.0 * inner * i / n)
	for i in range(side.size() - 1, -1, -1):
		out.append(half - side[i])
	return out


## The snow on and around the bunker, in the bunker's own coordinates (front = -z).
## Roof box: 6.8 x 6.3 m, top at 1.5 m, with the old flat snow slab (to 1.745 m) hidden inside.
static func bunker_mesh(mat: Material) -> ArrayMesh:
	var b := Builder.new()
	var n_a := _noise(21, 0.5)
	var n_b := _noise(22, 1.6)
	# --- the cap: a rounded pillow, a little longer at the front so it lies on the front logs ---
	var hx := 3.47
	var z_front := -3.42
	var z_back := 3.22
	var hz := (z_back - z_front) / 2.0
	var zc := (z_back + z_front) / 2.0
	var gx := _rim_coords(hx)
	var gz := _rim_coords(hz)
	var nx := gx.size()
	var nz := gz.size()
	var rows: Array = []
	var cols: Array = []
	for iz in nz:
		var row := PackedVector3Array()
		var col := PackedColorArray()
		for ix in nx:
			var x := gx[ix]
			var z := gz[iz]
			# Pull the corners of the grid in onto the rounded outline.
			for pass_i in 3:
				var d := _round_rect(x, z, hx, hz, 0.2)
				if d <= 0.0:
					break
				var e := 0.01
				var grad := Vector2(_round_rect(x + e, z, hx, hz, 0.2) - d, _round_rect(x, z + e, hx, hz, 0.2) - d) / e
				x -= grad.x * d
				z -= grad.y * d
			var inside := maxf(-_round_rect(x, z, hx, hz, 0.2), 0.0)
			var t := clampf(inside / 0.22, 0.0, 1.0)
			var deep := smoothstep(0.0, 1.2, inside)
			var y := 1.47 + 0.02 * n_b.get_noise_2d(x, z + zc) * (1.0 - t)
			y += 0.35 * sqrt(1.0 - (1.0 - t) * (1.0 - t))
			y += 0.09 * deep * (1.0 - pow(x / hx, 2.0)) * (1.0 - pow(z / hz, 2.0))
			y += 0.035 * deep * n_a.get_noise_2d(x, z + zc)
			row.append(Vector3(x, y, z + zc))
			col.append(Color.WHITE)
		rows.append(row)
		cols.append(col)
	b.add_grid(rows, cols, false)
	_smooth(b, 0)
	# The underside of the rim: a narrow strip from the edge back in to the roof.
	var ring: Array[Vector3] = []
	for ix in nx:
		ring.append(rows[0][ix])
	for iz in range(1, nz):
		ring.append(rows[iz][nx - 1])
	for ix in range(nx - 2, -1, -1):
		ring.append(rows[nz - 1][ix])
	for iz in range(nz - 2, 0, -1):
		ring.append(rows[iz][0])
	var under_rows: Array = []
	var under_cols: Array = []
	for p in ring:
		var inward := Vector3(-p.x, 0.0, -(p.z - zc)).normalized() * 0.12
		under_rows.append(PackedVector3Array([p, Vector3(p.x + inward.x, p.y - 0.05, p.z + inward.z)]))
		under_cols.append(PackedColorArray([Color.WHITE, Color.WHITE]))
	b.add_grid(under_rows, under_cols, true, PackedByteArray(), [], Vector3.DOWN)

	# --- low banks of snow against the side walls (walls: 6 x 5.5 m), wrapping round the front
	# corners. The middle of the front (the Maxim's field of fire) and the back stay clear. ---
	var start := b.verts.size()
	var bank := func(x: float, z: float) -> Variant:
		var d := _round_rect(x, z, 3.0, 2.75, 0.0)
		if d < -0.12:
			return null # inside the walls
		var u := maxf(d, 0.0)
		var mask := 1.0 - smoothstep(1.9, 2.6, z) # nothing behind the bunker
		var front := smoothstep(-2.6, -2.95, z)
		mask *= lerpf(1.0, smoothstep(1.5, 2.3, absf(x)), front)
		var top := lerpf(0.42, 0.72, _n01(n_a, x * 1.3, z * 1.3))
		var reach := lerpf(1.1, 1.6, _n01(n_a, x + 90.0, z))
		var s := clampf(1.0 - u / reach, 0.0, 1.0)
		var h := top * s * s * mask + 0.02 * n_b.get_noise_2d(x, z) * s
		if h < 0.004:
			return null
		return [h - 0.02, 1.0]
	_patch(b, Rect2(-4.8, -4.5, 9.6, 7.3), 0.2, bank)
	_smooth(b, start)
	return b.mesh(mat)


## Snow over the flat landing at the top of an exit ramp, sloping out into the ground around
## it. `ground.call(x, z)` = height of the ground / the earth slab.
static func build_aprons(ramps: Array, depth: float, ground: Callable, mat: Material) -> Builder:
	var b := Builder.new()
	var n_a := _noise(31, 0.8)
	for r: Dictionary in ramps:
		var rise: float = depth + 0.05
		var path := Rect2(r.x - 0.8, r.z1 - 0.3, 1.6, r.land_end - (r.z1 - 0.3))
		var start := b.verts.size()
		var height := func(x: float, z: float) -> Variant:
			# The walked surface: the ramp, then the landing 5 cm above the ground.
			var walked := minf(-depth + rise * (z - r.z0) / (r.z1 - r.z0), 0.05)
			var d := _outside(path, Vector2(x, z))
			var t := smoothstep(0.0, 1.0, d / 1.0)
			var g: float = ground.call(x, z)
			var y := lerpf(walked + 0.02 + 0.012 * n_a.get_noise_2d(x, z), g - 0.03, t)
			if z < path.position.y + 0.01:
				y = minf(y, walked - 0.02) # tucked under at the ramp end
			if d >= 1.0:
				return null
			return [y, lerpf(0.9, 1.0, smoothstep(0.0, 0.5, d))]
		_patch(b, path.grow_individual(1.1, 0.0, 1.1, 1.1), 0.2, height)
		_smooth(b, start)
	return b
