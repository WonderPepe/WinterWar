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

## 0..1: how far the right hand has moved from the grip to the bolt handle (bolt-action).
var bolt_hand: float = 0.0
## 0..1: how far the reloading hand has gone down to the ammo pouch.
var reload_hand: float = 0.0

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


## Where the hands go this frame: [right, left] as global transforms ([] = no grip points).
func get_hand_grips() -> Array[Transform3D]:
	if _grip_r == null or _grip_l == null:
		return []
	var r: Transform3D = _grip_r.global_transform
	var l: Transform3D = _grip_l.global_transform
	if _bolt_grip and bolt_hand > 0.0:
		r = r.interpolate_with(_bolt_grip.global_transform, smoothstep(0.0, 1.0, bolt_hand))
	if reload_hand > 0.0:
		var t: float = smoothstep(0.0, 1.0, reload_hand)
		var holder := get_parent() as Node3D
		if reload_with_right_hand:
			r = r.interpolate_with(Transform3D(r.basis, holder.global_transform * Vector3(0.12, -0.5, 0.25)), t)
		else:
			l = l.interpolate_with(Transform3D(l.basis, holder.global_transform * Vector3(-0.3, -0.5, 0.2)), t)
	return [r, l]


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


## Sets up the imported model: hide extra parts, build the Bolt node, no shadows.
func _prepare_imported_model() -> void:
	var mesh_root: Node = get_node_or_null("Model/Mesh")
	if mesh_root == null:
		return
	for part_name in hidden_part_names:
		var part := mesh_root.find_child(part_name, true, false) as Node3D
		if part:
			part.visible = false
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


## Reload: dip the weapon down and tilt it, then bring it back up.
func play_reload(duration: float) -> void:
	_restart_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "anim_offset", Vector3(-0.03, -0.12, 0.05), duration * 0.15)
	_tween.tween_property(self, "anim_rotation", Vector3(deg_to_rad(15), 0, deg_to_rad(-35)), duration * 0.15)
	_tween.chain().tween_property(self, "anim_offset", Vector3.ZERO, duration * 0.15).set_delay(duration * 0.7)
	_tween.tween_property(self, "anim_rotation", Vector3.ZERO, duration * 0.15).set_delay(duration * 0.7)
	# One hand goes down to the ammo pouch and comes back with a clip / drum.
	_hand_tween = create_tween()
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
	if bolt:
		bolt.position = _bolt_rest
	_tween = create_tween()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
