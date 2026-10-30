class_name FirstPersonArms
extends Node3D
## Your own arms in first person: the white snow-camo smock (lumipuku) over the grey tunic,
## and white wool "trigger-finger" mittens (thumb, index finger, and the other three together).
##
## Child of the Camera3D, only drawn for the player on this computer.
## Every frame the hands are put on the gun's grip points – Marker3D nodes named GripR and
## GripL on the hand weapon's view model or on the Maxim (WeaponController.get_hand_grips()).
## The elbows bend to fit with "two-bone IK": the upper arm and forearm lengths are known, so
## the elbow position follows from the triangle shoulder–elbow–wrist (law of cosines).
## Like the soldiers, the arms are ONE skinned mesh (one draw call) built in code.

enum Bone { UPPER_L, FORE_L, HAND_L, UPPER_R, FORE_R, HAND_R }

@export var shoulder_right: Vector3 = Vector3(0.16, -0.28, 0.2) ## Right shoulder in camera space (up at the butt of the gun).
@export var shoulder_left: Vector3 = Vector3(-0.17, -0.34, 0.05) ## Left shoulder: lower, so the arm comes up from below the gun.
@export var upper_arm_length: float = 0.3
@export var forearm_length: float = 0.27
## Direction the right elbow points (left is mirrored): out to the side, down and back –
## never forward, or the arm would fold up in front of the eye when aiming.
@export var elbow_pole_right: Vector3 = Vector3(0.7, -1.0, 0.4)

const SHOULDER_X: float = 0.2 # rest pose: arms hanging straight down
const SMOCK := Color(0.83, 0.84, 0.83, 0.5) # alpha 0.5 = cloth (grain in the shader)
const SMOCK_SEAM := Color(0.72, 0.73, 0.72, 0.5)
const TUNIC := Color(0.43, 0.44, 0.4, 0.5)
const WOOL := Color(0.88, 0.86, 0.81, 0.5)
const WOOL_CUFF := Color(0.78, 0.77, 0.73, 0.5)
## Right hand: centre of the palm surface in hand space (hand bone at the wrist, fingers
## along -Y, palm facing -X, thumb towards -Z). The grip markers mark this point.
const PALM_CONTACT := Vector3(-0.027, -0.068, 0.0)

static var _cached_mesh: ArrayMesh

var skeleton: Skeleton3D
var _mesh_instance: MeshInstance3D
var _player: Player


func _ready() -> void:
	process_priority = 100 # after the guns have moved this frame, so the hands don't lag
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	var names: Array[String] = ["UpperArmL", "ForearmL", "HandL", "UpperArmR", "ForearmR", "HandR"]
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
	mat.shader = load("res://resources/shaders/soldier.gdshader")
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
		update_pose(grips[0], grips[1])


## Puts the hands on two global transforms (right, left) and bends the arms to fit.
func update_pose(right_grip: Transform3D, left_grip: Transform3D) -> void:
	var to_local: Transform3D = global_transform.affine_inverse()
	_solve_arm(true, to_local * right_grip)
	_solve_arm(false, to_local * left_grip)


func _solve_arm(right: bool, grip: Transform3D) -> void:
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
	var side: float = -1.0 if bone <= Bone.HAND_L else 1.0
	var part: int = bone % 3 # 0 = shoulder, 1 = elbow, 2 = wrist
	var down: float = [0.0, upper_arm_length, upper_arm_length + forearm_length][part]
	return Vector3(SHOULDER_X * side, -down, 0.0)


# ------------------------------------------------------------------ the mesh
static func get_mesh(upper_len: float, fore_len: float) -> ArrayMesh:
	if _cached_mesh == null:
		_cached_mesh = _build_mesh(upper_len, fore_len)
	return _cached_mesh


static func _build_mesh(upper_len: float, fore_len: float) -> ArrayMesh:
	SoldierMesh.begin_build()
	for side: float in [-1.0, 1.0]:
		var first: int = Bone.UPPER_L if side < 0.0 else Bone.UPPER_R
		var s := Vector3(SHOULDER_X * side, 0.0, 0.0)
		var e: Vector3 = s + Vector3(0.0, -upper_len, 0.0)
		var w: Vector3 = e + Vector3(0.0, -fore_len, 0.0)
		# Upper arm: loose smock sleeve, a rounded elbow.
		SoldierMesh.use_bone(first)
		SoldierMesh.frustum(s + Vector3(0, 0.06, 0), e, 0.06, 0.051, 14, SMOCK)
		SoldierMesh.sphere(e, Vector3(0.051, 0.051, 0.051), 14, 7, SMOCK)
		# Forearm: the sleeve narrows to a gathered cuff with a seam; the grey tunic sleeve
		# shows a little below it.
		SoldierMesh.use_bone(first + 1)
		SoldierMesh.frustum(e + Vector3(0, 0.01, 0), w + Vector3(0, 0.07, 0), 0.05, 0.045, 14, SMOCK)
		SoldierMesh.frustum(w + Vector3(0, 0.072, 0), w + Vector3(0, 0.05, 0), 0.047, 0.045, 14, SMOCK_SEAM)
		SoldierMesh.frustum(w + Vector3(0, 0.052, 0), w + Vector3(0, 0.012, 0), 0.037, 0.035, 12, TUNIC)
		# Hand: the mitten.
		SoldierMesh.use_bone(first + 2)
		_mitten(w, side)
	return SoldierMesh.finish_build()


## A three-finger wool mitten around the wrist point `w`. Hand space: fingers down (-Y),
## palm towards the body's middle, thumb forward (-Z). `side` -1 = left, 1 = right.
static func _mitten(w: Vector3, side: float) -> void:
	var palm: float = -side # palm faces -X on the right hand, +X on the left
	# Knitted cuff over the wrist.
	SoldierMesh.frustum(w + Vector3(0, -0.03, 0), w + Vector3(0, 0.03, 0), 0.04, 0.036, 12, WOOL_CUFF) # closed at the top
	# Hand + the three fingers in one pouch, its end curled towards the palm (around the grip).
	SoldierMesh.sphere(w + Vector3(0, -0.07, 0.008), Vector3(0.026, 0.06, 0.042), 12, 7, WOOL)
	SoldierMesh.sphere(w + Vector3(palm * 0.02, -0.122, 0.014), Vector3(0.023, 0.03, 0.034), 12, 6, WOOL)
	# The free index finger (for the trigger), beside the pouch on the thumb side.
	_capsule(w + Vector3(0, -0.095, -0.03), w + Vector3(palm * 0.02, -0.14, -0.032), 0.0135, WOOL)
	# Thumb.
	_capsule(w + Vector3(palm * 0.008, -0.04, -0.03), w + Vector3(palm * 0.022, -0.085, -0.048), 0.015, WOOL)


## A tube with rounded ends.
static func _capsule(a: Vector3, b: Vector3, r: float, col: Color) -> void:
	SoldierMesh.frustum(a, b, r, r * 0.95, 10, col)
	SoldierMesh.sphere(a, Vector3.ONE * r, 10, 5, col)
	SoldierMesh.sphere(b, Vector3.ONE * r * 0.95, 10, 5, col)
