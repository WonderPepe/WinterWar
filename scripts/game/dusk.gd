class_name DuskLight
extends Node
## The weather and time of day of the battle (B3; before B3 this was the slow sunset over all ten
## battles). Every battle has its own look – sun or moon, sky, fog, falling snow, wind – in
## resources/weather/battle_NN.tres (`WeatherData`, made by tools/make_weather.gd). Battles 8 and
## 10 change DURING the battle (their look has an `end_look`: the fog clears / dusk deepens).
## The new look is set while the day screen is black, so nobody sees it change.
## Runs on every computer (only reads the synced `MatchDirector.waves_cleared` and the spawner's
## `wave_number`). The environment and sky material are COPIED at start, so the saved scene
## files never change. (Node and class keep their old names so the scene and tests stay.)

@export var wait_for_black: float = 6.0 ## Max seconds to wait for the black day screen before changing the look anyway.
@export var step: float = 0.01 ## The sky is only re-lit when the blend moved this much (re-lighting is costly).

signal look_changed

var battle: int = 0 ## The battle whose look is shown (1 = first).
var look: WeatherData ## What is shown now (a mix while the look changes).
var battle_clock: float = 0.0 ## Seconds since the battle began (drives the change).

var _looks: Array[WeatherData] = []
var _sun: DirectionalLight3D
var _env: Environment
var _sky: ShaderMaterial
var _wait: float = 0.0
var _blend: float = -1.0
var _started: bool = false
var _snow_applied: int = -1


func _ready() -> void:
	add_to_group("weather")
	for i in 10:
		var path: String = "res://resources/weather/battle_%02d.tres" % (i + 1)
		_looks.append(load(path) as WeatherData if ResourceLoader.exists(path) else WeatherData.new())
	_sun = get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	var we := get_tree().get_first_node_in_group("world_environment") as WorldEnvironment
	if we and we.environment:
		_env = we.environment.duplicate() as Environment
		if _env.sky and _env.sky.sky_material is ShaderMaterial:
			_env.sky = _env.sky.duplicate() as Sky
			_sky = _env.sky.sky_material.duplicate() as ShaderMaterial
			_env.sky.sky_material = _sky
		we.environment = _env
	Settings.changed.connect(apply_quality)
	_show_battle(1)


func _process(delta: float) -> void:
	var director := get_tree().get_first_node_in_group("match_director") as MatchDirector
	var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	var want: int = clampi((director.waves_cleared + 1) if director else 1, 1, _looks.size())
	if director and not _started:
		_started = true
		if want != battle:
			_show_battle(want) # test mode (or joining late): no change over the first seconds
	if want != battle:
		var day_screen := get_tree().get_first_node_in_group("day_screen") as DayScreen
		_wait += delta
		# The new battle's look appears behind the black day screen (or after a timeout, e.g. if
		# there is no day screen).
		if (day_screen and day_screen.is_black()) or _wait >= wait_for_black:
			_show_battle(want)
		return
	_wait = 0.0
	# The clock runs while this battle's wave is on (or has been started).
	if spawner and spawner.wave_number >= battle:
		battle_clock += delta
	if look and _current_base().end_look:
		var t: float = clampf(battle_clock / maxf(_current_base().change_seconds, 0.01), 0.0, 1.0)
		if absf(t - _blend) >= step or (t >= 1.0 and _blend < 1.0):
			_apply_blend(t)


## Sets the look of battle `n` at once (start look, clock at 0).
func _show_battle(n: int) -> void:
	battle = n
	battle_clock = 0.0
	_wait = 0.0
	_apply_blend(0.0)


func _current_base() -> WeatherData:
	return _looks[clampi(battle - 1, 0, _looks.size() - 1)]


func _apply_blend(t: float) -> void:
	_blend = t
	var base: WeatherData = _current_base()
	look = base.mixed(base.end_look, t) if base.end_look and t > 0.0 else base
	_apply(look)


## Puts a look on the sun, environment and sky, and on the quality-dependent parts.
func _apply(w: WeatherData) -> void:
	if _sun:
		_sun.rotation = Vector3(deg_to_rad(w.sun_pitch_deg), deg_to_rad(w.sun_yaw_deg), 0.0)
		_sun.light_color = w.sun_color
		_sun.light_energy = w.sun_energy
	if _env:
		_env.ambient_light_energy = w.ambient_energy
		_env.ambient_light_color = w.ambient_color
		_env.fog_light_color = w.fog_color
		_env.fog_sky_affect = w.fog_sky_affect
	if _sky:
		_sky.set_shader_parameter("zenith_color", w.zenith_color)
		_sky.set_shader_parameter("horizon_color", w.horizon_color)
		_sky.set_shader_parameter("ground_color", w.ground_color)
		_sky.set_shader_parameter("sun_glow_color", w.glow_color)
		_sky.set_shader_parameter("glow_strength", w.glow_strength)
		_sky.set_shader_parameter("cloud_cover", w.cloud_cover)
		_sky.set_shader_parameter("cloud_color", w.cloud_color)
		_sky.set_shader_parameter("sun_size_deg", w.sun_size_deg)
		_sky.set_shader_parameter("sun_brightness", w.sun_brightness)
		_sky.set_shader_parameter("star_strength", w.star_strength)
	apply_quality()
	var amb := get_parent().get_node_or_null("Ambience") as Ambience
	if amb:
		amb.set_wind_offset(w.wind_db)
	look_changed.emit()


## The parts that depend on BOTH the quality setting and the weather: fog density, falling snow
## (amount and sideways wind) and the snow blown along the ground. Called when the look or the
## quality setting changes, and by QualityApplier / a new Player.
func apply_quality() -> void:
	if look == null:
		return
	var p: Dictionary = Settings.preset()
	if _env:
		_env.fog_density = float(p.fog_density) * look.fog_scale
	var amount: int = int(round(float(p.snow_amount) * look.snowfall))
	for node in get_tree().get_nodes_in_group("players"):
		var pl := node as Player
		if pl.snow_particles.amount != maxi(amount, 1):
			pl.snow_particles.amount = maxi(amount, 1) # (changing it restarts the flakes: only when it changed)
		pl.snow_particles.emitting = pl.is_local_player() and amount > 0
		pl.snow_particles.gravity = Vector3(look.snow_wind, -1.0, look.snow_wind * 0.5)
		var fx := pl.get_node_or_null("PlayerFX") as PlayerFX
		if fx:
			fx.set_drift_amount(int(round(float(p.drift_amount) * look.drift_scale)))
