class_name DuskLight
extends Node
## The short winter day ends as the battle goes on: after every cleared wave the sun sinks a
## little, the light turns orange and the sky darker. When the last wave is cleared, it is dusk.
## Runs on every computer (only reads the MatchDirector's synced `waves_cleared`).
## The environment and sky material are COPIED at start, so the saved scene files never change.

@export var transition_time: float = 25.0 ## Seconds to move to the next step of the evening.
@export var sun_pitch_end_deg: float = -4.0 ## Sun height at dusk (start: from the level, -13°).
@export var sun_yaw_shift_deg: float = 14.0 ## The sun also moves west.
@export var sun_color_end: Color = Color(1.0, 0.56, 0.34)
@export var sun_energy_end: float = 0.55
@export var ambient_energy_end: float = 0.3
@export var fog_color_end: Color = Color(0.6, 0.55, 0.6)
@export var zenith_end: Color = Color(0.11, 0.16, 0.33)
@export var horizon_end: Color = Color(0.93, 0.62, 0.45)
@export var ground_end: Color = Color(0.48, 0.45, 0.52)
@export var glow_end: Color = Color(1.0, 0.5, 0.25)
@export var cloud_end: Color = Color(0.95, 0.72, 0.62)

var progress: float = 0.0 ## 0 = afternoon ... 1 = dusk (what is shown now).

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ShaderMaterial
var _start: Dictionary = {}
var _applied: float = -1.0
var _started: bool = false


func _ready() -> void:
	_sun = get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	var we := get_tree().get_first_node_in_group("world_environment") as WorldEnvironment
	if we and we.environment:
		_env = we.environment.duplicate() as Environment
		if _env.sky and _env.sky.sky_material is ShaderMaterial:
			_env.sky = _env.sky.duplicate() as Sky
			_sky = _env.sky.sky_material.duplicate() as ShaderMaterial
			_env.sky.sky_material = _sky
		we.environment = _env
	if _sun:
		_start["sun_rot"] = _sun.rotation
		_start["sun_color"] = _sun.light_color
		_start["sun_energy"] = _sun.light_energy
	if _env:
		_start["ambient"] = _env.ambient_light_energy
		_start["fog"] = _env.fog_light_color
	if _sky:
		for p in ["zenith_color", "horizon_color", "ground_color", "sun_glow_color", "cloud_color"]:
			_start[p] = _sky.get_shader_parameter(p)
	_apply(0.0)


func _process(delta: float) -> void:
	var director := get_tree().get_first_node_in_group("match_director") as MatchDirector
	var target: float = director.get_day_progress() if director else 0.0
	if director and not _started:
		_started = true
		progress = target # test mode (or joining late): no slow sunset over the first seconds
	progress = move_toward(progress, target, delta / maxf(transition_time, 0.01) / maxf(director.waves_to_win if director else 1, 1))
	# Changing the sky re-draws its lighting, so only do it when it changed noticeably.
	if absf(progress - _applied) > 0.004:
		_apply(progress)


func _apply(t: float) -> void:
	_applied = t
	var s: float = smoothstep(0.0, 1.0, t)
	if _sun:
		var rot: Vector3 = _start.sun_rot
		_sun.rotation = Vector3(lerpf(rot.x, deg_to_rad(sun_pitch_end_deg), s), rot.y + deg_to_rad(sun_yaw_shift_deg) * s, rot.z)
		_sun.light_color = (_start.sun_color as Color).lerp(sun_color_end, s)
		_sun.light_energy = lerpf(_start.sun_energy, sun_energy_end, s)
	if _env:
		_env.ambient_light_energy = lerpf(_start.ambient, ambient_energy_end, s)
		_env.fog_light_color = (_start.fog as Color).lerp(fog_color_end, s)
	if _sky:
		var ends := {"zenith_color": zenith_end, "horizon_color": horizon_end, "ground_color": ground_end,
				"sun_glow_color": glow_end, "cloud_color": cloud_end}
		for p: String in ends:
			if _start.get(p) is Color:
				_sky.set_shader_parameter(p, (_start[p] as Color).lerp(ends[p], s))
