class_name Player
extends CharacterBody3D
## Player logic: movement, sprint/stamina, crouch, jump, deep snow, health, death.
##
## The node's NAME is the peer id of the person controlling it ("1" = host).
## Movement is calculated only on the host (the "authority" for game state).
## Other computers receive the result through the StateSync MultiplayerSynchronizer.
## Input never comes from the keyboard directly - it comes from the PlayerInput child.

signal health_changed(new_health: int)
signal stamina_changed(new_stamina: float)
signal died(player: Player)   ## Emitted on the host when health reaches 0.
signal respawned(player: Player)

@export_group("Movement")
@export var walk_speed: float = 4.0
@export var sprint_speed: float = 6.5
@export var crouch_speed: float = 2.0
@export var deep_snow_multiplier: float = 0.5 ## Speed is multiplied by this in deep snow.
@export var jump_velocity: float = 4.5
@export var ground_acceleration: float = 12.0
@export var air_acceleration: float = 2.0

@export_group("Stamina")
@export var max_stamina: float = 100.0
@export var stamina_drain: float = 20.0 ## Per second while sprinting.
@export var stamina_regen: float = 15.0 ## Per second while not sprinting.
@export var stamina_regen_delay: float = 1.0 ## Seconds to wait before regenerating.
@export var min_stamina_to_sprint: float = 15.0 ## Needed to START sprinting again.

@export_group("Crouch")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.1
@export var stand_eye_height: float = 1.6
@export var crouch_eye_height: float = 0.95
@export var crouch_change_speed: float = 6.0

@export_group("Health")
@export var max_health: int = 100

# --- Synced from the host to everyone by StateSync ---
var health: int = 100:
	set(value):
		health = value
		health_changed.emit(health)
var stamina: float = 100.0:
	set(value):
		stamina = value
		stamina_changed.emit(stamina)
var is_crouching: bool = false
var is_sprinting: bool = false
var god_mode: bool = false ## Debug (F1): take no damage.
var is_dead: bool = false:
	set = _set_dead
var kills: int = 0
var deaths: int = 0

var _deep_snow_count: int = 0 # how many deep-snow zones we are standing in
var _regen_timer: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var input: PlayerInput = $PlayerInput
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var ceiling_check: ShapeCast3D = $CeilingCheck
@onready var snow_particles: CPUParticles3D = $SnowParticles
@onready var weapons: WeaponController = $WeaponController


func _enter_tree() -> void:
	# The player who owns this node controls its PlayerInput (and InputSync below it).
	$PlayerInput.set_multiplayer_authority(get_peer_id())


func _ready() -> void:
	add_to_group("players")
	collision.shape = collision.shape.duplicate() # each player needs its own capsule to resize
	health = max_health
	stamina = max_stamina
	var local: bool = is_local_player()
	camera.current = local
	body_mesh.visible = not local          # don't see your own body from inside
	snow_particles.emitting = local        # each player only simulates their own snowfall


## Peer id of the person controlling this player.
func get_peer_id() -> int:
	return str(name).to_int()


## True if this player is controlled on THIS computer.
func is_local_player() -> bool:
	return get_peer_id() == multiplayer.get_unique_id()


func is_in_deep_snow() -> bool:
	return _deep_snow_count > 0


func get_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _process(delta: float) -> void:
	# Looking is applied every frame on every computer (smooth mouse look).
	rotation.y = input.look_yaw
	head.rotation.x = input.look_pitch
	_update_crouch_shape(delta)
	# Death camera: sink to the ground and tilt the head sideways.
	head.rotation.z = move_toward(head.rotation.z, 0.5 if is_dead else 0.0, delta * 2.0)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return # only the host moves players; others get the position from StateSync
	rotation.y = input.look_yaw
	if is_dead:
		# Dead: no control, just fall to the ground and stop.
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= _gravity * delta
		input.consume_jump()
		move_and_slide()
		return
	_update_crouch_state()
	_apply_gravity_and_jump(delta)
	_update_sprint_and_stamina(delta)
	_apply_movement(delta)
	move_and_slide()


func _update_crouch_state() -> void:
	if input.crouch_held:
		is_crouching = true
	elif is_crouching and not ceiling_check.is_colliding():
		is_crouching = false # only stand up if there's room above our head


func _apply_gravity_and_jump(delta: float) -> void:
	var wants_jump: bool = input.consume_jump()
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif wants_jump and not is_crouching:
		velocity.y = jump_velocity * (0.6 if is_in_deep_snow() else 1.0)


func _update_sprint_and_stamina(delta: float) -> void:
	var moving_forward: bool = input.move_dir.y < -0.1
	var can_start: bool = is_sprinting or stamina >= min_stamina_to_sprint
	is_sprinting = input.sprint_held and moving_forward and not is_crouching and not input.aim_held \
			and stamina > 0.0 and can_start

	if is_sprinting:
		stamina = maxf(stamina - stamina_drain * delta, 0.0)
		_regen_timer = stamina_regen_delay
	elif stamina < max_stamina:
		_regen_timer -= delta
		if _regen_timer <= 0.0:
			stamina = minf(stamina + stamina_regen * delta, max_stamina)


func _apply_movement(delta: float) -> void:
	var speed: float = walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_sprinting:
		speed = sprint_speed
	if is_in_deep_snow():
		speed *= deep_snow_multiplier
	speed *= weapons.get_move_multiplier() # slower while aiming down the sights

	# Turn the 2D input (x = right, y = back) into a world direction using our facing.
	var direction: Vector3 = transform.basis * Vector3(input.move_dir.x, 0.0, input.move_dir.y)
	direction.y = 0.0
	direction = direction.normalized() * minf(input.move_dir.length(), 1.0)
	var target: Vector3 = direction * speed
	var accel: float = ground_acceleration if is_on_floor() else air_acceleration
	var weight: float = clampf(accel * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, target.x, weight)
	velocity.z = lerpf(velocity.z, target.z, weight)


## Smoothly resizes the capsule and moves the camera for crouching (runs on every computer).
func _update_crouch_shape(delta: float) -> void:
	var capsule := collision.shape as CapsuleShape3D
	var target_height: float = crouch_height if is_crouching else stand_height
	capsule.height = move_toward(capsule.height, target_height, crouch_change_speed * delta)
	collision.position.y = capsule.height / 2.0 # keep the feet on the ground
	body_mesh.scale.y = capsule.height / stand_height
	body_mesh.position.y = capsule.height / 2.0
	var target_eye: float = crouch_eye_height if is_crouching else stand_eye_height
	if is_dead:
		target_eye = 0.3
	head.position.y = move_toward(head.position.y, target_eye, crouch_change_speed * delta)


## Called on the host when this player is hit. Returns true if the hit was fatal.
func take_damage(amount: float, _attacker_id: int, _hit_position: Vector3, _hit_normal: Vector3) -> bool:
	if not multiplayer.is_server() or is_dead or god_mode:
		return false
	health = maxi(health - roundi(amount), 0)
	if health > 0:
		return false
	deaths += 1
	is_dead = true
	died.emit(self) # the Game starts the respawn timer
	return true


## Host only: bring the player back to life at the given place.
func respawn(at: Transform3D) -> void:
	if not multiplayer.is_server():
		return
	global_transform = at
	velocity = Vector3.ZERO
	health = max_health
	stamina = max_stamina
	is_crouching = false
	is_sprinting = false
	weapons.refill_ammo()
	is_dead = false
	input.set_look.rpc_id(get_peer_id(), at.basis.get_euler().y, 0.0) # the owner controls the view
	respawned.emit(self)


## Runs on every computer when is_dead changes (StateSync).
func _set_dead(value: bool) -> void:
	is_dead = value
	# Dead bodies are ignored by bullets and other bodies; keep colliding with the ground only.
	collision_layer = 0 if is_dead else 0b10
	collision_mask = 0b1 if is_dead else 0b111
	if is_node_ready():
		body_mesh.rotation.x = deg_to_rad(-85.0) if is_dead else 0.0


# --- Called by DeepSnowZone areas ---
func enter_deep_snow() -> void:
	_deep_snow_count += 1


func exit_deep_snow() -> void:
	_deep_snow_count = maxi(_deep_snow_count - 1, 0)
