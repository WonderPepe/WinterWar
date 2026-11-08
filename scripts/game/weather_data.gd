class_name WeatherData
extends Resource
## The look of one battle (B3): sun or moon, sky, fog, snowfall and wind. One file per battle in
## resources/weather/battle_01.tres … battle_10.tres (made by tools/make_weather.gd). Open one in
## the Inspector to tune it. `end_look` (optional) is where the look slowly goes DURING the battle
## (battle 8: the fog clears, battle 10: dusk deepens), over `change_seconds`.

@export var title: String = ""

@export_group("Sun or moon (the level's one directional light)")
@export var sun_pitch_deg: float = -13.0 ## Negative = shining down from above the horizon.
@export var sun_yaw_deg: float = -150.0
@export var sun_color: Color = Color(1.0, 0.87, 0.72)
@export var sun_energy: float = 1.25
@export var ambient_energy: float = 0.5 ## Light from the sky in the shadows.
@export var ambient_color: Color = Color(0.56, 0.68, 0.9)

@export_group("Sky")
@export var zenith_color: Color = Color(0.24, 0.42, 0.70)
@export var horizon_color: Color = Color(0.78, 0.85, 0.92)
@export var ground_color: Color = Color(0.82, 0.86, 0.92)
@export var glow_color: Color = Color(1.0, 0.80, 0.58) ## Glow around the sun / moon.
@export var glow_strength: float = 0.75
@export var cloud_cover: float = 0.35
@export var cloud_color: Color = Color(1.0, 0.98, 0.96)
@export var sun_size_deg: float = 0.8
@export var sun_brightness: float = 12.0 ## 0 = no sun / moon disc (hidden by clouds).
@export var star_strength: float = 0.0

@export_group("Fog")
@export var fog_scale: float = 1.0 ## × the quality preset's fog density (1 = the old clear day).
@export var fog_color: Color = Color(0.74, 0.81, 0.9)
@export var fog_sky_affect: float = 0.15 ## 1 = the sky fades into the fog too.
## How far the ENEMY can see through this weather (soldiers and tanks): their sight is the smaller
## of their own range and this. 1000 or more = no limit. Your own shots still make noise.
@export var visibility_m: float = 1000.0

@export_group("Snow and wind")
@export var snowfall: float = 0.0 ## × the quality preset's falling snow (0 = none).
@export var snow_wind: float = 0.4 ## Sideways push on the falling snow (m/s²).
@export var drift_scale: float = 1.0 ## × the preset's snow blown along the ground.
@export var wind_db: float = 0.0 ## Added to the wind sound.

@export_group("Change during the battle")
@export var end_look: WeatherData
@export var change_seconds: float = 120.0


## A new look `t` (0..1) of the way from this one to `other`. Only the numbers and colours
## are mixed (the title, `end_look` and `change_seconds` stay as they are).
func mixed(other: WeatherData, t: float) -> WeatherData:
	var out := WeatherData.new()
	for prop: Dictionary in get_script().get_script_property_list():
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue
		var n: String = prop.name
		var a: Variant = get(n)
		if a is float or a is Color:
			out.set(n, lerp(a, other.get(n), t))
		elif n != "end_look" and n != "change_seconds":
			out.set(n, a)
	return out
