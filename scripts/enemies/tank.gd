class_name Tank
extends AnimatableBody3D
## A Soviet T-26 light tank (T1). Armoured: rifle and machine-gun bullets only make sparks.
##
## It drives along a drawn route (a Path3D in the group "tank_route") from the southern forest
## to the edge of the Finnish trench, and stops there for good. On the way:
##   ADVANCE   – nobody in sight: drives at full speed, the turret searches.
##   SUPPRESS  – a player in sight: drives slower and fires the turret's DT machine gun.
##   HALT_FIRE – every 15–25 s (if someone is in sight) it stops, aims and fires one
##               45 mm high-explosive shell, then drives on.
##   AT_TRENCH – at the trench edge: stands still, sweeps the trench, DT + main gun.
##   BURNING   – (T2) a Molotov cocktail on the engine deck: stops, stops firing, the engine
##               burns, the crew bail out and run; after `burn_time` s → DESTROYED.
##   DESTROYED – stops, goes dark, smokes for the rest of the game (also debug key F10).
## Like the soldiers, all thinking, moving and shooting happens on the HOST. Other computers
## get the position, facing, turret/gun angles and state through StateSync and only draw it.

signal destroyed(tank: Tank)

enum State { ADVANCE, SUPPRESS, HALT_FIRE, AT_TRENCH, DESTROYED, BURNING } # (new states go at the end: synced as numbers)

const SOUNDS_DIR := "res://assets/audio/tank/"

@export_group("Driving")
@export var speed: float = 2.0 ## m/s with nobody in sight (T-26 in snow: a fast walk).
@export var suppress_speed: float = 1.2 ## m/s while firing the DT on the move.
@export var acceleration: float = 0.8 ## m/s² (also braking).
@export var turn_speed_deg: float = 22.0 ## How fast the hull turns to follow the route.
@export var look_ahead_m: float = 4.0 ## The hull points at the route this far ahead.
@export var track_half_length: float = 1.8 ## Ground is sampled this far in front of / behind the centre...
@export var track_half_width: float = 1.0 ## ...and this far to the sides (for tilting over bumps).

@export_group("Turret and sight")
@export var turret_speed_deg: float = 24.0 ## Turret traverse (hand-cranked).
@export var gun_speed_deg: float = 14.0 ## Gun elevation speed.
@export var gun_min_deg: float = -10.0 ## (The real T-26 managed about -6°; a little more so it can fire into the trench.)
@export var gun_max_deg: float = 22.0
@export var vision_range_m: float = 260.0 ## Players further than this are not noticed.
@export var spot_time: float = 1.5 ## Seconds a player must be in sight before the crew opens fire.
@export var crouch_spot_multiplier: float = 2.0 ## Crouching players take this much longer to notice.
@export var forget_time: float = 4.0 ## Seconds out of sight before the crew gives up on a target.

@export_group("DT machine gun")
@export var dt_damage: float = 25.0 ## Per round (× the difficulty's Enemy.damage_multiplier).
@export var dt_range_m: float = 350.0
@export var dt_interval: float = 0.1 ## Seconds between rounds (about 600 rounds/min).
@export var dt_burst_min: int = 5
@export var dt_burst_max: int = 12
@export var dt_pause_min: float = 1.2
@export var dt_pause_max: float = 2.6
@export var dt_magazine: int = 63 ## Rounds in a DT pan.
@export var dt_reload_time: float = 5.0
@export var dt_spread_deg: float = 0.8 ## Base cone...
@export var dt_spread_per_100m_deg: float = 0.5 ## ...growing with distance...
@export var dt_moving_spread_deg: float = 1.2 ## ...and wider while the tank drives.
@export var dt_aim_tolerance_deg: float = 3.0 ## Fires once the turret points this close to the target.

@export_group("45 mm gun")
@export var halt_interval_min: float = 15.0 ## Seconds between stops to fire the main gun...
@export var halt_interval_max: float = 25.0
@export var halt_min_distance_m: float = 20.0 ## ...only if the target is at least this far away.
@export var halt_max_time: float = 8.0 ## Gives up the stop after this long without a shot.
@export var gun_aim_time: float = 1.2 ## Steady aim needed before the shot.
@export var gun_aim_tolerance_deg: float = 1.5
@export var gun_reload_min: float = 6.0 ## At the trench: seconds between shells.
@export var gun_reload_max: float = 10.0
@export var gun_spread_deg: float = 0.5
@export var shell_kill_radius_m: float = 1.5 ## This close to the burst = dead.
@export var shell_harm_radius_m: float = 6.0 ## Hurt up to this far (if the blast can reach you).
@export var shell_near_damage: float = 80.0 ## Just outside the kill radius (falls to 10 at the edge).

@export_group("Trench edge")
@export var sweep_angle_deg: float = 55.0 ## With nobody in sight, the turret searches this far left/right.

@export_group("Molotov (T2)")
## The engine deck (model space, metres): a bottle bursting inside this box sets the tank on
## fire. T-26: the flat rear deck with the engine louvres, behind the turret.
@export var engine_deck: AABB = AABB(Vector3(-1.15, 1.1, 0.9), Vector3(2.3, 0.8, 1.55))
@export var burn_time: float = 20.0 ## Seconds of fire before it is a wreck.
@export var blind_time: float = 4.0 ## Fire on the armour elsewhere: the crew can't see / shoot.
@export var crew_count: int = 3
@export var crew_delay_min: float = 2.0 ## The crew bail out this many seconds after it catches fire.
@export var crew_delay_max: float = 4.0
@export var crew_panic_min: float = 6.0 ## Then they run back towards the forest for this long.
@export var crew_panic_max: float = 10.0

# --- Synced from the host by StateSync ---
var state: State = State.ADVANCE:
	set = _set_state
var turret_yaw: float = 0.0 ## Radians, relative to the hull (0 = straight ahead).
var gun_pitch: float = 0.0 ## Radians, up = positive.
var drive_speed: float = 0.0 ## m/s now (engine sound).

## Host: the route this tank follows (set by the TankSpawner before it is added).
var route: Path3D = null
## Host: who comes out when it burns (TankSpawner sets these).
var crew_scene: PackedScene = null
var crew_root: Node3D = null
var crew_bailed: int = 0 ## Tests.
var shells_fired: int = 0 ## Statistics / tests.
var dt_rounds_fired: int = 0

# --- Host-only memory ---
var _distance: float = 0.0 # metres driven along the route
var _route_length: float = 0.0
var _clock: float = 0.0
var _sense_timer: float = 0.0
var _target: Player = null
var _target_visible: bool = false
var _spot: Dictionary = {} # Player -> 0..1 how close to being noticed
var _last_known: Vector3
var _last_seen_time: float = -100.0
var _next_halt: float = 0.0
var _halt_started: float = 0.0
var _aim_steady: float = 0.0
var _next_gun_shot: float = 0.0
var _after_shot_until: float = -1.0
var _dt_burst_left: int = 0
var _dt_next_round: float = 0.0
var _dt_next_burst: float = 0.0
var _dt_ammo: int = 63
var _dt_reload_until: float = 0.0
var _sweep_phase: float = 0.0
var _yaw: float = 0.0 # hull heading
var _blind_until: float = -1.0
var _burn_until: float = 0.0
var _next_crew: float = 0.0
var _engine_fire: Node3D
var _rng := RandomNumberGenerator.new()

# --- Visuals (every computer) ---
var _turret_mesh: Node3D
var _gun_mesh: Node3D
var _turret_offset: Transform3D
var _gun_offset: Transform3D
var _last_smoke: float = 0.0
var _wreck_smoke: CPUParticles3D

@onready var model: Node3D = $Model
@onready var turret_pivot: Node3D = $TurretPivot
@onready var gun_pivot: Node3D = $TurretPivot/GunPivot
@onready var muzzle: Marker3D = $TurretPivot/GunPivot/Muzzle
@onready var dt_muzzle: Marker3D = $TurretPivot/GunPivot/DtMuzzle
@onready var eye: Marker3D = $TurretPivot/Eye
@onready var engine_sound: AudioStreamPlayer3D = $EngineSound
@onready var gun_sound: AudioStreamPlayer3D = $TurretPivot/GunPivot/GunSound
@onready var dt_sound: AudioStreamPlayer3D = $TurretPivot/GunPivot/DtSound


func _ready() -> void:
	add_to_group("tanks")
	_rng.randomize()
	_dt_ammo = dt_magazine
	_split_model()
	_setup_sounds()
	if multiplayer.is_server():
		_next_halt = _rng.randf_range(halt_interval_min * 0.5, halt_interval_max * 0.5)
		if route and route.curve:
			_route_length = route.curve.get_baked_length()
			var start: Vector3 = route.to_global(route.curve.sample_baked(0.0))
			var ahead: Vector3 = route.to_global(route.curve.sample_baked(look_ahead_m))
			_yaw = _heading_to(start, ahead)
			_place_on_ground(start, 0.0)
	_apply_pivots()
	if state == State.BURNING:
		_start_engine_fire() # joined a game where this one was already burning
	if state == State.DESTROYED:
		_become_wreck() # joined a game where this one was already knocked out


## The turret and the gun are separate parts of the glTF model. They are taken out of the
## model's own (scaled, rotated) node chain and made to follow TurretPivot / GunPivot instead.
func _split_model() -> void:
	_turret_mesh = model.find_child("vertices_001", true, false) as Node3D
	_gun_mesh = model.find_child("gun_08Shape", true, false) as Node3D
	for part in [_turret_mesh, _gun_mesh]:
		if part == null:
			push_warning("Tank: turret/gun part missing from the model")
			return
	_turret_offset = turret_pivot.global_transform.affine_inverse() * _turret_mesh.global_transform
	_gun_offset = gun_pivot.global_transform.affine_inverse() * _gun_mesh.global_transform
	_turret_mesh.top_level = true
	_gun_mesh.top_level = true


func _setup_sounds() -> void:
	var engines: Array[String] = ["engine_a.ogg", "engine_b.ogg"]
	var stream: AudioStream = load(SOUNDS_DIR + engines[absi(hash(name)) % engines.size()])
	engine_sound.stream = stream
	var gun: AudioStream = RecordedSounds.pick("tank_gun")
	gun_sound.stream = gun if gun else load(SOUNDS_DIR + "gun_bang.ogg")
	var dt: AudioStream = RecordedSounds.pick("tank_dt")
	dt_sound.stream = dt if dt else load(SOUNDS_DIR + "dt_shot.ogg")
	engine_sound.play(randf() * 5.0)


func _physics_process(delta: float) -> void:
	_clock += delta
	if not multiplayer.is_server() or state == State.DESTROYED:
		return
	if state == State.BURNING:
		_burning()
		return
	_sense_timer -= delta
	if _sense_timer <= 0.0:
		_sense_timer = 0.25
		_update_senses(0.25)
	_think(delta)
	_drive(delta)
	_aim(delta)
	_fire_dt()


func _process(_delta: float) -> void:
	_apply_pivots()
	if _engine_fire:
		var light := _engine_fire.get_node("FireLight") as OmniLight3D
		light.light_energy = 1.6 + randf() * 0.9 # flickering flames
	# Engine: idles low when standing, revs up when driving.
	var t: float = clampf(drive_speed / maxf(speed, 0.1), 0.0, 1.0)
	engine_sound.pitch_scale = lerpf(0.82, 1.0, t)
	engine_sound.volume_db = lerpf(-5.0, 0.0, t)


func _apply_pivots() -> void:
	turret_pivot.rotation.y = turret_yaw
	gun_pivot.rotation.x = gun_pitch
	if _turret_mesh and _gun_mesh:
		_turret_mesh.global_transform = turret_pivot.global_transform * _turret_offset
		_gun_mesh.global_transform = gun_pivot.global_transform * _gun_offset


# ------------------------------------------------------------------ senses (host)
func _update_senses(dt: float) -> void:
	var best: Player = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == null:
			continue
		var visible_now: bool = not p.is_dead and _can_see(p)
		if not visible_now:
			_spot[p] = maxf(float(_spot.get(p, 0.0)) - dt * 0.5, 0.0)
			continue
		var t: float = spot_time * (crouch_spot_multiplier if p.is_crouching else 1.0)
		if state == State.SUPPRESS or state == State.AT_TRENCH:
			t *= 0.5 # already fighting: quicker to notice the next one
		_spot[p] = minf(float(_spot.get(p, 0.0)) + dt / t, 1.0)
		if _spot[p] >= 1.0:
			var d: float = eye.global_position.distance_to(p.head.global_position)
			if p == _target:
				d *= 0.7 # stick with the one we are already shooting at
			if d < best_dist:
				best = p
				best_dist = d
	if best:
		_target = best
		_target_visible = true
		_last_known = _aim_point(best)
		_last_seen_time = _clock
	else:
		_target_visible = false
		if _target and (_clock - _last_seen_time > forget_time or not is_instance_valid(_target) or _target.is_dead):
			_target = null


func _can_see(p: Player) -> bool:
	var from: Vector3 = eye.global_position
	if from.distance_to(p.head.global_position) > vision_range_m:
		return false
	return _clear_line(from, p.head.global_position) or _clear_line(from, _chest_of(p))


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 0b1) # world only
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _chest_of(p: Player) -> Vector3:
	return p.global_position + Vector3.UP * (0.75 if p.is_crouching else 1.3)


## Where the gunner aims: the chest if it can be seen, else the head.
func _aim_point(p: Player) -> Vector3:
	var chest: Vector3 = _chest_of(p)
	return chest if _clear_line(eye.global_position, chest) else p.head.global_position


# ------------------------------------------------------------------ decisions (host)
func _think(_delta: float) -> void:
	var at_end: bool = _distance >= _route_length - 0.05
	match state:
		State.ADVANCE, State.SUPPRESS:
			if at_end:
				state = State.AT_TRENCH
				_next_gun_shot = _clock + _rng.randf_range(2.0, 4.0)
				return
			state = State.SUPPRESS if _target_visible else State.ADVANCE
			if _target_visible and _clock >= _next_halt and _distance_to_target() >= halt_min_distance_m:
				state = State.HALT_FIRE
				_halt_started = _clock
				_aim_steady = 0.0
				_after_shot_until = -1.0
		State.HALT_FIRE:
			var done_waiting: bool = _after_shot_until > 0.0 and _clock >= _after_shot_until
			if done_waiting or _clock - _halt_started > halt_max_time:
				_next_halt = _clock + _rng.randf_range(halt_interval_min, halt_interval_max)
				state = State.SUPPRESS if _target_visible else State.ADVANCE
				return
			if _after_shot_until < 0.0 and drive_speed < 0.05 and _main_gun_ready():
				_fire_main_gun()
				_after_shot_until = _clock + 1.5
		State.AT_TRENCH:
			if _clock >= _next_gun_shot and _main_gun_ready():
				_fire_main_gun()
				_next_gun_shot = _clock + _rng.randf_range(gun_reload_min, gun_reload_max)


func _distance_to_target() -> float:
	return global_position.distance_to(_last_known) if _target else 0.0


## True once the gun has pointed steadily at a visible target for `gun_aim_time`.
func _main_gun_ready() -> bool:
	return _target_visible and _aim_steady >= gun_aim_time and not is_blinded()


## Fire on the armour in front of the vision slits: the crew can't aim for a moment.
func is_blinded() -> bool:
	return _clock < _blind_until


# ------------------------------------------------------------------ driving (host)
func _drive(delta: float) -> void:
	var wanted: float = 0.0
	match state:
		State.ADVANCE:
			wanted = speed
		State.SUPPRESS:
			wanted = suppress_speed
	if route == null or route.curve == null:
		wanted = 0.0
	drive_speed = move_toward(drive_speed, wanted, acceleration * delta)
	if route == null or route.curve == null:
		return
	_distance = minf(_distance + drive_speed * delta, _route_length)
	var curve: Curve3D = route.curve
	var here: Vector3 = route.to_global(curve.sample_baked(_distance))
	var ahead: Vector3 = route.to_global(curve.sample_baked(minf(_distance + look_ahead_m, _route_length)))
	if here.distance_to(ahead) > 0.5:
		var want_yaw: float = _heading_to(here, ahead)
		_yaw = rotate_toward(_yaw, want_yaw, deg_to_rad(turn_speed_deg) * delta)
	_place_on_ground(here, delta)


## Heading (rotation.y) that makes -z point from `a` towards `b`.
func _heading_to(a: Vector3, b: Vector3) -> float:
	return atan2(-(b.x - a.x), -(b.z - a.z))


## Puts the tank on the ground at `pos`, tilted to follow the bumps under its tracks.
func _place_on_ground(pos: Vector3, delta: float) -> void:
	var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var h_front: float = _ground(terrain, pos + fwd * track_half_length)
	var h_back: float = _ground(terrain, pos - fwd * track_half_length)
	var h_left: float = _ground(terrain, pos - right * track_half_width)
	var h_right: float = _ground(terrain, pos + right * track_half_width)
	var pitch: float = atan2(h_front - h_back, track_half_length * 2.0)
	var roll: float = atan2(h_right - h_left, track_half_width * 2.0)
	var y: float = (h_front + h_back + h_left + h_right) / 4.0
	var target := Vector3(pos.x, y, pos.z)
	if delta > 0.0:
		# Smooth out tiny steps between the 1 m terrain vertices.
		var k: float = clampf(delta * 6.0, 0.0, 1.0)
		target.y = lerpf(global_position.y, y, k)
		pitch = lerp_angle(rotation.x, pitch, k)
		roll = lerp_angle(rotation.z, roll, k)
	global_position = target
	rotation = Vector3(pitch, _yaw, roll)


func _ground(terrain: TerrainGenerator, p: Vector3) -> float:
	return terrain.get_height(p.x, p.z) if terrain else 0.0


# ------------------------------------------------------------------ turret (host)
func _aim(delta: float) -> void:
	var want_yaw: float = 0.0
	var want_pitch: float = 0.0
	var has_point: bool = _target != null
	if has_point:
		# Turn the turret (around the hull's up axis) towards the target, then raise the gun.
		var local: Vector3 = turret_pivot.get_parent_node_3d().global_transform.affine_inverse() * _last_known
		var from_pivot: Vector3 = local - turret_pivot.position
		want_yaw = atan2(-from_pivot.x, -from_pivot.z)
		var gun_origin: Vector3 = turret_pivot.position + Basis(Vector3.UP, want_yaw) * gun_pivot.position
		var d: Vector3 = local - gun_origin
		want_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	elif state == State.AT_TRENCH:
		# Nobody in sight: slowly search left and right along the trench.
		_sweep_phase += delta * 0.18
		want_yaw = sin(_sweep_phase) * deg_to_rad(sweep_angle_deg)
		want_pitch = deg_to_rad(-4.0)
	turret_yaw = rotate_toward(turret_yaw, want_yaw, deg_to_rad(turret_speed_deg) * delta)
	gun_pitch = move_toward(gun_pitch, clampf(want_pitch, deg_to_rad(gun_min_deg), deg_to_rad(gun_max_deg)), deg_to_rad(gun_speed_deg) * delta)
	if has_point and _target_visible and _aim_error_deg(muzzle) < gun_aim_tolerance_deg:
		_aim_steady += delta
	else:
		_aim_steady = 0.0


## Angle between where `from` points (its -z) and the line to the target.
func _aim_error_deg(from: Node3D) -> float:
	var to_target: Vector3 = _last_known - from.global_position
	if to_target.length() < 0.1:
		return 0.0
	return rad_to_deg((-from.global_basis.z).angle_to(to_target))


# ------------------------------------------------------------------ DT machine gun (host)
func _fire_dt() -> void:
	if is_blinded():
		_dt_burst_left = 0
		return
	if _clock < _dt_reload_until:
		return
	if _dt_ammo <= 0:
		_dt_ammo = dt_magazine
		_dt_reload_until = _clock + dt_reload_time
		_dt_burst_left = 0
		return
	var can_fire: bool = _target_visible and _target and not _target.is_dead \
			and _aim_error_deg(dt_muzzle) < dt_aim_tolerance_deg \
			and dt_muzzle.global_position.distance_to(_last_known) < dt_range_m
	if not can_fire:
		_dt_burst_left = 0
		return
	if _dt_burst_left <= 0 and _clock >= _dt_next_burst:
		_dt_burst_left = _rng.randi_range(dt_burst_min, dt_burst_max)
	if _dt_burst_left > 0 and _clock >= _dt_next_round:
		_shoot_dt()
		_dt_ammo -= 1
		_dt_burst_left -= 1
		_dt_next_round = _clock + dt_interval
		if _dt_burst_left <= 0:
			_dt_next_burst = _clock + _rng.randf_range(dt_pause_min, dt_pause_max)


func _shoot_dt() -> void:
	dt_rounds_fired += 1
	var origin: Vector3 = dt_muzzle.global_position
	var distance: float = origin.distance_to(_last_known)
	var spread: float = dt_spread_deg + dt_spread_per_100m_deg * distance / 100.0
	if drive_speed > 0.2:
		spread += dt_moving_spread_deg
	spread *= Enemy.spread_multiplier
	var direction: Vector3 = _scatter((_last_known - origin).normalized(), spread)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * dt_range_m, 0b11) # world + players
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var hit_position := Vector3.ZERO
	var hit_normal := Vector3.UP
	var surface: String = ""
	var hit_player: Player = null
	if not hit.is_empty():
		hit_position = hit.position
		hit_normal = hit.normal
		if hit.collider is Player:
			hit_player = hit.collider
			hit_player.take_damage(dt_damage * Enemy.damage_multiplier, -1, hit.position, hit.normal)
			hit_player.notify_hurt.rpc_id(hit_player.get_peer_id(), origin)
		else:
			surface = ImpactEffects.surface_of(hit.collider, hit.normal)
	show_dt_effects.rpc(hit_position, hit_normal, surface)
	# Players the bullet flew close past hear its crack (like the soldiers' bullets).
	var bullet_end: Vector3 = hit_position if not hit.is_empty() else origin + direction * dt_range_m
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == hit_player or p.is_dead:
			continue
		var closest: Vector3 = Geometry3D.get_closest_point_to_segment(p.head.global_position, origin, bullet_end)
		if closest.distance_to(p.head.global_position) < 3.0 and closest.distance_to(origin) > 10.0:
			bullet_passed.rpc_id(p.get_peer_id(), closest)


## A random direction inside a cone of `spread_deg` around `forward`.
func _scatter(forward: Vector3, spread_deg: float) -> Vector3:
	var basis := Basis.looking_at(forward)
	var angle: float = deg_to_rad(spread_deg) * _rng.randf()
	var around: float = _rng.randf() * TAU
	return basis * Vector3(sin(angle) * cos(around), sin(angle) * sin(around), -cos(angle))


@rpc("authority", "call_local", "unreliable")
func show_dt_effects(hit_position: Vector3, hit_normal: Vector3, surface: String) -> void:
	dt_sound.play()
	var effects := get_tree().get_first_node_in_group("impact_effects") as ImpactEffects
	if effects == null:
		return
	effects.spawn_flash(dt_muzzle.global_position)
	if _clock - _last_smoke > 0.3:
		_last_smoke = _clock
		effects.spawn_smoke(dt_muzzle.global_position, -dt_muzzle.global_basis.z)
	if surface != "":
		effects.spawn_impact(hit_position, hit_normal, surface)


@rpc("authority", "call_local", "unreliable")
func bullet_passed(where: Vector3) -> void:
	var effects := get_tree().get_first_node_in_group("impact_effects") as ImpactEffects
	if effects:
		effects.play_crack(where)


# ------------------------------------------------------------------ 45 mm gun (host)
func _fire_main_gun() -> void:
	shells_fired += 1
	_aim_steady = 0.0
	var origin: Vector3 = muzzle.global_position
	var direction: Vector3 = _scatter((-muzzle.global_basis.z).normalized(), gun_spread_deg * Enemy.spread_multiplier)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 600.0, 0b11)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	show_gun_fire.rpc()
	if hit.is_empty():
		return # the shell flew over everything
	var pos: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	# Who is hurt: everyone near the burst whom the blast can reach (a trench wall shields you).
	var blast_from: Vector3 = pos + normal * 0.3
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p.is_dead:
			continue
		var d: float = minf(p.global_position.distance_to(pos), _chest_of(p).distance_to(pos))
		if d > shell_harm_radius_m:
			continue
		if p != hit.collider and not _clear_line(blast_from, _chest_of(p)) and not _clear_line(blast_from, p.head.global_position):
			continue
		var dmg: float = 500.0 if d <= shell_kill_radius_m else lerpf(shell_near_damage, 10.0, (d - shell_kill_radius_m) / (shell_harm_radius_m - shell_kill_radius_m))
		p.take_damage(dmg, -1, pos, normal)
		p.notify_hurt.rpc_id(p.get_peer_id(), global_position)
	show_shell_burst.rpc(pos)


## Muzzle blast of the 45 mm gun on every computer.
@rpc("authority", "call_local", "reliable")
func show_gun_fire() -> void:
	gun_sound.play()
	var effects := get_tree().get_first_node_in_group("impact_effects") as ImpactEffects
	if effects:
		effects.spawn_flash(muzzle.global_position)
		effects.spawn_smoke(muzzle.global_position, -muzzle.global_basis.z, true)
	_shake_local(global_position, 0.35, 60.0)


## The high-explosive shell bursts: the artillery's explosion (smaller) and its bang.
@rpc("authority", "call_local", "reliable")
func show_shell_burst(pos: Vector3) -> void:
	var arty := get_tree().get_first_node_in_group("artillery") as ArtilleryBarrage
	if arty:
		arty.show_explosion(pos, 0.25)
	else:
		_shake_local(pos, 0.6, 40.0)
	var bang := AudioStreamPlayer3D.new()
	bang.stream = gun_sound.stream
	bang.bus = &"SFX"
	bang.unit_size = 45.0
	bang.pitch_scale = 0.8
	bang.attenuation_filter_cutoff_hz = 3000.0
	get_parent().add_child(bang)
	bang.global_position = pos
	bang.play()
	bang.finished.connect(bang.queue_free)


func _shake_local(pos: Vector3, strength: float, reach: float) -> void:
	for node in get_tree().get_nodes_in_group("players"):
		var pl := node as Player
		if pl.is_local_player():
			pl.add_shake(clampf(1.0 - pl.global_position.distance_to(pos) / reach, 0.0, 1.0) * strength)


# ------------------------------------------------------------------ damage
## Armour: rifle and machine-gun bullets do nothing (the WeaponController shows sparks and
## gives no hit marker). Only a Molotov cocktail on the engine deck stops it (molotov_hit).
func take_damage(_amount: float, _attacker_id: int, _hit_position: Vector3, _hit_normal: Vector3) -> bool:
	return false


func deflects_bullets() -> bool:
	return true


func is_destroyed() -> bool:
	return state == State.DESTROYED


## Host (MolotovManager): a bottle burst at `local_pos` (model space). On the engine deck the
## tank catches fire (returns true); anywhere else the burning fuel only blinds the crew.
func molotov_hit(local_pos: Vector3) -> bool:
	if not multiplayer.is_server() or state == State.DESTROYED or state == State.BURNING:
		return false
	if engine_deck.has_point(local_pos):
		ignite()
		return true
	_blind_until = _clock + blind_time
	return false


## Host: the engine is on fire. The tank stops, the crew bail out, then it burns out.
func ignite() -> void:
	if not multiplayer.is_server() or state == State.DESTROYED or state == State.BURNING:
		return
	drive_speed = 0.0
	_burn_until = _clock + burn_time
	_next_crew = _clock + _rng.randf_range(crew_delay_min, crew_delay_max)
	state = State.BURNING


func _burning() -> void:
	if crew_bailed < crew_count and _clock >= _next_crew:
		_bail_out(crew_bailed)
		crew_bailed += 1
		_next_crew = _clock + _rng.randf_range(0.5, 1.0)
	if _clock >= _burn_until:
		destroy()


## Host: one crewman climbs out beside the hull and runs back towards the forest in panic.
func _bail_out(i: int) -> void:
	if crew_scene == null or crew_root == null:
		return
	var side: float = -1.0 if i % 2 == 0 else 1.0
	var spot: Vector3 = global_transform * Vector3(side * 1.7, 0.0, 0.6 - i * 0.9)
	var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
	spot.y = (terrain.get_height(spot.x, spot.z) if terrain else spot.y) + 0.1
	var e: Enemy = crew_scene.instantiate()
	e.name = "%sCrew%d" % [name, i + 1]
	e.position = spot
	e.rotation.y = _yaw + PI # facing back, away from the trench
	e.attack_point = _nearest_attack_point(spot)
	crew_root.add_child(e, true)
	e.state = Enemy.State.PATROL
	var away := Vector3(spot.x + _rng.randf_range(-8.0, 8.0), spot.y, spot.z - _rng.randf_range(35.0, 50.0))
	e.panic(_rng.randf_range(crew_panic_min, crew_panic_max), away)


func _nearest_attack_point(pos: Vector3) -> Vector3:
	var best := Vector3(pos.x, 0.0, 40.0)
	var best_d: float = INF
	for node in get_tree().get_nodes_in_group("attack_point"):
		var d: float = (node as Node3D).global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = (node as Node3D).global_position
	return best


## Host: knocked out (T1: debug key F10). Stops for good; the wreck stays on the field.
func destroy() -> void:
	if not multiplayer.is_server() or state == State.DESTROYED:
		return
	drive_speed = 0.0
	state = State.DESTROYED
	destroyed.emit(self)


## Host: the battle is over – stop where you are.
func freeze() -> void:
	drive_speed = 0.0
	set_physics_process(false)


func _set_state(value: State) -> void:
	var was: State = state
	state = value
	if not is_node_ready():
		return
	if value == State.BURNING and was != State.BURNING:
		_start_engine_fire()
	if value == State.DESTROYED and was != State.DESTROYED:
		_become_wreck()


## Every computer: the engine deck is on fire – flames, thick black smoke and a flickering
## light (the only light a tank has; budget: see CLAUDE.md).
func _start_engine_fire() -> void:
	engine_sound.stop()
	if _engine_fire:
		return
	var soft: Texture2D = ImpactEffects.make_soft_texture()
	_engine_fire = Node3D.new()
	_engine_fire.name = "EngineFire"
	add_child(_engine_fire)
	_engine_fire.position = engine_deck.get_center() + Vector3(0, -0.4, 0)
	var flames := MolotovManager.make_flames(48, 3.0, soft)
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flames.emission_box_extents = Vector3(0.8, 0.05, 0.8)
	flames.emitting = true
	_engine_fire.add_child(flames)
	var smoke := MolotovManager.make_black_smoke(30, 1.8, soft)
	smoke.position.y = 0.8
	smoke.emitting = true
	_engine_fire.add_child(smoke)
	var light := OmniLight3D.new()
	light.name = "FireLight"
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 9.0
	light.light_energy = 2.0
	light.position.y = 1.0
	_engine_fire.add_child(light)
	var crackle: AudioStream = RecordedSounds.pick("fire_loop")
	if crackle:
		var a := AudioStreamPlayer3D.new()
		a.bus = &"SFX"
		a.unit_size = 14.0
		a.stream = crackle
		_engine_fire.add_child(a)
		a.play()


## Every computer: engine off, the paint goes dark, black smoke rises for the rest of the game.
func _become_wreck() -> void:
	add_to_group("tank_wrecks")
	engine_sound.stop()
	if _engine_fire:
		_engine_fire.queue_free() # the fire burns out; the wreck smokes on
		_engine_fire = null
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.03, 0.03, 0.6)
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = dark
	_wreck_smoke = _make_wreck_smoke()
	add_child(_wreck_smoke)
	_wreck_smoke.position = Vector3(0, 1.6, 1.3) # over the engine deck at the back
	_wreck_smoke.emitting = true


func _make_wreck_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "WreckSmoke"
	p.amount = 48
	p.lifetime = 7.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0.5, 0.35, 0.25) # rises and drifts with the wind
	p.damping_min = 0.2
	p.damping_max = 0.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	p.scale_amount_min = 2.5
	p.scale_amount_max = 4.5
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = ImpactEffects.make_soft_texture()
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fade := Gradient.new()
	fade.set_color(0, Color(0.1, 0.1, 0.1, 0.55))
	fade.set_color(1, Color(0.25, 0.25, 0.27, 0.0))
	p.color_ramp = fade
	ImpactEffects.web_fallback(p) # (particle colours draw black in browsers – see CLAUDE.md)
	return p
