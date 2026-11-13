class_name ClimbHandler
extends Node
## C1: climbing out of the trench (child "Climb" of the Player).
##
## A jump only lifts the soldier about 1 m, the trench is 1.4 m deep. So when Space is pressed in
## front of a wall that is too high to jump onto (but not higher than `max_height`), the soldier
## hauls himself over the edge instead: `climb_time` seconds, hands busy (no shooting, no
## lighting a bottle), fully in the open. It works for any such ledge of the WORLD (layer 1) -
## trench walls on both sides, the communication trenches - and never onto a tank.
##
## Only the HOST decides and moves the player (like all movement). `Player.is_climbing` is synced
## by StateSync, so every computer can lower the gun / block firing.

@export var climb_time: float = 1.0 ## Seconds from the trench floor to standing on top.
@export var min_height: float = 0.9 ## Lower ledges are for a normal jump.
@export var max_height: float = 1.7 ## Higher walls can't be climbed.
@export var reach: float = 0.5 ## How far in front of the body the wall may be (m).
@export var step_in: float = 0.5 ## He ends up this far behind the edge (m).
@export var max_angle_deg: float = 60.0 ## He must face the wall at least this squarely.
@export var up_share: float = 0.6 ## This share of the time goes straight up, the rest forward.

const WORLD_MASK := 0b1
const BODY_RADIUS := 0.35

var _from: Vector3
var _to: Vector3
var _t: float = 0.0

@onready var player: Player = get_parent()


## Host: is there a ledge to climb in front of the player? Returns the place where he would
## stand afterwards, or null. (Also used by the tests.)
func find_ledge() -> Variant:
	var space := player.get_world_3d().direct_space_state
	var pos: Vector3 = player.global_position
	var forward: Vector3 = -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	# 1) A wall right in front (knee or chest height), faced squarely enough.
	var wall: Dictionary = {}
	for h: float in [0.4, 1.0]:
		var from: Vector3 = pos + Vector3(0, h, 0)
		wall = _ray(space, from, from + forward * (BODY_RADIUS + reach))
		if not wall.is_empty():
			break
	if wall.is_empty():
		return null
	var into := Vector3(-wall.normal.x, 0.0, -wall.normal.z) # horizontal direction into the wall
	if absf(wall.normal.y) > 0.5 or into.length() < 0.01:
		return null
	into = into.normalized()
	if into.dot(forward) < cos(deg_to_rad(max_angle_deg)):
		return null
	# 2) Ground on top of it, at a height that needs climbing.
	var over: Vector3 = Vector3(wall.position.x, pos.y, wall.position.z) + into * step_in
	var top: Dictionary = _ray(space, over + Vector3(0, max_height + 0.3, 0), over + Vector3(0, min_height, 0))
	if top.is_empty() or top.normal.y < 0.7:
		return null
	var land: Vector3 = top.position
	var height: float = land.y - pos.y
	if height < min_height or height > max_height:
		return null
	# 3) Nothing over his head on the way up, nothing between him and the spot ...
	if not _ray(space, pos + Vector3(0, 1.0, 0), pos + Vector3(0, height + player.stand_height, 0)).is_empty():
		return null
	for h: float in [0.3, 1.0, 1.7]:
		if not _ray(space, Vector3(pos.x, land.y + h, pos.z), land + Vector3(0, h, 0)).is_empty():
			return null
	# 4) ... and room to stand there.
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS - 0.05
	capsule.height = player.stand_height - 0.1
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.transform = Transform3D(Basis.IDENTITY, land + Vector3(0, player.stand_height / 2.0 + 0.1, 0))
	q.collision_mask = 0b101 # world + tanks
	if not space.intersect_shape(q, 1).is_empty():
		return null
	return land


## Host: Space was pressed on the ground. Starts a climb if there is a ledge; true = started.
func try_start() -> bool:
	if player.is_climbing or player.is_dead or player.is_bandaging or player.get_mounted_gun() != null:
		return false
	if not player.molotov.can_climb():
		return false # owner: no climbing with a burning bottle in the hand
	var land: Variant = find_ledge()
	if land == null:
		return false
	_from = player.global_position
	_to = land
	_t = 0.0
	player.weapons.is_reloading = false # the hands are needed: a reload is dropped
	player.is_sprinting = false
	player.is_crouching = false
	player.velocity = Vector3.ZERO
	player.is_climbing = true
	return true


## Host, every physics frame while climbing: first up the wall, then forward over the edge.
func update(delta: float) -> void:
	_t += delta / maxf(climb_time, 0.05)
	var up: float = smoothstep(0.0, 1.0, clampf(_t / up_share, 0.0, 1.0))
	var fwd: float = smoothstep(0.0, 1.0, clampf((_t - up_share * 0.7) / (1.0 - up_share * 0.7), 0.0, 1.0))
	var pos: Vector3 = _from.lerp(_to, fwd)
	pos.y = lerpf(_from.y, _to.y + 0.02, up)
	player.global_position = pos
	player.velocity = Vector3.ZERO
	if _t >= 1.0:
		player.is_climbing = false


## Host: stop at once (death, respawn).
func cancel() -> void:
	player.is_climbing = false


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = WORLD_MASK
	return space.intersect_ray(q)
