class_name SoldierVisual
extends Node3D
## What a Soviet soldier looks like and how he moves (the "Visual" child of Enemy).
##
## The body is the SoldierMesh on a Skeleton3D. This script poses the bones in code every
## frame: walking/running legs, kneeling to fire, rifle carried / held forward / shouldered,
## recoil, and the arms always reaching for the rifle (simple "IK": we place the hands and
## work out the elbows). It also plays his footsteps and breath vapour when you are near.
##
## Runs on EVERY computer and only reads what the host syncs (position, state, kneeling),
## so all players see the same soldier doing the same thing.

const B := SoldierMesh.Bone

@export var pose_speed: float = 10.0 ## How fast he changes from one pose to another.
@export var stride_m: float = 0.8 ## Distance per step.
@export var effects_distance: float = 30.0 ## Footsteps and breath only when you are this close.
@export var material: ShaderMaterial ## soldier.gdshader; each soldier gets his own copy (coat tint).

var muzzle: Marker3D ## Where his shots come from (follows the rifle).

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
var _breath_timer: float = 0.0
var _rot: Dictionary = {} # bone -> current Quaternion (smoothed)
var _rifle_pos: Vector3
var _rifle_rot: Quaternion = Quaternion.IDENTITY
var _hips_y: float = 0.95
var _rng := RandomNumberGenerator.new()

# Coats were not all the same colour: grey-brown, greener, darker.
const COAT_TINTS: Array[Color] = [Color(1, 1, 1), Color(0.92, 0.97, 0.9), Color(1.05, 1.0, 0.95),
		Color(0.85, 0.85, 0.85), Color(0.95, 0.92, 0.98)]


func _ready() -> void:
	_rng.randomize()
	_enemy = get_parent() as Enemy
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton"
	add_child(_skeleton)
	SoldierMesh.setup_skeleton(_skeleton)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Body"
	_mesh.mesh = SoldierMesh.get_mesh()
	_skeleton.add_child(_mesh)
	_mesh.skeleton = NodePath("..")
	if material:
		var m: ShaderMaterial = material.duplicate()
		m.set_shader_parameter("coat_tint", COAT_TINTS[_rng.randi() % COAT_TINTS.size()])
		_mesh.material_override = m
	_skeleton.scale = Vector3.ONE * _rng.randf_range(0.95, 1.06) # not all the same height

	var attach := BoneAttachment3D.new()
	attach.name = "RifleAttach"
	_skeleton.add_child(attach)
	attach.bone_name = SoldierMesh.BONE_NAMES[B.RIFLE]
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = SoldierMesh.MUZZLE
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
		for i in 3:
			_step_sounds.append(load("res://assets/audio/step_snow_%d.wav" % (i + 1)))
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
	var near: bool = _is_near_camera()
	if near and int(_phase / PI) != steps_before and _speed > 0.5:
		_play_step()
	if near and _enemy.state != Enemy.State.DEAD:
		_breath_timer -= delta
		if _breath_timer <= 0.0:
			_breath.restart()
			_breath_timer = _rng.randf_range(2.0, 3.5) if _speed < 2.5 else _rng.randf_range(1.0, 1.6)
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_hit = move_toward(_hit, 0.0, delta * 3.0)
	var dead: bool = _enemy.state == Enemy.State.DEAD
	if dead and not _was_dead and near:
		# The thud of the body falling into the snow.
		_footsteps.stream = _step_sounds[0]
		_footsteps.pitch_scale = 0.55
		_footsteps.volume_db = -2.0
		get_tree().create_timer(0.45).timeout.connect(_footsteps.play)
	_was_dead = dead
	_pose(delta)


func _is_near_camera() -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.global_position.distance_to(global_position) < effects_distance


func _play_step() -> void:
	_footsteps.stream = _step_sounds[_rng.randi() % _step_sounds.size()]
	_footsteps.pitch_scale = _rng.randf_range(0.9, 1.1)
	_footsteps.volume_db = -8.0
	_footsteps.play()


# ------------------------------------------------------------------ posing
func _pose(delta: float) -> void:
	var state: Enemy.State = _enemy.state
	var dead: bool = state == Enemy.State.DEAD
	var moving: bool = _speed > 0.4 and not dead
	var kneel: bool = _enemy.is_kneeling and not moving and not dead
	var attacking: bool = state == Enemy.State.ATTACK or state == Enemy.State.ALERT

	# Targets for this frame.
	var t := {}
	var hips_y: float = 0.95
	var lean: float = 0.0 # forward lean of the upper body (radians)
	if dead:
		pass # limp: everything goes back to straight, the Enemy tips the whole body over
	elif kneel:
		# Left foot forward, right knee on the snow.
		hips_y = 0.53
		t[B.THIGH_L] = _x(1.45)
		t[B.SHIN_L] = _x(-1.5)
		t[B.THIGH_R] = _x(-0.15)
		t[B.SHIN_R] = _x(-1.45)
		lean = 0.12
	elif moving:
		var amp: float = clampf(_speed * 0.15, 0.22, 0.52)
		var s: float = sin(_phase)
		t[B.THIGH_L] = _x(s * amp)
		t[B.THIGH_R] = _x(-s * amp)
		t[B.SHIN_L] = _x(-maxf(0.0, cos(_phase)) * amp * 1.4)
		t[B.SHIN_R] = _x(-maxf(0.0, -cos(_phase)) * amp * 1.4)
		hips_y = 0.95 - 0.02 + absf(cos(_phase)) * 0.025
		lean = 0.05 + _speed * 0.05
	t[B.SPINE] = _x(-lean + _hit * 0.35) # negative = top of the body forward; a hit pushes it back
	t[B.HIPS] = Quaternion.IDENTITY
	t[B.HEAD] = _x(lean * 0.6 + (0.08 if kneel else 0.0)) # keep looking ahead

	# Where the rifle is (relative to the chest).
	var rifle_pos: Vector3
	var rifle_rot: Quaternion
	if dead:
		rifle_pos = Vector3(0.25, -0.3, -0.1)
		rifle_rot = Quaternion.from_euler(Vector3(0.3, 0.0, 1.2))
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
	if dead:
		grip = SoldierMesh.BONE_REST[B.UPPER_ARM_R] + Vector3(0.05, -0.55, 0.0)
		fore_end = SoldierMesh.BONE_REST[B.UPPER_ARM_L] + Vector3(-0.05, -0.55, 0.0)
	_reach(B.UPPER_ARM_R, B.FOREARM_R, grip, Vector3(0.5, -1.0, 0.4))
	_reach(B.UPPER_ARM_L, B.FOREARM_L, fore_end, Vector3(-0.6, -1.0, 0.2))


## Two-bone arm: shoulder → elbow → hand. Puts the hand at `target` (chest space) with the
## elbow bending towards `pole`.
func _reach(upper: int, fore: int, target: Vector3, pole: Vector3) -> void:
	var shoulder: Vector3 = SoldierMesh.BONE_REST[upper]
	var to_target: Vector3 = target - shoulder
	var dist: float = clampf(to_target.length(), 0.05, SoldierMesh.ARM_UPPER + SoldierMesh.ARM_LOWER - 0.001)
	var dir: Vector3 = to_target.normalized()
	var l1: float = SoldierMesh.ARM_UPPER
	var l2: float = SoldierMesh.ARM_LOWER
	# Law of cosines: angle between the upper arm and the shoulder→hand line.
	var cos_a: float = clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var bend: Vector3 = pole.normalized() - dir * dir.dot(pole.normalized())
	bend = bend.normalized() if bend.length() > 0.001 else Vector3.DOWN
	var elbow: Vector3 = shoulder + dir * (l1 * cos_a) + bend * (l1 * sqrt(1.0 - cos_a * cos_a))
	var hand: Vector3 = shoulder + dir * dist
	var upper_q := Quaternion(Vector3.DOWN, (elbow - shoulder).normalized())
	var fore_q := upper_q.inverse() * Quaternion(Vector3.DOWN, (hand - elbow).normalized())
	_skeleton.set_bone_pose_rotation(upper, upper_q)
	_skeleton.set_bone_pose_rotation(fore, fore_q)


func _x(angle: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, angle)


## Small white puffs in front of the mouth (frost). Also used by the player.
static func make_breath_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Breath"
	p.emitting = false
	p.one_shot = true
	p.amount = 6
	p.lifetime = 1.4
	p.explosiveness = 0.6
	p.local_coords = false
	p.direction = Vector3(0, 0.2, -1)
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
	fade.set_color(0, Color(0.95, 0.97, 1.0, 0.3))
	fade.set_color(1, Color(0.95, 0.97, 1.0, 0.0))
	p.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
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
