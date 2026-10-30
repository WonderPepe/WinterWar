class_name SoldierMesh
extends RefCounted
## Builds the low-poly Soviet soldier (greatcoat, budenovka, boots, Mosin with bayonet) in code.
##
## Everything is ONE mesh with a skeleton ("skinning"): each vertex belongs to a bone
## (hips, spine, head, arms, legs, rifle). Moving the bones moves the body parts, and the
## whole soldier is still a single draw call – important with 16 soldiers in a browser.
## The mesh is built once and shared by all soldiers.
##
## Vertex colour: RGB = colour of the part, A = cloth type for the shader
## (1 = greatcoat: gets the per-soldier tint and cloth grain, 0.5 = other cloth, 0 = skin/metal/wood).
## UV = the vertex position (x+z, y) at rest, so the cloth grain doesn't slide when he moves.

enum Bone { HIPS, SPINE, HEAD, UPPER_ARM_L, FOREARM_L, UPPER_ARM_R, FOREARM_R, THIGH_L, SHIN_L, THIGH_R, SHIN_R, RIFLE }

const BONE_NAMES: Array[String] = ["Hips", "Spine", "Head", "UpperArmL", "ForearmL", "UpperArmR", "ForearmR",
		"ThighL", "ShinL", "ThighR", "ShinR", "Rifle"]
const BONE_PARENTS: Array[int] = [-1, 0, 1, 1, 3, 1, 5, 0, 7, 0, 9, 1]
## Bone positions relative to their parent bone, standing straight ("rest pose").
const BONE_REST: Array[Vector3] = [
	Vector3(0, 0.95, 0), Vector3(0, 0.05, 0), Vector3(0, 0.48, 0),
	Vector3(-0.21, 0.42, 0), Vector3(0, -0.29, 0), Vector3(0.21, 0.42, 0), Vector3(0, -0.29, 0),
	Vector3(-0.1, -0.03, 0), Vector3(0, -0.43, 0), Vector3(0.1, -0.03, 0), Vector3(0, -0.43, 0),
	Vector3(0.1, 0.15, -0.28),
]
const ARM_UPPER: float = 0.29
const ARM_LOWER: float = 0.31 # forearm + hand
const MUZZLE: Vector3 = Vector3(0, 0.02, -0.78) ## In rifle-bone space.

const COAT := Color(0.43, 0.4, 0.32, 1.0)
const COAT_DARK := Color(0.34, 0.32, 0.25, 1.0)
const TROUSERS := Color(0.3, 0.3, 0.24, 0.5)
const HAT := Color(0.35, 0.34, 0.28, 0.5)
const STAR := Color(0.7, 0.1, 0.08, 0.0)
const BELT := Color(0.22, 0.15, 0.09, 0.0)
const SKIN := Color(0.8, 0.62, 0.52, 0.0)
const BOOT := Color(0.1, 0.09, 0.08, 0.0)
const WOOD := Color(0.36, 0.22, 0.12, 0.0)
const METAL := Color(0.12, 0.12, 0.13, 0.0)
const SNOW := Color(0.9, 0.93, 0.98, 0.0)

static var _cached: ArrayMesh


## Global (skeleton-space) rest position of a bone.
static func rest_global(bone: int) -> Vector3:
	var p := Vector3.ZERO
	var b: int = bone
	while b >= 0:
		p += BONE_REST[b]
		b = BONE_PARENTS[b]
	return p


## Adds the bones to an empty Skeleton3D.
static func setup_skeleton(skeleton: Skeleton3D) -> void:
	skeleton.clear_bones()
	for i in BONE_NAMES.size():
		skeleton.add_bone(BONE_NAMES[i])
	for i in BONE_NAMES.size():
		skeleton.set_bone_parent(i, BONE_PARENTS[i])
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, BONE_REST[i]))
	skeleton.reset_bone_poses()


static func get_mesh() -> ArrayMesh:
	if _cached == null:
		_cached = _build()
	return _cached


# ------------------------------------------------------------------ building
static var _st: SurfaceTool
static var _bone_fn: Callable # Vector3 -> [PackedInt32Array, PackedFloat32Array]


static func _build() -> ArrayMesh:
	_st = SurfaceTool.new()
	_st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# --- Spine: chest, belt, pouches, collar, snow on the shoulders ---
	_use_bone(Bone.SPINE)
	_frustum(Vector3(0, 1.0, 0), Vector3(0, 1.4, 0), 0.175, 0.2, 8, COAT, 0.72)
	_frustum(Vector3(0, 1.4, 0), Vector3(0, 1.46, 0), 0.2, 0.09, 8, COAT, 0.72)
	_frustum(Vector3(0, 0.975, 0), Vector3(0, 1.04, 0), 0.186, 0.186, 8, BELT, 0.74)
	_frustum(Vector3(0, 1.43, 0), Vector3(0, 1.5, 0), 0.075, 0.07, 6, COAT_DARK)
	_box(Vector3(-0.1, 1.02, -0.13), Vector3(0.08, 0.07, 0.05), BELT)
	_box(Vector3(0.1, 1.02, -0.13), Vector3(0.08, 0.07, 0.05), BELT)
	_box(Vector3(-0.13, 1.445, 0.0), Vector3(0.11, 0.02, 0.13), SNOW)
	_box(Vector3(0.13, 1.445, 0.0), Vector3(0.11, 0.02, 0.13), SNOW)
	# Rolled blanket over the left shoulder (Soviet "skatka").
	_frustum(Vector3(-0.17, 1.47, -0.1), Vector3(0.12, 1.08, -0.14), 0.045, 0.045, 6, COAT_DARK)
	_frustum(Vector3(-0.17, 1.47, 0.1), Vector3(0.12, 1.08, 0.14), 0.045, 0.045, 6, COAT_DARK)

	# --- Greatcoat skirt: moves with the hips, the lower part follows the legs a little ---
	_bone_fn = func(p: Vector3) -> Array:
		var leg: float = clampf((0.98 - p.y) / 0.62, 0.0, 1.0) * 0.6
		var side: float = clampf(0.5 + p.x / 0.25, 0.0, 1.0) # 0 = left, 1 = right
		return [PackedInt32Array([Bone.HIPS, Bone.THIGH_L, Bone.THIGH_R, 0]),
			PackedFloat32Array([1.0 - leg, leg * (1.0 - side), leg * side, 0.0])]
	_frustum(Vector3(0, 0.98, 0), Vector3(0, 0.36, 0), 0.18, 0.29, 10, COAT, 0.8)
	_bone_fn = Callable()

	# --- Head: neck, face, budenovka (pointed cloth helmet) with star, peak and neck flap ---
	_use_bone(Bone.HEAD)
	_frustum(Vector3(0, 1.46, 0), Vector3(0, 1.55, 0), 0.05, 0.05, 6, SKIN)
	_sphere(Vector3(0, 1.62, -0.01), Vector3(0.1, 0.11, 0.105), 8, 5, SKIN)
	_frustum(Vector3(0, 1.66, 0), Vector3(0, 1.86, 0.01), 0.118, 0.014, 8, HAT)
	_frustum(Vector3(0, 1.645, 0), Vector3(0, 1.665, 0), 0.115, 0.118, 8, HAT)
	_box(Vector3(0, 1.66, -0.115), Vector3(0.15, 0.014, 0.07), HAT)
	_box(Vector3(0, 1.595, 0.095), Vector3(0.2, 0.12, 0.02), HAT)
	_box(Vector3(0, 1.735, -0.105), Vector3(0.035, 0.035, 0.012), STAR)
	_frustum(Vector3(0, 1.82, 0.006), Vector3(0, 1.865, 0.01), 0.03, 0.012, 6, SNOW)

	# --- Arms: sleeve (upper), sleeve + cuff + hand (lower) ---
	for side in [-1.0, 1.0]:
		var upper: int = Bone.UPPER_ARM_L if side < 0 else Bone.UPPER_ARM_R
		var fore: int = Bone.FOREARM_L if side < 0 else Bone.FOREARM_R
		var shoulder := rest_global(upper)
		_use_bone(upper)
		_frustum(shoulder + Vector3(0, 0.02, 0), shoulder - Vector3(0, ARM_UPPER, 0), 0.062, 0.052, 6, COAT)
		var elbow := rest_global(fore)
		_use_bone(fore)
		_frustum(elbow + Vector3(0, 0.02, 0), elbow - Vector3(0, 0.25, 0), 0.052, 0.047, 6, COAT)
		_frustum(elbow - Vector3(0, 0.2, 0), elbow - Vector3(0, 0.26, 0), 0.05, 0.05, 6, COAT_DARK)
		_sphere(elbow - Vector3(0, 0.3, 0), Vector3(0.038, 0.045, 0.038), 6, 4, SKIN)

	# --- Legs: trousers, knee-high boots, feet ---
	for side in [-1.0, 1.0]:
		var thigh: int = Bone.THIGH_L if side < 0 else Bone.THIGH_R
		var shin: int = Bone.SHIN_L if side < 0 else Bone.SHIN_R
		var hip := rest_global(thigh)
		var knee := rest_global(shin)
		_use_bone(thigh)
		_frustum(hip + Vector3(0, 0.03, 0), knee, 0.078, 0.062, 6, TROUSERS)
		_use_bone(shin)
		_frustum(knee + Vector3(0, 0.02, 0), Vector3(knee.x, 0.06, 0), 0.063, 0.052, 6, BOOT)
		_box(Vector3(knee.x, 0.04, -0.05), Vector3(0.09, 0.08, 0.25), BOOT)

	# --- Mosin rifle with the long spike bayonet ---
	_use_bone(Bone.RIFLE)
	var r := rest_global(Bone.RIFLE)
	_box(r + Vector3(0, -0.03, 0.25), Vector3(0.045, 0.1, 0.34), WOOD)
	_box(r + Vector3(0, 0.0, -0.2), Vector3(0.04, 0.045, 0.62), WOOD)
	_frustum(r + Vector3(0, 0.02, 0.06), r + Vector3(0, 0.02, -0.78), 0.012, 0.011, 5, METAL)
	_box(r + Vector3(0, 0.025, 0.06), Vector3(0.03, 0.035, 0.12), METAL) # receiver
	_box(r + Vector3(0.04, 0.02, 0.1), Vector3(0.05, 0.012, 0.012), METAL) # bolt handle
	_frustum(r + Vector3(0.012, 0.0, -0.74), r + Vector3(0.012, 0.0, -1.2), 0.007, 0.002, 4, METAL)

	var mesh := _st.commit()
	_st = null
	return mesh


# ------------------------------------------------------------------ shared building blocks
## Other code-built skinned meshes (FirstPersonArms) use the same helpers:
## begin_build(), use_bone(), frustum()/box()/sphere(), then finish_build().
static func begin_build() -> void:
	_st = SurfaceTool.new()
	_st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS) # must come before begin()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bone_fn = Callable()


static func finish_build() -> ArrayMesh:
	var mesh := _st.commit()
	_st = null
	return mesh


static func use_bone(bone: int) -> void:
	_use_bone(bone)


static func frustum(a: Vector3, b: Vector3, ra: float, rb: float, sides: int, col: Color, depth: float = 1.0) -> void:
	_frustum(a, b, ra, rb, sides, col, depth)


static func box(center: Vector3, size: Vector3, col: Color) -> void:
	_box(center, size, col)


static func sphere(center: Vector3, radius: Vector3, segments: int, rings: int, col: Color) -> void:
	_sphere(center, radius, segments, rings, col)


static var _bones := PackedInt32Array([0, 0, 0, 0])
static var _weights := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])


static func _use_bone(bone: int) -> void:
	_bones = PackedInt32Array([bone, 0, 0, 0])
	_weights = PackedFloat32Array([1.0, 0.0, 0.0, 0.0])


static func _vertex(p: Vector3, n: Vector3, c: Color) -> void:
	_st.set_color(c)
	_st.set_normal(n)
	_st.set_uv(Vector2(p.x + p.z, p.y))
	if _bone_fn.is_valid():
		var bw: Array = _bone_fn.call(p)
		_st.set_bones(bw[0])
		_st.set_weights(bw[1])
	else:
		_st.set_bones(_bones)
		_st.set_weights(_weights)
	_st.add_vertex(p)


## One triangle; the corner order is fixed so it faces `outward` (Godot: clockwise = front).
static func _tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		_vertex(a, na, col)
		_vertex(c, nc, col)
		_vertex(b, nb, col)
	else:
		_vertex(a, na, col)
		_vertex(b, nb, col)
		_vertex(c, nc, col)


## A tapered tube from a (radius ra) to b (radius rb). `depth` squashes it front-to-back.
static func _frustum(a: Vector3, b: Vector3, ra: float, rb: float, sides: int, col: Color, depth: float = 1.0) -> void:
	var axis: Vector3 = (b - a).normalized()
	var u: Vector3 = Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	u = (u - axis * axis.dot(u)).normalized()
	var v: Vector3 = axis.cross(u).normalized()
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for i in sides + 1:
		var ang: float = TAU * i / sides
		var dir: Vector3 = u * cos(ang) + v * sin(ang) * depth
		ring_a.append(a + dir * ra)
		ring_b.append(b + dir * rb)
		normals.append((u * cos(ang) + v * sin(ang) / maxf(depth, 0.01)).normalized())
	for i in sides:
		_tri(ring_a[i], ring_b[i], ring_b[i + 1], normals[i], normals[i], normals[i + 1], col)
		_tri(ring_a[i], ring_b[i + 1], ring_a[i + 1], normals[i], normals[i + 1], normals[i + 1], col)
	# Close the narrow end so you can't look into the tube.
	var tip: Vector3 = b if rb <= ra else a
	var ring: Array[Vector3] = ring_b if rb <= ra else ring_a
	var cap_n: Vector3 = axis if rb <= ra else -axis
	for i in sides:
		_tri(tip, ring[i], ring[i + 1], cap_n, cap_n, cap_n, col)


static func _box(center: Vector3, size: Vector3, col: Color) -> void:
	var h: Vector3 = size / 2.0
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var t := Vector3.ZERO
			t[(axis + 1) % 3] = 1.0
			var bt := Vector3.ZERO
			bt[(axis + 2) % 3] = 1.0
			var c: Vector3 = center + n * h[axis]
			var tu: Vector3 = t * h[(axis + 1) % 3]
			var tv: Vector3 = bt * h[(axis + 2) % 3]
			_tri(c - tu - tv, c + tu - tv, c + tu + tv, n, n, n, col)
			_tri(c - tu - tv, c + tu + tv, c - tu + tv, n, n, n, col)


static func _sphere(center: Vector3, radius: Vector3, segments: int, rings: int, col: Color) -> void:
	var pts: Array = []
	for r in rings + 1:
		var lat: float = PI * r / rings - PI / 2.0
		var row: Array[Vector3] = []
		for s in segments + 1:
			var lon: float = TAU * s / segments
			row.append(Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)))
		pts.append(row)
	for r in rings:
		for s in segments:
			var d00: Vector3 = pts[r][s]
			var d01: Vector3 = pts[r][s + 1]
			var d10: Vector3 = pts[r + 1][s]
			var d11: Vector3 = pts[r + 1][s + 1]
			_tri(center + d00 * radius, center + d10 * radius, center + d11 * radius, d00, d10, d11, col)
			_tri(center + d00 * radius, center + d11 * radius, center + d01 * radius, d00, d11, d01, col)
