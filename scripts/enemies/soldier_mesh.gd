class_name SoldierMesh
extends RefCounted
## Builds the low-poly Soviet soldier (greatcoat, budenovka, boots, Mosin with bayonet) in code.
## G2 variants (EnemyData.Kind): the officer (peaked cap, belts, map case, TT pistol) and the
## machine-gunner (DP-27 with its flat pan magazine and bipod) – same skeleton, own mesh each.
##
## Everything is ONE mesh with a skeleton ("skinning"): each vertex belongs to a bone
## (hips, spine, head, arms, legs, rifle). Moving the bones moves the body parts, and the
## whole soldier is still a single draw call – important with 16 soldiers in a browser.
## The mesh is built once and shared by all soldiers.
##
## Vertex colour: RGB = colour of the part, A = cloth type for the shader
## (1 = greatcoat: gets the per-soldier tint and cloth grain, 0.5 = other cloth, 0 = skin/metal/wood).
## UV = the vertex position (x+z, y) at rest, so the cloth grain doesn't slide when he moves.

## SV1: the hands and feet got their own bones – added at the END so no old number changes.
enum Bone { HIPS, SPINE, HEAD, UPPER_ARM_L, FOREARM_L, UPPER_ARM_R, FOREARM_R, THIGH_L, SHIN_L, THIGH_R, SHIN_R, RIFLE,
		HAND_L, HAND_R, FOOT_L, FOOT_R }

const BONE_NAMES: Array[String] = ["Hips", "Spine", "Head", "UpperArmL", "ForearmL", "UpperArmR", "ForearmR",
		"ThighL", "ShinL", "ThighR", "ShinR", "Rifle", "HandL", "HandR", "FootL", "FootR"]
const BONE_PARENTS: Array[int] = [-1, 0, 1, 1, 3, 1, 5, 0, 7, 0, 9, 1, 4, 6, 8, 10]
## Bone positions relative to their parent bone, standing straight ("rest pose").
const BONE_REST: Array[Vector3] = [
	Vector3(0, 0.95, 0), Vector3(0, 0.05, 0), Vector3(0, 0.48, 0),
	Vector3(-0.21, 0.42, 0), Vector3(0, -0.29, 0), Vector3(0.21, 0.42, 0), Vector3(0, -0.29, 0),
	Vector3(-0.1, -0.03, 0), Vector3(0, -0.43, 0), Vector3(0.1, -0.03, 0), Vector3(0, -0.43, 0),
	Vector3(0.1, 0.15, -0.28),
	Vector3(0, -0.25, 0), Vector3(0, -0.25, 0), # wrists (SV1)
	Vector3(0, -0.39, 0), Vector3(0, -0.39, 0), # ankles, 0.1 m above the ground (SV1)
]
## SV1: how far a foot may bend at the ankle (radians): toes up / toes down.
const ANKLE_UP: float = 0.6
const ANKLE_DOWN: float = -0.9
const ARM_UPPER: float = 0.29
const ARM_LOWER: float = 0.31 # forearm + hand
const MUZZLE: Vector3 = Vector3(0, 0.02, -0.78) ## In rifle-bone space.
const MUZZLE_PISTOL: Vector3 = Vector3(0, 0.012, -0.12)
const MUZZLE_DP27: Vector3 = Vector3(0, 0.012, -0.82)

const COAT := Color(0.43, 0.4, 0.32, 1.0)
const COAT_DARK := Color(0.34, 0.32, 0.25, 1.0)
const TROUSERS := Color(0.3, 0.3, 0.24, 0.5)
const HAT := Color(0.35, 0.34, 0.28, 0.5)
const STAR := Color(0.7, 0.1, 0.08, 0.0)
const BELT := Color(0.22, 0.15, 0.09, 0.0)
const SKIN := Color(0.8, 0.62, 0.52, 0.0)
## SV1: the face. Alpha 0.15 tells soldier.gdshader to paint the face texture on it.
const FACE := Color(0.8, 0.62, 0.52, 0.15)
const BOOT := Color(0.1, 0.09, 0.08, 0.0)
const WOOD := Color(0.36, 0.22, 0.12, 0.0)
const METAL := Color(0.12, 0.12, 0.13, 0.0)
const SNOW := Color(0.9, 0.93, 0.98, 0.0)
const CAP := Color(0.36, 0.36, 0.27, 0.5)
const CAP_BAND := Color(0.5, 0.1, 0.13, 0.0)
const LEATHER := Color(0.3, 0.19, 0.11, 0.0)

static var _cached: Dictionary = {} # EnemyData.Kind -> ArrayMesh


## Where the shots come from, in rifle-bone space, for each kind of soldier.
static func muzzle_for(kind: int) -> Vector3:
	match kind:
		EnemyData.Kind.OFFICER:
			return MUZZLE_PISTOL
		EnemyData.Kind.MG_GUNNER:
			return MUZZLE_DP27
	return MUZZLE


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


static func get_mesh(kind: int = 0) -> ArrayMesh:
	if not _cached.has(kind):
		_cached[kind] = _build(kind)
	return _cached[kind]


# ------------------------------------------------------------------ building
static var _st: SurfaceTool
static var _bone_fn: Callable # Vector3 -> [PackedInt32Array, PackedFloat32Array]
static var _color_fn: Callable # NET2b: (Vector3, Color) -> Color, see use_color_fn()


static func _build(kind: int = 0) -> ArrayMesh:
	var officer: bool = kind == EnemyData.Kind.OFFICER
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
	if officer:
		# Shoulder strap across the chest, and the map case on the left hip.
		_box(Vector3(0.0, 1.24, -0.155), Vector3(0.035, 0.46, 0.012), LEATHER, Vector3(0, 0, -0.62))
		_box(Vector3(0.0, 1.24, 0.155), Vector3(0.035, 0.46, 0.012), LEATHER, Vector3(0, 0, 0.62))
		_box(Vector3(0.12, 1.02, -0.13), Vector3(0.07, 0.08, 0.05), LEATHER) # pistol holster
	else:
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
	if officer:
		_use_bone(Bone.HIPS)
		_box(Vector3(-0.2, 0.8, -0.02), Vector3(0.04, 0.2, 0.23), LEATHER) # map case

	# --- Head: neck, face, budenovka (pointed cloth helmet) with star, peak and neck flap ---
	# SV1: the neck bends smoothly – its bottom stays with the chest, its top turns with the head.
	_bone_fn = func(p: Vector3) -> Array:
		var k: float = clampf((p.y - 1.47) / 0.07, 0.0, 1.0)
		return [PackedInt32Array([Bone.SPINE, Bone.HEAD, 0, 0]), PackedFloat32Array([1.0 - k, k, 0.0, 0.0])]
	_frustum(Vector3(0, 1.44, 0.005), Vector3(0, 1.505, 0.003), 0.05, 0.048, 6, SKIN)
	_frustum(Vector3(0, 1.505, 0.003), Vector3(0, 1.56, 0.0), 0.048, 0.046, 6, SKIN)
	_bone_fn = Callable()
	_use_bone(Bone.HEAD)
	_build_head()
	if officer:
		# Peaked cap: band, wide flat crown, black peak, star – easy to pick out.
		_frustum(Vector3(0, 1.655, 0), Vector3(0, 1.705, 0), 0.108, 0.11, 10, CAP_BAND)
		_frustum(Vector3(0, 1.705, 0.005), Vector3(0, 1.765, 0.0), 0.11, 0.142, 10, CAP)
		_frustum(Vector3(0, 1.765, 0.0), Vector3(0, 1.775, 0.0), 0.142, 0.13, 10, CAP)
		_box(Vector3(0, 1.665, -0.13), Vector3(0.16, 0.012, 0.07), BOOT, Vector3(0.25, 0, 0))
		_box(Vector3(0, 1.685, -0.111), Vector3(0.03, 0.03, 0.01), STAR)
		_box(Vector3(0, 1.778, 0.01), Vector3(0.16, 0.012, 0.14), SNOW)
	else:
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
		_use_bone(Bone.HAND_L if side < 0 else Bone.HAND_R)
		_build_fist(elbow - Vector3(0, 0.25, 0), side)

	# --- Legs: trousers, knee-high boots, feet ---
	for side in [-1.0, 1.0]:
		var thigh: int = Bone.THIGH_L if side < 0 else Bone.THIGH_R
		var shin: int = Bone.SHIN_L if side < 0 else Bone.SHIN_R
		var hip := rest_global(thigh)
		var knee := rest_global(shin)
		_use_bone(thigh)
		_frustum(hip + Vector3(0, 0.03, 0), knee, 0.078, 0.062, 6, TROUSERS)
		_use_bone(shin)
		_frustum(knee + Vector3(0, 0.02, 0), Vector3(knee.x, 0.17, 0), 0.063, 0.055, 6, BOOT)
		_build_boot_foot(knee.x, shin, Bone.FOOT_L if side < 0 else Bone.FOOT_R, BOOT)

	_use_bone(Bone.RIFLE)
	var r := rest_global(Bone.RIFLE)
	if officer:
		# --- TT pistol (the rifle bone is "the weapon" bone) ---
		_box(r + Vector3(0, -0.035, 0.035), Vector3(0.028, 0.085, 0.034), METAL, Vector3(-0.25, 0, 0))
		_box(r + Vector3(0, 0.012, -0.035), Vector3(0.026, 0.032, 0.17), METAL)
	elif kind == EnemyData.Kind.MG_GUNNER:
		_build_dp27(r)
	else:
		_build_mosin(r)

	var mesh := _st.commit()
	_st = null
	return mesh


## SV1: the head – a skull with a jaw and chin, cheekbones, a brow, eye sockets, a nose and ears.
## Built like a sphere whose radius is pushed in and out in places. The front faces −Z.
## Its skin uses FACE (soldier.gdshader paints the eyes, brows and mouth from the face texture).
static func _build_head() -> void:
	var c := HEAD_CENTER
	var segs: int = 12
	var rings: int = 8
	var grid: Array = [] # rows of points, bottom → top
	for r in rings + 1:
		var lat: float = PI * r / rings - PI / 2.0
		var row: Array[Vector3] = []
		for s in segs + 1:
			row.append(c + _head_offset(lat, TAU * s / segs))
		grid.append(row)
	for r in rings:
		for s in segs:
			var q: Array[Vector3] = [grid[r][s], grid[r + 1][s], grid[r + 1][s + 1], grid[r][s + 1]]
			var n: Array[Vector3] = [_head_normal(grid, r, s), _head_normal(grid, r + 1, s),
					_head_normal(grid, r + 1, s + 1), _head_normal(grid, r, s + 1)]
			_tri(q[0], q[1], q[2], n[0], n[1], n[2], FACE)
			_tri(q[0], q[2], q[3], n[0], n[2], n[3], FACE)
	# Nose: a little wedge from between the eyes down to the tip.
	var z0: float = c.z - HEAD_RADIUS.z
	var top := Vector3(0, 1.627, z0 + 0.006)
	var tip := Vector3(0, 1.584, z0 - 0.017)
	var left := Vector3(-0.017, 1.577, z0 + 0.002)
	var right := Vector3(0.017, 1.577, z0 + 0.002)
	var under := Vector3(0, 1.575, z0 - 0.007)
	for f in [[top, left, tip], [top, tip, right], [left, under, tip], [tip, under, right]]:
		var fn: Vector3 = ((f[1] - f[0]).cross(f[2] - f[0])).normalized()
		if fn.z > 0.0 or (fn.z == 0.0 and fn.y > 0.0):
			fn = -fn
		_tri(f[0], f[1], f[2], fn, fn, fn, FACE)
	# Ears.
	for side in [-1.0, 1.0]:
		_sphere(Vector3(side * (HEAD_RADIUS.x - 0.002), 1.603, c.z + 0.012), Vector3(0.012, 0.027, 0.019), 4, 2, SKIN)


const HEAD_CENTER := Vector3(0, 1.6, -0.005)
const HEAD_RADIUS := Vector3(0.091, 0.106, 0.1)


## Where a point of the head is, from the centre: `lat` −PI/2 (chin) … PI/2 (crown), `a` 0 = front.
static func _head_offset(lat: float, a: float) -> Vector3:
	var h: float = sin(lat)
	var d := Vector3(cos(lat) * sin(a), h, -cos(lat) * cos(a))
	var front: float = maxf(cos(a), 0.0)
	var below: float = smoothstep(0.0, 0.9, -h)
	# Jaw: narrower towards the chin, the back of the jaw narrower still.
	var wx: float = 1.0 - 0.3 * below
	var wz: float = 1.0 - (0.2 * below if cos(a) < 0.0 else 0.0)
	var p := Vector3(d.x * HEAD_RADIUS.x * wx, d.y * HEAD_RADIUS.y, d.z * HEAD_RADIUS.z * wz)
	var out: float = 0.0 # pushed out (+) or in (−) along the surface
	out += 0.008 * pow(front, 4.0) * _bell(h, 0.27, 0.09) # brow
	out -= 0.011 * front * _bell(h, 0.13, 0.08) * _bell(absf(sin(a)), 0.37, 0.13) # eye sockets
	out += 0.006 * _bell(h, -0.08, 0.13) * _bell(absf(sin(a)), 0.62, 0.17) # cheekbones
	out += 0.01 * pow(front, 3.0) * _bell(h, -0.78, 0.17) # chin
	return p + d.normalized() * out


## SV1: where a point of the face is on the face texture (front view: 0.2 m wide, from the hat
## brim at 1.66 m down to 1.49 m). The back of the head gets a corner of the texture, which is
## left empty there (so nothing is painted on it).
static func face_uv(p: Vector3) -> Vector2:
	if p.z > 0.0:
		return Vector2(-1.0, -1.0)
	return Vector2(0.5 + p.x / FACE_UV_WIDTH, (FACE_UV_TOP - p.y) / FACE_UV_HEIGHT)


const FACE_UV_WIDTH: float = 0.2
const FACE_UV_TOP: float = 1.66
const FACE_UV_HEIGHT: float = 0.17


static func _bell(x: float, mid: float, width: float) -> float:
	return exp(-pow((x - mid) / width, 2.0))


## Smooth normal of head grid point (r, s) from its neighbours (the seam wraps round).
static func _head_normal(grid: Array, r: int, s: int) -> Vector3:
	var row: Array = grid[r]
	var n_s: int = row.size() - 1
	var sl: int = (s - 1 + n_s) % n_s
	var sr: int = (s + 1) % n_s
	var up: int = mini(r + 1, grid.size() - 1)
	var dn: int = maxi(r - 1, 0)
	var across: Vector3 = (grid[r][sr] as Vector3) - (grid[r][sl] as Vector3)
	var along: Vector3 = (grid[up][s % n_s] as Vector3) - (grid[dn][s % n_s] as Vector3)
	var n: Vector3 = across.cross(along)
	var outward: Vector3 = (row[s] as Vector3) - HEAD_CENTER
	if n.length() < 0.000001:
		return outward.normalized()
	n = n.normalized()
	return n if n.dot(outward) > 0.0 else -n


## SV1: a fist hanging from the wrist (rest pose: arm straight down). The palm faces the body,
## the thumb is in front (−Z) – so when the arm reaches forward, the thumb is on top of the grip.
static func _build_fist(wrist: Vector3, side: float, col: Color = SKIN) -> void:
	_sphere(wrist - Vector3(0, 0.048, 0.0), Vector3(0.026, 0.045, 0.043), 5, 3, col) # back of the hand
	_frustum(wrist + Vector3(-side * 0.012, -0.085, 0.034), wrist + Vector3(-side * 0.012, -0.085, -0.036),
			0.019, 0.019, 5, col) # curled fingers
	_sphere(wrist + Vector3(-side * 0.014, -0.035, -0.04), Vector3(0.013, 0.025, 0.013), 4, 2, col) # thumb


## SV1: the lower boot (the top half blends from the shin to the ankle) and the foot, which
## bends at the ankle.
static func _build_boot_foot(x: float, shin: int, foot: int, col: Color) -> void:
	_bone_fn = func(p: Vector3) -> Array:
		var k: float = clampf((0.17 - p.y) / 0.08, 0.0, 1.0)
		return [PackedInt32Array([shin, foot, 0, 0]), PackedFloat32Array([1.0 - k, k, 0.0, 0.0])]
	_frustum(Vector3(x, 0.175, 0), Vector3(x, 0.07, 0.0), 0.055, 0.052, 6, col)
	_bone_fn = Callable()
	_use_bone(foot)
	_box(Vector3(x, 0.045, -0.015), Vector3(0.092, 0.09, 0.19), col)
	_frustum(Vector3(x, 0.036, -0.105), Vector3(x, 0.036, -0.17), 0.045, 0.032, 5, col, 0.8) # rounded toe


## Mosin rifle with the long spike bayonet.
static func _build_mosin(r: Vector3) -> void:
	_box(r + Vector3(0, -0.03, 0.25), Vector3(0.045, 0.1, 0.34), WOOD)
	_box(r + Vector3(0, 0.0, -0.2), Vector3(0.04, 0.045, 0.62), WOOD)
	_frustum(r + Vector3(0, 0.02, 0.06), r + Vector3(0, 0.02, -0.78), 0.012, 0.011, 5, METAL)
	_box(r + Vector3(0, 0.025, 0.06), Vector3(0.03, 0.035, 0.12), METAL) # receiver
	_box(r + Vector3(0.04, 0.02, 0.1), Vector3(0.05, 0.012, 0.012), METAL) # bolt handle
	_frustum(r + Vector3(0.012, 0.0, -0.74), r + Vector3(0.012, 0.0, -1.2), 0.007, 0.002, 4, METAL)


## DP-27 light machine gun: wooden butt, receiver, perforated barrel shroud, cone flash
## hider, the flat round pan magazine on top and the bipod.
static func _build_dp27(r: Vector3) -> void:
	_box(r + Vector3(0, -0.035, 0.27), Vector3(0.045, 0.1, 0.3), WOOD)          # butt
	_box(r + Vector3(0, -0.06, 0.1), Vector3(0.035, 0.08, 0.06), WOOD)          # grip
	_box(r + Vector3(0, 0.0, 0.02), Vector3(0.05, 0.065, 0.24), METAL)          # receiver
	_frustum(r + Vector3(0, 0.012, -0.1), r + Vector3(0, 0.012, -0.6), 0.025, 0.025, 8, METAL) # shroud
	_frustum(r + Vector3(0, 0.012, -0.6), r + Vector3(0, 0.012, -0.74), 0.01, 0.01, 5, METAL)  # barrel
	_frustum(r + Vector3(0, 0.012, -0.83), r + Vector3(0, 0.012, -0.73), 0.024, 0.012, 6, METAL) # flash hider
	_frustum(r + Vector3(0, 0.035, 0.0), r + Vector3(0, 0.055, 0.0), 0.13, 0.13, 14, METAL)    # pan
	_frustum(r + Vector3(0, 0.055, 0.0), r + Vector3(0, 0.068, 0.0), 0.05, 0.05, 8, METAL)     # pan centre
	for side in [-1.0, 1.0]:
		_frustum(r + Vector3(0.0, 0.0, -0.52), r + Vector3(side * 0.12, -0.3, -0.64), 0.008, 0.008, 4, METAL)


## SV1: how a foot bends at the ankle for a leg posed `thigh` then `shin` (both turns about X, as
## SoldierVisual and PlayerBody pose them). `flat` 1 = sole flat on the ground, 0 = foot keeps the
## shin's angle; `toes` adds a bend of its own (+ = toes up). Kept within the ankle's range.
static func foot_pose(thigh: Quaternion, shin: Quaternion, flat: float, toes: float = 0.0) -> Quaternion:
	var leg: float = (thigh * shin).get_euler().x
	return Quaternion(Vector3.RIGHT, clampf(-leg * flat + toes, ANKLE_DOWN, ANKLE_UP))


## Two-bone arm: shoulder → elbow → hand. Puts the hand at `target` (chest = spine-bone space)
## with the elbow bending towards `pole`. Used by SoldierVisual and (NET2b) PlayerBody.
static func reach(skeleton: Skeleton3D, upper: int, fore: int, target: Vector3, pole: Vector3) -> void:
	var shoulder: Vector3 = BONE_REST[upper]
	var to_target: Vector3 = target - shoulder
	var dist: float = clampf(to_target.length(), 0.05, ARM_UPPER + ARM_LOWER - 0.001)
	var dir: Vector3 = to_target.normalized()
	var l1: float = ARM_UPPER
	var l2: float = ARM_LOWER
	# Law of cosines: angle between the upper arm and the shoulder→hand line.
	var cos_a: float = clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var bend: Vector3 = pole.normalized() - dir * dir.dot(pole.normalized())
	bend = bend.normalized() if bend.length() > 0.001 else Vector3.DOWN
	var elbow: Vector3 = shoulder + dir * (l1 * cos_a) + bend * (l1 * sqrt(1.0 - cos_a * cos_a))
	var hand: Vector3 = shoulder + dir * dist
	var upper_q := Quaternion(Vector3.DOWN, (elbow - shoulder).normalized())
	var fore_q := upper_q.inverse() * Quaternion(Vector3.DOWN, (hand - elbow).normalized())
	skeleton.set_bone_pose_rotation(upper, upper_q)
	skeleton.set_bone_pose_rotation(fore, fore_q)


# ------------------------------------------------------------------ shared building blocks
## Other code-built skinned meshes (FirstPersonArms) use the same helpers:
## begin_build(), use_bone(), frustum()/box()/sphere(), then finish_build().
static func begin_build() -> void:
	_st = SurfaceTool.new()
	_st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS) # must come before begin()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bone_fn = Callable()
	_color_fn = Callable()


static func finish_build() -> ArrayMesh:
	var mesh := _st.commit()
	_st = null
	_color_fn = Callable()
	return mesh


static func use_bone(bone: int) -> void:
	_bone_fn = Callable()
	_use_bone(bone)


## Blended weights: `fn(rest position) -> [PackedInt32Array bones, PackedFloat32Array weights]`
## (4 each) decides per vertex until the next use_bone() (AR1b: the arms' wrists).
static func use_bone_fn(fn: Callable) -> void:
	_bone_fn = fn


## NET2b: `fn(rest position, colour) -> Color` changes each vertex's colour until set back to
## Callable() (the Finn's smock gets grime on the elbows, knees, stomach and hem this way).
static func use_color_fn(fn: Callable) -> void:
	_color_fn = fn


static func frustum(a: Vector3, b: Vector3, ra: float, rb: float, sides: int, col: Color, depth: float = 1.0) -> void:
	_frustum(a, b, ra, rb, sides, col, depth)


static func box(center: Vector3, size: Vector3, col: Color, rot := Vector3.ZERO) -> void:
	_box(center, size, col, rot)


static func sphere(center: Vector3, radius: Vector3, segments: int, rings: int, col: Color) -> void:
	_sphere(center, radius, segments, rings, col)


## One triangle (AR1: the arms' folded sleeves are built from their own rings of points).
static func tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color) -> void:
	_tri(a, b, c, na, nb, nc, col)


static var _bones := PackedInt32Array([0, 0, 0, 0])
static var _weights := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])


static func _use_bone(bone: int) -> void:
	_bones = PackedInt32Array([bone, 0, 0, 0])
	_weights = PackedFloat32Array([1.0, 0.0, 0.0, 0.0])


static func _vertex(p: Vector3, n: Vector3, c: Color) -> void:
	if _color_fn.is_valid():
		c = _color_fn.call(p, c)
	_st.set_color(c)
	_st.set_normal(n)
	if absf(c.a - FACE.a) < 0.01:
		_st.set_uv(face_uv(p))
	else:
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


static func _box(center: Vector3, size: Vector3, col: Color, rot := Vector3.ZERO) -> void:
	var h: Vector3 = size / 2.0
	var b := Basis.from_euler(rot)
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var t := Vector3.ZERO
			t[(axis + 1) % 3] = 1.0
			var bt := Vector3.ZERO
			bt[(axis + 2) % 3] = 1.0
			var c: Vector3 = center + b * (n * h[axis])
			var tu: Vector3 = b * (t * h[(axis + 1) % 3])
			var tv: Vector3 = b * (bt * h[(axis + 2) % 3])
			n = b * n
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
