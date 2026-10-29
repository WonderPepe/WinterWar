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

var _jump_requested: bool = false # only used on the host


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
		return
	move_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	sprint_held = Input.is_action_pressed("sprint")
	crouch_held = Input.is_action_pressed("crouch")
	if Input.is_action_just_pressed("jump"):
		# Ask the host (peer 1) to make us jump. In single player that is us.
		request_jump.rpc_id(1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		look_yaw -= motion.screen_relative.x * mouse_sensitivity
		var limit: float = deg_to_rad(max_pitch_degrees)
		look_pitch = clampf(look_pitch - motion.screen_relative.y * mouse_sensitivity, -limit, limit)
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Click the game to grab the mouse again (browsers require a click for this).
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## One-time actions are sent as RPCs ("remote procedure calls") instead of synced variables,
## so a quick key tap can never be missed. "authority" = only this player's owner may call it.
@rpc("authority", "call_local", "reliable")
func request_jump() -> void:
	_jump_requested = true


## Called by the Player on the host: returns true once per jump request.
func consume_jump() -> bool:
	var requested: bool = _jump_requested
	_jump_requested = false
	return requested
