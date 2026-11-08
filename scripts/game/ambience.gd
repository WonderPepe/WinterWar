class_name Ambience
extends Node
## The sound of the place: a cold wind that never stops, and the battle going on all along
## the Mannerheim Line – distant artillery and machine guns from different directions.
## Down in the trench or inside the bunker the wind and the distant battle sound muffled.
## Only sound: nothing here changes the game, so every computer simply plays its own.

@export var min_gap: float = 5.0 ## Seconds between distant battle sounds (random in between).
@export var max_gap: float = 16.0
@export var battle_distance_min: float = 500.0
@export var battle_distance_max: float = 1100.0
@export var muffled_cutoff_hz: float = 1400.0 ## Ambience low-pass in the trench / bunker.

const ARTILLERY: Array[String] = ["res://assets/audio/artillery_far_1.wav", "res://assets/audio/artillery_far_2.wav"]
const MACHINE_GUNS: Array[String] = ["res://assets/audio/mg_far_1.wav", "res://assets/audio/mg_far_2.wav"]

var _wind: AudioStreamPlayer
var _wind_offset_db: float = 0.0 ## From the battle's weather (B3).
var _far: Array[AudioStreamPlayer3D] = []
var _next_far: int = 0
var _timer: float = 3.0
var _artillery: Array[AudioStream] = []
var _machine_guns: Array[AudioStream] = []
var _muffle: AudioEffectLowPassFilter
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var wind_stream: AudioStreamWAV = load("res://assets/audio/wind_loop.wav")
	wind_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wind_stream.loop_begin = 0
	wind_stream.loop_end = int(wind_stream.get_length() * wind_stream.mix_rate) # in samples
	_wind = AudioStreamPlayer.new()
	_wind.stream = wind_stream
	_wind.bus = &"Ambience"
	_wind.volume_db = -14.0 + _wind_offset_db # quiet: you should notice the cold wind, not listen to it
	add_child(_wind)
	_wind.play()
	for path in ARTILLERY:
		_artillery.append(load(path))
	for path in MACHINE_GUNS:
		_machine_guns.append(load(path))
	for i in 3:
		var a := AudioStreamPlayer3D.new()
		a.bus = &"Ambience"
		a.unit_size = 220.0 # very loud sounds far away
		a.max_db = 0.0
		a.attenuation_filter_cutoff_hz = 1200.0 # distance takes the high tones away
		a.attenuation_filter_db = -18.0
		add_child(a)
		_far.append(a)
	var bus: int = AudioServer.get_bus_index(&"Ambience")
	if bus >= 0 and AudioServer.get_bus_effect_count(bus) > 0:
		_muffle = AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter


## Louder wind in a snowstorm, quieter in fog (B3).
func set_wind_offset(db: float) -> void:
	_wind_offset_db = db
	if _wind:
		_wind.volume_db = -14.0 + db


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	_timer -= delta
	if _timer <= 0.0 and cam:
		_timer = _rng.randf_range(min_gap, max_gap)
		_play_far_battle(cam.global_position)
	# Below the parapet (in the trench or bunker) the outside sounds are muffled.
	if _muffle and cam:
		# Ears 0.4 m above the ground: open air. Ears 0.3 m below it: down in the trench.
		var open_air: float = smoothstep(-0.3, 0.4, cam.global_position.y)
		var target: float = lerpf(muffled_cutoff_hz, 20000.0, open_air * open_air)
		_muffle.cutoff_hz = lerpf(_muffle.cutoff_hz, target, clampf(delta * 3.0, 0.0, 1.0))


## One distant sound: mostly from the south (the Soviet side), sometimes along the front line.
func _play_far_battle(listener: Vector3) -> void:
	var a := _far[_next_far]
	_next_far = (_next_far + 1) % _far.size()
	var artillery: bool = _rng.randf() < 0.45
	a.stream = (_artillery if artillery else _machine_guns)[_rng.randi() % 2]
	var angle: float = _rng.randf_range(-PI * 0.85, PI * 0.85) # around "south" (-z), rarely from behind
	var dir := Vector3(sin(angle), 0.0, -cos(angle))
	a.global_position = listener + dir * _rng.randf_range(battle_distance_min, battle_distance_max) + Vector3.UP * 20.0
	a.volume_db = _rng.randf_range(-6.0, 0.0) + (2.0 if artillery else -2.0)
	a.pitch_scale = _rng.randf_range(0.85, 1.1)
	a.play()
