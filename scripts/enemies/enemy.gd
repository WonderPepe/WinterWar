class_name Enemy
extends CharacterBody3D
## A Soviet rifleman, controlled by a simple "state machine".
##
## The soldier is always in exactly ONE state (Idle, Patrol, Alert, Attack, Dead).
## Each state has its own behaviour and rules for switching to another state.
## All thinking, moving and shooting happens on the HOST only; other computers just
## receive the position, facing and state through StateSync.

signal died(enemy: Enemy)

enum State { IDLE, PATROL, ALERT, ATTACK, DEAD }

static var show_debug_labels: bool = false ## Toggled with F2 for all enemies.

@export var data: EnemyData
@export var corpse_time: float = 20.0 ## Seconds before a dead body is removed.

# --- Synced from the host by StateSync ---
var state: State = State.IDLE:
	set = _set_state
var is_kneeling: bool = false:
	set = _set_kneeling
var health: float = 100.0

## Set by the WaveSpawner: the place in front of the trench this soldier advances to.
var attack_point: Vector3 = Vector3.ZERO

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
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rng := RandomNumberGenerator.new()

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var visual: Node3D = $Visual
@onready var rifle: Node3D = $Visual/Rifle
@onready var eyes: Marker3D = $Eyes
@onready var muzzle: Marker3D = $Visual/Rifle/Muzzle
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var shot_audio: AudioStreamPlayer3D = $ShotAudio
@onready var debug_label: Label3D = $DebugLabel


func _ready() -> void:
	add_to_group("enemies")
	_rng.randomize()
	collision.shape = collision.shape.duplicate() # each soldier resizes its own capsule
	health = data.max_health
	_idle_time = _rng.randf_range(1.0, 3.0)
	_update_visuals()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or state == State.DEAD:
		return
	_state_time += delta
	_sense_timer -= delta
	if _sense_timer <= 0.0:
		# Looking around costs raycasts, so do it ~5 times a second, not every frame.
		var interval: float = 0.2 + _rng.randf() * 0.05
		_update_senses(interval)
		_sense_timer = interval

	match state:
		State.IDLE:
			_stop()
			if _state_time > _idle_time:
				state = State.PATROL
		State.PATROL:
			if _move_to(attack_point, data.walk_speed):
				_face_towards(attack_point + Vector3(0, 0, 30), delta) # hold and watch the trench
			else:
				_face_towards(global_position + velocity, delta)
		State.ALERT:
			# Advance (hurrying) while looking towards the noise.
			_move_to(attack_point, data.hurry_speed)
			_face_towards(_noise_position, delta)
			if _state_time > data.alert_duration:
				state = State.PATROL
		State.ATTACK:
			_attack(delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


# ------------------------------------------------------------------ senses
func _update_senses(dt: float) -> void:
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
		if p == null or p.health <= 0:
			continue
		var to_player: Vector3 = p.head.global_position - eyes.global_position
		var distance: float = to_player.length()
		if distance > data.vision_range_m or distance > best_distance:
			continue
		var flat := Vector3(to_player.x, 0.0, to_player.z)
		if distance > 5.0 and forward.angle_to(flat) > half_angle:
			continue # outside the view cone (but always notice someone very close)
		if _has_line_of_sight(p.head.global_position) or _has_line_of_sight(_chest_of(p)):
			best = p
			best_distance = distance
	return best


func _has_line_of_sight(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(eyes.global_position, point, 0b1) # world only
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _chest_of(p: Player) -> Vector3:
	return p.global_position + Vector3.UP * (0.75 if p.is_crouching else 1.3)


## Called (through the "enemies" group) whenever a shot is fired.
## `source` is where the sound came from, `interest` is where to look.
func hear_noise(source: Vector3, interest: Vector3, radius: float) -> void:
	if not multiplayer.is_server() or state == State.DEAD or state == State.ATTACK:
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


func _attack(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _target.health <= 0:
		_target = null
		state = State.PATROL
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
	_face_towards(_last_known_position, delta)
	if _can_see_target:
		_aim_time += delta
		var now: float = Time.get_ticks_msec() / 1000.0
		if _aim_time >= _reaction_delay and now >= _next_shot_time:
			_shoot()
			_next_shot_time = now + _rng.randf_range(data.fire_interval_min, data.fire_interval_max)
			_shots_this_stop += 1
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
	if _shots_at_target == 0:
		spread *= data.first_shot_multiplier
	_shots_at_target += 1

	var forward: Vector3 = (aim_point - origin).normalized()
	var basis := Basis.looking_at(forward)
	var angle: float = deg_to_rad(spread) * _rng.randf()
	var around: float = _rng.randf() * TAU
	var direction: Vector3 = basis * Vector3(sin(angle) * cos(around), sin(angle) * sin(around), -cos(angle))

	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * data.shot_range_m, 0b11) # world + players
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var hit_position := Vector3.ZERO
	var hit_normal := Vector3.UP
	var surface: String = ""
	if not hit.is_empty():
		hit_position = hit.position
		hit_normal = hit.normal
		if hit.collider is Player:
			(hit.collider as Player).take_damage(data.damage, -1, hit.position, hit.normal)
		else:
			surface = ImpactEffects.surface_of(hit.collider, hit.normal)
	show_shot_effects.rpc(hit_position, hit_normal, surface)
	# Comrades nearby hear the shot and look towards what we are shooting at.
	get_tree().call_group("enemies", "hear_noise", origin, _last_known_position, data.shot_noise_radius_m)


## Muzzle flash, sound and impact on every computer. Empty surface = no impact to show.
@rpc("authority", "call_local", "unreliable")
func show_shot_effects(hit_position: Vector3, hit_normal: Vector3, surface: String) -> void:
	shot_audio.play()
	var effects := get_tree().get_first_node_in_group("impact_effects") as ImpactEffects
	if effects:
		effects.spawn_flash(muzzle.global_position)
		if surface != "":
			effects.spawn_impact(hit_position, hit_normal, surface)


# ------------------------------------------------------------------ damage & death
## Called on the host when a bullet hits. Returns true if this hit killed the soldier.
func take_damage(amount: float, attacker_id: int, _hit_position: Vector3, _hit_normal: Vector3) -> bool:
	if not multiplayer.is_server() or state == State.DEAD:
		return false
	health -= amount
	if health <= 0.0:
		_die()
		return true
	# Wounded: react towards whoever shot us.
	var attacker: Player = null
	for node in get_tree().get_nodes_in_group("players"):
		if (node as Player).get_peer_id() == attacker_id:
			attacker = node
	if attacker and state != State.ATTACK:
		_spot_progress = 1.0
		_last_known_position = attacker.global_position
		_start_attack(attacker)
	return false


func _die() -> void:
	health = 0.0
	velocity = Vector3.ZERO
	is_kneeling = false
	state = State.DEAD
	died.emit(self)
	get_tree().create_timer(corpse_time).timeout.connect(queue_free)


# ------------------------------------------------------------------ movement helpers
## Walks along the navigation path. Returns true when the destination is reached.
func _move_to(destination: Vector3, speed: float) -> bool:
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


func _set_kneeling(value: bool) -> void:
	if value == is_kneeling:
		return
	is_kneeling = value
	if is_node_ready():
		_update_visuals()


func _process(_delta: float) -> void:
	debug_label.visible = show_debug_labels and state != State.DEAD
	if debug_label.visible:
		debug_label.text = "%s  %d hp" % [State.keys()[state], int(health)]


func _update_visuals() -> void:
	var capsule := collision.shape as CapsuleShape3D
	var tween := create_tween().set_parallel(true)
	if state == State.DEAD:
		collision.set_deferred("disabled", true) # bullets and players pass through bodies
		tween.tween_property(visual, "rotation:x", deg_to_rad(88.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		return
	# Kneeling makes the soldier smaller (harder to hit) and lowers his eyes.
	var height: float = 1.2 if is_kneeling else 1.8
	capsule.height = height
	collision.position.y = height / 2.0
	eyes.position.y = 1.05 if is_kneeling else 1.6
	tween.tween_property(visual, "scale:y", height / 1.8, 0.25)
	# Rifle: shouldered and pointing forward when attacking, carried diagonally otherwise.
	var aiming: bool = state == State.ATTACK
	tween.tween_property(rifle, "rotation", Vector3(0.0, 0.0, 0.0) if aiming else Vector3(deg_to_rad(55.0), 0.0, deg_to_rad(25.0)), 0.3)
	tween.tween_property(rifle, "position", Vector3(0.12, 1.42, -0.35) if aiming else Vector3(0.18, 1.15, -0.22), 0.3)
