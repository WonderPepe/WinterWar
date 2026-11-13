class_name Enemy
extends CharacterBody3D
## A Soviet rifleman, controlled by a simple "state machine".
##
## The soldier is always in exactly ONE state (Idle, Patrol, Alert, Attack, Dead, Assault).
## Hold (L3, battle 6): he is one of the Soviets who took part of the Finnish trench – he stays at
## his spot in it and fires at any Finn he sees, goes for a Finn close by round a corner, but never
## leaves his stretch of trench.
## Assault (G1): after firing for a while from his jump-off point in front of the trench, he
## rushes the trench, jumps in (NavigationLink3D "trench entries") and fights inside it.
## Each state has its own behaviour and rules for switching to another state.
## G2 "pressure": bullets flying close make him duck (suppression) and throw himself flat
## (prone); an officer steadies the soldiers around him and sends them forward with his
## whistle; a DP-27 gunner lies down and fires bursts, with a helper next to him.
## All thinking, moving and shooting happens on the HOST only; other computers just
## receive the position, facing and state through StateSync.

signal died(enemy: Enemy)
signal whistled ## An officer blew his whistle (host).

enum State { IDLE, PATROL, ALERT, ATTACK, DEAD, ASSAULT, HOLD } # (new states go at the end: synced as numbers)

const TRENCH_FLOOR_BELOW: float = -0.85 ## Below this height (and behind z = 48) = inside the trench.
const TRENCH_FRONT_Z: float = 48.0

## Set by the MatchDirector from the difficulty: < 1 = better aim.
static var spread_multiplier: float = 1.0
## Difficulty: soldiers' bullet damage × this (host, set by the MatchDirector).
static var damage_multiplier: float = 1.0
## Host: while an artillery barrage falls on the trench, nobody comes closer than this z
## (INF = no barrage). They hurry up to it, wait there, and go on when it lifts.
## B3: how far the weather lets soldiers see (set by DuskLight; INF = no limit). Host AI only.
static var visibility_limit: float = INF
static var barrage_hold_z: float = INF

static var show_debug_labels: bool = false ## Toggled with F2 for all enemies.

@export var data: EnemyData
@export var corpse_time: float = 20.0 ## Seconds before a dead body is removed.
@export var near_miss_distance: float = 3.0 ## A bullet this close to your head makes a crack.
@export_group("Holding the trench (L3)")
## HOLD: sees and fires at Finns up to this far (fog can limit it) – short, so the rear spawn
## points (34–42 m away) are out of reach and the Finns can work their way up to the line...
@export var hold_sight_m: float = 30.0
## ...but a Finn who shoots AT them (a hit or a bullet close past) is seen up to this far for a while.
@export var hold_alert_sight_m: float = 40.0
@export var hold_alert_time: float = 8.0
@export var hold_chase_m: float = 14.0 ## HOLD: goes for a Finn in the trench this close who is out of sight...
@export var hold_leash_m: float = 18.0 ## ...but only this far from his spot.
@export_group("")

# --- Synced from the host by StateSync ---
var state: State = State.IDLE:
	set = _set_state
var is_kneeling: bool = false:
	set = _set_kneeling
var is_prone: bool = false: ## Lying flat (suppressed, or a machine-gun team in position).
	set = _set_prone
var health: float = 100.0

## Set by the WaveSpawner: the place in front of the trench this soldier advances to.
var attack_point: Vector3 = Vector3.ZERO
## L3: HOLD – his spot in the captured trench (set by the WaveSpawner with `start_holding`).
var hold_point: Vector3 = Vector3.ZERO
var _hold_alert_until: float = -100.0 # HOLD: shot at – looking further for the shooter until then

# --- G2, host only ---
## 0 = calm … 1 = can't lift his head. Close bullets raise it, it wears off by itself.
var suppression: float = 0.0
var mg_gunner: Enemy = null    ## Machine-gun helper: the gunner he stays with.
var mg_assistant: Enemy = null ## Machine-gunner: his helper.
var home_point: Vector3        ## MG team: where he goes as a rifleman (helper: gunner fell; both: team sent forward).
var mg_ammo: int = 0           ## Machine-gunner: rounds left in the pan.
var whistle_count: int = 0     ## Officer: how many times he has whistled (tests, statistics).
## Machine-gunner: sent forward like a rifleman (all the riflemen of the wave are dead).
var mg_released: bool = false
var _mg_final_goal: Vector3      # gunner: his last position, 5–10 m behind the riflemen's attack point
var _mg_fire_range: float = 100.0 # gunner: opens fire within this distance of the trench (80–130 m)
var _mg_follow_back: float = 7.0  # gunner: stays this far behind his riflemen
var _mg_follow_timer: float = 0.0
var _mg_no_deploy_before_z: float = -INF # gunner: moving up – don't lie down again before this z
var _mg_hurry: bool = false        # gunner: far behind his riflemen – hurry to catch up
var _mg_deployed_at: float = 0.0   # gunner: when the gun was last set up

# --- Host-only memory ---
var _state_time: float = 0.0
var _sense_timer: float = 0.0
var _target: Player = null
var _can_see_target: bool = false
var _spot_progress: float = 0.0     # 0..1, how close we are to noticing a player
var _last_known_position: Vector3
var _lost_sight_time: float = 0.0
var _noise_position: Vector3
var _idle_time: float = 2.0
var _aim_time: float = 0.0          # how long we have been steadily aiming
var _reaction_delay: float = 1.0
var _next_shot_time: float = 0.0
var _shots_at_target: int = 0
var _attack_moving: bool = false    # advancing between firing stops
var _attack_phase_time: float = 0.0
var _attack_phase_length: float = 0.0 # how long the current advance / firing stop lasts
var _shots_this_stop: int = 0
var _deep_snow_count: int = 0
var _hold_time: float = 0.0         # time spent at the jump-off point
var _assault_after: float = 10.0
var _entry_point: Vector3           # where we land in the trench
var _retarget_timer: float = 0.0
var _stuck_time: float = 0.0
var _last_rush_pos: Vector3
var _deployed: bool = false        # MG team lying in position (stays flat, doesn't advance)
var _last_close_bullet: float = -100.0
var _rallied_until: float = -100.0
var _leaderless_until: float = -100.0
var _officer_near: bool = false
var _whistle_timer: float = 0.0
var _mg_burst_left: int = 0
var _mg_next_round: float = 0.0
var _mg_reload_until: float = 0.0
var _whistle_audio: AudioStreamPlayer3D
var _last_smoke: float = 0.0
var _clock: float = 0.0             # game seconds since he appeared
var _mg_next_burst: float = 0.0
var _prone_since: float = 0.0
var _prone_patience: float = 8.0
var _dash_until: float = -100.0     # up and running for a few seconds despite the fire
var _hold_offset: float = 0.0       # each soldier waits for the barrage at a slightly different line
var _panic_until: float = -100.0    # T2: crew of a burning tank – running away, not fighting
var _flee_point: Vector3
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rng := RandomNumberGenerator.new()

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var visual: SoldierVisual = $Visual
@onready var eyes: Marker3D = $Eyes
@onready var muzzle: Marker3D = visual.muzzle
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var shot_audio: AudioStreamPlayer3D = $ShotAudio
@onready var debug_label: Label3D = $DebugLabel


func _ready() -> void:
	add_to_group("enemies")
	_rng.randomize()
	collision.shape = collision.shape.duplicate() # each soldier resizes its own capsule
	health = data.max_health
	_idle_time = _rng.randf_range(1.0, 3.0)
	_assault_after = _rng.randf_range(data.assault_hold_min, data.assault_hold_max)
	_whistle_timer = _rng.randf_range(0.0, 3.0)
	_hold_offset = _rng.randf_range(-8.0, 0.0)
	mg_ammo = data.mg_magazine
	_mg_final_goal = attack_point
	_mg_fire_range = _rng.randf_range(data.mg_fire_range_min_m, data.mg_fire_range_max_m)
	_mg_follow_back = _rng.randf_range(data.mg_follow_back_min_m, data.mg_follow_back_max_m)
	_setup_sounds()
	_update_visuals()


func _setup_sounds() -> void:
	# A real recording if there is one (e.g. assets/audio/recorded/dp27…), else the placeholder.
	var recorded: AudioStream = RecordedSounds.pick(data.fire_sound_recording) if data.fire_sound_recording != "" else null
	if recorded:
		shot_audio.stream = recorded
	elif data.fire_sound:
		shot_audio.stream = data.fire_sound
		shot_audio.pitch_scale = data.fire_sound_pitch
	if data.kind == EnemyData.Kind.MG_GUNNER:
		shot_audio.max_polyphony = 4
	if data.kind == EnemyData.Kind.OFFICER:
		_whistle_audio = AudioStreamPlayer3D.new()
		_whistle_audio.name = "WhistleAudio"
		_whistle_audio.bus = &"SFX"
		_whistle_audio.unit_size = 25.0
		_whistle_audio.position = Vector3(0, 1.6, 0)
		_whistle_audio.attenuation_filter_cutoff_hz = 4000.0
		_whistle_audio.attenuation_filter_db = -18.0
		add_child(_whistle_audio)


## G2 timers run on game time (this soldier's own clock), so they also work in slow motion
## or sped-up tests.
func _now() -> float:
	return _clock


func _physics_process(delta: float) -> void:
	_clock += delta
	if not multiplayer.is_server() or state == State.DEAD:
		return
	_state_time += delta
	_sense_timer -= delta
	if _sense_timer <= 0.0:
		# Looking around costs raycasts, so do it ~5 times a second, not every frame.
		var interval: float = 0.2 + _rng.randf() * 0.05
		_update_senses(interval)
		_sense_timer = interval
	if _now() < _panic_until:
		# T2: bailed out of a burning tank – run back towards the forest, don't fight yet.
		suppression = 0.0
		is_prone = false
		is_kneeling = false
		if _move_to(_flee_point, data.hurry_speed):
			_panic_until = _now() # there already: pull himself together
		_face_towards(global_position + Vector3(velocity.x, 0.0, velocity.z), delta)
		_fall_and_slide(delta)
		return
	_update_suppression(delta)

	if state == State.HOLD:
		_hold(delta) # L3: holding the captured trench (also the DP-27 gunner: no team, no moving up)
		_fall_and_slide(delta)
		return
	if data.kind == EnemyData.Kind.MG_GUNNER and not mg_released:
		_mg_follow(delta) # fire, then move up behind the riflemen
	if _deployed and data.kind == EnemyData.Kind.MG_GUNNER and not mg_released:
		_mg_deployed(delta) # in position: no walking, only bursts
		_fall_and_slide(delta)
		return

	match state:
		State.IDLE:
			_stop()
			if _state_time > _idle_time:
				state = State.PATROL
		State.PATROL:
			if _move_to(attack_point, data.walk_speed):
				_face_towards(attack_point + Vector3(0, 0, 30), delta) # hold and watch the trench
				_hold_at_goal(delta)
			else:
				_face_towards(global_position + velocity, delta)
		State.ALERT:
			# Advance (hurrying) while looking towards the noise.
			if _move_to(attack_point, data.hurry_speed):
				_hold_at_goal(delta)
			_face_towards(_noise_position, delta)
			if state == State.ALERT and _state_time > data.alert_duration:
				state = State.PATROL
		State.ATTACK:
			_attack(delta)
		State.ASSAULT:
			_assault(delta)
	_fall_and_slide(delta)


func _fall_and_slide(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


# ------------------------------------------------------------------ senses
func _update_senses(dt: float) -> void:
	_officer_near = _find_officer_near() != null
	if data.kind == EnemyData.Kind.OFFICER:
		_officer_think(dt)
	if state == State.HOLD:
		_hold_senses()
		return
	if state == State.ASSAULT:
		# In the final rush there is no careful spotting: in the trench, anyone in sight is shot at.
		_can_see_target = is_in_trench() and _target != null and is_instance_valid(_target) \
				and not _target.is_dead and global_position.distance_to(_target.global_position) < 60.0 \
				and (_has_line_of_sight(_target.head.global_position) or _has_line_of_sight(_chest_of(_target)))
		return
	var seen: Player = _find_visible_player()
	if seen != null:
		var distance: float = eyes.global_position.distance_to(seen.head.global_position)
		var spot_time: float = lerpf(data.spot_time_near, data.spot_time_far, clampf(distance / data.vision_range_m, 0.0, 1.0))
		if seen.is_crouching:
			spot_time *= data.crouch_spot_multiplier
		if state == State.ALERT or state == State.ATTACK:
			spot_time *= 0.5 # already looking for trouble
		_spot_progress = minf(_spot_progress + dt / spot_time, 1.0)
		if _spot_progress >= 1.0:
			_last_known_position = seen.global_position
			_lost_sight_time = 0.0
			_can_see_target = true
			if state != State.ATTACK or seen != _target:
				_start_attack(seen)
		return

	_spot_progress = maxf(_spot_progress - dt * 0.5, 0.0)
	_can_see_target = false
	if state == State.ATTACK:
		_lost_sight_time += dt
		if _lost_sight_time > data.lose_sight_time:
			_noise_position = _last_known_position
			state = State.ALERT


## Returns the nearest living player we can see, or null.
func _find_visible_player() -> Player:
	var best: Player = null
	var best_distance: float = INF
	var forward: Vector3 = -global_basis.z
	var half_angle: float = deg_to_rad(data.vision_angle_deg / 2.0)
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == null or p.is_dead:
			continue
		var to_player: Vector3 = p.head.global_position - eyes.global_position
		var distance: float = to_player.length()
		if distance > minf(data.vision_range_m, visibility_limit) or distance > best_distance:
			continue
		var flat := Vector3(to_player.x, 0.0, to_player.z)
		if distance > 5.0 and forward.angle_to(flat) > half_angle:
			continue # outside the view cone (but always notice someone very close)
		if _has_line_of_sight(p.head.global_position) or _has_line_of_sight(_chest_of(p)):
			best = p
			best_distance = distance
	return best


func _has_line_of_sight(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(eyes.global_position, point, Tank.SIGHT_MASK) # world + armour (T5: no seeing through a tank or wreck)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _chest_of(p: Player) -> Vector3:
	return p.global_position + Vector3.UP * (0.75 if p.is_crouching else 1.3)


## Called (through the "enemies" group) whenever a shot is fired.
## `source` is where the sound came from, `interest` is where to look.
func hear_noise(source: Vector3, interest: Vector3, radius: float) -> void:
	if not multiplayer.is_server() or state in [State.DEAD, State.ATTACK, State.ASSAULT, State.HOLD]:
		return
	if global_position.distance_to(source) > radius:
		return
	_noise_position = interest
	if state == State.ALERT:
		_state_time = 0.0 # stay alert longer
	else:
		state = State.ALERT


# ------------------------------------------------------------------ attack
func _start_attack(target: Player) -> void:
	_target = target
	_shots_at_target = 0
	_aim_time = 0.0
	_reaction_delay = _rng.randf_range(data.reaction_time_min, data.reaction_time_max)
	_begin_firing_stop()
	state = State.ATTACK
	if data.kind == EnemyData.Kind.OFFICER and _whistle_timer <= 2.0:
		_blow_whistle() # "Forward!" – the soldiers around him pick themselves up
		_rally_nearby()


func _attack(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _target.is_dead:
		_target = null
		state = State.PATROL
		return
	if data.kind == EnemyData.Kind.MG_GUNNER and not mg_released:
		_mg_attack(delta)
		return
	_attack_phase_time += delta
	var at_goal: bool = global_position.distance_to(attack_point) < 3.0

	if _attack_moving:
		# Advance towards our position in front of the trench, then stop to fire again.
		is_kneeling = false
		_aim_time = 0.0
		var arrived: bool = _move_to(attack_point, data.walk_speed)
		_face_towards(_last_known_position, delta)
		if arrived or _attack_phase_time > _attack_phase_length:
			_begin_firing_stop()
		return

	# Firing stop: kneel, aim, shoot.
	_stop()
	is_kneeling = true
	if at_goal:
		_hold_at_goal(delta)
		if state != State.ATTACK:
			return
	_face_towards(_last_known_position, delta)
	if _can_see_target and not is_pinned() and _in_fire_range():
		_aim_time += delta
		var now: float = Time.get_ticks_msec() / 1000.0
		if _aim_time >= _reaction_delay and now >= _next_shot_time:
			_shoot()
			_next_shot_time = now + _rng.randf_range(data.fire_interval_min, data.fire_interval_max) * _fire_interval_factor()
			_shots_this_stop += 1
	elif is_pinned():
		_aim_time = 0.0 # head down: has to aim again afterwards
	# Done firing (or waited long enough without a clear shot)? Advance again.
	if not at_goal and (_shots_this_stop >= data.shots_per_stop or _attack_phase_time > _attack_phase_length):
		_attack_moving = true
		_attack_phase_time = 0.0
		_attack_phase_length = _rng.randf_range(data.advance_time_min, data.advance_time_max)


func _begin_firing_stop() -> void:
	_attack_moving = false
	_attack_phase_time = 0.0
	_attack_phase_length = _rng.randf_range(data.stop_time_min, data.stop_time_max)
	_shots_this_stop = 0


func _shoot() -> void:
	var origin: Vector3 = muzzle.global_position
	var aim_point: Vector3 = _chest_of(_target)
	var distance: float = origin.distance_to(aim_point)
	var spread: float = data.base_spread_deg + data.spread_per_100m_deg * distance / 100.0
	if _target.get_speed() > 1.0:
		spread += data.moving_target_spread_deg
	spread *= lerpf(1.0, data.best_aim_multiplier, clampf(_aim_time / data.full_aim_time, 0.0, 1.0))
	spread *= spread_multiplier
	spread *= lerpf(1.0, data.suppressed_spread_multiplier, suppression)
	if _shots_at_target == 0:
		spread *= data.first_shot_multiplier
	_shots_at_target += 1

	var forward: Vector3 = (aim_point - origin).normalized()
	var basis := Basis.looking_at(forward)
	var angle: float = deg_to_rad(spread) * _rng.randf()
	var around: float = _rng.randf() * TAU
	var direction: Vector3 = basis * Vector3(sin(angle) * cos(around), sin(angle) * sin(around), -cos(angle))

	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * data.shot_range_m, Tank.BULLET_MASK) # world + players + armour (T5)
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
			hit_player.take_damage(data.damage * damage_multiplier, -1, hit.position, hit.normal)
			hit_player.notify_hurt.rpc_id(hit_player.get_peer_id(), origin) # where it came from
		else:
			surface = ImpactEffects.surface_of(hit.collider, hit.normal)
			# A DP-27 burst thumping into sandbags / the bunker has its own sound.
			if data.kind == EnemyData.Kind.MG_GUNNER and ImpactEffects.is_cover(hit.collider):
				surface = "cover:" + surface
	show_shot_effects.rpc(hit_position, hit_normal, surface)
	# Players the bullet flew close past hear its crack.
	var bullet_end: Vector3 = hit_position if not hit.is_empty() else origin + direction * data.shot_range_m
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == hit_player or p.is_dead:
			continue
		var closest: Vector3 = Geometry3D.get_closest_point_to_segment(p.head.global_position, origin, bullet_end)
		if closest.distance_to(p.head.global_position) < near_miss_distance and closest.distance_to(origin) > 10.0:
			bullet_passed.rpc_id(p.get_peer_id(), closest)
	# Comrades nearby hear the shot and look towards what we are shooting at.
	get_tree().call_group("enemies", "hear_noise", origin, _last_known_position, data.shot_noise_radius_m)


## Muzzle flash, sound and impact on every computer. Empty surface = no impact to show.
@rpc("authority", "call_local", "unreliable")
func show_shot_effects(hit_position: Vector3, hit_normal: Vector3, surface: String) -> void:
	shot_audio.play()
	visual.play_fire()
	var effects := get_tree().get_first_node_in_group("impact_effects") as ImpactEffects
	if effects:
		effects.spawn_flash(muzzle.global_position)
		var t: float = Time.get_ticks_msec() / 1000.0
		if t - _last_smoke > 0.25: # a burst makes one puff, not one per round
			_last_smoke = t
			effects.spawn_smoke(muzzle.global_position, -muzzle.global_basis.z)
		if surface != "":
			var parts: Dictionary = ImpactEffects.split_cover(surface)
			effects.spawn_impact(hit_position, hit_normal, parts.surface)
			if parts.cover:
				effects.play_cover_hit(hit_position)


## Wounded (but not killed): flinch on every computer.
@rpc("authority", "call_local", "unreliable")
func show_hit() -> void:
	visual.play_hit()


## Sent only to the player the bullet flew past: play its crack there.
@rpc("authority", "call_local", "unreliable")
func bullet_passed(where: Vector3) -> void:
	var effects := get_tree().get_first_node_in_group("impact_effects") as ImpactEffects
	if effects:
		effects.play_crack(where)


# ------------------------------------------------------------------ damage & death
## Called on the host when a bullet hits. Returns true if this hit killed the soldier.
func take_damage(amount: float, attacker_id: int, _hit_position: Vector3, _hit_normal: Vector3) -> bool:
	if not multiplayer.is_server() or state == State.DEAD:
		return false
	health -= amount
	if health <= 0.0:
		_die()
		return true
	show_hit.rpc()
	add_suppression(data.wounded_suppression)
	# Wounded: react towards whoever shot us.
	var attacker: Player = null
	for node in get_tree().get_nodes_in_group("players"):
		if (node as Player).get_peer_id() == attacker_id:
			attacker = node
	if attacker and state == State.HOLD:
		_hold_alert_until = _now() + hold_alert_time
		if not _can_see_target:
			_set_target(attacker) # turns towards whoever shot him (and goes for him if he is close)
			_last_known_position = attacker.global_position
	elif attacker and state == State.ASSAULT:
		if not is_in_trench():
			pass # still rushing: keep running
		elif _target == null or not is_instance_valid(_target) or _target.is_dead:
			_set_target(attacker)
	elif attacker and state != State.ATTACK:
		_spot_progress = 1.0
		_last_known_position = attacker.global_position
		_start_attack(attacker)
	return false


func _die() -> void:
	health = 0.0
	velocity = Vector3.ZERO
	is_kneeling = false
	state = State.DEAD
	_on_death_g2()
	died.emit(self)
	get_tree().create_timer(corpse_time).timeout.connect(queue_free)


# ------------------------------------------------------------------ assault on the trench
## True while this soldier is down inside the Finnish trench (counts towards "the line is broken").
func is_in_trench() -> bool:
	return global_position.y < TRENCH_FLOOR_BELOW and global_position.z > TRENCH_FRONT_Z


## At the jump-off point in front of the trench: fire for a while, then rush in.
func _hold_at_goal(delta: float) -> void:
	if data.kind == EnemyData.Kind.MG_GUNNER and not mg_released:
		# The gun team doesn't rush the trench while there are riflemen to cover. At its last
		# position it sets up the gun anyway; on the way it waits behind its riflemen.
		if _at_final_gun_position():
			_deploy()
		else:
			is_kneeling = true
		return
	if barrage_hold_z < INF:
		is_kneeling = true # waiting for the barrage to lift – no rush now
		return
	if is_instance_valid(mg_gunner):
		if mg_gunner._deployed and not _deployed:
			_deployed = true # lie down next to the gun
		return
	if is_prone:
		return # pinned down: no rush until he can lift his head again
	_hold_time += delta
	if _hold_time >= _assault_after:
		if data.kind == EnemyData.Kind.OFFICER:
			_order_assault()
		else:
			_begin_assault()


## True if this soldier may be sent into the trench by an officer.
func can_join_assault() -> bool:
	return state in [State.PATROL, State.ALERT, State.ATTACK] and (data.kind != EnemyData.Kind.MG_GUNNER or mg_released) \
			and not is_instance_valid(mg_gunner) and not is_pinned()


func _begin_assault() -> void:
	_deployed = false
	_entry_point = _pick_trench_entry()
	is_kneeling = false
	_aim_time = 0.0
	state = State.ASSAULT


## The landing point of the nearest trench entry (NavigationLink3D in group "trench_entry").
func _pick_trench_entry() -> Vector3:
	var best: Vector3 = global_position + Vector3(0, 0, 15)
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("trench_entry"):
		var link := node as NavigationLink3D
		var start: Vector3 = link.global_transform * link.start_position
		var dist: float = global_position.distance_to(start)
		if dist < best_dist:
			best_dist = dist
			best = link.global_transform * link.end_position
	return best


func _assault(delta: float) -> void:
	if not is_in_trench():
		if is_prone:
			_stop() # thrown flat by fire during the rush: up again when it eases
			_face_towards(_entry_point, delta)
			return
		# The rush: run (bayonet first) to the trench edge and jump down.
		is_kneeling = false
		var arrived: bool = _move_to(_entry_point, data.hurry_speed)
		if arrived or _state_time > 25.0:
			# At the edge (or stuck): step straight towards the landing point and drop in.
			var to_entry: Vector3 = _entry_point - global_position
			to_entry.y = 0.0
			var dir: Vector3 = to_entry.normalized() if to_entry.length() > 0.05 else Vector3.BACK
			velocity.x = dir.x * data.hurry_speed
			velocity.z = dir.z * data.hurry_speed
		# Not getting anywhere (e.g. landed on someone's shoulders)? Step aside.
		_stuck_time = _stuck_time + delta if global_position.distance_to(_last_rush_pos) < 0.02 else 0.0
		_last_rush_pos = global_position
		if _stuck_time > 1.0:
			var side := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
			velocity.x = side.x * data.hurry_speed
			velocity.z = side.z * data.hurry_speed
			if _stuck_time > 1.6:
				_stuck_time = 0.0
		_face_towards(global_position + Vector3(velocity.x, 0.0, velocity.z), delta)
		return
	_trench_fight(delta)


## Inside the trench: go for the nearest Finn; shoot whenever he is in sight.
func _trench_fight(delta: float) -> void:
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or _target == null or not is_instance_valid(_target) or _target.is_dead:
		_retarget_timer = 1.0
		var nearest: Player = _nearest_player()
		if nearest != _target:
			_set_target(nearest)
	if _target == null:
		_stop()
		return
	if _can_see_target:
		_stop()
		is_kneeling = false
		_face_towards(_target.global_position, delta)
		_aim_time += delta
		var now: float = Time.get_ticks_msec() / 1000.0
		if _aim_time >= _reaction_delay and now >= _next_shot_time and _in_fire_range():
			_shoot()
			_next_shot_time = now + _rng.randf_range(data.trench_fire_interval_min, data.trench_fire_interval_max)
	else:
		_aim_time = 0.0
		_move_to(_target.global_position, data.hurry_speed)
		_face_towards(global_position + Vector3(velocity.x, 0.0, velocity.z), delta)


# ------------------------------------------------------------------ L3: holding the captured trench
## Host: from now on he holds `at` (a spot on the trench floor) – see State.HOLD.
func start_holding(at: Vector3) -> void:
	hold_point = at
	attack_point = at
	_reaction_delay = _rng.randf_range(data.reaction_time_min, data.reaction_time_max)
	state = State.HOLD


## HOLD senses (~5×/s): the nearest Finn in sight (no view cone – he is watching for the
## counterattack, and no slow spotting: the first shot still waits for his reaction time).
## Nobody in sight: he remembers the last one (to go for him round a corner).
func _hold_senses() -> void:
	var best: Player = null
	var sight: float = hold_alert_sight_m if _now() < _hold_alert_until else hold_sight_m
	var best_distance: float = minf(sight, visibility_limit)
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == null or p.is_dead:
			continue
		var distance: float = eyes.global_position.distance_to(p.head.global_position)
		if distance > best_distance:
			continue
		if _has_line_of_sight(p.head.global_position) or _has_line_of_sight(_chest_of(p)):
			best = p
			best_distance = distance
	if best:
		if best != _target:
			_set_target(best)
		_last_known_position = best.global_position
		_can_see_target = true
		return
	_can_see_target = false
	if _target != null and (not is_instance_valid(_target) or _target.is_dead):
		_target = null


## HOLD (host): fire at a Finn in sight (ducking while bullets fly close), go for one who is close
## but round a corner, otherwise back to his spot, watching the rear where the Finns will come from.
func _hold(delta: float) -> void:
	var has_target: bool = _target != null and is_instance_valid(_target) and not _target.is_dead
	if has_target and _can_see_target:
		_stop()
		is_kneeling = suppression >= data.prone_threshold # head down behind the trench wall
		_face_towards(_target.global_position, delta)
		if is_kneeling or not _in_fire_range():
			_aim_time = 0.0
			_mg_burst_left = 0
			return
		_aim_time += delta
		if _aim_time >= _reaction_delay:
			_hold_fire()
		return
	_aim_time = 0.0
	_mg_burst_left = 0
	if has_target and _target.global_position.y < TRENCH_FLOOR_BELOW \
			and _target.global_position.distance_to(hold_point) < hold_leash_m \
			and global_position.distance_to(_target.global_position) < hold_chase_m:
		_move_to(_target.global_position, data.hurry_speed)
		_face_towards(global_position + Vector3(velocity.x, 0.0, velocity.z), delta)
		return
	var to_post: Vector3 = hold_point - global_position
	to_post.y = 0.0
	if to_post.length() > 1.0:
		_move_to(hold_point, data.walk_speed)
		_face_towards(global_position + Vector3(velocity.x, 0.0, velocity.z), delta)
		return
	_stop()
	is_kneeling = suppression >= data.prone_threshold
	var look: Vector3 = _last_known_position if has_target else global_position + Vector3(0, 0, 30)
	_face_towards(look, delta)


## HOLD: one rifle shot – or, for the DP-27 gunner, the next round of a burst.
func _hold_fire() -> void:
	var now: float = _now()
	if data.kind != EnemyData.Kind.MG_GUNNER:
		if now >= _next_shot_time:
			_shoot()
			_next_shot_time = now + _rng.randf_range(data.trench_fire_interval_min, data.trench_fire_interval_max) * _fire_interval_factor()
		return
	if now < _mg_reload_until:
		return
	if mg_ammo <= 0:
		_mg_reload_until = now + data.mg_reload_time
		mg_ammo = data.mg_magazine
		_mg_burst_left = 0
		return
	if _mg_burst_left <= 0 and now >= _mg_next_burst:
		_mg_burst_left = _rng.randi_range(data.mg_burst_min, data.mg_burst_max)
	if _mg_burst_left > 0 and now >= _mg_next_round:
		_shoot()
		mg_ammo -= 1
		_mg_burst_left -= 1
		_mg_next_round = now + data.mg_shot_interval
		if _mg_burst_left <= 0 or mg_ammo <= 0:
			_mg_burst_left = 0
			_mg_next_burst = now + _rng.randf_range(data.mg_burst_pause_min, data.mg_burst_pause_max) * _fire_interval_factor()


func _set_target(p: Player) -> void:
	_target = p
	_shots_at_target = 0
	_aim_time = 0.0
	_reaction_delay = _rng.randf_range(data.reaction_time_min, data.reaction_time_max) * 0.5


func _nearest_player() -> Player:
	var best: Player = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p.is_dead:
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < best_dist:
			best = p
			best_dist = dist
	return best


## Host (T2): panic – run to `flee_to` for `time` seconds without fighting (tank crew).
func panic(time: float, flee_to: Vector3) -> void:
	if not multiplayer.is_server() or state == State.DEAD:
		return
	_panic_until = _now() + time
	_flee_point = flee_to


func is_panicking() -> bool:
	return _now() < _panic_until


## Host: the battle is over – stand still.
func freeze() -> void:
	_stop()
	velocity = Vector3.ZERO
	set_physics_process(false)


# ------------------------------------------------------------------ G2: suppression
## Host: a player's bullet flew from `from` to `to` (called for every shot, through the
## "enemies" group). The closer it passed, the more it pins him down.
func bullet_near(from: Vector3, to: Vector3, strength: float) -> void:
	if not multiplayer.is_server() or state == State.DEAD or strength <= 0.0:
		return
	var centre: Vector3 = global_position + Vector3.UP * (0.35 if is_prone else (0.8 if is_kneeling else 1.1))
	var closest: Vector3 = Geometry3D.get_closest_point_to_segment(centre, from, to)
	if closest.distance_to(from) < 4.0:
		return # right next to the shooter: that's a fight, not suppressing fire
	var distance: float = closest.distance_to(centre)
	if distance > data.suppression_radius_m:
		return
	if state == State.HOLD:
		_hold_alert_until = _now() + hold_alert_time # L3: someone is shooting at us – look for him
	add_suppression(strength * (1.0 - 0.7 * distance / data.suppression_radius_m))


## Host: makes him more suppressed (less if an officer is near, more without a leader).
func add_suppression(amount: float) -> void:
	if state == State.DEAD or (state == State.ASSAULT and is_in_trench()):
		return # in the trench it's hand-to-hand: nobody ducks any more
	var now: float = _now()
	amount *= data.nerve
	if _officer_near:
		amount *= _officer_data_value("rally_nerve_multiplier", 0.6)
	if now < _rallied_until:
		amount *= 0.5
	if now < _leaderless_until:
		amount *= data.leaderless_nerve_multiplier
	suppression = clampf(suppression + amount, 0.0, 1.0)
	_last_close_bullet = now


func is_pinned() -> bool:
	return suppression >= data.pinned_threshold


func _fire_interval_factor() -> float:
	return lerpf(1.0, data.suppressed_fire_interval_multiplier, suppression)


func _in_fire_range() -> bool:
	return _target != null and is_instance_valid(_target) \
			and global_position.distance_to(_target.global_position) <= data.max_fire_distance_m


func _update_suppression(delta: float) -> void:
	if _now() - _last_close_bullet > data.recovery_delay:
		suppression = maxf(suppression - data.suppression_recovery * delta, 0.0)
	var now: float = _now()
	var prone: bool = is_prone
	if _deployed:
		prone = true
	elif (state == State.ASSAULT and is_in_trench()) or state == State.HOLD:
		prone = false # (HOLD: ducks behind the trench wall instead, see _hold)
	elif now < _dash_until and not is_pinned():
		prone = false # making a dash for it
	elif suppression >= data.prone_threshold:
		prone = true
	elif suppression < data.prone_threshold * 0.5:
		prone = false # (in between: stays as he is, so he doesn't bob up and down)
	if prone and not is_prone:
		_prone_since = now
	is_prone = prone
	# Nobody lies in the snow for ever: once the fire lets up a little (not pinned), he jumps
	# up and dashes forward for a few seconds, then drops again if it is still hot.
	if is_prone and not _deployed and not is_pinned() and now - _prone_since > _prone_patience:
		_dash_until = now + _rng.randf_range(3.0, 5.0)
		_prone_patience = _rng.randf_range(6.0, 10.0)
		is_prone = false


# ------------------------------------------------------------------ G2: officer
## The nearest living officer whose rally radius reaches us (or null).
func _find_officer_near() -> Enemy:
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e == self or e.state == State.DEAD or e.data.kind != EnemyData.Kind.OFFICER:
			continue
		if global_position.distance_to(e.global_position) <= e.data.rally_radius_m:
			return e
	return null


func _officer_data_value(property: String, fallback: float) -> float:
	var officer: Enemy = _find_officer_near()
	return officer.data.get(property) if officer else fallback


## Living soldiers within `radius` m of this one (not counting himself).
func _comrades_within(radius: float) -> Array[Enemy]:
	var list: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e and e != self and e.state != State.DEAD and global_position.distance_to(e.global_position) <= radius:
			list.append(e)
	return list


## Officer (host, ~5×/s): when his men are pinned down, he whistles them back up.
func _officer_think(dt: float) -> void:
	_whistle_timer -= dt
	if _whistle_timer > 0.0 or state == State.DEAD or is_in_trench():
		return
	for e in _comrades_within(data.rally_radius_m):
		if e.suppression >= e.data.prone_threshold:
			_blow_whistle()
			_rally_nearby()
			return


func _rally_nearby() -> void:
	for e in _comrades_within(data.rally_radius_m):
		e.rally(data.whistle_rally)


## Host: an officer's whistle – shake off some suppression and get up.
func rally(amount: float) -> void:
	suppression = maxf(suppression - amount, 0.0)
	_rallied_until = _now() + 4.0


## Officer at his jump-off point: whistle, and everyone around him rushes the trench together.
func _order_assault() -> void:
	_blow_whistle()
	for e in _comrades_within(data.rally_radius_m * 1.4):
		if e.can_join_assault():
			e.rally(1.0)
			e._begin_assault()
	_begin_assault()


## Host: the barrage has lifted – the officer whistles and his men get up and go.
func signal_advance() -> void:
	_blow_whistle()
	_rally_nearby()


func _blow_whistle() -> void:
	_whistle_timer = _rng.randf_range(data.whistle_cooldown_min, data.whistle_cooldown_max)
	whistle_count += 1
	whistled.emit()
	play_whistle.rpc()


## The whistle on every computer: the sound, and his hand goes to his mouth.
@rpc("authority", "call_local", "reliable")
func play_whistle() -> void:
	visual.play_whistle()
	if _whistle_audio:
		var stream: AudioStream = RecordedSounds.pick("officer_whistle")
		_whistle_audio.stream = stream if stream else load("res://assets/audio/officer_whistle_placeholder.wav")
		_whistle_audio.pitch_scale = _rng.randf_range(0.97, 1.03)
		_whistle_audio.play()


## Host: our officer has fallen – hesitate for a while.
func lose_leader(time: float, extra_hold: float) -> void:
	_leaderless_until = _now() + time
	_assault_after += extra_hold


## Host: what a death means for the others (officer → hesitation, MG team → the other one).
func _on_death_g2() -> void:
	if data.kind == EnemyData.Kind.OFFICER:
		for e in _comrades_within(data.rally_radius_m * 1.5):
			e.lose_leader(data.leaderless_time, data.leaderless_extra_hold)
	if is_instance_valid(mg_assistant):
		mg_assistant._gunner_lost()
	if is_instance_valid(mg_gunner):
		mg_gunner.mg_assistant = null
	mg_assistant = null
	mg_gunner = null


# ------------------------------------------------------------------ G2: machine-gun team
## Gunner: lie down here and set up the gun. His helper comes to lie next to him.
func _deploy() -> void:
	if _deployed:
		return
	_deployed = true
	_mg_deployed_at = _now()
	_stop()
	is_kneeling = false
	if is_instance_valid(mg_assistant):
		var spot: Vector3 = global_position + global_basis.x * 1.3 + global_basis.z * 0.5
		var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
		if terrain:
			spot.y = terrain.get_height(spot.x, spot.z)
		mg_assistant.attack_point = spot
		mg_assistant._deployed = false


## True while he belongs to a DP-27 team that is still covering the riflemen (gunner or helper).
func is_mg_team_member() -> bool:
	if data.kind == EnemyData.Kind.MG_GUNNER:
		return not mg_released
	return is_instance_valid(mg_gunner)


## Host, gunner: all the riflemen are dead – pick up the gun and go for the trench like a rifleman
## (to his home point in front of the trench, fire from there, then rush in). His helper too.
func advance_as_rifleman() -> void:
	if not multiplayer.is_server() or state == State.DEAD or mg_released:
		return
	mg_released = true
	_deployed = false
	_hold_time = 0.0
	_mg_burst_left = 0
	attack_point = home_point if home_point != Vector3.ZERO else _nearest_attack_point()
	if is_instance_valid(mg_assistant):
		mg_assistant._gunner_lost() # the helper goes too, as a rifleman
	mg_assistant = null
	if state == State.IDLE:
		state = State.PATROL


## The riflemen's attack point nearest to him (on the ground), or a spot 15 m ahead.
func _nearest_attack_point() -> Vector3:
	var best: Vector3 = global_position + Vector3(0, 0, 15)
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("attack_point"):
		var pos: Vector3 = (node as Node3D).global_position
		if pos.distance_to(global_position) < best_dist:
			best_dist = pos.distance_to(global_position)
			best = pos
	var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
	if terrain:
		best.y = terrain.get_height(best.x, best.z)
	return best


## Helper: the gunner is dead – carry on as an ordinary rifleman.
func _gunner_lost() -> void:
	mg_gunner = null
	_deployed = false
	attack_point = home_point
	_hold_time = 0.0


## Gunner in the ATTACK state, gun not set up: he sees a Finn and is within his fire range of the
## trench (80–130 m) → down and open fire. Otherwise keep following the riflemen.
func _mg_attack(delta: float) -> void:
	var may_deploy: bool = global_position.z >= _mg_no_deploy_before_z
	if (_can_see_target and may_deploy and distance_to_trench() <= _mg_fire_range) or _at_final_gun_position():
		_deploy()
		return
	if _move_to(attack_point, data.walk_speed):
		is_kneeling = true # caught up with the riflemen: wait for them to go on
	_face_towards(_last_known_position, delta)


## Metres from the front edge of the Finnish trench (positive = in front of it).
func distance_to_trench() -> float:
	return TRENCH_FRONT_Z - global_position.z


func _at_final_gun_position() -> bool:
	return global_position.distance_to(_mg_final_goal) < 3.0


## Gunner (host, ~1×/s): "fire, then move up" (owner). The team keeps `_mg_follow_back` (5–10 m)
## behind the nearest of its riflemen, never closer to the trench than its last position (5–10 m
## behind the riflemen's attack point). Lying at the gun: once the riflemen are `mg_move_up_m`
## further forward (and the pan isn't being changed), the team gets up and catches up.
func _mg_follow(delta: float) -> void:
	_mg_follow_timer -= delta
	if _mg_follow_timer > 0.0:
		return
	_mg_follow_timer = 1.0
	var goal: Vector3 = _mg_final_goal
	var leader: Enemy = _mg_leader()
	if leader:
		goal.z = minf(_mg_final_goal.z, leader.global_position.z - _mg_follow_back)
	if not _deployed:
		goal.z = maxf(goal.z, minf(global_position.z, _mg_final_goal.z)) # never back towards the forest
	var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
	if terrain:
		goal.y = terrain.get_height(goal.x, goal.z)
	if _deployed:
		if leader == null or goal.z - global_position.z < data.mg_move_up_m or _now() < _mg_reload_until \
				or _now() - _mg_deployed_at < data.mg_min_fire_time:
			return # the riflemen are still close enough (or none left outside the trench): keep firing
		_deployed = false # up, and after them
		_mg_burst_left = 0
		_mg_no_deploy_before_z = goal.z - 2.0
	attack_point = goal
	_mg_hurry = goal.z - global_position.z > 8.0 # well behind his riflemen: hurry
	if is_instance_valid(mg_assistant):
		mg_assistant._deployed = false
		mg_assistant.attack_point = goal + Vector3(1.5, 0.0, -1.0)


## The nearest living soldier of the wave who isn't in a gun team, isn't fleeing and isn't in the
## trench yet (the riflemen the gun team covers), or null.
func _mg_leader() -> Enemy:
	var best: Enemy = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e == self or e.state == State.DEAD or e.is_mg_team_member() or e.is_panicking() or e.is_in_trench():
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d < best_dist:
			best = e
			best_dist = d
	return best


## Gunner in position: bursts at whoever he can see, pauses, new pan when empty.
func _mg_deployed(delta: float) -> void:
	_stop()
	var has_target: bool = _target != null and is_instance_valid(_target) and not _target.is_dead
	if state == State.ATTACK and has_target:
		_face_towards(_last_known_position, delta)
	elif state == State.ALERT:
		_face_towards(_noise_position, delta)
	else:
		_face_towards(global_position + Vector3(0, 0, 30), delta) # watch the trench
	var now: float = _now()
	if now < _mg_reload_until:
		return
	if mg_ammo <= 0:
		# Changing the pan: quicker with the helper lying next to him.
		var helped: bool = is_instance_valid(mg_assistant) and mg_assistant.global_position.distance_to(global_position) < 4.0
		_mg_reload_until = now + (data.mg_reload_time_assisted if helped else data.mg_reload_time)
		mg_ammo = data.mg_magazine
		_mg_burst_left = 0
		return
	if is_pinned() or state != State.ATTACK or not has_target or not _can_see_target or not _in_fire_range():
		_mg_burst_left = 0
		_aim_time = 0.0 if is_pinned() else _aim_time
		return
	_aim_time += delta
	if _aim_time < _reaction_delay:
		return
	if _mg_burst_left <= 0 and now >= _mg_next_burst:
		_mg_burst_left = _rng.randi_range(data.mg_burst_min, data.mg_burst_max)
	if _mg_burst_left > 0 and now >= _mg_next_round:
		_shoot()
		mg_ammo -= 1
		_mg_burst_left -= 1
		_mg_next_round = now + data.mg_shot_interval
		if _mg_burst_left <= 0 or mg_ammo <= 0:
			_mg_burst_left = 0
			_mg_next_burst = now + _rng.randf_range(data.mg_burst_pause_min, data.mg_burst_pause_max) * _fire_interval_factor()


func is_deployed() -> bool:
	return _deployed


# ------------------------------------------------------------------ movement helpers
## Walks along the navigation path. Returns true when the destination is reached.
func _move_to(destination: Vector3, speed: float) -> bool:
	if is_prone:
		_stop() # lying flat: nobody walks
		return global_position.distance_to(destination) < 3.0 and nav_agent.is_navigation_finished()
	if barrage_hold_z < INF and not is_in_trench():
		# Our own guns are shelling the trench: hurry forward behind the shells, but stop short.
		destination.z = minf(destination.z, barrage_hold_z + _hold_offset)
		speed = maxf(speed, data.hurry_speed)
	if _mg_hurry and not _deployed and data.kind == EnemyData.Kind.MG_GUNNER and not mg_released:
		speed = maxf(speed, data.hurry_speed) # catching up with his riflemen
	if nav_agent.target_position.distance_to(destination) > 0.5:
		nav_agent.target_position = destination
	if nav_agent.is_navigation_finished():
		_stop()
		return true
	var next: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = next - global_position
	direction.y = 0.0
	direction = direction.normalized()
	if _deep_snow_count > 0:
		speed *= 0.5
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	is_kneeling = false
	return false


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _face_towards(point: Vector3, delta: float) -> void:
	var to_point: Vector3 = point - global_position
	to_point.y = 0.0
	if to_point.length() < 0.1:
		return
	var target_yaw: float = atan2(-to_point.x, -to_point.z)
	rotation.y = rotate_toward(rotation.y, target_yaw, data.turn_speed * delta)


func enter_deep_snow() -> void:
	_deep_snow_count += 1


func exit_deep_snow() -> void:
	_deep_snow_count = maxi(_deep_snow_count - 1, 0)


# ------------------------------------------------------------------ visuals (every computer)
func _set_state(value: State) -> void:
	state = value
	_state_time = 0.0
	if is_node_ready():
		_update_visuals()


func _set_prone(value: bool) -> void:
	if value == is_prone:
		return
	is_prone = value
	if is_node_ready():
		_update_visuals()


func _set_kneeling(value: bool) -> void:
	if value == is_kneeling:
		return
	is_kneeling = value
	if is_node_ready():
		_update_visuals()


func _process(_delta: float) -> void:
	debug_label.visible = show_debug_labels and state != State.DEAD
	if debug_label.visible:
		debug_label.text = "%s %s  %d hp%s%s" % [EnemyData.Kind.keys()[data.kind].substr(0, 3), State.keys()[state], int(health),
				"  sup %.2f" % suppression if suppression > 0.01 else "", "  PRONE" if is_prone else ""]


func _update_visuals() -> void:
	var capsule := collision.shape as CapsuleShape3D
	if state == State.DEAD:
		collision.set_deferred("disabled", true) # bullets and players pass through bodies
		if is_prone:
			return # already lying in the snow: the visual just goes limp
		# Fall: backwards most of the time, sometimes forwards, a little twisted. Chosen from the
		# soldier's name so every computer shows the same fall.
		var h: int = absi(hash(str(name)))
		var fall_x: float = deg_to_rad(86.0) if h % 10 < 7 else deg_to_rad(-84.0)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(visual, "rotation:x", fall_x, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(visual, "rotation:y", ((h / 10) % 9 - 4) * 0.1, 0.55)
		return
	if is_prone:
		# Lying flat: the capsule lies along the body (head forward), eyes just above the snow.
		capsule.height = 1.7
		collision.rotation.x = PI / 2.0
		collision.position = Vector3(0.0, 0.3, -0.15)
		eyes.position = Vector3(0.0, 0.5, -0.7)
		return
	collision.rotation.x = 0.0
	collision.position.z = 0.0
	eyes.position.z = -0.1
	# Kneeling makes the soldier smaller (harder to hit) and lowers his eyes.
	var height: float = 1.2 if is_kneeling else 1.8
	capsule.height = height
	collision.position.y = height / 2.0
	eyes.position.y = 1.05 if is_kneeling else 1.6
	# The pose itself (kneeling, aiming, walking) is done by the SoldierVisual.
