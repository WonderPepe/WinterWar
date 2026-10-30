class_name PlayerFX
extends Node3D
## Small things that make a player feel present (child of Player, runs on every computer):
## - footsteps: crunching snow, the duller trampled trench floor, wood in the bunker;
## - breath vapour in front of your face (only your own player);
## - drifting snow: thin streaks of snow blown along the ground around you (only your own).
## Only reads the player's synced state, so it works the same for remote players in co-op.

@export var stride_m: float = 0.75 ## Distance per step when walking.
@export var sprint_stride_m: float = 1.0
@export var breath_interval: float = 3.2 ## Seconds between breaths when calm...
@export var tired_breath_interval: float = 1.3 ## ...and when out of breath.

const STEP_SOUNDS: Dictionary = {
	"snow": ["res://assets/audio/step_snow_1.wav", "res://assets/audio/step_snow_2.wav", "res://assets/audio/step_snow_3.wav"],
	"trench": ["res://assets/audio/step_trench_1.wav", "res://assets/audio/step_trench_2.wav"],
	"wood": ["res://assets/audio/step_wood_1.wav", "res://assets/audio/step_wood_2.wav"],
}

var _streams: Dictionary = {} # surface -> Array[AudioStream]
var _distance: float = 0.0
var _last_pos: Vector3
var _breath_timer: float = 1.0
var _rng := RandomNumberGenerator.new()

var footsteps: AudioStreamPlayer3D
var breath: CPUParticles3D
var drift: CPUParticles3D

@onready var player: Player = get_parent()


func _ready() -> void:
	_rng.randomize()
	# The sound and particle nodes are made here in code (they are the same for every player).
	footsteps = AudioStreamPlayer3D.new()
	footsteps.name = "Footsteps"
	footsteps.bus = &"SFX"
	footsteps.unit_size = 4.0
	add_child(footsteps)
	breath = SoldierVisual.make_breath_emitter()
	breath.position = Vector3(0, -0.07, -0.25)
	get_node("../Head/Camera3D").add_child(breath) # (the Player's own variables aren't ready yet)
	drift = make_drift_emitter()
	drift.top_level = true # the wind blows the same way whichever way you face
	add_child(drift)
	for surface: String in STEP_SOUNDS:
		var list: Array[AudioStream] = []
		for path: String in STEP_SOUNDS[surface]:
			list.append(load(path))
		_streams[surface] = list
	_last_pos = player.global_position
	var local: bool = player.is_local_player()
	set_drift_amount(Settings.preset().get("drift_amount", 200))
	breath.visible = local


## Quality setting: how many drifting snow streaks (0 = off).
func set_drift_amount(amount: int) -> void:
	drift.amount = maxi(amount, 1)
	drift.emitting = player.is_local_player() and amount > 0
	drift.visible = drift.emitting


func _process(delta: float) -> void:
	var pos: Vector3 = player.global_position
	var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos
	if moved > 2.0:
		moved = 0.0 # teleported (respawn, mounting the Maxim): not a step
	if not player.is_dead and player.get_mounted_gun() == null and absf(player.velocity.y) < 1.0:
		_distance += moved
		var stride: float = sprint_stride_m if player.is_sprinting else stride_m
		if _distance >= stride:
			_distance = 0.0
			_play_step()
	if player.is_local_player():
		_update_breath(delta)
		drift.global_position = Vector3(pos.x, pos.y + 0.1, pos.z)


func _play_step() -> void:
	var surface: String = _surface_below()
	var list: Array = _streams[surface]
	footsteps.stream = list[_rng.randi() % list.size()]
	footsteps.pitch_scale = _rng.randf_range(0.9, 1.12)
	var vol: float = -10.0 if player.is_crouching else -4.0
	if player.is_sprinting:
		vol += 2.0
	footsteps.volume_db = vol
	footsteps.play()


## What is under our feet? Wood (bunker, gun platform), the trampled trench floor, or snow.
func _surface_below() -> String:
	var from: Vector3 = player.global_position + Vector3.UP * 0.2
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.6, 0b1)
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var surface: String = ImpactEffects.surface_of(hit.collider, hit.normal)
		if surface == "wood":
			return "wood"
	return "trench" if player.global_position.y < -0.8 else "snow"


func _update_breath(delta: float) -> void:
	if player.is_dead:
		return
	_breath_timer -= delta
	if _breath_timer > 0.0:
		return
	var tired: bool = player.is_sprinting or player.stamina < player.max_stamina * 0.4
	_breath_timer = (tired_breath_interval if tired else breath_interval) * _rng.randf_range(0.85, 1.15)
	breath.restart()


## Thin streaks of snow blown along the ground (the wind is the same as the falling snow's).
static func make_drift_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "SnowDrift"
	p.amount = 200
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.fixed_fps = 30
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(14, 0.15, 14)
	p.direction = Vector3(0.9, 0.05, 0.4)
	p.spread = 8.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0.6, -0.15, 0.25)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var fade := Gradient.new() # fade in, drift, fade out
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(0.95, 0.97, 1.0, 0.0), Color(0.95, 0.97, 1.0, 0.55),
		Color(0.95, 0.97, 1.0, 0.45), Color(0.95, 0.97, 1.0, 0.0)])
	p.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = ImpactEffects.make_soft_texture()
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ImpactEffects.web_fallback(p)
	return p
