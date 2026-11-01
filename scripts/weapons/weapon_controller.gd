class_name WeaponController
extends Node
## The player's weapons: switching, aiming, firing, reloading and ammo.
##
## Who does what (multiplayer-ready):
## - The OWNER (the computer of the player holding the gun) decides when the trigger
##   fires, plays the flash/sound/recoil immediately, then asks the host to fire (RPC).
## - The HOST checks the shot is allowed, does the raycast, applies damage, owns the
##   ammo counts and tells everyone where the bullet hit.
## In single player we are both, so everything happens instantly.
## While the player is on a mounted gun (Maxim), the trigger, ammo and reload go to that
## gun instead of the hand weapons (see MountedGun).

signal weapon_changed(data: WeaponData)
signal hit_confirmed(killed: bool)

@export var loadout: Array[WeaponData] = [] ## Slot 1, slot 2, ...
@export var hip_position: Vector3 = Vector3(0.13, -0.17, -0.3) ## Gun position (from the eye) when not aiming.
@export var base_fov: float = 75.0
@export var friendly_fire: bool = false
@export_flags_3d_physics var shot_collision_mask: int = 0b111 ## What bullets can hit.
@export var wall_check_distance: float = 0.9 ## Pull the gun back when a wall is closer than this.
@export var switch_time: float = 0.4

# --- Synced from the host to everyone by WeaponSync ---
var current_slot: int = 0:
	set = _set_current_slot
var mag_ammo: PackedInt32Array = PackedInt32Array()     ## Rounds in each weapon's magazine.
var reserve_ammo: PackedInt32Array = PackedInt32Array() ## Spare rounds for each weapon.
var is_reloading: bool = false:
	set = _set_is_reloading

var is_aiming: bool = false

# --- Statistics for the end screen (host counts, WeaponSync shares) ---
var shots_fired: int = 0
var shots_hit: int = 0 ## Hits on Soviet soldiers.

var _aim_t: float = 0.0           # 0 = hip, 1 = fully aimed
var _next_fire_time: float = 0.0  # owner: when the trigger may fire again
var _trigger_ready: bool = true   # owner: semi/bolt need the button released between shots
var _bloom_deg: float = 0.0       # owner: extra spread from sustained fire
var _recoil_to_recover: float = 0.0
var _bob_time: float = 0.0
var _server_next_fire: float = 0.0 # host: anti-cheat fire-rate check
var _had_bottle: bool = false     # T2: a Molotov was in the hand last frame
var _fire_blocked: bool = false   # T2: wait for the fire button to be let go after a throw
var _reload_timer: float = 0.0     # host
var _view_models: Array[ViewModel] = []
var _last_smoke_time: float = 0.0
var _rng := RandomNumberGenerator.new()

@onready var player: Player = get_parent()
@onready var input: PlayerInput = $"../PlayerInput"
@onready var camera: Camera3D = $"../Head/Camera3D"
@onready var holder: Node3D = $"../Head/Camera3D/WeaponHolder"
@onready var wall_check: RayCast3D = $"../Head/Camera3D/WallCheck"
@onready var shot_audio: AudioStreamPlayer = $ShotAudio
@onready var mech_audio: AudioStreamPlayer = $MechAudio
@onready var remote_audio: AudioStreamPlayer3D = $"../Head/RemoteAudio"


func _ready() -> void:
	_rng.randomize()
	if multiplayer.is_server():
		refill_ammo()
	for w in loadout:
		var vm: ViewModel = w.view_model.instantiate()
		holder.add_child(vm)
		_view_models.append(vm)
	holder.position = hip_position
	_apply_slot()


## The mounted gun the player is using, or null.
func get_mounted_gun() -> MountedGun:
	return player.get_mounted_gun()


func get_current_weapon() -> WeaponData:
	var gun := get_mounted_gun()
	if gun:
		return gun.data
	return loadout[current_slot] if current_slot < loadout.size() else null


func get_mag_ammo() -> int:
	var gun := get_mounted_gun()
	if gun:
		return gun.ammo
	return mag_ammo[current_slot] if current_slot < mag_ammo.size() else 0


## Spare rounds; -1 means "unlimited" (mounted gun with plenty of belts).
func get_reserve_ammo() -> int:
	var gun := get_mounted_gun()
	if gun:
		return -1 if gun.infinite_belts else 0
	return reserve_ammo[current_slot] if current_slot < reserve_ammo.size() else 0


## True while the current weapon (hand weapon or mounted gun) is being reloaded.
func is_reloading_now() -> bool:
	var gun := get_mounted_gun()
	return gun.is_reloading if gun else is_reloading


## Where the first-person hands go this frame: [right, left] as global transforms
## (on the hand weapon's grips, or on the Maxim's). Empty = no hands (dead).
func get_hand_grips() -> Array[Transform3D]:
	if player.is_dead:
		return []
	var gun := get_mounted_gun()
	if gun:
		return gun.get_hand_grips()
	if player.molotov.is_selected():
		return player.molotov.get_hand_grips() # T2: a bottle in the hand
	if current_slot >= _view_models.size():
		return []
	return _current_view_model().get_hand_grips()


## True while the mounted gun is too hot to fire.
func is_gun_overheated() -> bool:
	var gun := get_mounted_gun()
	return gun != null and gun.is_overheated


## Movement speed multiplier while aiming (used by Player on the host).
func get_move_multiplier() -> float:
	var w := get_current_weapon()
	return w.ads_move_multiplier if (w and is_aiming) else 1.0


func _process(delta: float) -> void:
	var w := get_current_weapon()
	if w == null:
		return
	if multiplayer.is_server():
		_host_process(delta, w)
	# A hand weapon leaves the shoulder to reload; on the Maxim the gunner stays behind the sights
	# while the right hand feeds the new belt.
	var reloading_hand_weapon: bool = is_reloading_now() and get_mounted_gun() == null
	var bottle: bool = player.molotov.is_selected() # T2: right mouse lights / aims the bottle instead
	is_aiming = input.aim_held and not reloading_hand_weapon and not player.is_sprinting and not player.is_bandaging \
			and not bottle
	_aim_t = move_toward(_aim_t, 1.0 if is_aiming else 0.0, delta / maxf(w.ads_time, 0.01))
	holder.visible = player.is_local_player() and not player.is_dead and get_mounted_gun() == null and not bottle
	if _had_bottle and not bottle and current_slot < _view_models.size():
		_view_models[current_slot].play_raise(switch_time) # the gun comes back up
		_next_fire_time = _now() + switch_time
	_had_bottle = bottle
	if player.is_local_player():
		_owner_process(delta, w)


# ------------------------------------------------------------------ owner side
func _owner_process(delta: float, w: WeaponData) -> void:
	_bloom_deg = maxf(_bloom_deg - w.bloom_recovery_deg_per_s * delta, 0.0)
	if _recoil_to_recover > 0.0:
		var step: float = _recoil_to_recover * clampf(w.recoil_return_speed * delta, 0.0, 1.0)
		input.add_look(-step, 0.0)
		_recoil_to_recover -= step

	if player.molotov.is_selected():
		# T2: the left mouse button throws the bottle (PlayerInput); the gun waits until it is
		# let go, so the throwing click can't fire it afterwards.
		_fire_blocked = true
		camera.position = Vector3.ZERO
		camera.fov = base_fov
		input.look_sensitivity_scale = 1.0
		return
	if not input.fire_held:
		_trigger_ready = true
		_fire_blocked = false
	elif _fire_blocked:
		pass
	elif is_gun_overheated():
		if _trigger_ready: # boiling: the trigger just clicks
			_trigger_ready = false
			_play(mech_audio, w.empty_sound)
	elif _can_fire_now() and (w.fire_mode == WeaponData.FireMode.FULL_AUTO or _trigger_ready):
		_trigger_ready = false
		if get_mag_ammo() > 0:
			_fire(w)
		else:
			_dry_fire(w)
	if get_mounted_gun():
		_update_mounted_view(w, get_mounted_gun())
	else:
		_update_view(delta, w)


func _can_fire_now() -> bool:
	return _now() >= _next_fire_time and not is_reloading_now() and not player.is_sprinting and not player.is_dead \
			and not player.is_bandaging


func _fire(w: WeaponData) -> void:
	var rounds_before: int = get_mag_ammo()
	var interval: float = w.get_shot_interval()
	if w.fire_mode == WeaponData.FireMode.FULL_AUTO and _now() - _next_fire_time < interval:
		_next_fire_time += interval # keep an exact rhythm even though frames don't line up
	else:
		_next_fire_time = _now() + interval
	var direction: Vector3 = _spread_direction(w)
	var gun := get_mounted_gun()
	if gun:
		gun.server_fire.rpc_id(1, camera.global_position, direction) # ask the host to fire
		gun.play_local_fire()
		_add_recoil(w)
		return
	server_fire.rpc_id(1, camera.global_position, direction) # ask the host to fire

	# Local effects right away (no waiting for the network).
	var vm := _current_view_model()
	vm.play_fire(w.kick_back_m, w.kick_rotation_deg)
	_play(shot_audio, w.fire_sound)
	_spawn_smoke((vm.get_node("Model/Muzzle") as Node3D).global_position, -camera.global_basis.z, true)
	if w.fire_mode == WeaponData.FireMode.BOLT_ACTION and rounds_before > 1:
		vm.play_bolt_cycle(w.bolt_cycle_time)
		get_tree().create_timer(w.bolt_cycle_time * 0.25).timeout.connect(_play.bind(mech_audio, w.get_cycle_sound()))
	_add_recoil(w)


## Recoil moves the real aim; part of it returns by itself.
func _add_recoil(w: WeaponData) -> void:
	var kick: float = deg_to_rad(w.recoil_pitch_deg)
	var pitch_before: float = input.look_pitch
	input.add_look(kick, deg_to_rad(_rng.randf_range(-w.recoil_yaw_deg, w.recoil_yaw_deg)))
	# Only bring back what the kick really moved: at the Maxim's elevation limit (or looking
	# straight up) the kick is cut off, and recovering the full amount would drag the aim down.
	var applied: float = maxf(input.look_pitch - pitch_before, 0.0)
	_recoil_to_recover += applied * w.recoil_recovery
	_bloom_deg = minf(_bloom_deg + w.bloom_per_shot_deg, w.max_bloom_deg)


func _dry_fire(w: WeaponData) -> void:
	_next_fire_time = _now() + 0.3
	_play(mech_audio, w.empty_sound)
	if get_reserve_ammo() != 0:
		input.request_reload.rpc_id(1) # empty: reload automatically


## Current maximum spread in degrees (also used by the HUD crosshair).
func get_current_spread_deg() -> float:
	var w := get_current_weapon()
	if w == null:
		return 0.0
	var spread: float = lerpf(w.hip_spread_deg, w.ads_spread_deg, _aim_t)
	spread += w.move_spread_deg * clampf(player.get_speed() / player.walk_speed, 0.0, 1.5)
	return spread + _bloom_deg


## Random direction inside a cone around the view direction.
func _spread_direction(_w: WeaponData) -> Vector3:
	var spread: float = get_current_spread_deg()
	# randf() without sqrt() puts more shots near the centre than near the edge.
	var angle: float = deg_to_rad(spread) * _rng.randf()
	var around: float = _rng.randf() * TAU
	var local := Vector3(sin(angle) * cos(around), sin(angle) * sin(around), -cos(angle))
	return (camera.global_basis * local).normalized()


## Positions the gun (hip/aim, walking bob, wall pull-back) and sets zoom.
func _update_view(delta: float, w: WeaponData) -> void:
	var vm := _current_view_model()
	var aim_smooth: float = smoothstep(0.0, 1.0, _aim_t)
	var ads_position: Vector3 = Vector3(0.0, 0.0, -vm.ads_eye_distance) - vm.aim_point_rest
	var target: Vector3 = (hip_position + vm.hip_offset).lerp(ads_position, aim_smooth)

	var speed: float = player.get_speed()
	if speed > 0.5:
		_bob_time += delta * speed * 2.2
		var bob: float = 0.012 * (1.0 - aim_smooth * 0.8)
		target += Vector3(cos(_bob_time * 0.5) * bob, absf(sin(_bob_time * 0.5)) * -bob, 0.0)

	if player.is_bandaging:
		target += Vector3(0.05, -0.28, 0.08) # gun lowered while the hands are busy

	if wall_check.is_colliding():
		var dist: float = camera.global_position.distance_to(wall_check.get_collision_point())
		target.z += clampf(wall_check_distance - dist, 0.0, 0.35)

	holder.position = holder.position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))
	camera.position = Vector3.ZERO # (moved only on a mounted gun)
	camera.fov = lerpf(base_fov, w.ads_fov, aim_smooth)
	input.look_sensitivity_scale = lerpf(1.0, w.ads_sensitivity_multiplier, aim_smooth)


## On a mounted gun the gun doesn't move to your eye – your eye moves to the gun: right mouse
## brings the camera down behind the rear sight (Pivot/SightEye) and zooms in.
func _update_mounted_view(w: WeaponData, gun: MountedGun) -> void:
	var aim_smooth: float = smoothstep(0.0, 1.0, _aim_t)
	camera.position = (camera.get_parent() as Node3D).to_local(gun.get_sight_eye_position()) * aim_smooth
	camera.fov = lerpf(base_fov, w.ads_fov, aim_smooth)
	input.look_sensitivity_scale = lerpf(0.8, w.ads_sensitivity_multiplier, aim_smooth)


# ------------------------------------------------------------------ host side
func _host_process(delta: float, w: WeaponData) -> void:
	var gun := get_mounted_gun()
	if gun:
		input.consume_switch() # no weapon switching on the gun
		if input.consume_reload():
			gun.start_reload() # a new belt
		return
	var slot: int = input.consume_switch()
	if player.molotov.is_selected():
		# T2: 1 / 2 put the bottle away (not a lit one: that has to be thrown).
		if slot >= 0 and slot < loadout.size() and player.molotov.can_put_away():
			player.molotov.put_away()
		else:
			slot = -1
		input.consume_reload()
		if slot == current_slot:
			return
	if slot >= 0 and slot < loadout.size() and slot != current_slot:
		is_reloading = false
		current_slot = slot
	if input.consume_reload():
		_start_reload(w)
	if is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload(get_current_weapon())


## Host only: spare ammo back to the starting amount (ammo crate). Magazines stay as they are.
func refill_reserve() -> void:
	var reserves := PackedInt32Array()
	for w in loadout:
		reserves.append(w.starting_reserve)
	reserve_ammo = reserves


## Host only: full magazines and starting spare ammo (used when respawning).
func refill_ammo() -> void:
	var mags := PackedInt32Array()
	var reserves := PackedInt32Array()
	for w in loadout:
		mags.append(w.magazine_size)
		reserves.append(w.starting_reserve)
	mag_ammo = mags
	reserve_ammo = reserves
	is_reloading = false


func _start_reload(w: WeaponData) -> void:
	if is_reloading or get_mag_ammo() >= w.magazine_size or get_reserve_ammo() <= 0:
		return
	_reload_timer = w.reload_time
	is_reloading = true


func _finish_reload(w: WeaponData) -> void:
	var taken: int = mini(w.magazine_size - get_mag_ammo(), get_reserve_ammo())
	mag_ammo[current_slot] += taken
	reserve_ammo[current_slot] -= taken
	is_reloading = false


## The owner asks the host to fire. "any_peer" = clients may call it, so we check who did.
@rpc("any_peer", "call_local", "reliable")
func server_fire(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var shooter: int = multiplayer.get_remote_sender_id()
	if shooter != player.get_peer_id():
		return # someone tried to fire another player's gun
	var w := get_current_weapon()
	var now: float = _now()
	if w == null or get_mounted_gun() or is_reloading or player.is_dead or get_mag_ammo() <= 0 or now < _server_next_fire:
		return
	_server_next_fire = now + w.get_shot_interval() * 0.8 # small tolerance for network jitter
	if origin.distance_to(camera.global_position) > 2.0:
		origin = camera.global_position # don't trust a far-away origin
	mag_ammo[current_slot] -= 1
	resolve_shot(origin, direction, w, [])
	# Let other computers see/hear this player's shot.
	if not player.is_local_player():
		_play_remote_fire_effects()
	remote_fire_effects.rpc()


## Host only: the bullet itself. Raycast, damage, hit marker, impact effect, noise.
## Also used by mounted guns (`exclude` = the gun's own body, so it can't shoot itself).
func resolve_shot(origin: Vector3, direction: Vector3, w: WeaponData, exclude: Array[RID]) -> void:
	var shooter: int = player.get_peer_id()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * w.max_range_m, shot_collision_mask)
	query.exclude = [player.get_rid()] + exclude
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	shots_fired += 1
	if not hit.is_empty():
		var collider: Node = hit.collider
		var target := _find_damageable(collider)
		if target and target.has_method("deflects_bullets") and target.deflects_bullets():
			target = null # tank armour: sparks only, no damage and no hit marker
		if target is Enemy and (target as Enemy).state != Enemy.State.DEAD:
			shots_hit += 1
		if target and (friendly_fire or not target is Player):
			var killed: bool = target.take_damage(w.damage_at(origin.distance_to(hit.position)), shooter, hit.position, hit.normal)
			if killed and target is Enemy:
				player.kills += 1
			confirm_hit.rpc_id(shooter, killed)
		var attach: NodePath = collider.get_path() if collider.has_meta("attach_holes") else NodePath()
		show_impact.rpc(hit.position, hit.normal, ImpactEffects.surface_of(collider, hit.normal), attach)
	# G2: soldiers the bullet flew close past duck (suppression).
	var bullet_end: Vector3 = hit.position if not hit.is_empty() else origin + direction.normalized() * w.max_range_m
	get_tree().call_group("enemies", "bullet_near", origin, bullet_end, w.suppression)
	# Enemies within earshot hear the shot and look towards it.
	get_tree().call_group("enemies", "hear_noise", origin, origin, w.noise_radius_m)


@rpc("authority", "call_local", "reliable")
func confirm_hit(killed: bool) -> void:
	hit_confirmed.emit(killed)


@rpc("authority", "call_local", "unreliable")
func show_impact(pos: Vector3, normal: Vector3, surface: String, attach_path: NodePath) -> void:
	var effects := get_tree().get_first_node_in_group("impact_effects") as ImpactEffects
	if effects:
		var attach_to: Node3D = get_node_or_null(attach_path) if not attach_path.is_empty() else null
		effects.spawn_impact(pos, normal, surface, attach_to)


@rpc("authority", "call_remote", "unreliable")
func remote_fire_effects() -> void:
	if not player.is_local_player():
		_play_remote_fire_effects()


func _play_remote_fire_effects() -> void:
	_play(remote_audio, get_current_weapon().fire_sound)
	var effects := get_tree().get_first_node_in_group("impact_effects") as ImpactEffects
	if effects:
		effects.spawn_flash(camera.global_position - camera.global_basis.z * 0.9)
	_spawn_smoke(camera.global_position - camera.global_basis.z * 0.9, -camera.global_basis.z)


## Gun smoke at the muzzle. Automatic fire makes one puff every ~0.15 s, not one per round.
func _spawn_smoke(pos: Vector3, direction: Vector3, faint: bool = false) -> void:
	if _now() - _last_smoke_time < 0.15:
		return
	_last_smoke_time = _now()
	var effects := get_tree().get_first_node_in_group("impact_effects") as ImpactEffects
	if effects:
		effects.spawn_smoke(pos, direction, false, faint)


# ------------------------------------------------------------------ helpers
func _set_current_slot(value: int) -> void:
	current_slot = value
	if is_node_ready():
		_apply_slot()


func _apply_slot() -> void:
	for i in _view_models.size():
		_view_models[i].visible = (i == current_slot)
	_next_fire_time = _now() + switch_time
	_bloom_deg = 0.0
	if current_slot < _view_models.size():
		_view_models[current_slot].play_raise(switch_time)
	weapon_changed.emit(get_current_weapon())


func _set_is_reloading(value: bool) -> void:
	var started: bool = value and not is_reloading
	is_reloading = value
	if started and is_node_ready() and player.is_local_player():
		var w := get_current_weapon()
		_current_view_model().play_reload(w.reload_time)
		_play(mech_audio, w.get_reload_sound())


func _current_view_model() -> ViewModel:
	return _view_models[current_slot]


## Walks up from the hit collider to find something with take_damage().
func _find_damageable(node: Node) -> Node:
	var n: Node = node
	for i in 4:
		if n == null:
			return null
		if n.has_method("take_damage"):
			return n
		n = n.get_parent()
	return null


func _play(audio: Node, stream: AudioStream) -> void:
	if stream == null:
		return
	audio.set("stream", stream)
	audio.call("play")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
