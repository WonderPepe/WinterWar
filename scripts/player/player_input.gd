class_name PlayerInput
extends Node
## Collects the keyboard and mouse input of ONE player.
##
## Only the computer that owns this player reads its keyboard/mouse here.
## The values below are copied to the host (and other players) by the
## child MultiplayerSynchronizer "InputSync". The Player node never reads the
## keyboard itself - it only reads these variables. That is what lets remote
## players work later: their input simply arrives over the network.

@export var mouse_sensitivity: float = 0.0025 ## Radians per pixel of mouse movement.
@export var max_pitch_degrees: float = 85.0 ## How far you can look up/down.

# --- Synced to the host by InputSync ---
var move_dir: Vector2 = Vector2.ZERO ## x = right, y = back (so forward is -1).
var sprint_held: bool = false
var crouch_held: bool = false
var look_yaw: float = 0.0   ## Left/right turn of the body (radians).
var look_pitch: float = 0.0 ## Up/down tilt of the head (radians).
var aim_held: bool = false  ## Right mouse: aim down the sights.

# --- Only used on this player's own computer (not synced) ---
var fire_held: bool = false ## The weapon decides locally when a shot happens.
var look_sensitivity_scale: float = 1.0 ## Lowered by the weapon while aiming.

# --- One-time requests, only used on the host ---
var _jump_requested: bool = false
var _reload_requested: bool = false
var _switch_requested: int = -1
var _block_fire_until_release: bool = false # the click that grabs the mouse must not shoot


func _ready() -> void:
	# Start facing the same way the player was spawned.
	look_yaw = get_parent().rotation.y
	var mine: bool = is_multiplayer_authority()
	set_process(mine)
	set_process_unhandled_input(mine)
	if mine:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Mouse released (Esc): stand still instead of running off.
		move_dir = Vector2.ZERO
		sprint_held = false
		fire_held = false
		aim_held = false
		return
	move_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	sprint_held = Input.is_action_pressed("sprint")
	crouch_held = Input.is_action_pressed("crouch")
	aim_held = Input.is_action_pressed("aim")
	if _block_fire_until_release and not Input.is_action_pressed("fire"):
		_block_fire_until_release = false
	fire_held = Input.is_action_pressed("fire") and not _block_fire_until_release
	# One-time actions: ask the host (peer 1). In single player the host is us.
	if Input.is_action_just_pressed("jump"):
		request_jump.rpc_id(1)
	if Input.is_action_just_pressed("reload"):
		request_reload.rpc_id(1)
	if Input.is_action_just_pressed("weapon_1"):
		request_switch.rpc_id(1, 0)
	if Input.is_action_just_pressed("weapon_2"):
		request_switch.rpc_id(1, 1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sens: float = mouse_sensitivity * look_sensitivity_scale
		add_look(-motion.screen_relative.y * sens, -motion.screen_relative.x * sens)
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Click the game to grab the mouse again (browsers require a click for this).
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_block_fire_until_release = true


## One-time actions are sent as RPCs ("remote procedure calls") instead of synced variables,
## so a quick key tap can never be missed. "authority" = only this player's owner may call it.
@rpc("authority", "call_local", "reliable")
func request_jump() -> void:
	_jump_requested = true


## Turns the view. Used by the mouse and by weapon recoil.
func add_look(pitch_delta: float, yaw_delta: float) -> void:
	var limit: float = deg_to_rad(max_pitch_degrees)
	look_pitch = clampf(look_pitch + pitch_delta, -limit, limit)
	look_yaw += yaw_delta


@rpc("authority", "call_local", "reliable")
func request_reload() -> void:
	_reload_requested = true


@rpc("authority", "call_local", "reliable")
func request_switch(slot: int) -> void:
	_switch_requested = slot


## Called by the WeaponController on the host: returns true once per reload request.
func consume_reload() -> bool:
	var requested: bool = _reload_requested
	_reload_requested = false
	return requested


## Called by the WeaponController on the host: returns the requested slot once, or -1.
func consume_switch() -> int:
	var slot: int = _switch_requested
	_switch_requested = -1
	return slot


## Called by the Player on the host: returns true once per jump request.
func consume_jump() -> bool:
	var requested: bool = _jump_requested
	_jump_requested = false
	return requested
