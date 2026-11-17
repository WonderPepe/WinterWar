class_name FirstPersonArms
extends Node3D
## Your own arms in first person: the baggy ivory snow-camo smock (lumipuku) over the grey wool
## tunic, and thick grey-ivory wool "trigger-finger" mittens (thumb, index finger, and the other
## three together). AR1: folded sleeves, dirt and wear baked into the colours, own matte shader.
##
## Child of the Camera3D, only drawn for the player on this computer.
## Every frame the hands are put on the gun's grip points – Marker3D nodes named GripR and
## GripL on the hand weapon's view model or on the Maxim (WeaponController.get_hand_grips()).
## The elbows bend to fit with "two-bone IK": the upper arm and forearm lengths are known, so
## the elbow position follows from the triangle shoulder–elbow–wrist (law of cosines).
## Like the soldiers, the arms are ONE skinned mesh (one draw call) built in code.

enum Bone { UPPER_L, FORE_L, HAND_L, UPPER_R, FORE_R, HAND_R, THUMB_L, THUMB_R }

@export var shoulder_right: Vector3 = Vector3(0.16, -0.28, 0.2) ## Right shoulder in camera space (up at the butt of the gun).
@export var shoulder_left: Vector3 = Vector3(-0.17, -0.34, 0.05) ## Left shoulder: lower, so the arm comes up from below the gun.
@export var upper_arm_length: float = 0.3
@export var forearm_length: float = 0.27
## Direction the right elbow points (left is mirrored): out to the side, down and back –
## never forward, or the arm would fold up in front of the eye when aiming.
@export var elbow_pole_right: Vector3 = Vector3(0.7, -1.0, 0.4)

const SHOULDER_X: float = 0.2 # rest pose: arms hanging straight down
## Colours (AR1). The alpha tells the shader (fp_arms.gdshader) which cloth it is:
## 0.5 = cotton snow smock, 0.65 = grey wool tunic, 0.8 = knitted wool mitten.
const SMOCK := Color(0.8, 0.79, 0.73, 0.5)        # warm, slightly dirty ivory – not pure white
const SMOCK_INSIDE := Color(0.52, 0.51, 0.47, 0.5) # inside of the sleeve end (in shadow)
const TUNIC := Color(0.42, 0.43, 0.39, 0.65)       # grey wool uniform sleeve under the smock
const WOOL := Color(0.72, 0.69, 0.63, 0.8)         # grey-ivory wool mitten (owner's choice)
const WOOL_CUFF := Color(0.66, 0.63, 0.57, 0.8)    # its knitted cuff, a little darker
## Colours that dirt, grime and snow are blended towards (baked into the mesh, see _bake_wear).
const SMOCK_DIRT := Color(0.5, 0.47, 0.4)
const WOOL_DIRT := Color(0.33, 0.3, 0.26)
const SNOW := Color(0.93, 0.95, 0.98)
## Which way the underside of each sleeve faces, in the bone's own (rest) space – measured from
## the hip and aiming poses of both guns ([left arm, right arm]). Dirt goes there.
const UNDERSIDE: Array[Vector3] = [Vector3(-1.0, 0.0, 0.1), Vector3(-0.3, 0.0, 0.95)]
## Right hand: centre of the palm surface in hand space (hand bone at the wrist, fingers
## along -Y, palm facing -X, thumb towards -Z). The grip markers mark this point.
const PALM_CONTACT := Vector3(-0.03, -0.068, 0.0) # (AR1: the thicker mitten, was -0.027)
## AR1b: where the mitten's thumb is hinged, in right-hand space (left: x mirrored). Each gun
## turns the thumbs around this point (ViewModel.thumb_right_deg / thumb_left_deg).
const THUMB_BASE := Vector3(-0.008, -0.04, -0.032)
## AR1b: the wrist bends smoothly – the grey tunic cuff and the knitted mitten cuff are shared
## between the forearm and the hand over this stretch (metres above → below the wrist point).
const WRIST_BLEND_TOP: float = 0.06
const WRIST_BLEND_BOTTOM: float = -0.02

static var _cached_mesh: ArrayMesh

var skeleton: Skeleton3D
var _mesh_instance: MeshInstance3D
var _player: Player


func _ready() -> void:
	process_priority = 100 # after the guns have moved this frame, so the hands don't lag
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	var names: Array[String] = ["UpperArmL", "ForearmL", "HandL", "UpperArmR", "ForearmR", "HandR", "ThumbL", "ThumbR"]
	for i in names.size():
		skeleton.add_bone(names[i])
	for i in names.size():
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, _rest_position(i)))
	skeleton.reset_bone_poses()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "ArmsMesh"
	_mesh_instance.mesh = get_mesh(upper_arm_length, forearm_length)
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The mesh is built hanging down (outside the view); a fixed box around the camera keeps
	# it from being culled when the arms are raised.
	_mesh_instance.custom_aabb = AABB(Vector3(-0.9, -0.9, -1.3), Vector3(1.8, 1.8, 1.8))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://resources/shaders/fp_arms.gdshader")
	mat.set_shader_parameter("noise_texture", load("res://assets/textures/snow_mask.png"))
	_mesh_instance.material_override = mat
	skeleton.add_child(_mesh_instance)
	_mesh_instance.skeleton = NodePath("..")
	_player = _find_player()
	visible = false


func _find_player() -> Player:
	var n: Node = get_parent()
	while n != null and not n is Player:
		n = n.get_parent()
	return n as Player


func _process(_delta: float) -> void:
	if _player == null or not _player.is_local_player():
		visible = false
		return
	var grips: Array[Transform3D] = _player.weapons.get_hand_grips()
	visible = grips.size() == 2
	if visible:
		var thumbs: Array[Basis] = _player.weapons.get_thumb_turns()
		update_pose(grips[0], grips[1], thumbs[0], thumbs[1])


## Puts the hands on two global transforms (right, left) and bends the arms to fit.
## `thumb_right` / `thumb_left`: how each thumb is turned around its hinge, in hand space.
func update_pose(right_grip: Transform3D, left_grip: Transform3D, thumb_right := Basis.IDENTITY, thumb_left := Basis.IDENTITY) -> void:
	var to_local: Transform3D = global_transform.affine_inverse()
	_solve_arm(true, to_local * right_grip, thumb_right)
	_solve_arm(false, to_local * left_grip, thumb_left)


## The thumb's hinge in the hand's own space (right or left hand).
static func thumb_base(right: bool) -> Vector3:
	return Vector3(THUMB_BASE.x * (1.0 if right else -1.0), THUMB_BASE.y, THUMB_BASE.z)


func _solve_arm(right: bool, grip: Transform3D, thumb := Basis.IDENTITY) -> void:
	var sgn: float = 1.0 if right else -1.0
	var upper: int = Bone.UPPER_R if right else Bone.UPPER_L
	var hand_basis: Basis = grip.basis.orthonormalized()
	var contact := Vector3(PALM_CONTACT.x * sgn, PALM_CONTACT.y, PALM_CONTACT.z)
	var wrist: Vector3 = grip.origin - hand_basis * contact
	var shoulder: Vector3 = shoulder_right if right else shoulder_left
	var l1: float = upper_arm_length
	var l2: float = forearm_length
	var reach: float = (l1 + l2) * 0.985
	var to_wrist: Vector3 = wrist - shoulder
	if to_wrist.length() > reach:
		# Out of reach: the shoulder comes forward (you lean into the gun).
		shoulder = wrist - to_wrist.normalized() * reach
		to_wrist = wrist - shoulder
	var dist: float = clampf(to_wrist.length(), 0.08, reach)
	var dir: Vector3 = to_wrist.normalized()
	# Law of cosines: angle between the upper arm and the shoulder→wrist line.
	var cos_a: float = clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var pole := Vector3(elbow_pole_right.x * sgn, elbow_pole_right.y, elbow_pole_right.z).normalized()
	var bend: Vector3 = pole - dir * dir.dot(pole)
	bend.z = maxf(bend.z, 0.0) # the elbow never swings forward into the view
	bend = bend.normalized() if bend.length() > 0.001 else Vector3(sgn, -1.0, 0.0).normalized()
	var elbow: Vector3 = shoulder + dir * (l1 * cos_a) + bend * (l1 * sqrt(1.0 - cos_a * cos_a))
	wrist = shoulder + dir * dist
	# The forearm twists with the hand (palm direction), so the wrist doesn't look wrung.
	_set_bone(upper, shoulder, _along(elbow - shoulder, hand_basis.x))
	_set_bone(upper + 1, elbow, _along(wrist - elbow, hand_basis.x))
	_set_bone(upper + 2, wrist, hand_basis)
	# The thumb rides on the hand, turned around its hinge.
	var thumb_bone: int = Bone.THUMB_R if right else Bone.THUMB_L
	_set_bone(thumb_bone, wrist + hand_basis * thumb_base(right), hand_basis * thumb)


## A bone basis whose -Y points along `dir` (the rest pose hangs down), rolled towards `x_hint`.
static func _along(dir: Vector3, x_hint: Vector3) -> Basis:
	var y: Vector3 = -dir.normalized()
	var x: Vector3 = x_hint - y * y.dot(x_hint)
	if x.length() < 0.001:
		x = Vector3.RIGHT - y * y.dot(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


func _set_bone(bone: int, pos: Vector3, basis: Basis) -> void:
	skeleton.set_bone_pose_position(bone, pos)
	skeleton.set_bone_pose_rotation(bone, basis.get_rotation_quaternion())


## Where a bone starts when the arms hang straight down (the mesh is built like this).
func _rest_position(bone: int) -> Vector3:
	if bone >= Bone.THUMB_L:
		var r: bool = bone == Bone.THUMB_R
		return _rest_position(Bone.HAND_R if r else Bone.HAND_L) + thumb_base(r)
	var side: float = -1.0 if bone <= Bone.HAND_L else 1.0
	var part: int = bone % 3 # 0 = shoulder, 1 = elbow, 2 = wrist
	var down: float = [0.0, upper_arm_length, upper_arm_length + forearm_length][part]
	return Vector3(SHOULDER_X * side, -down, 0.0)


# ------------------------------------------------------------------ the mesh
static func get_mesh(upper_len: float, fore_len: float) -> ArrayMesh:
	if _cached_mesh == null:
		_cached_mesh = _bake_wear(_build_mesh(upper_len, fore_len), upper_len, fore_len)
	return _cached_mesh


static func _build_mesh(upper_len: float, fore_len: float) -> ArrayMesh:
	SoldierMesh.begin_build()
	for side: float in [-1.0, 1.0]:
		var first: int = Bone.UPPER_L if side < 0.0 else Bone.UPPER_R
		var s := Vector3(SHOULDER_X * side, 0.0, 0.0)
		var e: Vector3 = s + Vector3(0.0, -upper_len, 0.0)
		var w: Vector3 = e + Vector3(0.0, -fore_len, 0.0)
		# Each arm folds a little differently (left and right are not mirror images).
		var ph: float = 0.6 if side < 0.0 else 2.3
		var ph2: float = 1.9 if side < 0.0 else 0.4
		var bunch_freq: float = 2.4 if side < 0.0 else 2.9
		# Upper arm: a loose, baggy smock sleeve with long folds, bunched above the elbow.
		var upper_shape := func(t: float, ang: float) -> float:
			var base: float = lerpf(0.066, 0.058, t)
			var ridges: float = 0.035 * sin(3.0 * ang + ph + 2.5 * t) + 0.015 * sin(5.0 * ang + ph2)
			var bunch: float = 0.05 * smoothstep(0.55, 0.8, t) * sin(TAU * 2.0 * t + 0.9 * sin(2.0 * ang + ph2))
			# The end goes smoothly into the round elbow (no open edge sticking out of it).
			return base * (1.0 + (ridges + bunch) * (1.0 - smoothstep(0.8, 1.0, t)))
		SoldierMesh.use_bone(first)
		_tube(s + Vector3(0, 0.06, 0), e, 12, 18, upper_shape, SMOCK)
		SoldierMesh.sphere(e, Vector3(0.06, 0.058, 0.06), 18, 8, SMOCK)
		# Forearm: the sleeve swells and bunches in broad folds above the wrist, then is gathered
		# into the cuff. The grey wool tunic sleeve shows a little below it.
		SoldierMesh.use_bone(first + 1)
		# Its own rounded elbow end too, so a sharply bent elbow never shows an open tube.
		SoldierMesh.sphere(e, Vector3(0.057, 0.055, 0.057), 18, 8, SMOCK)
		var cuff: Vector3 = w + Vector3(0, 0.058, 0)
		var fore_shape := func(t: float, ang: float) -> float:
			var base: float = lerpf(0.054, 0.061, smoothstep(0.0, 0.72, t))
			base = lerpf(base, 0.046, smoothstep(0.8, 1.0, t))
			var open: float = smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.85, 1.0, t)) # not at the ends
			var ridges: float = (0.03 * sin(3.0 * ang + ph + 3.0 * t) + 0.012 * sin(5.0 * ang + ph2 - 2.0 * t)) * open
			var bunch: float = 0.065 * smoothstep(0.35, 0.6, t) * (1.0 - smoothstep(0.88, 0.98, t)) \
					* sin(TAU * bunch_freq * t + 1.1 * sin(2.0 * ang + ph2) + ph)
			var gather: float = 0.03 * smoothstep(0.88, 1.0, t) * sin(9.0 * ang + ph)
			var elbow: float = 0.04 * smoothstep(0.03, 0.1, t) * (1.0 - smoothstep(0.1, 0.25, t)) * sin(2.0 * ang + ph2)
			return base * (1.0 + ridges + bunch + gather + elbow)
		_tube(e + Vector3(0, 0.012, 0), cuff, 20, 22, fore_shape, SMOCK)
		# The sleeve end is hemmed: it turns in towards the tunic sleeve (so you never look into an
		# empty tube or see a paper-thin edge).
		SoldierMesh.frustum(cuff, cuff - Vector3(0, 0.007, 0), 0.047, 0.039, 22, SMOCK_INSIDE)
		# AR1b: the tunic cuff and the mitten's knitted cuff bend with the wrist (shared weights), so
		# a bent wrist doesn't push the grey sleeve through the mitten.
		var wrist_y: float = w.y
		SoldierMesh.use_bone_fn(func(q: Vector3) -> Array:
			var h: float = smoothstep(0.0, 1.0, (wrist_y + WRIST_BLEND_TOP - q.y) / (WRIST_BLEND_TOP - WRIST_BLEND_BOTTOM))
			return [PackedInt32Array([first + 1, first + 2, 0, 0]), PackedFloat32Array([1.0 - h, h, 0.0, 0.0])])
		SoldierMesh.frustum(w + Vector3(0, 0.08, 0), w + Vector3(0, 0.006, 0), 0.04, 0.034, 14, TUNIC) # slimmer inside the mitten cuff
		_mitten_cuff(w)
		# Hand: the mitten.
		SoldierMesh.use_bone(first + 2)
		_mitten(w, side, Bone.THUMB_R if side > 0.0 else Bone.THUMB_L)
	return SoldierMesh.finish_build()


## A thick three-finger wool mitten around the wrist point `w`. Hand space: fingers down (-Y),
## palm towards the body's middle, thumb forward (-Z). `side` -1 = left, 1 = right.
## The mitten's ribbed knitted cuff over the wrist, flaring a little at the top, its rolled edge
## closed (a strongly bent wrist then shows wool, not a hollow tube).
static func _mitten_cuff(w: Vector3) -> void:
	var rib := func(t: float, ang: float) -> float:
		return lerpf(0.041, 0.037, t) * (1.0 + 0.03 * sin(18.0 * ang))
	_tube(w + Vector3(0, 0.032, 0), w + Vector3(0, -0.024, 0), 8, 18, rib, WOOL_CUFF)
	SoldierMesh.frustum(w + Vector3(0, 0.032, 0), w + Vector3(0, 0.039, 0), 0.042, 0.03, 18, WOOL_CUFF) # rolled top, closed


## The hand part of the mitten (the cuff is `_mitten_cuff`); the thumb on its own bone.
static func _mitten(w: Vector3, side: float, thumb_bone: int) -> void:
	var palm: float = -side # palm faces -X on the right hand, +X on the left
	# Hand + the three fingers in one rounded, padded pouch, its end curled towards the palm.
	SoldierMesh.sphere(w + Vector3(0, -0.072, 0.008), Vector3(0.029, 0.064, 0.047), 14, 8, WOOL)
	SoldierMesh.sphere(w + Vector3(palm * 0.021, -0.127, 0.014), Vector3(0.026, 0.034, 0.039), 14, 7, WOOL)
	# The free index finger (for the trigger), beside the pouch on the thumb side.
	_capsule(w + Vector3(0, -0.095, -0.032), w + Vector3(palm * 0.02, -0.143, -0.034), 0.0155, WOOL)
	# Thumb (its own bone, so each gun can turn it around its hinge – AR1b).
	SoldierMesh.use_bone(thumb_bone)
	_capsule(w + Vector3(palm * 0.008, -0.04, -0.032), w + Vector3(palm * 0.024, -0.087, -0.05), 0.017, WOOL)


## A tube with rounded ends.
static func _capsule(a: Vector3, b: Vector3, r: float, col: Color) -> void:
	SoldierMesh.frustum(a, b, r, r * 0.95, 10, col)
	SoldierMesh.sphere(a, Vector3.ONE * r, 10, 5, col)
	SoldierMesh.sphere(b, Vector3.ONE * r * 0.95, 10, 5, col)


## A cloth tube straight down from `a` to `b` (the rest pose hangs down) with `rings` + 1 rings
## of `sides` points. `shape(t, angle)` gives the radius of each point (t 0 at a … 1 at b), so the
## folds are real bumps in the outline. Normals come from the neighbouring points, so the folds
## catch the light like cloth. Open at both ends (they are hidden inside other parts).
static func _tube(a: Vector3, b: Vector3, rings: int, sides: int, shape: Callable, col: Color) -> void:
	var pts: Array[PackedVector3Array] = []
	for i in rings + 1:
		var t: float = float(i) / rings
		var centre: Vector3 = a.lerp(b, t)
		var row := PackedVector3Array()
		for j in sides:
			var ang: float = TAU * j / sides
			var r: float = shape.call(t, ang)
			row.append(centre + Vector3(cos(ang), 0.0, sin(ang)) * r)
		pts.append(row)
	var nrm: Array[PackedVector3Array] = []
	for i in rings + 1:
		var row := PackedVector3Array()
		for j in sides:
			var along: Vector3 = pts[mini(i + 1, rings)][j] - pts[maxi(i - 1, 0)][j]
			var around: Vector3 = pts[i][(j + 1) % sides] - pts[i][(j + sides - 1) % sides]
			var n: Vector3 = around.cross(along).normalized()
			var ang: float = TAU * j / sides
			if n.dot(Vector3(cos(ang), 0.0, sin(ang))) < 0.0:
				n = -n
			row.append(n)
		nrm.append(row)
	for i in rings:
		for j in sides:
			var k: int = (j + 1) % sides
			SoldierMesh.tri(pts[i][j], pts[i + 1][j], pts[i + 1][k], nrm[i][j], nrm[i + 1][j], nrm[i + 1][k], col)
			SoldierMesh.tri(pts[i][j], pts[i + 1][k], pts[i][k], nrm[i][j], nrm[i + 1][k], nrm[i][k], col)


## Dirt, wear and a little snow, painted into the vertex colours once when the mesh is made
## (costs nothing while playing). Works in the rest pose (arms hanging down):
## - smock: the underside of the sleeves (UNDERSIDE), the elbows and the cuff edge get darker;
##   a few faint snow patches stick to the top side;
## - mittens: palms and fingertips darker, the right trigger finger and thumb oily.
static func _bake_wear(mesh: ArrayMesh, upper_len: float, fore_len: float) -> ArrayMesh:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var wrist_y: float = -(upper_len + fore_len)
	for i in verts.size():
		var bone: int = bones[i * 4]
		var right: bool = bone in [Bone.UPPER_R, Bone.FORE_R, Bone.HAND_R, Bone.THUMB_R]
		var sgn: float = 1.0 if right else -1.0
		var p: Vector3 = verts[i]
		var n: Vector3 = normals[i]
		var c: Color = colors[i]
		var code: float = c.a
		var noise: float = _noise(p, sgn)
		var dirt: float = 0.0
		if code < 0.6: # snow smock
			var radial := Vector3(n.x, 0.0, n.z)
			radial = radial.normalized() if radial.length() > 0.001 else Vector3.ZERO
			var under: float = radial.dot(UNDERSIDE[1 if right else 0].normalized())
			var on_forearm: bool = bone % 3 == 1
			dirt += 0.5 * smoothstep(0.15, 0.9, under) * (1.0 if on_forearm else 0.55) * (0.6 + 0.6 * noise)
			dirt += 0.28 * (1.0 - smoothstep(0.015, 0.075, absf(p.y + upper_len))) * (0.5 + noise)
			if on_forearm:
				dirt += 0.35 * (1.0 - smoothstep(0.0, 0.035, p.y - (wrist_y + 0.058))) * (0.6 + 0.5 * noise)
			var snow: float = 0.55 * smoothstep(0.45, 0.95, -under) * smoothstep(0.62, 0.85, _noise(p * 1.7, -sgn))
			c = c.lerp(SMOCK_DIRT, clampf(dirt, 0.0, 0.7)).lerp(SNOW, snow)
		elif code < 0.75: # grey wool tunic: only a slightly worn edge
			dirt = 0.2 * (1.0 - smoothstep(0.0, 0.015, p.y - (wrist_y + 0.006)))
			c = c.lerp(WOOL_DIRT, dirt)
		else: # wool mitten
			var palm := Vector3(-sgn, 0.0, 0.0)
			var below_wrist: float = wrist_y - p.y
			dirt += 0.6 * smoothstep(0.05, 0.75, n.dot(palm)) * smoothstep(0.02, 0.05, below_wrist)
			dirt += 0.4 * smoothstep(0.11, 0.15, below_wrist) # fingertips
			if right and p.z < -0.018 and below_wrist > 0.085:
				dirt += 0.25 # gun oil on the trigger finger
			if right and p.z < -0.04 and below_wrist > 0.06:
				dirt += 0.2 # ... and the thumb tip
			dirt *= 0.75 + 0.5 * noise
			c = c.lerp(WOOL_DIRT, clampf(dirt, 0.0, 0.75))
		c.a = code
		colors[i] = c
	arrays[Mesh.ARRAY_COLOR] = colors
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## Smooth 0..1 blotches over a few centimetres (no texture needed while building the mesh).
static func _noise(p: Vector3, salt: float) -> float:
	return 0.5 + 0.25 * sin(31.0 * p.y + 17.0 * p.x + 3.1 * salt) + 0.25 * sin(23.0 * p.z - 19.0 * p.y + 1.7 * salt)
