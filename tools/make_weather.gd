extends SceneTree
## B3: writes the ten weather looks (resources/weather/battle_01.tres … battle_10.tres).
## build_scenes.gd calls `write_all()`; to make only these files:
##   godot --headless --path . --script tools/make_weather.gd
## Anything not listed in a look keeps the WeatherData default = the old clear freezing day.
## `visibility_m` = how far ENEMIES see (soldiers and tanks), 1000 = no limit.
## Fog: `fog_scale` 1 = the old light haze; ~5 → about 120 m of view, ~8 → ~80 m, ~11 → ~60 m.
## Battles 1 and 2 are lit by the MOON (owner: before sunrise); 8 and 10 change during the battle
## (`end`): the fog clears / dusk deepens.

const MOON := Color(0.62, 0.72, 1.0)

const LOOKS: Array = [
	# 1 – 30 Nov, 06:45: blue twilight, a moon between thin clouds, light snowfall.
	{"title": "Blue twilight, light snowfall",
	"sun_pitch_deg": -32.0, "sun_yaw_deg": -140.0, "sun_color": MOON, "sun_energy": 0.5,
	"ambient_energy": 0.7, "ambient_color": Color(0.5, 0.6, 0.9),
	"zenith_color": Color(0.04, 0.07, 0.17), "horizon_color": Color(0.36, 0.44, 0.62), "ground_color": Color(0.3, 0.36, 0.5),
	"glow_color": Color(0.8, 0.85, 1.0), "glow_strength": 0.5, "cloud_cover": 0.5, "cloud_color": Color(0.36, 0.42, 0.58),
	"sun_size_deg": 1.5, "sun_brightness": 2.6, "star_strength": 0.7,
	"fog_scale": 1.6, "fog_color": Color(0.32, 0.38, 0.52), "fog_sky_affect": 0.3, "visibility_m": 150.0,
	"snowfall": 0.35, "snow_wind": 0.4, "drift_scale": 0.5, "wind_db": 0.0},
	# 2 – 17 Dec, 05:30: dark blue before dawn, the moon behind heavy cloud, heavy snowfall, poor visibility.
	{"title": "Dark pre-dawn, heavy snowfall",
	"sun_pitch_deg": -38.0, "sun_yaw_deg": -120.0, "sun_color": MOON, "sun_energy": 0.32,
	"ambient_energy": 0.5, "ambient_color": Color(0.45, 0.55, 0.85),
	"zenith_color": Color(0.05, 0.07, 0.14), "horizon_color": Color(0.22, 0.27, 0.4), "ground_color": Color(0.22, 0.27, 0.38),
	"glow_color": Color(0.6, 0.68, 0.9), "glow_strength": 0.3, "cloud_cover": 0.95, "cloud_color": Color(0.22, 0.26, 0.38),
	"sun_size_deg": 1.5, "sun_brightness": 0.0, "star_strength": 0.0,
	"fog_scale": 7.0, "fog_color": Color(0.24, 0.29, 0.42), "fog_sky_affect": 0.8, "visibility_m": 80.0,
	"snowfall": 1.2, "snow_wind": 1.6, "drift_scale": 1.5, "wind_db": 5.0},
	# 3 – 19 Dec, 11:20: clear and bitterly cold – the old look.
	{"title": "Clear and bitterly cold"},
	# 4 – 22 Dec, 08:00: clear sky, low golden sun.
	{"title": "Clear skies, golden low sun",
	"sun_pitch_deg": -8.0, "sun_yaw_deg": -165.0, "sun_color": Color(1.0, 0.76, 0.5), "sun_energy": 1.3,
	"ambient_energy": 0.5, "zenith_color": Color(0.2, 0.36, 0.64), "horizon_color": Color(0.9, 0.8, 0.74),
	"glow_color": Color(1.0, 0.7, 0.45), "cloud_cover": 0.12, "fog_scale": 1.0, "fog_color": Color(0.85, 0.78, 0.76),
	"snowfall": 0.0, "wind_db": -2.0},
	# 5 – 1 Feb, 07:15: smoke and haze over the front, a dim sun, some snow.
	{"title": "Snow and artillery smoke",
	"sun_pitch_deg": -7.0, "sun_yaw_deg": -150.0, "sun_color": Color(1.0, 0.68, 0.45), "sun_energy": 0.7,
	"ambient_energy": 0.55, "ambient_color": Color(0.62, 0.62, 0.7),
	"zenith_color": Color(0.36, 0.4, 0.5), "horizon_color": Color(0.62, 0.56, 0.5), "ground_color": Color(0.55, 0.5, 0.48),
	"glow_color": Color(1.0, 0.65, 0.4), "glow_strength": 0.6, "cloud_cover": 0.85, "cloud_color": Color(0.5, 0.45, 0.42),
	"sun_brightness": 3.0, "fog_scale": 3.2, "fog_color": Color(0.5, 0.46, 0.43), "fog_sky_affect": 0.5, "visibility_m": 110.0,
	"snowfall": 0.3, "snow_wind": 0.8, "drift_scale": 1.0, "wind_db": 1.0},
	# 6 – 6 Feb, 06:30 (owner, L3): the counterattack goes in in the DARK of the morning – overcast,
	# no moon, light snow, a little darker than battle 2 (but less fog and snow, so the trench reads).
	{"title": "Dark morning, overcast",
	"sun_pitch_deg": -36.0, "sun_yaw_deg": -125.0, "sun_color": MOON, "sun_energy": 0.26,
	"ambient_energy": 0.42, "ambient_color": Color(0.42, 0.5, 0.78),
	"zenith_color": Color(0.035, 0.05, 0.11), "horizon_color": Color(0.17, 0.21, 0.32), "ground_color": Color(0.18, 0.22, 0.31),
	"glow_color": Color(0.55, 0.62, 0.85), "glow_strength": 0.2, "cloud_cover": 1.0, "cloud_color": Color(0.17, 0.2, 0.3),
	"sun_size_deg": 1.5, "sun_brightness": 0.0, "star_strength": 0.0,
	"fog_scale": 3.5, "fog_color": Color(0.19, 0.23, 0.34), "fog_sky_affect": 0.7, "visibility_m": 90.0,
	"snowfall": 0.3, "snow_wind": 0.5, "drift_scale": 0.8, "wind_db": 0.0},
	# 7 – 11 Feb, 08:40: dense fog, about -20 C.
	{"title": "Dense fog",
	"sun_pitch_deg": -9.0, "sun_yaw_deg": -145.0, "sun_color": Color(1.0, 0.9, 0.8), "sun_energy": 0.55,
	"ambient_energy": 0.9, "ambient_color": Color(0.7, 0.75, 0.85),
	"zenith_color": Color(0.62, 0.68, 0.76), "horizon_color": Color(0.76, 0.8, 0.85), "ground_color": Color(0.76, 0.8, 0.85),
	"glow_strength": 0.15, "cloud_cover": 0.8, "cloud_color": Color(0.8, 0.83, 0.87), "sun_brightness": 0.0,
	"fog_scale": 10.0, "fog_color": Color(0.74, 0.78, 0.83), "fog_sky_affect": 1.0, "visibility_m": 60.0,
	"snowfall": 0.0, "wind_db": -4.0},
	# 8 – 12 Feb, 13:30: fog at the start that clears soon, then a cold clear day (end look).
	{"title": "Fog clearing",
	"sun_pitch_deg": -11.0, "sun_yaw_deg": -150.0, "sun_color": Color(1.0, 0.9, 0.8), "sun_energy": 0.6,
	"ambient_energy": 0.9, "ambient_color": Color(0.7, 0.75, 0.85),
	"zenith_color": Color(0.6, 0.67, 0.76), "horizon_color": Color(0.76, 0.8, 0.85), "ground_color": Color(0.76, 0.8, 0.85),
	"glow_strength": 0.2, "cloud_cover": 0.7, "cloud_color": Color(0.8, 0.83, 0.87), "sun_brightness": 0.0,
	"fog_scale": 9.0, "fog_color": Color(0.74, 0.78, 0.83), "fog_sky_affect": 1.0, "visibility_m": 60.0,
	"snowfall": 0.0, "wind_db": -3.0,
	"change_seconds": 75.0,
	"end": {"sun_pitch_deg": -13.0, "sun_color": Color(1.0, 0.88, 0.74), "sun_energy": 1.2, "ambient_energy": 0.55,
		"ambient_color": Color(0.56, 0.68, 0.9), "zenith_color": Color(0.26, 0.44, 0.72), "horizon_color": Color(0.78, 0.85, 0.92),
		"ground_color": Color(0.82, 0.86, 0.92), "glow_strength": 0.75, "cloud_cover": 0.3, "cloud_color": Color(1.0, 0.98, 0.96),
		"sun_brightness": 12.0, "fog_scale": 1.0, "fog_color": Color(0.74, 0.81, 0.9), "fog_sky_affect": 0.15, "visibility_m": 1000.0, "wind_db": 0.0}},
	# 9 – 13 Feb, 09:15: low cloud and fog, moderate visibility.
	{"title": "Low cloud and fog",
	"sun_pitch_deg": -10.0, "sun_yaw_deg": -150.0, "sun_color": Color(0.95, 0.9, 0.85), "sun_energy": 0.45,
	"ambient_energy": 0.85, "ambient_color": Color(0.62, 0.68, 0.8),
	"zenith_color": Color(0.5, 0.55, 0.63), "horizon_color": Color(0.68, 0.72, 0.78), "ground_color": Color(0.7, 0.74, 0.8),
	"glow_strength": 0.1, "cloud_cover": 1.0, "cloud_color": Color(0.6, 0.63, 0.68), "sun_brightness": 0.0,
	"fog_scale": 5.5, "fog_color": Color(0.64, 0.68, 0.74), "fog_sky_affect": 0.9, "visibility_m": 120.0,
	"snowfall": 0.1, "snow_wind": 0.3, "wind_db": -2.0},
	# 10 – 15 Feb, 17:20: DUSK, no snowfall. Orange low sun, fading to violet and dark during the battle.
	{"title": "Dusk, orange fading to violet",
	"sun_pitch_deg": -5.0, "sun_yaw_deg": -140.0, "sun_color": Color(1.0, 0.56, 0.34), "sun_energy": 0.8,
	"ambient_energy": 0.4, "ambient_color": Color(0.62, 0.55, 0.78),
	"zenith_color": Color(0.11, 0.16, 0.33), "horizon_color": Color(0.93, 0.62, 0.45), "ground_color": Color(0.48, 0.45, 0.52),
	"glow_color": Color(1.0, 0.5, 0.25), "glow_strength": 0.9, "cloud_cover": 0.4, "cloud_color": Color(0.95, 0.72, 0.62),
	"fog_scale": 1.2, "fog_color": Color(0.6, 0.55, 0.6), "snowfall": 0.0, "wind_db": 0.0,
	"change_seconds": 200.0,
	"end": {"sun_pitch_deg": -1.5, "sun_yaw_deg": -128.0, "sun_color": Color(0.85, 0.4, 0.5), "sun_energy": 0.3,
		"ambient_energy": 0.6, "ambient_color": Color(0.5, 0.48, 0.8),
		"zenith_color": Color(0.05, 0.06, 0.18), "horizon_color": Color(0.5, 0.3, 0.5), "ground_color": Color(0.28, 0.27, 0.38),
		"glow_color": Color(0.8, 0.3, 0.45), "glow_strength": 0.7, "cloud_cover": 0.4, "cloud_color": Color(0.5, 0.38, 0.55),
		"sun_size_deg": 1.0, "sun_brightness": 4.0, "star_strength": 0.5, "fog_scale": 1.5, "fog_color": Color(0.4, 0.36, 0.5)}},
]


func _initialize() -> void:
	write_all()
	quit()


## Makes WeatherData `dict` (values over the defaults).
static func make(dict: Dictionary) -> WeatherData:
	var w := WeatherData.new()
	for key: String in dict:
		if key != "end":
			w.set(key, dict[key])
	if dict.has("end"):
		var e: WeatherData = w.duplicate() # the end look starts as a copy of the start look
		for key: String in dict["end"]:
			e.set(key, dict["end"][key])
		e.title = w.title + " (end)"
		w.end_look = e
	return w


static func write_all() -> void:
	DirAccess.make_dir_recursive_absolute("res://resources/weather")
	for i in LOOKS.size():
		var w: WeatherData = make(LOOKS[i])
		ResourceSaver.save(w, "res://resources/weather/battle_%02d.tres" % (i + 1))
	print("WEATHER LOOKS WRITTEN: %d" % LOOKS.size())
