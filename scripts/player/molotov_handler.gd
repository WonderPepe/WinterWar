class_name MolotovHandler
extends Node
## The player's Molotov cocktails (T2). Child "Molotov" of the Player.
##
##   G            take a bottle in your hand (if you have one) – 1 / 2 take the gun back
##   right mouse  held ~1 s: light the rag (let go earlier = stop). Once lit: held = aim
##   left mouse   throw (only a lit bottle; aimed = further and flatter)
## A lit bottle must not be held for long: after `warn_time` the flame grows, after
## `danger_time` it burns your hand and you may drop it at your feet (the fuel catches fire).
## Lit bottles can't be put away – throw it!
##
## The HOST runs the rules (`phase`, `count` are synced by MolotovSync). Every computer shows
## the result; the bottle in the hand (with its flame and light) is only drawn for the player
## on his own computer.

signal picked_up(count: int)

enum Phase { NONE, HELD, IGNITING, LIT, THROWING } # (new values at the end: synced as numbers)

@export var max_carry: int = 2 ## Bottles you can carry.
@export var ignite_time: float = 1.0 ## Seconds of right mouse to light the rag.
@export var warn_time: float = 5.0 ## Lit this long: bigger flame + warning.
@export var danger_time: float = 8.0 ## Lit this long: it burns your hand, you may drop it.
@export var hand_burn_damage: float = 4.0 ## Per half second after `danger_time`.
@export var drop_chance: float = 0.08 ## Per half second at `danger_time`...
@export var drop_chance_growth: float = 0.06 ## ...plus this much for every second after it.
@export var throw_speed: float = 11.0 ## m/s from the hip...
@export var aimed_throw_speed: float = 16.0 ## ...and aimed (right mouse held).
@export var throw_lift: float = 2.5 ## Extra upward speed (m/s): the bottle is lobbed.
@export var throw_time: float = 0.45 ## The arm swings through, then the next bottle comes up.

# --- Synced from the host (MolotovSync) ---
var count: int = 0 ## Bottles carried (also the one in the hand).
var phase: Phase = Phase.NONE:
	set = _set_phase

var thrown: int = 0 ## Statistics / tests (host).

# Host
var _ignite_t: float = 0.0
var _lit_t: float = 0.0
var _throw_t: float = 0.0
var _burn_tick: float = 0.0
var _rmb_released: bool = true # lighting needs a fresh press of the right mouse button
var _rng := RandomNumberGenerator.new()
# Every computer: when the phase last changed (game time on THIS computer).
var _clock: float = 0.0
var _phase_since: float = 0.0
# Local player only: the bottle in the hand.
var _hand: Node3D
var _bottle: Node3D
var _rag_flame: CPUParticles3D
var _match_flame: CPUParticles3D
var _light: OmniLight3D
var _grip_r: Marker3D
var _grip_l: Marker3D
var _hand_t: float = 0.0 # 0 = down out of view, 1 = up in the hand
var _aim_t: float = 0.0
var _ignite_audio: AudioStreamPlayer
var _flame_audio: AudioStreamPlayer

@onready var player: Player = get_parent()


func _ready() -> void:
	_rng.randomize()
	if player.is_local_player():
		_build_hand.call_deferred()


## Host: the crate gives you a full load.
func refill() -> void:
	if not multiplayer.is_server():
		return
	count = max_carry
	notify_picked_up.rpc_id(player.get_peer_id(), count)


@rpc("authority", "call_local", "reliable")
func notify_picked_up(n: int) -> void:
	picked_up.emit(n)


## True while a bottle (not the gun) is in the hands.
func is_selected() -> bool:
	return phase != Phase.NONE


func is_lit() -> bool:
	return phase == Phase.LIT


## Seconds the rag has been burning (this computer's view; exact on the host).
func get_lit_time() -> float:
	if phase != Phase.LIT:
		return 0.0
	return _lit_t if multiplayer.is_server() else _clock - _phase_since


## 0..1 how far the rag is lit (for the HUD).
func get_ignite_progress() -> float:
	if phase != Phase.IGNITING:
		return 0.0
	var t: float = _ignite_t if multiplayer.is_server() else _clock - _phase_since
	return clampf(t / ignite_time, 0.0, 1.0)


## Host (WeaponController): may the player switch to a gun now? A lit bottle can't be put away.
func can_put_away() -> bool:
	return phase != Phase.LIT and phase != Phase.THROWING


## C1 (owner): no climbing out of the trench while the rag is being lit or is burning.
func can_climb() -> bool:
	return phase == Phase.NONE or phase == Phase.HELD


## Host: back to the gun.
func put_away() -> void:
	if can_put_away():
		phase = Phase.NONE


## Host: the player is reset (respawn / new day): no bottles, gun in hand.
func reset() -> void:
	count = 0
	phase = Phase.NONE


# ------------------------------------------------------------------ host rules
func _physics_process(delta: float) -> void:
	_clock += delta
	if not multiplayer.is_server():
		return
	var input: PlayerInput = player.input
	var wants_select: bool = input.consume_molotov()
	var wants_throw: bool = input.consume_throw()
	if player.is_dead:
		if phase == Phase.LIT:
			_drop() # the lit bottle falls where he fell
		if phase != Phase.NONE:
			phase = Phase.NONE
		return
	if wants_select and phase == Phase.NONE and count > 0 and player.get_mounted_gun() == null \
			and not player.is_bandaging:
		_ignite_t = 0.0
		player.weapons.is_reloading = false # (a reload is dropped for the bottle)
		_rmb_released = not input.aim_held
		phase = Phase.HELD
	match phase:
		Phase.HELD:
			if not input.aim_held:
				_rmb_released = true
			if count <= 0:
				phase = Phase.NONE
			elif input.aim_held and _rmb_released and not player.is_sprinting and not player.is_climbing:
				_ignite_t = 0.0
				phase = Phase.IGNITING
		Phase.IGNITING:
			if not input.aim_held:
				phase = Phase.HELD # let go too early: the match goes out
			else:
				_ignite_t += delta
				if _ignite_t >= ignite_time:
					_lit_t = 0.0
					_burn_tick = 0.0
					phase = Phase.LIT
		Phase.LIT:
			_lit_t += delta
			if wants_throw:
				_throw()
			elif _lit_t >= danger_time:
				_burn_tick -= delta
				if _burn_tick <= 0.0:
					_burn_tick = 0.5
					player.take_damage(hand_burn_damage, -1, player.global_position, Vector3.UP)
					player.notify_hurt.rpc_id(player.get_peer_id(), player.global_position + Vector3(0, 1.2, 0))
					var chance: float = drop_chance + drop_chance_growth * (_lit_t - danger_time)
					if _rng.randf() < chance:
						_drop()
		Phase.THROWING:
			_throw_t -= delta
			if _throw_t <= 0.0:
				_rmb_released = not input.aim_held # (still holding right mouse: no new lighting)
				phase = Phase.HELD if count > 0 else Phase.NONE


func _throw() -> void:
	var manager := get_tree().get_first_node_in_group("molotovs") as MolotovManager
	var cam: Camera3D = player.camera
	var aimed: bool = player.input.aim_held
	var forward: Vector3 = -cam.global_basis.z
	var origin: Vector3 = cam.global_position + cam.global_basis * Vector3(0.2, 0.1, -0.35)
	var speed: float = aimed_throw_speed if aimed else throw_speed
	var velocity: Vector3 = forward * speed + Vector3.UP * throw_lift + player.velocity * 0.5
	if manager:
		manager.throw(origin, velocity, player)
	count -= 1
	thrown += 1
	_throw_t = throw_time
	phase = Phase.THROWING


## Host: the lit bottle slips and breaks at the player's feet.
func _drop() -> void:
	var manager := get_tree().get_first_node_in_group("molotovs") as MolotovManager
	if manager:
		manager.drop_at(player.global_position + Vector3(0, 0.05, 0), player.get_peer_id())
	count -= 1
	_rmb_released = false
	phase = Phase.HELD if count > 0 and not player.is_dead else Phase.NONE


func _set_phase(value: Phase) -> void:
	if value != phase:
		_phase_since = _clock
	var was: Phase = phase
	phase = value
	if _hand and is_node_ready():
		_on_phase_changed(was, value)


# ------------------------------------------------------------------ the hand (local player)
## Bottle in the right hand (with grip markers for the first-person arms), a match for the
## left hand, the burning rag with its flame and a small flickering light.
func _build_hand() -> void:
	var soft: Texture2D = ImpactEffects.make_soft_texture()
	_hand = Node3D.new()
	_hand.name = "MolotovHand"
	player.camera.add_child(_hand)
	_hand.visible = false
	_bottle = MolotovManager.make_bottle()
	_hand.add_child(_bottle)
	# Right hand round the bottle's body: fingers wrap forward-down, palm towards the bottle.
	_grip_r = Marker3D.new()
	_grip_r.name = "GripR"
	_bottle.add_child(_grip_r)
	_grip_r.transform = Transform3D(Basis.looking_at(Vector3(0, -0.3, -1).normalized(), Vector3.UP) * Basis(Vector3.UP, PI / 2.0), Vector3(0.05, -0.02, 0.0))
	_rag_flame = MolotovManager.make_flames(14, 0.22, soft)
	_rag_flame.local_coords = true # stays on the rag when you turn (or it smears across the view)
	_rag_flame.position = Vector3(0.012, 0.26, 0.0)
	_rag_flame.emitting = false
	_bottle.add_child(_rag_flame)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.omni_range = 2.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.3, 0)
	_bottle.add_child(_light)
	# Left hand: holds the match while lighting, otherwise stretched out low (aiming) / down.
	_grip_l = Marker3D.new()
	_grip_l.name = "GripL"
	_hand.add_child(_grip_l)
	_match_flame = MolotovManager.make_flames(6, 0.1, soft)
	_match_flame.local_coords = true
	_match_flame.emitting = false
	_grip_l.add_child(_match_flame)
	_match_flame.position = Vector3(0.02, 0.03, -0.06)
	_ignite_audio = AudioStreamPlayer.new()
	_ignite_audio.bus = &"SFX"
	add_child(_ignite_audio)
	_flame_audio = AudioStreamPlayer.new()
	_flame_audio.bus = &"SFX"
	_flame_audio.volume_db = -8.0
	add_child(_flame_audio)


func _on_phase_changed(was: Phase, now: Phase) -> void:
	if now == Phase.IGNITING:
		_play(_ignite_audio, RecordedSounds.pick("molotov_ignite"))
	if now == Phase.LIT:
		var crackle: AudioStream = RecordedSounds.pick("fire_loop")
		if crackle:
			_play(_flame_audio, crackle)
	if was == Phase.LIT:
		_flame_audio.stop()
	if was == Phase.IGNITING and now == Phase.HELD:
		_ignite_audio.stop() # let go too early: the match goes out
	if now == Phase.HELD and was == Phase.THROWING:
		_hand_t = 0.0 # the next bottle comes up from below


## Where the hands go while a bottle is held: [right, left]. Empty = not holding one.
func get_hand_grips() -> Array[Transform3D]:
	if _hand == null or not _hand.visible:
		return []
	return [_grip_r.global_transform, _grip_l.global_transform]


func _process(delta: float) -> void:
	if _hand == null:
		return
	var shown: bool = is_selected() and not player.is_dead
	_hand.visible = shown
	if not shown:
		_hand_t = 0.0
		_rag_flame.emitting = false
		_light.light_energy = 0.0
		return
	var since: float = _clock - _phase_since
	_hand_t = minf(_hand_t + delta / 0.3, 1.0)
	var aiming: bool = phase == Phase.LIT and player.input.aim_held
	_aim_t = move_toward(_aim_t, 1.0 if aiming else 0.0, delta / 0.25)
	# Key poses in camera space: [bottle position, bottle rotation (deg), left hand position].
	var down := Vector3(0.24, -0.62, -0.4)
	var held := Vector3(0.19, -0.33, -0.55)
	var pos: Vector3 = held
	var rot := Vector3(-10.0, 0.0, -12.0)
	var left := Vector3(-0.22, -0.5, -0.25) # low, mostly out of view
	if phase == Phase.IGNITING:
		var k: float = smoothstep(0.0, 0.35, since)
		pos = held.lerp(Vector3(0.07, -0.3, -0.52), k)
		rot = Vector3(-10.0, 0.0, -12.0).lerp(Vector3(-5.0, 0.0, 22.0), k)
		left = left.lerp(Vector3(-0.03, -0.1, -0.48), k) # the match at the rag
	elif phase == Phase.LIT:
		var cocked := Vector3(0.3, -0.02, -0.26) # arm back by the shoulder, ready to throw (flame just in view)
		var a: float = smoothstep(0.0, 1.0, _aim_t)
		pos = held.lerp(cocked, a)
		rot = Vector3(-10.0, 0.0, -12.0).lerp(Vector3(35.0, 10.0, -20.0), a)
		left = left.lerp(Vector3(-0.2, -0.16, -0.5), a) # free arm points at the target
	elif phase == Phase.THROWING:
		var k: float = clampf(since / 0.15, 0.0, 1.0)
		pos = Vector3(0.3, -0.02, -0.26).lerp(Vector3(0.05, -0.12, -0.75), k)
		rot = Vector3(35.0, 10.0, -20.0).lerp(Vector3(-60.0, 0.0, 0.0), k)
	_bottle.visible = phase != Phase.THROWING
	pos = down.lerp(pos, smoothstep(0.0, 1.0, _hand_t))
	_bottle.position = pos
	_bottle.rotation_degrees = rot
	_grip_l.transform = Transform3D(Basis.looking_at(Vector3(0.3, -0.2, -1).normalized(), Vector3.UP) * Basis(Vector3.UP, -PI / 2.0), left)
	_match_flame.emitting = phase == Phase.IGNITING and since > 0.3
	# The rag: lit at the end of the lighting, then bigger and bigger the longer it burns.
	var lit: bool = phase == Phase.LIT or (phase == Phase.IGNITING and get_ignite_progress() > 0.85)
	_rag_flame.emitting = lit
	var t: float = get_lit_time()
	var size: float = 1.0
	if t > danger_time:
		size = 1.9
	elif t > warn_time:
		size = lerpf(1.2, 1.7, (t - warn_time) / (danger_time - warn_time))
	_rag_flame.scale_amount_min = 0.7 * size
	_rag_flame.scale_amount_max = 1.3 * size
	_light.light_energy = (0.22 * size + randf() * 0.1) if lit else 0.0


func _play(a: AudioStreamPlayer, stream: AudioStream) -> void:
	if stream:
		a.stream = stream
		a.play()
