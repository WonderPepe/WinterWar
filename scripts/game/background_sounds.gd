class_name BackgroundSounds
extends Node
## Background sounds of the war around you: each one plays ONCE per battle, at a random moment
## in the middle of a random wave, and moves across the sky (it comes from one direction and
## flies over you), so it doesn't sound as if it played inside your head.
##
## The HOST picks when and from which direction; every computer then plays it around its own
## player (`play_flyover` RPC). Add more sounds to `sounds` (e.g. in the Inspector of
## Game/BackgroundSounds) and each gets its own random moment.

@export var sounds: Array[AudioStream] = [] ## Each one plays once per battle.
@export var overhead_at: Array[float] = [] ## Seconds into each sound when it is right above you (loudest point).
@export var height_m: float = 80.0 ## How high it flies.
@export var speed_m_s: float = 50.0 ## How fast it moves across the sky (~180 km/h).
@export var unit_size: float = 120.0 ## Large = the distance hardly changes the volume (the recording already gets louder by itself).
@export var volume_db: float = -2.0
@export var earliest_s: float = 15.0 ## Not before this many seconds into its wave...
@export var latest_s: float = 60.0 ## ...and not after this many.

var _waves: Array[int] = [] # host: the wave in which each sound plays
var _at: Array[float] = []  # host: seconds into that wave
var _played: Array[bool] = []
var _wave_time: float = 0.0
var _last_wave: int = 0
var _flying: Array = [] # [player, start, velocity] on this computer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if not multiplayer.is_server():
		return
	# Waves are chosen when the first wave starts (the difficulty is known by then).
	for i in sounds.size():
		_waves.append(0)
		_at.append(_rng.randf_range(earliest_s, latest_s))
		_played.append(false)


func _process(delta: float) -> void:
	_move_flyovers(delta)
	if not multiplayer.is_server() or sounds.is_empty():
		return
	var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	var director := get_tree().get_first_node_in_group("match_director") as MatchDirector
	if spawner == null or (director and director.is_over()):
		return
	if spawner.wave_number != _last_wave:
		_last_wave = spawner.wave_number
		_wave_time = 0.0
		if _waves.size() > 0 and _waves[0] == 0:
			_pick_waves(director.waves_to_win if director else 3)
	if spawner.wave_number <= 0 or spawner.alive_count <= 0:
		return # only while a wave is being fought
	_wave_time += delta
	for i in sounds.size():
		if not _played[i] and spawner.wave_number >= _waves[i] and _wave_time >= _at[i]:
			_played[i] = true
			play_flyover.rpc(i, _rng.randf_range(0.0, TAU), _rng.randf_range(-60.0, 60.0))


## "In the middle of the battle": not the first wave, not the last one (if there are enough).
func _pick_waves(total: int) -> void:
	var lo: int = 2 if total >= 3 else 1
	var hi: int = maxi(total - 1, lo)
	for i in _waves.size():
		_waves[i] = _rng.randi_range(lo, hi)


## Every computer: the sound flies over its own player. `heading` = direction of flight
## (radians), `side_m` = how far to the side of the player it passes.
@rpc("authority", "call_local", "reliable")
func play_flyover(index: int, heading: float, side_m: float) -> void:
	if index < 0 or index >= sounds.size():
		return
	var cam := get_viewport().get_camera_3d()
	var centre: Vector3 = cam.global_position if cam else Vector3.ZERO
	var dir := Vector3(sin(heading), 0.0, cos(heading))
	var side := Vector3(dir.z, 0.0, -dir.x)
	var t_over: float = overhead_at[index] if index < overhead_at.size() else 10.0
	var velocity: Vector3 = dir * speed_m_s
	# Start where it must be so it is right above (beside) us after t_over seconds.
	var start: Vector3 = centre + side * side_m + Vector3.UP * height_m - velocity * t_over
	var p := AudioStreamPlayer3D.new()
	p.name = "Flyover%d" % index
	p.stream = sounds[index]
	p.bus = &"SFX"
	p.unit_size = unit_size
	p.volume_db = volume_db
	p.max_db = 3.0
	p.attenuation_filter_db = 0.0 # (no extra muffling with distance: it's in the recording)
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED # the recording has its own
	add_child(p)
	p.global_position = start
	p.play()
	p.finished.connect(p.queue_free)
	_flying.append([p, start, velocity])


func _move_flyovers(delta: float) -> void:
	for i in range(_flying.size() - 1, -1, -1):
		var f: Array = _flying[i]
a		var p := f[0] as AudioStreamPlayer3D
		if not is_instance_valid(p):
			_flying.remove_at(i)
			continue
		p.global_position += (f[2] as Vector3) * delta
