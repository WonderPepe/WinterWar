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
## The parts of the imported model that turn with the aim get a new parent, `TurnPivot`, at
## start; it follows `Pivot` (the aim) every frame. The model's own belt-feed animation is
## re-pointed at the moved parts and played while firing.
## Water cooling: every shot heats the water jacket (`heat`, synced). Long bursts make it
## steam, and at full heat the gun is OVERHEATED until it has cooled down to about half.
## Children used: Pivot/Muzzle, Pivot/SightEye (right mouse = look through the sights),
## Pivot/GripR, Pivot/GripL, Pivot/BeltGrip (hands), Pivot/SteamPoint.

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
@export_range(0.0, 1.0) var sight_kick_share: float = 0.25 ## How much of the recoil push the aiming eye follows.

# --- Synced from the host by GunSync ---
var user_id: int = 0 ## Peer id of the player on the gun, 0 = free.
var ammo: int = 250 ## Rounds left in the belt.
var is_reloading: bool = false:
	set = _set_is_reloading
var heat: float = 0.0 ## 0 = cold water jacket ... 1 = boiling: overheated.
var is_overheated: bool = false

var _reload_timer: float = 0.0   # host
var _server_next_fire: float = 0.0 # host
var _flash_until: float = 0.0
var _kick: float = 0.0
var _pivot_rest: Vector3
var _smoke: CPUParticles3D
var _smoke_until: float = 0.0
var _last_shot_time: float = -10.0 # host: slower cooling while firing
var _reload_started: float = -10.0
var _turn_pivot: Node3D
var _turn_offset: Transform3D # TurnPivot relative to Pivot (includes the model's scale)
var _belt_anim: AnimationPlayer
var _steam: CPUParticles3D
var _steam_mat: StandardMaterial3D

@onready var pivot: Node3D = $Pivot
@onready var muzzle: Node3D = $Pivot/Muzzle
@onready var flash: Node3D = $Pivot/Muzzle/MuzzleFlash
@onready var flash_light: OmniLight3D = $Pivot/Muzzle/FlashLight
@onready var seat: Marker3D = $SeatPoint
@onready var exit_point: Marker3D = $ExitPoint
@onready var shot_audio: AudioStreamPlayer3D = $ShotAudio
@onready var mech_audio: AudioStreamPlayer3D = $MechAudio
@onready var steam_audio: AudioStreamPlayer3D = $SteamAudio
@onready var sight_eye: Node3D = $Pivot/SightEye
@onready var grip_r: Node3D = $Pivot/GripR
@onready var grip_l: Node3D = $Pivot/GripL
@onready var belt_grip: Node3D = $Pivot/BeltGrip


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
	var hiss := steam_audio.stream as AudioStreamWAV
	if hiss:
		hiss.loop_mode = AudioStreamWAV.LOOP_FORWARD
		hiss.loop_end = int(hiss.get_length() * hiss.mix_rate) # in samples
	_steam = make_steam_emitter()
	_steam_mat = (_steam.mesh as PrimitiveMesh).material as StandardMaterial3D
	get_node("Pivot/SteamPoint").add_child(_steam)


## Hides extra parts and gives the turning parts of the imported model their TurnPivot.
func _prepare_model() -> void:
	var model: Node = get_node_or_null("Model")
	if model == null:
		return
	for part_name in hidden_part_names:
		var part := model.find_child(part_name, true, false) as Node3D
		if part:
			part.visible = false
	var parts: Array[Node3D] = []
	for part_name in turning_part_names:
		var part := model.find_child(part_name, true, false) as Node3D
		if part:
			parts.append(part)
	if parts.is_empty():
		return
	# TurnPivot sits at the Pivot point but inside the model, so the moved parts keep the
	# model's units – the belt animation's numbers stay valid (only shifted).
	var parts_parent: Node3D = parts[0].get_parent()
	_turn_pivot = Node3D.new()
	_turn_pivot.name = "TurnPivot"
	parts_parent.add_child(_turn_pivot)
	_turn_pivot.global_position = pivot.global_position
	for part in parts:
		if part.get_parent() == parts_parent:
			part.reparent(_turn_pivot, true)
	_turn_offset = pivot.global_transform.affine_inverse() * _turn_pivot.global_transform
	_setup_belt_animation(model)


## The glTF's animation feeds the belt: cartridges move in, empty cases drop out.
## Its tracks still point at the parts' old place, so a copy is re-pointed and shifted.
func _setup_belt_animation(model: Node) -> void:
	var ap := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(&"Animation"):
		return
	var anim := ap.get_animation(&"Animation").duplicate(true) as Animation
	var anim_root: Node = ap.get_node(ap.root_node)
	var shift: Vector3 = _turn_pivot.position
	for t in range(anim.get_track_count() - 1, -1, -1):
		var path: NodePath = anim.track_get_path(t)
		var part_name: StringName = path.get_name(path.get_name_count() - 1)
		var part := _turn_pivot.get_node_or_null(NodePath(part_name)) as Node3D
		if part == null or not part.visible:
			anim.remove_track(t) # e.g. the model's own muzzle flash (hidden)
			continue
		anim.track_set_path(t, anim_root.get_path_to(part))
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
			for k in anim.track_get_key_count(t):
				anim.track_set_key_value(t, k, (anim.track_get_key_value(t, k) as Vector3) - shift)
	anim.loop_mode = Animation.LOOP_NONE
	var lib := AnimationLibrary.new()
	lib.add_animation(&"belt", anim)
	for old_lib in ap.get_animation_library_list():
		ap.remove_animation_library(old_lib) # the original tracks point at the old places
	ap.add_animation_library(&"feed", lib)
	_belt_anim = ap
	ap.play(&"feed/belt")
	ap.seek(0.0, true)
	ap.pause()


## Steam from the water jacket: white wisps rising and drifting with the wind.
static func make_steam_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Steam"
	p.emitting = false
	p.amount = 16
	p.lifetime = 1.6
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.7
	p.gravity = Vector3(0.25, 0.45, 0.1) # rises, the wind takes it
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.96, 0.97, 0.98, 0.2))
	fade.set_color(1, Color(0.96, 0.97, 0.98, 0.0))
	p.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = ImpactEffects.make_soft_texture()
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ImpactEffects.web_fallback(p) # fixed material colour (particle colours turn black on some GPUs)
	return p


## Where the eye goes when aiming through the sights (global). The gun's recoil push moves the
## sights only a little here (a quarter): with the full push, the view jolted back and forth at
## every round and looked as if the aim dropped out.
func get_sight_eye_position() -> Vector3:
	var pivot_pos: Vector3 = _pivot_rest + pivot.basis.z * _kick * sight_kick_share
	return global_transform * (pivot_pos + pivot.basis * sight_eye.position)


## Where the gunner's hands go this frame: [right, left] as global transforms.
## While a new belt goes in, the right hand works the feed block.
func get_hand_grips() -> Array[Transform3D]:
	var r: Transform3D = grip_r.global_transform
	if is_reloading and data:
		var t: float = Time.get_ticks_msec() / 1000.0 - _reload_started
		var w: float = smoothstep(0.0, 0.6, t) * (1.0 - smoothstep(data.reload_time - 0.7, data.reload_time - 0.1, t))
		r = r.interpolate_with(belt_grip.global_transform, w)
	return [r, grip_l.global_transform]


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
	if _turn_pivot:
		_turn_pivot.global_transform = pivot.global_transform * _turn_offset
	_update_steam()
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


func _update_steam() -> void:
	var steaming: bool = data != null and data.heat_per_shot > 0.0 and heat >= data.steam_heat
	_steam.emitting = steaming
	if steaming:
		var t: float = inverse_lerp(data.steam_heat, 1.0, heat)
		_steam_mat.albedo_color.a = lerpf(0.06, 0.22, t) * (1.4 if is_overheated else 1.0)
		if not steam_audio.playing:
			steam_audio.play()
		steam_audio.volume_db = lerpf(-24.0, -10.0, t)
	elif steam_audio.playing:
		steam_audio.stop()


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
	# The water jacket cools down (faster when hot, slower while still firing).
	if heat > 0.0 and data:
		var firing: bool = Time.get_ticks_msec() / 1000.0 - _last_shot_time < 0.3
		var rate: float = data.cooling_rate * (data.firing_cooling_multiplier if firing else 1.0)
		heat = maxf(heat - heat * rate * delta, 0.0)
		if heat < 0.002:
			heat = 0.0
		if is_overheated and heat <= data.overheat_recover_heat:
			is_overheated = false


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
	if user == null or shooter != user_id or user.is_dead or is_reloading or is_overheated or ammo <= 0 or now < _server_next_fire:
		return
	_server_next_fire = now + data.get_shot_interval() * 0.8 # small tolerance for network jitter
	_last_shot_time = now
	if data.heat_per_shot > 0.0:
		heat = minf(heat + data.heat_per_shot, 1.0)
		if heat >= 1.0:
			is_overheated = true
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
	if _belt_anim:
		# One run of the feed animation per round.
		_belt_anim.speed_scale = _belt_anim.get_animation(&"feed/belt").length / data.get_shot_interval()
		_belt_anim.play(&"feed/belt")
		_belt_anim.seek(0.0, true)
	if data and data.fire_sound:
		shot_audio.stream = data.fire_sound
		shot_audio.play()


func _set_is_reloading(value: bool) -> void:
	var started: bool = value and not is_reloading
	is_reloading = value
	if started:
		_reload_started = Time.get_ticks_msec() / 1000.0
	var sound: AudioStream = data.get_reload_sound() if data else null
	if started and is_node_ready() and sound:
		mech_audio.stream = sound
		mech_audio.play()
