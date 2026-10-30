class_name MountedGun
extends StaticBody3D
## A heavy machine gun on a fixed mount (the Maxim in the bunker).
##
## Walk up to it and press F (action "interact") to use it; press F again to leave.
## Multiplayer-ready like the hand weapons:
## - The HOST decides who is on the gun (`user_id`, one player at a time), owns the ammo
##   and does the hit raycast (via the user's WeaponController, `resolve_shot`).
## - The USER's computer decides when the trigger fires and plays the effects at once.
## - Everyone turns the gun to where its user is looking (look angles are synced anyway).
## The part of the imported model that turns with the aim is moved under `Pivot` at start.

@export var data: WeaponData ## Fire rate, damage, belt size, sounds...
@export var traverse_left_deg: float = 35.0 ## How far the gun turns to the left...
@export var traverse_right_deg: float = 35.0 ## ...and to the right (the firing slit limits this).
@export var elevation_min_deg: float = -6.0 ## Lowest aim (the firing slit limits this).
@export var elevation_max_deg: float = 5.0
@export var use_distance: float = 1.8 ## How close (to SeatPoint) you must be to take the gun.
@export var infinite_belts: bool = true ## The bunker has plenty of ammunition boxes.
## Names of the imported model's parts that turn with the gun (everything else stays put).
@export var turning_part_names: PackedStringArray = PackedStringArray()
@export var hidden_part_names: PackedStringArray = PackedStringArray()
@export var flash_duration: float = 0.05

# --- Synced from the host by GunSync ---
var user_id: int = 0 ## Peer id of the player on the gun, 0 = free.
var ammo: int = 250 ## Rounds left in the belt.
var is_reloading: bool = false:
	set = _set_is_reloading

var _reload_timer: float = 0.0   # host
var _server_next_fire: float = 0.0 # host
var _flash_until: float = 0.0
var _kick: float = 0.0
var _pivot_rest: Vector3
var _smoke: CPUParticles3D
var _smoke_until: float = 0.0

@onready var pivot: Node3D = $Pivot
@onready var muzzle: Node3D = $Pivot/Muzzle
@onready var flash: Node3D = $Pivot/Muzzle/MuzzleFlash
@onready var flash_light: OmniLight3D = $Pivot/Muzzle/FlashLight
@onready var seat: Marker3D = $SeatPoint
@onready var exit_point: Marker3D = $ExitPoint
@onready var shot_audio: AudioStreamPlayer3D = $ShotAudio
@onready var mech_audio: AudioStreamPlayer3D = $MechAudio


func _ready() -> void:
	add_to_group("mounted_guns")
	if data:
		ammo = data.magazine_size
	flash.visible = false
	flash_light.visible = false
	_pivot_rest = pivot.position
	_prepare_model()
	# Long bursts leave a haze of gun smoke in front of the slit.
	_smoke = ImpactEffects.make_smoke_emitter(ImpactEffects.make_soft_texture())
	_smoke.one_shot = false
	_smoke.explosiveness = 0.0
	_smoke.amount = 10
	_smoke.lifetime = 1.4
	_smoke.initial_velocity_min = 3.0 # pushed out through the slit, away from the gunner
	_smoke.initial_velocity_max = 5.0
	_smoke.gravity = Vector3(0.1, 0.25, 0.0)
	((_smoke.mesh as PrimitiveMesh).material as StandardMaterial3D).albedo_color.a = 0.15
	_smoke.emitting = false
	_smoke.direction = Vector3.FORWARD # muzzle space: out of the barrel
	muzzle.add_child(_smoke)


## Puts the turning parts of the imported model under Pivot and hides extra parts.
func _prepare_model() -> void:
	var model: Node = get_node_or_null("Model")
	if model == null:
		return
	for part_name in hidden_part_names:
		var part := model.find_child(part_name, true, false) as Node3D
		if part:
			part.visible = false
	for part_name in turning_part_names:
		var part := model.find_child(part_name, true, false) as Node3D
		if part:
			part.reparent(pivot, true)


## Left/right direction the gun points when centred (radians, like PlayerInput.look_yaw).
func get_base_yaw() -> float:
	return global_rotation.y


func get_user() -> Player:
	if user_id == 0:
		return null
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p and p.get_peer_id() == user_id:
			return p
	return null


func is_free() -> bool:
	return user_id == 0


## Keeps a view direction inside what the gun can reach (used by the user's PlayerInput).
func clamp_look(yaw: float, pitch: float) -> Vector2:
	var base: float = get_base_yaw()
	# Positive = turned to the left (Godot turns counter-clockwise seen from above).
	var rel: float = clampf(wrapf(yaw - base, -PI, PI), -deg_to_rad(traverse_right_deg), deg_to_rad(traverse_left_deg))
	return Vector2(base + rel, clampf(pitch, deg_to_rad(elevation_min_deg), deg_to_rad(elevation_max_deg)))


func _process(delta: float) -> void:
	if multiplayer.is_server():
		_host_process(delta)
	# Turn the gun towards where its user looks (on every computer).
	var user := get_user()
	if user:
		var look: Vector2 = clamp_look(user.input.look_yaw, user.input.look_pitch)
		pivot.rotation = Vector3(look.y, wrapf(look.x - get_base_yaw(), -PI, PI), 0.0)
	_kick = lerpf(_kick, 0.0, clampf(delta * 18.0, 0.0, 1.0))
	pivot.position = _pivot_rest + pivot.basis.z * _kick # recoil pushes the gun back
	var flashing: bool = Time.get_ticks_msec() / 1000.0 < _flash_until
	flash.visible = flashing
	flash_light.visible = flashing and user != null and user.is_local_player()
	_smoke.emitting = Time.get_ticks_msec() / 1000.0 < _smoke_until


# ------------------------------------------------------------------ host side
## Host: put `player` on the gun.
func mount(player: Player) -> void:
	if not multiplayer.is_server() or not is_free():
		return
	user_id = player.get_peer_id()
	player.mounted_gun_path = player.get_path_to(self)
	player.global_position = seat.global_position
	player.velocity = Vector3.ZERO
	player.input.set_look.rpc_id(user_id, get_base_yaw(), 0.0) # face down the barrel


## Host: the user leaves the gun (also used when the user dies or disconnects).
func release() -> void:
	if not multiplayer.is_server():
		return
	var user := get_user()
	user_id = 0
	is_reloading = false
	if user:
		user.mounted_gun_path = NodePath()
		if not user.is_dead:
			user.global_position = exit_point.global_position
			user.velocity = Vector3.ZERO


func _host_process(delta: float) -> void:
	if user_id != 0:
		var user := get_user()
		if user == null or user.is_dead:
			release() # the user died or left the game
	if is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			ammo = data.magazine_size
			is_reloading = false


## Host: a new belt (R).
func start_reload() -> void:
	if not multiplayer.is_server() or is_reloading or ammo >= data.magazine_size or not infinite_belts:
		return
	_reload_timer = data.reload_time
	is_reloading = true


## The user asks the host to fire one round.
@rpc("any_peer", "call_local", "reliable")
func server_fire(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var shooter: int = multiplayer.get_remote_sender_id()
	var user := get_user()
	var now: float = Time.get_ticks_msec() / 1000.0
	if user == null or shooter != user_id or user.is_dead or is_reloading or ammo <= 0 or now < _server_next_fire:
		return
	_server_next_fire = now + data.get_shot_interval() * 0.8 # small tolerance for network jitter
	if origin.distance_to(user.camera.global_position) > 2.0:
		origin = user.camera.global_position # don't trust a far-away origin
	ammo -= 1
	user.weapons.resolve_shot(origin, direction, data, [get_rid()])
	remote_fire_effects.rpc()


@rpc("authority", "call_remote", "unreliable")
func remote_fire_effects() -> void:
	var user := get_user()
	if user and user.is_local_player():
		return # the user already played them
	_show_fire(false)


# ------------------------------------------------------------------ effects
## The user's computer: flash, sound and kick right away.
func play_local_fire() -> void:
	_show_fire(true)


func _show_fire(local: bool) -> void:
	_flash_until = Time.get_ticks_msec() / 1000.0 + flash_duration
	_smoke_until = Time.get_ticks_msec() / 1000.0 + 0.3
	flash.rotation.z = randf() * TAU
	_kick = 0.025 if local else 0.015
	if data and data.fire_sound:
		shot_audio.stream = data.fire_sound
		shot_audio.play()


func _set_is_reloading(value: bool) -> void:
	var started: bool = value and not is_reloading
	is_reloading = value
	if started and is_node_ready() and data and data.reload_sound:
		mech_audio.stream = data.reload_sound
		mech_audio.play()
