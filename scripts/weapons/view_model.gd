class_name ViewModel
extends Node3D
## The first-person model of a weapon (only drawn for the player on this computer).
## Plays simple code-driven animations: recoil kick, bolt cycling, reloading, raising.
## Expected children: Model (with AimPoint, Muzzle/MuzzleFlash, Muzzle/FlashLight, and the
## hand positions GripR / GripL / BoltGrip used by FirstPersonArms).
## The visible gun is an imported 3D model (Model/Mesh). Its moving parts are found by
## name when the game starts (`bolt_part_names`), and loose extra parts can be hidden.

@export var bolt: Node3D ## Optional part that slides back when the bolt is worked.
## Parts of the imported model that form the bolt: they are gathered into one "Bolt" node.
@export var bolt_part_names: PackedStringArray = PackedStringArray()
## Parts of the imported model that should not be shown (e.g. loose cartridges).
@export var hidden_part_names: PackedStringArray = PackedStringArray()
@export var bolt_travel: float = 0.08 ## How far the bolt slides back (metres).
@export var flash_duration: float = 0.05
@export var ads_eye_distance: float = 0.3 ## When aiming, the rear sight sits this far in front of the eye.
@export var hip_offset: Vector3 = Vector3.ZERO ## Moves this gun from the standard hip position.
@export var reload_with_right_hand: bool = false ## Which hand fetches new ammo (Mosin: right, Suomi: left).
## Part of the imported model that is the magazine (Suomi: the drum). If set, the left hand
## holds it (GripL is on it) and the reload really changes it: pull it out, drop it, fetch a
## new one from the pouch and push it in. Empty = the hand only dips to the pouch.
@export var magazine_part_name: String = ""
@export var reload_offset: Vector3 = Vector3(-0.03, -0.12, 0.05) ## Where the gun is moved while reloading.
@export var reload_rotation_deg: Vector3 = Vector3(15.0, 0.0, -35.0) ## How the gun is turned while reloading (degrees).
@export var magazine_pull_m: float = 0.14 ## How far the magazine is pulled down out of the gun.
@export var magazine_drop_lifetime: float = 15.0 ## Seconds a dropped magazine stays on the ground.

const MAX_DROPPED_MAGAZINES: int = 4
## Magazine reload, as parts of the reload time: [pulled out, dropped, at the pouch,
## new one in the hand, under the gun, pushed in].
const MAG_STEPS: Array[float] = [0.24, 0.27, 0.42, 0.49, 0.66, 0.76]
const MAG_PULL_START: float = 0.12
const MAG_GRAB_AT: float = 0.46 # the new magazine appears in the hand (at the pouch)
## Where the reloading hand goes (the ammo pouch), in the space of the node holding the gun.
const POUCH_RIGHT := Vector3(0.12, -0.5, 0.25)
const POUCH_LEFT := Vector3(-0.3, -0.5, 0.2)

static var _dropped_magazines: Array[Node3D] = []

## 0..1: how far the right hand has moved from the grip to the bolt handle (bolt-action).
var bolt_hand: float = 0.0
## 0..1: how far the reloading hand has gone down to the ammo pouch.
var reload_hand: float = 0.0
## 0..1 through a magazine change (only guns with `magazine_part_name`); < 0 = not changing.
var magazine_progress: float = -1.0

## Where the rear sight is when the model is at rest (used to line up the sights).
var aim_point_rest: Vector3

# Animation offsets that tweens change; combined with the recoil kick each frame.
var anim_offset: Vector3 = Vector3.ZERO
var anim_rotation: Vector3 = Vector3.ZERO

var _kick_back: float = 0.0
var _kick_rotation: float = 0.0
var _flash_until: float = 0.0
var _bolt_rest: Vector3
var _tween: Tween
var _hand_tween: Tween
var _grip_r: Node3D
var _grip_l: Node3D
var _bolt_grip: Node3D
var _magazine: Node3D            # holder node for the magazine part (moves with the hand)
var _magazine_rest: Transform3D  # its place in the gun (Model space)
var _magazine_in_hand: Transform3D # the magazine relative to the left hand (GripL)
var _magazine_last_pos: Vector3
var _magazine_velocity: Vector3

@onready var model: Node3D = $Model
@onready var flash: Node3D = $Model/Muzzle/MuzzleFlash
@onready var flash_light: OmniLight3D = $Model/Muzzle/FlashLight


func _ready() -> void:
	_prepare_imported_model()
	aim_point_rest = ($Model/AimPoint as Node3D).position
	flash.visible = false
	flash_light.visible = false
	if bolt:
		_bolt_rest = bolt.position
	_grip_r = get_node_or_null("Model/GripR")
	_grip_l = get_node_or_null("Model/GripL")
	_bolt_grip = get_node_or_null("Model/BoltGrip")
	if _bolt_grip and bolt:
		_bolt_grip.reparent(bolt, true) # the hand rides along with the bolt
	if _magazine and _grip_l:
		_magazine_in_hand = _grip_l.transform.affine_inverse() * _magazine_rest


## Where the hands go this frame: [right, left] as global transforms ([] = no grip points).
func get_hand_grips() -> Array[Transform3D]:
	if _grip_r == null or _grip_l == null:
		return []
	var r: Transform3D = _grip_r.global_transform
	var l: Transform3D = _grip_l.global_transform
	if _bolt_grip and bolt_hand > 0.0:
		r = r.interpolate_with(_bolt_grip.global_transform, smoothstep(0.0, 1.0, bolt_hand))
	if magazine_progress >= 0.0 and _magazine:
		l = model.global_transform * _left_hand_on_magazine(magazine_progress)
	elif reload_hand > 0.0:
		var t: float = smoothstep(0.0, 1.0, reload_hand)
		var holder := get_parent() as Node3D
		if reload_with_right_hand:
			r = r.interpolate_with(Transform3D(r.basis, holder.global_transform * POUCH_RIGHT), t)
		else:
			l = l.interpolate_with(Transform3D(l.basis, holder.global_transform * POUCH_LEFT), t)
	return [r, l]


## The left hand during a magazine change, in Model space. `u` = 0..1 through the reload.
func _left_hand_on_magazine(u: float) -> Transform3D:
	var grip: Transform3D = _grip_l.transform
	var below := grip.translated(Vector3(-0.015, -magazine_pull_m, 0.02)) # magazine pulled out
	var holder := get_parent() as Node3D
	var pouch_pos: Vector3 = (model.global_transform.affine_inverse() * holder.global_transform) * POUCH_LEFT
	var pouch := Transform3D(grip.basis, pouch_pos)
	# Key poses and the times they are reached.
	var times: Array[float] = [MAG_PULL_START]
	times.append_array(MAG_STEPS)
	var poses: Array[Transform3D] = [grip, below, below, pouch, pouch, below, grip]
	if u <= times[0]:
		return grip
	for i in range(1, times.size()):
		if u < times[i]:
			var t: float = smoothstep(times[i - 1], times[i], u)
			return poses[i - 1].interpolate_with(poses[i], t)
	return grip


## True while the hand has a magazine: the old one until it is dropped, the new one after
## it was taken from the pouch.
func _magazine_in_hand_at(u: float) -> bool:
	return u < MAG_STEPS[1] or u >= MAG_GRAB_AT


func _process(delta: float) -> void:
	# The kick springs back to rest.
	var settle: float = clampf(delta * 12.0, 0.0, 1.0)
	_kick_back = lerpf(_kick_back, 0.0, settle)
	_kick_rotation = lerpf(_kick_rotation, 0.0, settle)
	model.position = anim_offset + Vector3(0.0, 0.0, _kick_back)
	model.rotation = anim_rotation + Vector3(_kick_rotation, 0.0, 0.0)
	var flashing: bool = _now() < _flash_until
	flash.visible = flashing
	flash_light.visible = flashing
	if _magazine:
		_update_magazine(delta)


## Moves the magazine with the left hand during a reload (and drops the old one).
func _update_magazine(delta: float) -> void:
	if magazine_progress < 0.0:
		_magazine.transform = _magazine_rest
		_magazine.visible = true
	else:
		_magazine.visible = _magazine_in_hand_at(magazine_progress)
		_magazine.transform = _left_hand_on_magazine(magazine_progress) * _magazine_in_hand
	# How fast the magazine moves (a dropped one keeps that speed).
	var pos: Vector3 = _magazine.global_position
	if delta > 0.0:
		_magazine_velocity = ((pos - _magazine_last_pos) / delta).limit_length(4.0)
	_magazine_last_pos = pos


## Sets the magazine-change progress; drops the old magazine when the hand lets go of it.
func _set_magazine_progress(u: float) -> void:
	var before: float = magazine_progress
	magazine_progress = u
	if before >= 0.0 and before < MAG_STEPS[1] and u >= MAG_STEPS[1] and is_visible_in_tree():
		_drop_magazine()


## The empty magazine falls to the ground: a copy of the part on a small physics body
## (only on this computer – nobody else sees your view model anyway).
func _drop_magazine() -> void:
	var body := RigidBody3D.new()
	body.name = "DroppedMagazine"
	body.collision_layer = 0
	body.collision_mask = 1 # the world only (not players or enemies)
	body.mass = 1.0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = magazine_radius()
	cylinder.height = 0.05
	shape.shape = cylinder
	shape.rotation = Vector3(PI / 2.0, 0.0, 0.0) # the drum's axis is the gun's z axis
	body.add_child(shape)
	var copy: Node3D = _magazine.duplicate()
	copy.transform = Transform3D.IDENTITY
	copy.visible = true
	body.add_child(copy)
	var parent: Node = get_tree().get_first_node_in_group("game")
	if parent == null:
		parent = get_tree().root
	parent.add_child(body)
	body.global_transform = Transform3D(_magazine.global_basis.orthonormalized(), _magazine.global_position)
	body.linear_velocity = _magazine_velocity + Vector3(randf_range(-0.3, 0.3), -0.8, 0.0)
	body.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4))
	# Keep only the newest few (forget ones already freed, e.g. after "Play again").
	var kept: Array[Node3D] = []
	for i in _dropped_magazines.size():
		if is_instance_valid(_dropped_magazines[i]):
			kept.append(_dropped_magazines[i])
	kept.append(body)
	while kept.size() > MAX_DROPPED_MAGAZINES:
		kept.pop_front().queue_free()
	_dropped_magazines = kept
	# (a connection to a freed node goes away by itself, so an early free is fine)
	get_tree().create_timer(magazine_drop_lifetime).timeout.connect(body.queue_free)


## Rough radius of the magazine (for the dropped copy's collision shape).
func magazine_radius() -> float:
	var r: float = 0.03
	for mi in _magazine.find_children("*", "VisualInstance3D", true, false):
		var vi := mi as VisualInstance3D
		var to_mag: Transform3D = _magazine.global_transform.affine_inverse() * vi.global_transform
		var box: AABB = to_mag * vi.get_aabb()
		r = maxf(r, maxf(box.size.x, box.size.y) * 0.5)
	return r


## Sets up the imported model: hide extra parts, build the Bolt node, no shadows.
func _prepare_imported_model() -> void:
	var mesh_root: Node = get_node_or_null("Model/Mesh")
	if mesh_root == null:
		return
	for part_name in hidden_part_names:
		var part := mesh_root.find_child(part_name, true, false) as Node3D
		if part:
			part.visible = false
	if magazine_part_name != "":
		var mag_part := mesh_root.find_child(magazine_part_name, true, false) as Node3D
		if mag_part:
			# A holder node at the magazine's centre, so it can move (and spin when dropped).
			_magazine = Node3D.new()
			_magazine.name = "Magazine"
			model.add_child(_magazine)
			_magazine.position = _centre_in_model(mag_part)
			mag_part.reparent(_magazine, true)
			_magazine_rest = _magazine.transform
	if bolt == null and not bolt_part_names.is_empty():
		var new_bolt := Node3D.new()
		new_bolt.name = "Bolt"
		model.add_child(new_bolt)
		for part_name in bolt_part_names:
			var part := mesh_root.find_child(part_name, true, false) as Node3D
			if part:
				part.reparent(new_bolt, true) # keep where it is, but move with the bolt now
		bolt = new_bolt
	# A gun held in front of the camera must not throw shadows on the world.
	for mi in mesh_root.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Centre of a part's meshes in Model space.
func _centre_in_model(part: Node3D) -> Vector3:
	var box := AABB()
	var first: bool = true
	for mi in part.find_children("*", "VisualInstance3D", true, false):
		var vi := mi as VisualInstance3D
		var b: AABB = (model.global_transform.affine_inverse() * vi.global_transform) * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.get_center() if not first else model.to_local(part.global_position)


func play_fire(kick_back_m: float, kick_rotation_deg: float) -> void:
	_kick_back += kick_back_m
	_kick_rotation += deg_to_rad(kick_rotation_deg)
	_flash_until = _now() + flash_duration
	flash.rotation.z = randf() * TAU # vary the flash shape a little


## Bolt-action: tilt the rifle and slide the bolt back and forward.
func play_bolt_cycle(duration: float) -> void:
	_restart_tween()
	var tilt := Vector3(0.0, 0.0, deg_to_rad(-20.0))
	_tween.tween_property(self, "anim_rotation", tilt, duration * 0.2).set_delay(duration * 0.1)
	if bolt:
		_tween.tween_property(bolt, "position", _bolt_rest + Vector3(0, 0, bolt_travel), duration * 0.2)
		_tween.tween_property(bolt, "position", _bolt_rest, duration * 0.2)
	_tween.tween_property(self, "anim_rotation", Vector3.ZERO, duration * 0.2)
	# The right hand leaves the grip, works the bolt and comes back.
	if _bolt_grip:
		_hand_tween = create_tween()
		_hand_tween.tween_property(self, "bolt_hand", 1.0, duration * 0.2).set_delay(duration * 0.06)
		_hand_tween.tween_property(self, "bolt_hand", 0.0, duration * 0.2).set_delay(duration * 0.44)


## Reload: move and tilt the weapon (`reload_offset` / `reload_rotation_deg`), then bring it back.
func play_reload(duration: float) -> void:
	_restart_tween()
	_tween.set_parallel(true)
	var turn := Vector3(deg_to_rad(reload_rotation_deg.x), deg_to_rad(reload_rotation_deg.y), deg_to_rad(reload_rotation_deg.z))
	_tween.tween_property(self, "anim_offset", reload_offset, duration * 0.15)
	_tween.tween_property(self, "anim_rotation", turn, duration * 0.15)
	_tween.chain().tween_property(self, "anim_offset", Vector3.ZERO, duration * 0.15).set_delay(duration * 0.7)
	_tween.tween_property(self, "anim_rotation", Vector3.ZERO, duration * 0.15).set_delay(duration * 0.7)
	_hand_tween = create_tween()
	if _magazine and _grip_l:
		# The left hand pulls the magazine out, drops it, takes a new one and pushes it in.
		_set_magazine_progress(0.0)
		_hand_tween.tween_method(_set_magazine_progress, 0.0, 1.0, duration)
		_hand_tween.tween_callback(_set_magazine_progress.bind(-1.0))
		return
	# One hand goes down to the ammo pouch and comes back with a clip.
	_hand_tween.tween_property(self, "reload_hand", 1.0, duration * 0.2).set_delay(duration * 0.08)
	_hand_tween.tween_property(self, "reload_hand", 0.0, duration * 0.25).set_delay(duration * 0.15)


## Weapon switched in: start low and raise it.
func play_raise(duration: float = 0.35) -> void:
	_restart_tween()
	anim_offset = Vector3(0, -0.25, 0)
	anim_rotation = Vector3(deg_to_rad(-30), 0, 0)
	_tween.set_parallel(true)
	_tween.tween_property(self, "anim_offset", Vector3.ZERO, duration).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "anim_rotation", Vector3.ZERO, duration).set_ease(Tween.EASE_OUT)


func _restart_tween() -> void:
	if _tween:
		_tween.kill()
	if _hand_tween:
		_hand_tween.kill()
	bolt_hand = 0.0
	reload_hand = 0.0
	magazine_progress = -1.0
	if bolt:
		bolt.position = _bolt_rest
	_tween = create_tween()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
