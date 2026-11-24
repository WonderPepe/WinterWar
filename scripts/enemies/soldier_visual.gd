class_name SoldierVisual
extends Node3D
## What a Soviet soldier looks like and how he moves (the "Visual" child of Enemy).
##
## The body is the SoldierMesh on a Skeleton3D. This script poses the bones in code every
## frame: walking/running legs, kneeling to fire, rifle carried / held forward / shouldered,
## recoil, and the arms always reaching for the rifle (simple "IK": we place the hands and
## work out the elbows). It also plays his breath vapour when you are near, and his
## footsteps if there are recordings (see FootstepSounds).
##
## Runs on EVERY computer and only reads what the host syncs (position, state, kneeling),
## so all players see the same soldier doing the same thing.
##
## V10b: a few seconds after he falls, this node leaves the soldier and is kept by the
## BodyKeeper as a plain picture (`become_body`) – the body stays on the field, the soldier
## node itself is removed as before. V10c: once he lies still the BodyKeeper "bakes" him
## (`bake_body`): the pose is frozen into a plain shape, the skeleton goes, and the keeper draws
## him together with other bodies in one batch.

const B := SoldierMesh.Bone

@export var pose_speed: float = 10.0 ## How fast he changes from one pose to another.
@export var stride_m: float = 0.8 ## Distance per step.
@export var effects_distance: float = 30.0 ## Footsteps and breath only when you are this close.
@export var material: ShaderMaterial ## soldier.gdshader; each soldier gets his own copy (coat tint).
@export var kind: EnemyData.Kind = EnemyData.Kind.RIFLEMAN ## Used when there is no Enemy parent (warm-up, screenshots).
## V10b: this long after he fell (he lies still by then) the body is handed to the BodyKeeper.
@export var body_after: float = 3.0
## V10c: further away than this he is posed every 2nd frame, beyond twice this every 3rd – from
## that far nobody sees the difference, and posing the bones is most of a soldier's cost.
@export var far_pose_distance: float = 60.0

var muzzle: Marker3D ## Where his shots come from (follows the rifle).
var is_body: bool = false ## V10b: true once this is only a body kept by the BodyKeeper.
var baked: Array = [] ## V10c: the frozen body (mesh arrays in this node's space) once baked; empty before.

var _enemy: Enemy
var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _footsteps: AudioStreamPlayer3D
var _breath: CPUParticles3D
var _step_sounds: Array[AudioStream] = []
var _last_pos: Vector3
var _speed: float = 0.0
var _phase: float = 0.0 # walk cycle, one step = PI
var _kick: float = 0.0
var _hit: float = 0.0
var _was_dead: bool = false
var _dead_time: float = 0.0 # seconds since he fell (V10b)
var _breath_timer: float = 0.0
var _rot: Dictionary = {} # bone -> current Quaternion (smoothed)
var _rifle_pos: Vector3
var _rifle_rot: Quaternion = Quaternion.IDENTITY
var _hips_y: float = 0.95
var _whistle: float = 0.0 # officer: > 0 while the whistle is at his mouth
var _throw_t: float = 0.0 # GR1: seconds into a grenade throw (0 = not throwing)
var _hand_grenade: Node3D # GR1: the F-1 in his right hand during the wind-up (made when first needed)
var _rng := RandomNumberGenerator.new()
var _tint: Color = Color(1, 1, 1) # his coat tint
var _snow_cover: float = 0.0 # V10b/V10c: snow on the body
var _pose_wait: int = 0 # V10c: frames left before the next pose (far away)
var _pose_delta: float = 0.0 # V10c: time gathered since the last pose

# Coats were not all the same colour: grey-brown, greener, darker.
const COAT_TINTS: Array[Color] = [Color(1, 1, 1), Color(0.92, 0.97, 0.9), Color(1.05, 1.0, 0.95),
		Color(0.85, 0.85, 0.85), Color(0.95, 0.92, 0.98)]


func _ready() -> void:
	_rng.randomize()
	_pose_wait = _rng.randi() % 3 # far soldiers are not all posed on the same frame
	_enemy = get_parent() as Enemy
	if _enemy and _enemy.data:
		kind = _enemy.data.kind
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton"
	add_child(_skeleton)
	SoldierMesh.setup_skeleton(_skeleton)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Body"
	_mesh.mesh = SoldierMesh.get_mesh(kind)
	_skeleton.add_child(_mesh)
	_mesh.skeleton = NodePath("..")
	if material:
		var m: ShaderMaterial = material.duplicate()
		_tint = COAT_TINTS[_rng.randi() % COAT_TINTS.size()]
		m.set_shader_parameter("coat_tint", _tint)
		_mesh.material_override = m
	_skeleton.scale = Vector3.ONE * _rng.randf_range(0.95, 1.06) # not all the same height

	var attach := BoneAttachment3D.new()
	attach.name = "RifleAttach"
	_skeleton.add_child(attach)
	attach.bone_name = SoldierMesh.BONE_NAMES[B.RIFLE]
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = SoldierMesh.muzzle_for(kind)
	attach.add_child(muzzle)

	for i in SoldierMesh.BONE_NAMES.size():
		_rot[i] = Quaternion.IDENTITY
	_rifle_pos = SoldierMesh.BONE_REST[B.RIFLE]
	_last_pos = global_position

	if _enemy:
		_footsteps = AudioStreamPlayer3D.new()
		_footsteps.bus = &"SFX"
		_footsteps.unit_size = 3.0
		_footsteps.volume_db = -8.0
		add_child(_footsteps)
		_step_sounds = FootstepSounds.get_sounds("snow")
		_breath = make_breath_emitter()
		_breath.position = Vector3(0, 1.6, -0.15)
		add_child(_breath)
		_breath_timer = _rng.randf_range(0.0, 3.0)


## The recoil kick when he fires (called on every computer).
func play_fire() -> void:
	_kick = 1.0


## Hit but still alive: he flinches back for a moment.
func play_hit() -> void:
	_hit = 1.0


## Officer: whistle to the mouth for a moment.
func play_whistle() -> void:
	_whistle = 1.4


func _process(delta: float) -> void:
	if _enemy == null:
		return # e.g. used by the shader warm-up: just stand there
	var pos: Vector3 = _enemy.global_position
	var moved: Vector3 = pos - _last_pos
	moved.y = 0.0
	_last_pos = pos
	var instant: float = moved.length() / maxf(delta, 0.0001)
	_speed = lerpf(_speed, minf(instant, 8.0), clampf(delta * 8.0, 0.0, 1.0))
	var steps_before: int = int(_phase / PI)
	_phase += moved.length() / stride_m * PI
	var cam_dist: float = _camera_distance()
	var near: bool = cam_dist < effects_distance
	if near and int(_phase / PI) != steps_before and _speed > 0.5:
		_play_step()
	if near and _enemy.state != Enemy.State.DEAD:
		_breath_timer -= delta
		if _breath_timer <= 0.0:
			if Settings.show_breath:
				_breath.restart()
			_breath_timer = _rng.randf_range(2.0, 3.5) if _speed < 2.5 else _rng.randf_range(1.0, 1.6)
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_hit = move_toward(_hit, 0.0, delta * 3.0)
	_whistle = maxf(_whistle - delta, 0.0)
	var dead: bool = _enemy.state == Enemy.State.DEAD
	if dead and not _was_dead and near and not _step_sounds.is_empty():
		# The thud of the body falling into the snow.
		_footsteps.stream = _step_sounds[0]
		_footsteps.pitch_scale = 0.55
		_footsteps.volume_db = -2.0
		get_tree().create_timer(0.45).timeout.connect(_footsteps.play)
	_was_dead = dead
	# V10c: far away he is posed less often (with the time gathered meanwhile).
	_pose_delta += delta
	_pose_wait -= 1
	if _pose_wait <= 0:
		_pose_wait = 1 if cam_dist < far_pose_distance or cam_dist == INF else (2 if cam_dist < far_pose_distance * 2.0 else 3)
		_pose(_pose_delta)
		_pose_delta = 0.0
	if dead:
		_dead_time += delta
		if _dead_time >= body_after:
			hand_over_body()


## V10b: he lies still now – the BodyKeeper takes this node over (on this computer). Without a
## BodyKeeper (tests, the benchmark) the body goes when the soldier node is removed, as before.
func hand_over_body() -> void:
	if is_body:
		return
	var keeper := get_tree().get_first_node_in_group("body_keeper") as BodyKeeper
	if keeper:
		keeper.take(self)
	else:
		_dead_time = -INF # nobody to hand it to: don't ask again


## V10b: from now on this is only a picture of a body: no posing, no sounds, no breath, no
## shadow, and not drawn at all beyond `hide_distance_m`. Called by the BodyKeeper.
func become_body(hide_distance_m: float, shadows: bool) -> void:
	is_body = true
	_enemy = null
	set_process(false)
	if _footsteps:
		_footsteps.queue_free()
		_footsteps = null
	if _breath:
		_breath.queue_free()
		_breath = null
	if _mesh:
		if not shadows:
			_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh.visibility_range_end = hide_distance_m


## V10b: how much snow lies on the body (0 = none … 1 = nearly covered). A baked body (V10c)
## only keeps the number – the BodyKeeper puts it into the batch.
func set_snow_cover(amount: float) -> void:
	_snow_cover = clampf(amount, 0.0, 1.0)
	var m: ShaderMaterial = (_mesh.material_override as ShaderMaterial) if _mesh else null
	if m:
		m.set_shader_parameter("snow_cover", _snow_cover)


func get_snow_cover() -> float:
	return _snow_cover


## V10c: the material of this soldier (the BodyKeeper copies it once for its batches).
func get_material() -> ShaderMaterial:
	return (_mesh.material_override as ShaderMaterial) if _mesh else null


## V10c: freezes the body as it lies now into a plain shape and frees the skeleton (and the
## rifle marker, a grenade in the hand…). Fills `baked` with the shape's arrays in this node's
## space: positions, normals, colours (coat tint already in them) and UV – no bones, no indices
## (every triangle has its own 3 corners, so bodies can be glued together without renumbering).
## Called by the BodyKeeper; after this the node draws nothing itself.
func bake_body() -> void:
	if not baked.is_empty() or _mesh == null:
		return
	# Godot freezes the pose itself (fast). Without a real renderer (the tests run "headless") it
	# can't, so then the script does the same: `_pose_on_cpu`.
	var posed: ArrayMesh = _mesh.bake_mesh_from_current_skeleton_pose() if RenderingServer.get_video_adapter_name() != "" else null
	if posed == null:
		posed = _pose_on_cpu()
	var st := SurfaceTool.new()
	st.create_from(posed, 0)
	st.deindex()
	var src: Array = st.commit_to_arrays()
	var xf: Transform3D = global_transform.affine_inverse() * _mesh.global_transform
	var nxf := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
	var colors: PackedColorArray = src[Mesh.ARRAY_COLOR]
	if _tint != Color(1, 1, 1):
		for i in colors.size():
			var c: Color = colors[i]
			if c.a > 0.75: # greatcoat (see soldier.gdshader)
				colors[i] = Color(c.r * _tint.r, c.g * _tint.g, c.b * _tint.b, c.a)
	baked.resize(Mesh.ARRAY_MAX)
	baked[Mesh.ARRAY_VERTEX] = xf * (src[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	baked[Mesh.ARRAY_NORMAL] = nxf * (src[Mesh.ARRAY_NORMAL] as PackedVector3Array)
	baked[Mesh.ARRAY_COLOR] = colors
	baked[Mesh.ARRAY_TEX_UV] = src[Mesh.ARRAY_TEX_UV]
	for c in get_children():
		c.queue_free()
	_skeleton = null
	_mesh = null
	_hand_grenade = null
	muzzle = null


## V10c: the soldier mesh as it is posed now, worked out in the script: every corner is moved
## by the bones it hangs on (up to 4, weighted) from where it is in the rest pose. Same result
## as `bake_mesh_from_current_skeleton_pose`, just slower (once per body, a few ms).
func _pose_on_cpu() -> ArrayMesh:
	var src: Array = _mesh.mesh.surface_get_arrays(0)
	var bone_xf: Array[Transform3D] = []
	for b in _skeleton.get_bone_count():
		bone_xf.append(_skeleton.get_bone_global_pose(b) * _skeleton.get_bone_global_rest(b).affine_inverse())
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = src[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = src[Mesh.ARRAY_WEIGHTS]
	var per: int = bones.size() / maxi(verts.size(), 1) # 4 bones per corner
	for i in verts.size():
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		for k in per:
			var w: float = weights[i * per + k]
			if w > 0.0:
				var t: Transform3D = bone_xf[bones[i * per + k]]
				p += (t * verts[i]) * w
				n += (t.basis * normals[i]) * w
		verts[i] = p
		normals[i] = n.normalized()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = src[Mesh.ARRAY_COLOR]
	arrays[Mesh.ARRAY_TEX_UV] = src[Mesh.ARRAY_TEX_UV]
	arrays[Mesh.ARRAY_INDEX] = src[Mesh.ARRAY_INDEX]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _is_near_camera() -> bool:
	return _camera_distance() < effects_distance


## How far the camera of this computer is (very far without a camera).
func _camera_distance() -> float:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position.distance_to(global_position) if cam else INF


func _play_step() -> void:
	if _step_sounds.is_empty():
		return
	_footsteps.stream = _step_sounds[_rng.randi() % _step_sounds.size()]
	_footsteps.pitch_scale = _rng.randf_range(0.9, 1.1)
	_footsteps.volume_db = -14.0 if _enemy.is_crouching else -8.0 # EC1: quieter when crouching
	_footsteps.play()


# ------------------------------------------------------------------ posing
func _pose(delta: float) -> void:
	var state: Enemy.State = _enemy.state
	var dead: bool = state == Enemy.State.DEAD
	var prone: bool = _enemy.is_prone # lying flat (also stays flat when killed lying down)
	var moving: bool = _speed > 0.4 and not dead and not prone
	var kneel: bool = _enemy.is_kneeling and not moving and not dead and not prone
	var crouch: bool = _enemy.is_crouching and not kneel and not dead and not prone # EC1
	var attacking: bool = state == Enemy.State.ATTACK or state == Enemy.State.ALERT or state == Enemy.State.ASSAULT
	# GR1: a grenade throw – he stands, rifle down in his left hand, and swings his right arm.
	var throwing: bool = _enemy.is_throwing and not dead and not prone
	_throw_t = _throw_t + delta if throwing else 0.0
	_update_hand_grenade(throwing)
	if throwing:
		moving = false
		kneel = false
		crouch = false

	# Targets for this frame.
	var t := {}
	var hips_y: float = 0.95
	var lean: float = 0.0 # forward lean of the upper body (radians)
	var head_extra: float = 0.0
	if prone:
		# Flat on the snow: the whole body tips forward at the hips, chest a little up, legs apart.
		hips_y = PRONE_HIPS_Y
		t[B.HIPS] = _x(PRONE_HIPS_PITCH)
		t[B.THIGH_L] = Quaternion(Vector3.BACK, -0.14)
		t[B.THIGH_R] = Quaternion(Vector3.BACK, 0.14)
		t[B.SHIN_L] = _x(-0.12)
		t[B.SHIN_R] = _x(-0.25)
		lean = -PRONE_CHEST_UP if not dead else 0.0
		head_extra = 0.75 if not dead else 0.1 # look ahead, not into the snow
	elif dead:
		pass # limp: everything goes back to straight, the Enemy tips the whole body over
	elif kneel:
		# Left foot forward, right knee on the snow.
		hips_y = 0.53
		t[B.THIGH_L] = _x(1.45)
		t[B.SHIN_L] = _x(-1.5)
		t[B.THIGH_R] = _x(-0.15)
		t[B.SHIN_R] = _x(-1.45)
		lean = 0.12
	elif crouch:
		# EC1: bent low – knees well bent, upper body forward, head up to look ahead. Moving: short
		# steps from that bent stance (the hips bob a little).
		lean = CROUCH_LEAN
		head_extra = 0.3
		if moving:
			var c_amp: float = clampf(_speed * 0.12, 0.18, 0.34)
			var c_s: float = sin(_phase)
			t[B.THIGH_L] = _x(CROUCH_THIGH + c_s * c_amp)
			t[B.THIGH_R] = _x(CROUCH_THIGH - c_s * c_amp)
			t[B.SHIN_L] = _x(CROUCH_SHIN - maxf(0.0, cos(_phase)) * c_amp)
			t[B.SHIN_R] = _x(CROUCH_SHIN - maxf(0.0, -cos(_phase)) * c_amp)
			hips_y = CROUCH_HIPS_Y + 0.03 + absf(cos(_phase)) * 0.02
		else:
			t[B.THIGH_L] = _x(CROUCH_THIGH + 0.2) # left foot a little forward
			t[B.SHIN_L] = _x(CROUCH_SHIN - 0.15)
			t[B.THIGH_R] = _x(CROUCH_THIGH - 0.1)
			t[B.SHIN_R] = _x(CROUCH_SHIN - 0.25)
			hips_y = CROUCH_HIPS_Y
	elif moving:
		var amp: float = clampf(_speed * 0.15, 0.22, 0.52)
		var s: float = sin(_phase)
		t[B.THIGH_L] = _x(s * amp)
		t[B.THIGH_R] = _x(-s * amp)
		t[B.SHIN_L] = _x(-maxf(0.0, cos(_phase)) * amp * 1.4)
		t[B.SHIN_R] = _x(-maxf(0.0, -cos(_phase)) * amp * 1.4)
		hips_y = 0.95 - 0.02 + absf(cos(_phase)) * 0.025
		lean = 0.05 + _speed * 0.05
	if throwing:
		var swing: Dictionary = _throw_swing()
		lean = swing.lean
		t[B.THIGH_L] = _x(0.3) # left foot forward, weight going onto it
		t[B.SHIN_L] = _x(-0.15)
		t[B.THIGH_R] = _x(-0.25)
	t[B.SPINE] = _x(-lean + _hit * 0.35) # negative = top of the body forward; a hit pushes it back
	if not prone:
		t[B.HIPS] = Quaternion.IDENTITY
	t[B.HEAD] = _x(lean * 0.6 + (0.08 if kneel else 0.0) + head_extra) # keep looking ahead

	# Where the rifle is (relative to the chest).
	var rifle_pos: Vector3
	var rifle_rot: Quaternion
	var officer: bool = kind == EnemyData.Kind.OFFICER
	if prone:
		# Lying down: the weapon points straight ahead, level, butt in the right shoulder
		# (killed: it lies on its side in the snow next to him).
		# Worked out in skeleton space, then turned into chest (spine) space.
		var spine_xf: Transform3D = Transform3D(Basis(t[B.HIPS]), Vector3(0, hips_y, 0)) \
				* Transform3D(Basis(t[B.SPINE]), SoldierMesh.BONE_REST[B.SPINE])
		var shoulder: Vector3 = spine_xf * SoldierMesh.BONE_REST[B.UPPER_ARM_R]
		var offset := Vector3(-0.12, 0.04, -0.38)
		if officer:
			offset = Vector3(-0.1, 0.02, -0.48)
		elif kind == EnemyData.Kind.MG_GUNNER:
			offset = Vector3(-0.13, -0.02, -0.4) # the bipod stands in the snow
		var weapon_xf := Transform3D(Basis.IDENTITY, shoulder + offset)
		if dead:
			weapon_xf = Transform3D(Basis.from_euler(Vector3(0.0, 0.45, 1.5)), Vector3(0.38, 0.05, -0.45))
		var local: Transform3D = spine_xf.affine_inverse() * weapon_xf
		rifle_pos = local.origin
		rifle_rot = local.basis.get_rotation_quaternion()
	elif officer and not dead:
		if attacking and not moving:
			rifle_pos = Vector3(0.17, 0.44, -0.52) # pistol held out at arm's length
			rifle_rot = Quaternion.IDENTITY
		else:
			rifle_pos = Vector3(0.24, 0.02, -0.18) # pistol down by his side
			rifle_rot = _x(-0.9)
	elif dead:
		# The Enemy tips the whole body over, so the weapon must lie ALONG the body (its long
		# axis = the body's up axis), a little way to the side. Then it ends up flat on the snow
		# next to him instead of pointing at the sky. (z = 0: not under him if he fell forwards.)
		rifle_pos = Vector3(0.42, -0.25, 0.0)
		rifle_rot = Quaternion.from_euler(Vector3(PI / 2.0, 0.12, 0.0))
	elif attacking and not moving:
		rifle_pos = Vector3(0.09, 0.47, -0.38) # shouldered, aiming
		rifle_rot = Quaternion.IDENTITY
	elif attacking:
		rifle_pos = Vector3(0.1, 0.12, -0.3) # held forward, bayonet first
		rifle_rot = Quaternion.from_euler(Vector3(0.12, 0.0, 0.0))
	else:
		# Carried across the chest ("port arms"): muzzle up and to the left.
		rifle_pos = Vector3(0.02, 0.2, -0.22)
		rifle_rot = Quaternion(Basis.looking_at(Vector3(-0.55, 0.78, -0.3).normalized(), Vector3.FORWARD))
	if crouch and not officer:
		# EC1: the chest leans forward, so tip the rifle back up – level when aiming, a little
		# down while moving (bayonet first, held low).
		rifle_rot = _x(lean * (1.0 if attacking and not moving else 0.75)) * rifle_rot
	if throwing:
		rifle_pos = Vector3(-0.3, -0.12, -0.18) # hanging in his left hand, muzzle forward and down
		rifle_rot = _x(-0.55)
	# Recoil: the rifle jumps back and up.
	rifle_pos += rifle_rot * Vector3(0, 0.02, 0.07) * _kick
	rifle_rot = rifle_rot * _x(0.18 * _kick)

	var w: float = clampf(delta * pose_speed, 0.0, 1.0)
	for bone in [B.HIPS, B.SPINE, B.HEAD, B.THIGH_L, B.SHIN_L, B.THIGH_R, B.SHIN_R]:
		var target: Quaternion = t.get(bone, Quaternion.IDENTITY)
		_rot[bone] = (_rot[bone] as Quaternion).slerp(target, w)
		_skeleton.set_bone_pose_rotation(bone, _rot[bone])
	_hips_y = lerpf(_hips_y, hips_y, w)
	_skeleton.set_bone_pose_position(B.HIPS, Vector3(0, _hips_y, 0))
	_rifle_pos = _rifle_pos.lerp(rifle_pos, clampf(w + _kick, 0.0, 1.0))
	_rifle_rot = _rifle_rot.slerp(rifle_rot, clampf(w + _kick, 0.0, 1.0))
	_skeleton.set_bone_pose_position(B.RIFLE, _rifle_pos)
	_skeleton.set_bone_pose_rotation(B.RIFLE, _rifle_rot)

	# Arms: right hand on the grip, left hand under the fore-end (dead: hanging down).
	var rifle_xf := Transform3D(Basis(_rifle_rot), _rifle_pos)
	var grip: Vector3 = rifle_xf * Vector3(0.0, -0.05, 0.12)
	var fore_end: Vector3 = rifle_xf * Vector3(0.0, -0.03, -0.3)
	if officer:
		grip = rifle_xf * Vector3(0.0, -0.035, 0.035)
		# Left hand: free (a little forward), or the whistle at his mouth.
		fore_end = Vector3(-0.2, 0.05, -0.12) if not prone else rifle_xf * Vector3(-0.08, -0.06, 0.15)
		if _whistle > 0.0 and not dead:
			fore_end = SoldierMesh.BONE_REST[B.HEAD] + Vector3(-0.02, 0.12, -0.13)
	elif kind == EnemyData.Kind.MG_GUNNER:
		grip = rifle_xf * Vector3(0.0, -0.08, 0.1)
		# Lying behind the DP: left hand holds the butt; otherwise under the shroud.
		fore_end = rifle_xf * (Vector3(0.0, -0.06, 0.24) if prone else Vector3(0.0, -0.025, -0.2))
	if dead and not prone:
		grip = SoldierMesh.BONE_REST[B.UPPER_ARM_R] + Vector3(0.05, -0.55, 0.0)
		fore_end = SoldierMesh.BONE_REST[B.UPPER_ARM_L] + Vector3(-0.05, -0.55, 0.0)
	var pole_r := Vector3(0.5, -1.0, 0.4)
	if throwing:
		grip = _throw_swing().hand # GR1: the throwing arm
		fore_end = rifle_xf * Vector3(0.0, -0.03, -0.08)
		pole_r = Vector3(0.8, -0.3, 0.6) # elbow out to the side and back
	_reach(B.UPPER_ARM_R, B.FOREARM_R, grip, pole_r)
	_reach(B.UPPER_ARM_L, B.FOREARM_L, fore_end, Vector3(-0.6, -1.0, 0.2))


## GR1: the throwing arm at this moment of the throw: {hand: chest-space point, lean: radians}.
## Arm back and up behind the head → fast swing over the shoulder (the grenade leaves the hand
## at `grenade_release_at`) → follow through down in front of him.
func _throw_swing() -> Dictionary:
	var release: float = _enemy.data.grenade_release_at if _enemy and _enemy.data else 0.62
	var windup: float = _enemy.data.grenade_windup if _enemy and _enemy.data else 1.0
	var back := Vector3(0.3, 0.72, 0.34)   # cocked: hand high behind the shoulder
	var front := Vector3(0.18, 0.78, -0.4) # let go: arm up and forward
	var down := Vector3(0.12, 0.12, -0.38) # follow-through
	var cock_end: float = release * 0.7
	if _throw_t < cock_end:
		var k: float = smoothstep(0.0, 1.0, _throw_t / cock_end)
		return {"hand": Vector3(0.2, 0.25, -0.15).lerp(back, k), "lean": lerpf(0.0, -0.18, k)}
	if _throw_t < release:
		var k: float = (_throw_t - cock_end) / (release - cock_end)
		return {"hand": back.lerp(front, k * k), "lean": lerpf(-0.18, 0.3, k)}
	var k: float = smoothstep(0.0, 1.0, (_throw_t - release) / maxf(windup - release, 0.01))
	return {"hand": front.lerp(down, k), "lean": lerpf(0.3, 0.1, k)}


## GR1: the grenade in his right hand – shown from the start of the throw until it leaves the hand.
func _update_hand_grenade(throwing: bool) -> void:
	var release: float = _enemy.data.grenade_release_at if _enemy and _enemy.data else 0.62
	var show: bool = throwing and _throw_t < release
	if show and _hand_grenade == null:
		var attach := BoneAttachment3D.new()
		attach.name = "HandAttach"
		_skeleton.add_child(attach)
		attach.bone_name = SoldierMesh.BONE_NAMES[B.FOREARM_R]
		_hand_grenade = GrenadeManager.make_grenade(true)
		_hand_grenade.position = Vector3(0.0, -SoldierMesh.ARM_LOWER + 0.03, -0.02)
		attach.add_child(_hand_grenade)
	if _hand_grenade:
		_hand_grenade.visible = show


## Two-bone arm (shared with the Finns' PlayerBody: SoldierMesh.reach).
func _reach(upper: int, fore: int, target: Vector3, pole: Vector3) -> void:
	SoldierMesh.reach(_skeleton, upper, fore, target, pole)


const PRONE_HIPS_Y: float = 0.2
const CROUCH_HIPS_Y: float = 0.6 ## EC1: hip height while crouching (standing 0.95, kneeling 0.53).
const CROUCH_THIGH: float = 1.1 ## EC1: thighs forward (radians)...
const CROUCH_SHIN: float = -1.8 ## ...shins folded back.
const CROUCH_LEAN: float = 0.55 ## EC1: upper body forward (radians).
const PRONE_HIPS_PITCH: float = -1.45 ## Whole body tipped forward (radians).
const PRONE_CHEST_UP: float = 0.3 ## Chest lifted off the snow (radians).


func _x(angle: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, angle)


## Small white puffs in front of the mouth (frost). Also used by the player.
static func make_breath_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Breath"
	p.emitting = false
	p.one_shot = true
	p.amount = 4
	p.lifetime = 1.2
	p.explosiveness = 0.6
	p.local_coords = false
	p.direction = Vector3(0, -0.1, -1)
	p.spread = 25.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.5
	p.damping_min = 0.3
	p.damping_max = 0.5
	p.gravity = Vector3(0.15, 0.12, 0.05)
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.95, 0.97, 1.0, 0.12)) # a faint white puff, nothing more
	fade.set_color(1, Color(0.95, 0.97, 1.0, 0.0))
	p.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = ImpactEffects.make_soft_texture()
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ImpactEffects.web_fallback(p)
	return p
