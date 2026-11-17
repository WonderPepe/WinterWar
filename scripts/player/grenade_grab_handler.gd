class_name GrenadeGrabHandler
extends Node
## GR2: pick up a live Soviet grenade and throw it back.
##
## A live grenade lies (or rolls) within `grab_radius_m` of you: press F. You snatch it up and
## throw it straight away the way you look (~20 m). It takes `done_time` s and the gun is lowered
## meanwhile. THE FUSE KEEPS RUNNING – grab it too late and it goes off in your hand.
## Not while dead, climbing out, bandaging, on the Maxim, or holding a lit Molotov (an unlit
## bottle is put away). A thrown-back grenade's kills count for you.
##
## Made in code by the Player (child "GrenadeGrab" on every computer). The HOST decides
## (`try_grab`, called from the Player's F handling) and throws; the owner's computer only shows
## the hand (`show_grab` RPC) and counts `thrown_back` for the end screen.

@export var grab_radius_m: float = 1.5 ## How close a grenade must be (to your feet or waist).
@export var throw_at: float = 0.4 ## Seconds after F: the grenade leaves your hand...
@export var done_time: float = 0.65 ## ...and the gun is back up.
@export var throw_speed: float = 14.0 ## m/s the way you look...
@export var throw_lift: float = 2.5 ## ...plus this much upwards (a lob).

## Grenades this player threw back in this run (end screen; host, sent to the owner's computer).
var thrown_back: int = 0:
	set = _set_thrown_back

var player: Player
var _active: bool = false # grabbing (host and the owner's computer)
var _t: float = 0.0
var _thrown: bool = false # host: it has left the hand (or gone off in it)
var _fuse_end: float = 0.0 # host: GrenadeManager clock time when it goes off
var _hand: Node3D # owner's computer: the grenade in the first-person hand
var _grenade: Node3D
var _grip_r: Marker3D
var _grip_l: Marker3D


func _ready() -> void:
	player = get_parent() as Player


## True while the hands are busy with a grenade (the gun is lowered, no firing / switching).
func is_busy() -> bool:
	return _active


## Host: F was pressed – grab the nearest live grenade within reach. True if one was taken.
func try_grab() -> bool:
	if not multiplayer.is_server() or _active or player.is_dead or player.is_climbing or player.is_bandaging \
			or player.get_mounted_gun() != null or not player.molotov.can_put_away():
		return false
	var manager := _manager()
	if manager == null:
		return false
	var id: int = manager.find_grabbable(grab_points(), grab_radius_m)
	if id < 0:
		return false
	var fuse_left: float = manager.grab(id)
	player.molotov.put_away() # (an unlit bottle goes back in the bag)
	_fuse_end = manager.clock() + fuse_left
	_thrown = false
	show_grab.rpc(player.get_peer_id())
	return true


## The points a grenade must be close to: your feet and your waist.
func grab_points() -> Array[Vector3]:
	return [player.global_position + Vector3.UP * 0.1, player.global_position + Vector3.UP * 0.8]


## Host: reset on respawn / new day (nothing in the hand).
func reset() -> void:
	_active = false
	_thrown = true


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	if multiplayer.is_server() and not _thrown:
		var manager := _manager()
		var left: float = _fuse_end - manager.clock()
		if player.is_dead:
			# Killed with it in the hand: it falls at his feet and goes off as it would have.
			_thrown = true
			manager.throw(player.global_position + Vector3.UP * 0.8, Vector3(0, 0.3, 0), player.get_peer_id(), false, maxf(left, 0.0))
		elif left <= 0.0:
			# Too late: it goes off in the hand.
			_thrown = true
			manager.throw(_hand_origin(), Vector3.ZERO, player.get_peer_id(), false, 0.0)
		elif _t >= throw_at:
			_thrown = true
			var forward: Vector3 = -player.camera.global_basis.z
			var velocity: Vector3 = forward * throw_speed + Vector3.UP * throw_lift + player.velocity * 0.5
			manager.throw(_hand_origin(), velocity, player.get_peer_id(), false, left)
			thrown_back += 1
	if _t >= done_time:
		_active = false


func _hand_origin() -> Vector3:
	var cam: Camera3D = player.camera
	return cam.global_position + cam.global_basis * Vector3(0.2, 0.1, -0.35)


func _manager() -> GrenadeManager:
	return get_tree().get_first_node_in_group("grenades") as GrenadeManager


## Host → everyone (the hand is only drawn on the owner's computer): the grab starts now.
@rpc("authority", "call_local", "reliable")
func show_grab(_peer: int) -> void:
	_active = true
	_t = 0.0
	if player.is_local_player() and _hand == null:
		_build_hand()


func _set_thrown_back(value: int) -> void:
	thrown_back = value
	if multiplayer.is_server() and is_inside_tree() and not player.is_local_player():
		sync_thrown_back.rpc_id(player.get_peer_id(), value)


@rpc("authority", "call_remote", "reliable")
func sync_thrown_back(value: int) -> void:
	thrown_back = value


# ------------------------------------------------------------------ the hand (local player)
func _build_hand() -> void:
	_hand = Node3D.new()
	_hand.name = "GrenadeHand"
	player.camera.add_child(_hand)
	_hand.visible = false
	_grenade = GrenadeManager.make_grenade(false)
	_hand.add_child(_grenade)
	# Right mitten round the grenade (like the Molotov bottle's grip, a little smaller).
	_grip_r = Marker3D.new()
	_grip_r.name = "GripR"
	_grenade.add_child(_grip_r)
	_grip_r.transform = Transform3D(Basis.looking_at(Vector3(0, -0.3, -1).normalized(), Vector3.UP) * Basis(Vector3.UP, PI / 2.0), Vector3(0.035, -0.01, 0.0))
	_grip_l = Marker3D.new()
	_grip_l.name = "GripL"
	_hand.add_child(_grip_l)
	_grip_l.transform = Transform3D(Basis.looking_at(Vector3(0.3, -0.2, -1).normalized(), Vector3.UP) * Basis(Vector3.UP, -PI / 2.0), Vector3(-0.22, -0.5, -0.25))


## Where the hands go while grabbing: [right, left]. Empty = not grabbing.
func get_hand_grips() -> Array[Transform3D]:
	if _hand == null or not _hand.visible:
		return []
	return [_grip_r.global_transform, _grip_l.global_transform]


func _process(_delta: float) -> void:
	if _hand == null:
		return
	var shown: bool = _active and not player.is_dead
	_hand.visible = shown
	if not shown:
		return
	# Snatched up from low down → cocked by the shoulder → thrown forward → arm comes down.
	var low := Vector3(0.12, -0.62, -0.5)
	var cocked := Vector3(0.3, -0.02, -0.26)
	var out := Vector3(0.05, -0.12, -0.75)
	var pos: Vector3
	var rot: Vector3
	var up_end: float = throw_at * 0.7
	if _t < up_end:
		var k: float = smoothstep(0.0, 1.0, _t / up_end)
		pos = low.lerp(cocked, k)
		rot = Vector3(-20.0, 0.0, -10.0).lerp(Vector3(35.0, 10.0, -20.0), k)
	elif _t < throw_at:
		var k: float = (_t - up_end) / (throw_at - up_end)
		pos = cocked.lerp(out, k * k)
		rot = Vector3(35.0, 10.0, -20.0).lerp(Vector3(-60.0, 0.0, 0.0), k)
	else:
		var k: float = smoothstep(0.0, 1.0, (_t - throw_at) / maxf(done_time - throw_at, 0.01))
		pos = out.lerp(low, k)
		rot = Vector3(-60.0, 0.0, 0.0)
	_grenade.visible = _t < throw_at
	_grenade.position = pos
	_grenade.rotation_degrees = rot
