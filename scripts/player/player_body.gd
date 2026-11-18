class_name PlayerBody
extends Node3D
## NET2b: the Finnish soldier body the OTHER players see (child "Body" of Player, made in code).
## Your own body stays hidden – you look out of its eyes and see the first-person arms instead.
##
## Picture only: it runs on every computer and only READS what the network already sends
## (position, view direction, crouch, sprint, aim, weapon slot, reload, Maxim, Molotov phase,
## grenade grab, climbing, bandaging, dead) – no new network traffic, no collision (bullets
## still hit the player's invisible capsule).
##
## The mesh is FinnMesh on the same 12-bone skeleton as the Soviet soldiers, and the arms use
## the same two-bone "IK" (SoldierMesh.reach): we put the hands where they should be and the
## elbows are worked out. When the hands are busy (Maxim, bottle, grenade, climbing, bandage)
## the gun goes onto his back.

const B := SoldierMesh.Bone

@export var pose_speed: float = 10.0 ## How fast he changes from one pose to another.
@export var stride_m: float = 0.85 ## Distance per step.
@export var material: ShaderMaterial ## soldier.gdshader (each body gets its own copy).
## Show the body even for your own player (screenshots / tests).
@export var force_visible: bool = false

var muzzle: Marker3D ## Where the other players see his shots come from.
var gun: int = FinnMesh.Gun.MOSIN ## Which gun is in his hands now.

var _player: Player
var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _attach: BoneAttachment3D
var _bottle: MeshInstance3D # the Molotov in his right hand
var _last_pos: Vector3
var _speed: float = 0.0
var _phase: float = 0.0 # walk cycle, one step = PI
var _kick: float = 0.0
var _rot: Dictionary = {} # bone -> current Quaternion (smoothed)
var _gun_pos: Vector3
var _gun_rot: Quaternion = Quaternion.IDENTITY
var _hips_y: float = 0.95
var _was_dead: bool = false
var _fall_tween: Tween
var _molotov_phase: int = 0
var _molotov_t: float = 0.0 # seconds since the Molotov phase changed
var _grab_t: float = 0.0 # seconds since he grabbed a grenade (GR2)
var _was_grabbing: bool = false
# NET3: his view arrives from his computer in small steps – the body turns and looks after it
# smoothly (picture only, every computer).
var _shown_yaw: float = 0.0
var _shown_pitch: float = 0.0
var _view_started: bool = false
## NET3: how quickly the body follows his view (1/s): ~40 ms behind, no visible steps.
@export var view_smoothing: float = 25.0

# The smock was not the same white on everybody (washing, wear).
const SMOCK_TINTS: Array[Color] = [Color(1, 1, 1), Color(0.97, 0.97, 0.94), Color(1.02, 1.01, 0.98),
		Color(0.94, 0.94, 0.92)]


func _ready() -> void:
	_player = get_parent() as Player
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton"
	add_child(_skeleton)
	SoldierMesh.setup_skeleton(_skeleton)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = FinnMesh.get_mesh(gun)
	_skeleton.add_child(_mesh)
	_mesh.skeleton = NodePath("..")
	if material == null:
		material = load("res://resources/materials/soldier.tres")
	var m: ShaderMaterial = material.duplicate()
	var n: int = absi(hash(str(_player.name) if _player else "")) # same on every computer
	m.set_shader_parameter("coat_tint", SMOCK_TINTS[n % SMOCK_TINTS.size()])
	_mesh.material_override = m

	_attach = BoneAttachment3D.new()
	_attach.name = "GunAttach"
	_skeleton.add_child(_attach)
	_attach.bone_name = SoldierMesh.BONE_NAMES[B.RIFLE]
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = FinnMesh.muzzle_for(gun)
	_attach.add_child(muzzle)

	for i in SoldierMesh.BONE_NAMES.size():
		_rot[i] = Quaternion.IDENTITY
	_gun_pos = SoldierMesh.BONE_REST[B.RIFLE]
	_last_pos = global_position
	_update_visible()


## His shot: the gun kicks back (called on the other computers with the muzzle flash).
func play_fire() -> void:
	_kick = 1.0


## True when this body is drawn on this computer (every player but your own).
func is_shown() -> bool:
	return visible


func _update_visible() -> void:
	var show: bool = force_visible or _player == null or not _player.is_local_player()
	if visible != show:
		visible = show
	set_process(show)


func _process(delta: float) -> void:
	if _player == null:
		return
	_update_visible()
	if not visible:
		return
	var pos: Vector3 = _player.global_position
	var moved: Vector3 = pos - _last_pos
	moved.y = 0.0
	_last_pos = pos
	if moved.length() > 3.0:
		moved = Vector3.ZERO # a respawn / teleport, not a step
	var instant: float = moved.length() / maxf(delta, 0.0001)
	_speed = lerpf(_speed, minf(instant, 8.0), clampf(delta * 8.0, 0.0, 1.0))
	_phase += moved.length() / stride_m * PI
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_smooth_view(delta)
	_update_gun()
	_update_timers(delta)
	_update_fall()
	_pose(delta)


## NET3: the skeleton turns after his synced view yaw; the pitch glides the same way.
func _smooth_view(delta: float) -> void:
	var yaw: float = _player.global_rotation.y
	var pitch: float = _player.input.look_pitch
	if not _view_started:
		_view_started = true
		_shown_yaw = yaw
		_shown_pitch = pitch
	var k: float = 1.0 - exp(-delta * view_smoothing)
	_shown_yaw = lerp_angle(_shown_yaw, yaw, k)
	_shown_pitch = lerpf(_shown_pitch, pitch, k)
	_skeleton.rotation.y = wrapf(_shown_yaw - yaw, -PI, PI)


## Which gun he holds: the weapon slot that is synced anyway.
func _update_gun() -> void:
	var w: WeaponData = null
	var wc: WeaponController = _player.weapons
	if wc and wc.current_slot >= 0 and wc.current_slot < wc.loadout.size():
		w = wc.loadout[wc.current_slot]
	var want: int = FinnMesh.Gun.SUOMI if w and w.recording_name == "suomi" else FinnMesh.Gun.MOSIN
	if want != gun:
		gun = want
		_mesh.mesh = FinnMesh.get_mesh(gun)
		muzzle.position = FinnMesh.muzzle_for(gun)


func _update_timers(delta: float) -> void:
	var phase: int = _player.molotov.phase if _player.molotov else 0
	if phase != _molotov_phase:
		_molotov_phase = phase
		_molotov_t = 0.0
	_molotov_t += delta
	var grabbing: bool = _player.grab != null and _player.grab.is_busy()
	if grabbing and not _was_grabbing:
		_grab_t = 0.0
	_was_grabbing = grabbing
	_grab_t += delta


## Dead: the whole body tips over, like the Soviets (direction from his name, so every computer
## shows the same fall). Back on his feet when he respawns.
func _update_fall() -> void:
	var dead: bool = _player.is_dead
	if dead == _was_dead:
		return
	_was_dead = dead
	if _fall_tween:
		_fall_tween.kill()
		_fall_tween = null
	if not dead:
		rotation = Vector3.ZERO
		return
	var h: int = absi(hash(str(_player.name)))
	var fall_x: float = deg_to_rad(86.0) if h % 10 < 6 else deg_to_rad(-84.0)
	_fall_tween = create_tween().set_parallel(true)
	_fall_tween.tween_property(self, "rotation:x", fall_x, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall_tween.tween_property(self, "rotation:y", ((h / 10) % 9 - 4) * 0.1, 0.55)


## What his hands are doing now.
enum Hands { GUN, MAXIM, BOTTLE, GRENADE, CLIMB, BANDAGE, DEAD }


func _hands() -> Hands:
	if _player.is_dead:
		return Hands.DEAD
	if _player.is_climbing:
		return Hands.CLIMB
	if _player.get_mounted_gun():
		return Hands.MAXIM
	if _player.grab and _player.grab.is_busy():
		return Hands.GRENADE
	if _player.molotov and _player.molotov.phase != MolotovHandler.Phase.NONE:
		return Hands.BOTTLE
	if _player.is_bandaging:
		return Hands.BANDAGE
	return Hands.GUN


func _pose(delta: float) -> void:
	var hands: Hands = _hands()
	var dead: bool = hands == Hands.DEAD
	var crouch: bool = _player.is_crouching and not dead
	var moving: bool = _speed > 0.4 and not dead
	var running: bool = _player.is_sprinting and moving
	var aiming: bool = _player.input.aim_held and hands == Hands.GUN
	var reloading: bool = _player.weapons.is_reloading and hands == Hands.GUN
	# Looking up / down: the chest takes 40 %, the head and the gun the rest.
	var pitch: float = 0.0 if dead else clampf(_shown_pitch, -1.2, 1.2)
	if hands == Hands.MAXIM:
		pitch *= 0.3

	var t := {}
	var hips_y: float = 0.95
	var lean: float = 0.0 # forward lean of the upper body (radians)
	if dead:
		pass # limp: everything goes back to straight, the whole body tips over (_update_fall)
	elif crouch and not moving:
		# Down on the right knee, left foot forward.
		hips_y = 0.5
		t[B.THIGH_L] = _x(1.5)
		t[B.SHIN_L] = _x(-1.5)
		t[B.THIGH_R] = _x(-0.1)
		t[B.SHIN_R] = _x(-1.5)
		lean = 0.4
	elif crouch:
		# Moving bent low: deep knees, short steps.
		var s: float = sin(_phase)
		hips_y = 0.52 + absf(cos(_phase)) * 0.02
		t[B.THIGH_L] = _x(1.25 + s * 0.22)
		t[B.THIGH_R] = _x(1.25 - s * 0.22)
		t[B.SHIN_L] = _x(-1.95 + maxf(0.0, cos(_phase)) * 0.2)
		t[B.SHIN_R] = _x(-1.95 + maxf(0.0, -cos(_phase)) * 0.2)
		lean = 0.45
	elif moving:
		var amp: float = clampf(_speed * 0.13, 0.22, 0.6)
		var s: float = sin(_phase)
		t[B.THIGH_L] = _x(s * amp)
		t[B.THIGH_R] = _x(-s * amp)
		t[B.SHIN_L] = _x(-maxf(0.0, cos(_phase)) * amp * 1.4)
		t[B.SHIN_R] = _x(-maxf(0.0, -cos(_phase)) * amp * 1.4)
		hips_y = 0.95 - 0.02 + absf(cos(_phase)) * 0.025
		lean = 0.05 + _speed * 0.04
	if hands == Hands.CLIMB:
		# Hauling himself over the edge: chest forward on the parapet, one knee up.
		lean = 0.55
		t[B.THIGH_L] = _x(1.3)
		t[B.SHIN_L] = _x(-1.6)
		t[B.THIGH_R] = _x(0.2)
		t[B.SHIN_R] = _x(-0.4)
		hips_y = 0.95
	t[B.HIPS] = Quaternion.IDENTITY
	t[B.SPINE] = _x(-lean + pitch * 0.4) # negative = top of the body forward
	t[B.HEAD] = _x(lean * 0.7 + pitch * 0.6) # keep looking where the player looks

	# Where the gun is (chest space), and where each hand goes.
	var gun_pos: Vector3
	var gun_rot: Quaternion
	var on_back: bool = hands != Hands.GUN and hands != Hands.DEAD
	var ready: bool = false # the gun held low in front of him (left hand a little further back)
	if dead:
		# Lies ALONG the body, a little to the side: flat on the snow next to him after the fall.
		gun_pos = Vector3(0.42, -0.25, 0.0)
		gun_rot = Quaternion.from_euler(Vector3(PI / 2.0, 0.12, 0.0))
	elif on_back:
		# Slung across the back, muzzle up over the left shoulder.
		gun_pos = Vector3(0.0, 0.2, 0.2)
		gun_rot = Quaternion(Basis.looking_at(Vector3(-0.45, 0.85, 0.1).normalized(), Vector3.BACK))
	elif reloading:
		gun_pos = Vector3(0.06, 0.18, -0.32) # lowered, tipped so he can reach the magazine
		gun_rot = Quaternion.from_euler(Vector3(0.25, 0.0, 0.5))
	elif running:
		# Carried across the chest, muzzle up and to the left.
		gun_pos = Vector3(0.02, 0.2, -0.22)
		gun_rot = Quaternion(Basis.looking_at(Vector3(-0.55, 0.78, -0.3).normalized(), Vector3.FORWARD))
	else:
		# Aiming: shouldered. Otherwise held ready at the hip/chest. Both follow his view.
		# (Ready: close to the chest, muzzle a little down – the hands must reach it.)
		var pivot := Vector3(0.1, 0.45, 0.0)
		# Ready: butt under the right arm, muzzle down in front of him.
		var at: Vector3 = Vector3(0.09, 0.47, -0.36) if aiming else Vector3(0.05, 0.24, -0.26)
		var down: float = 0.0 if aiming else -0.45
		if gun == FinnMesh.Gun.SUOMI and not aiming:
			at = Vector3(0.06, 0.26, -0.26)
			down = -0.3
		ready = not aiming
		var tilt: Quaternion = _x(pitch * 0.6)
		gun_pos = pivot + tilt * (at - pivot)
		gun_rot = tilt * _x(down)
	# Recoil: the gun jumps back and up.
	gun_pos += gun_rot * Vector3(0, 0.02, 0.06) * _kick
	gun_rot = gun_rot * _x(0.15 * _kick)

	var w: float = clampf(delta * pose_speed, 0.0, 1.0)
	for bone in [B.HIPS, B.SPINE, B.HEAD, B.THIGH_L, B.SHIN_L, B.THIGH_R, B.SHIN_R]:
		var target: Quaternion = t.get(bone, Quaternion.IDENTITY)
		_rot[bone] = (_rot[bone] as Quaternion).slerp(target, w)
		_skeleton.set_bone_pose_rotation(bone, _rot[bone])
	_hips_y = lerpf(_hips_y, hips_y, w)
	_skeleton.set_bone_pose_position(B.HIPS, Vector3(0, _hips_y, 0))
	var gw: float = clampf(w + _kick, 0.0, 1.0)
	_gun_pos = _gun_pos.lerp(gun_pos, gw)
	_gun_rot = _gun_rot.slerp(gun_rot, gw)
	_skeleton.set_bone_pose_position(B.RIFLE, _gun_pos)
	_skeleton.set_bone_pose_rotation(B.RIFLE, _gun_rot)

	var gun_xf := Transform3D(Basis(_gun_rot), _gun_pos)
	var right: Vector3 = gun_xf * FinnMesh.grip_for(gun)
	var left: Vector3 = gun_xf * FinnMesh.fore_for(gun)
	if ready and gun == FinnMesh.Gun.MOSIN:
		left = gun_xf * (FinnMesh.fore_for(gun) + Vector3(0, 0, 0.1))
	var pole_r := Vector3(0.5, -1.0, 0.4)
	var pole_l := Vector3(-0.6, -1.0, 0.2)
	var show_bottle: bool = false
	match hands:
		Hands.DEAD:
			right = SoldierMesh.BONE_REST[B.UPPER_ARM_R] + Vector3(0.05, -0.55, 0.0)
			left = SoldierMesh.BONE_REST[B.UPPER_ARM_L] + Vector3(-0.05, -0.55, 0.0)
		Hands.MAXIM:
			var grips: Array[Transform3D] = _player.get_mounted_gun().get_hand_grips()
			var chest: Transform3D = _chest_global()
			right = chest.affine_inverse() * grips[0].origin
			left = chest.affine_inverse() * grips[1].origin
			pole_r = Vector3(0.6, -1.0, 0.2)
			pole_l = Vector3(-0.6, -1.0, 0.2)
		Hands.CLIMB:
			right = Vector3(0.22, 0.45, -0.5)
			left = Vector3(-0.22, 0.45, -0.5)
			pole_r = Vector3(0.8, 0.0, 0.3)
			pole_l = Vector3(-0.8, 0.0, 0.3)
		Hands.BANDAGE:
			right = Vector3(-0.12, 0.22, -0.22) # winding the bandage round his left forearm
			left = Vector3(-0.05, 0.16, -0.3)
		Hands.BOTTLE:
			show_bottle = _molotov_phase != MolotovHandler.Phase.THROWING or _molotov_t < 0.15
			right = Vector3(0.16, 0.22, -0.32)
			left = Vector3(-0.2, -0.05, -0.12)
			if _molotov_phase == MolotovHandler.Phase.IGNITING:
				left = Vector3(0.1, 0.25, -0.36) # the match to the rag
			elif _molotov_phase == MolotovHandler.Phase.THROWING:
				right = _throw_hand(_molotov_t, 0.15, 0.45)
				pole_r = Vector3(0.8, -0.3, 0.6)
		Hands.GRENADE:
			right = _throw_hand(_grab_t, _player.grab.throw_at, _player.grab.throw_at + 0.35)
			left = Vector3(-0.2, 0.1, -0.25)
			pole_r = Vector3(0.8, -0.3, 0.6)
	_update_bottle(show_bottle)
	SoldierMesh.reach(_skeleton, B.UPPER_ARM_R, B.FOREARM_R, right, pole_r)
	SoldierMesh.reach(_skeleton, B.UPPER_ARM_L, B.FOREARM_L, left, pole_l)


## Overhand throw (chest space): hand back behind the shoulder → over the top, letting go at
## `release` seconds → follow-through down in front of him by `done`.
func _throw_hand(time: float, release: float, done: float) -> Vector3:
	var back := Vector3(0.3, 0.7, 0.3)
	var front := Vector3(0.18, 0.76, -0.4)
	var down := Vector3(0.12, 0.15, -0.38)
	var cock_end: float = release * 0.6
	if time < cock_end:
		return Vector3(0.16, 0.25, -0.3).lerp(back, smoothstep(0.0, 1.0, time / maxf(cock_end, 0.01)))
	if time < release:
		var k: float = (time - cock_end) / maxf(release - cock_end, 0.01)
		return back.lerp(front, k * k)
	return front.lerp(down, smoothstep(0.0, 1.0, (time - release) / maxf(done - release, 0.01)))


## The chest (spine bone) in world space, worked out from the targets of this frame's pose.
func _chest_global() -> Transform3D:
	var hips := Transform3D(Basis(_rot[B.HIPS]), Vector3(0, _hips_y, 0))
	var spine := Transform3D(Basis(_rot[B.SPINE]), SoldierMesh.BONE_REST[B.SPINE])
	return _skeleton.global_transform * hips * spine


## The Molotov bottle in his right hand (made the first time it is needed).
func _update_bottle(show: bool) -> void:
	if show and _bottle == null:
		var attach := BoneAttachment3D.new()
		attach.name = "HandAttach"
		_skeleton.add_child(attach)
		attach.bone_name = SoldierMesh.BONE_NAMES[B.FOREARM_R]
		_bottle = MeshInstance3D.new()
		_bottle.name = "Bottle"
		var c := CylinderMesh.new()
		c.top_radius = 0.022
		c.bottom_radius = 0.035
		c.height = 0.2
		c.radial_segments = 6
		c.rings = 1
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.22, 0.3, 0.2)
		m.roughness = 0.3
		c.material = m
		_bottle.mesh = c
		_bottle.position = Vector3(0.0, -SoldierMesh.ARM_LOWER + 0.02, -0.03)
		_bottle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		attach.add_child(_bottle)
	if _bottle:
		_bottle.visible = show


func _x(angle: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, angle)
