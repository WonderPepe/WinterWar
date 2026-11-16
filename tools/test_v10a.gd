extends Node
## Test for V10a "the world moves" (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_v10a.gd
## Spruce sway: the tree shader has the wind, every tree material gets each battle's wind
## (WeatherData.wind) from DuskLight, also while a look changes and after the forest is rebuilt.
## Cloud drift: the clouds move with the wind, faster in more wind, sent to the sky only a few
## times a second, and the sky shader itself does NOT use TIME (that would re-light it every frame).
## Shader mistakes only show with a real graphics window: run shots_v10a.gd for that.

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _ready() -> void:
	await get_tree().process_frame
	run()


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## The shader's text without its // comments.
func code_of(path: String) -> String:
	var out: String = ""
	for line in (load(path) as Shader).code.split("\n"):
		out += line.split("//")[0] + "\n"
	return out


func run() -> void:
	# --- The shaders.
	var spruce: String = code_of("res://resources/shaders/spruce.gdshader")
	check(spruce.contains("TIME") and spruce.contains("uniform float wind_strength") and spruce.contains("uniform vec2 wind_direction"),
			"the spruce shader moves with TIME and has the wind strength and direction")
	check(spruce.find("local_pos = VERTEX") < spruce.find("VERTEX +=") and spruce.find("local_pos = VERTEX") >= 0,
			"the snow pattern uses the place BEFORE the wind moves it (snow stays on the branches)")
	var sky: String = code_of("res://resources/shaders/winter_sky.gdshader")
	check(not sky.contains("TIME"), "the sky shader does not use TIME (it would be re-lit every frame)")
	check(sky.contains("uniform vec2 cloud_offset") and sky.contains("uv - cloud_offset"), "the sky shader has the cloud drift value")

	# --- Wind per battle.
	var looks: Array[WeatherData] = []
	for i in 10:
		looks.append(load("res://resources/weather/battle_%02d.tres" % (i + 1)) as WeatherData)
	var strongest: int = 0
	var calmest: int = 0
	var snowy_same: bool = true
	var in_range: bool = true
	for i in 10:
		if looks[i].wind > looks[strongest].wind:
			strongest = i
		if looks[i].wind < looks[calmest].wind:
			calmest = i
		if looks[i].snowfall > 0.0 and not is_equal_approx(looks[i].wind, looks[i].snow_wind):
			snowy_same = false
		in_range = in_range and looks[i].wind >= 0.0 and looks[i].wind <= 2.0
	check(strongest == 1 and is_equal_approx(looks[1].wind, 1.6), "the snowstorm of battle 2 has the strongest wind (%.1f)" % looks[1].wind)
	check(calmest == 6, "the dense fog of battle 7 is the calmest (battle %d, %.2f)" % [calmest + 1, looks[calmest].wind])
	check(snowy_same, "where snow falls, the wind on the trees = the wind on the snow")
	check(in_range, "all winds are between 0 and 2")
	check(looks[7].end_look != null and looks[7].end_look.wind > looks[7].wind, "battle 8: the wind picks up as the fog clears")
	var snow_push := Vector2(1.0, 0.5).normalized() # DuskLight.apply_quality: gravity (snow_wind, -1, snow_wind * 0.5)
	check(WeatherData.WIND_DIRECTION.is_equal_approx(snow_push), "trees and clouds go the way the falling snow is pushed")

	# --- In the game.
	Settings.difficulty = 1
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await wait(0.5)
	(get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner).set_process(false)
	(get_tree().get_first_node_in_group("match_director") as MatchDirector).set_process(false)
	var dusk := game.get_node("Dusk") as DuskLight
	dusk.wait_for_black = 1.0e9 # the test chooses the looks
	var forest := get_tree().get_first_node_in_group("forest") as ForestScatter
	check(forest != null and forest.has_method("set_wind"), "the forest takes the wind")
	var mats: Array[ShaderMaterial] = forest._near_materials + forest._far_materials
	check(mats.size() == 4, "four tree materials (near / far, branches / trunk)")
	var all_ok: bool = true
	for n in [1, 2, 3, 7, 10]:
		dusk._show_battle(n)
		for m in mats:
			if not is_equal_approx(float(m.get_shader_parameter("wind_strength")), looks[n - 1].wind):
				all_ok = false
			if not (m.get_shader_parameter("wind_direction") as Vector2).is_equal_approx(WeatherData.WIND_DIRECTION):
				all_ok = false
	check(all_ok, "every tree material gets each battle's wind and its direction (battles 1, 2, 3, 7, 10)")
	check(is_equal_approx(forest.get_wind(), looks[9].wind), "the forest remembers the wind (%.2f)" % forest.get_wind())
	# A look that changes during the battle (8: the fog clears).
	dusk._show_battle(8)
	dusk._apply_blend(0.5)
	var half: float = (looks[7].wind + looks[7].end_look.wind) * 0.5
	check(is_equal_approx(forest.get_wind(), half), "battle 8 half way: the wind is half way too (%.3f)" % forest.get_wind())
	# The forest built again (quality, editor button): the new materials have the wind.
	dusk._show_battle(2)
	forest.build()
	mats = forest._near_materials + forest._far_materials
	all_ok = mats.size() == 4
	for m in mats:
		all_ok = all_ok and is_equal_approx(float(m.get_shader_parameter("wind_strength")), 1.6)
	check(all_ok, "after the forest is rebuilt its new materials still have the wind")
	forest.set_wind(-3.0, Vector2.ZERO)
	check(forest.get_wind() == 0.0 and (mats[0].get_shader_parameter("wind_direction") as Vector2).is_equal_approx(WeatherData.WIND_DIRECTION),
			"a wrong wind (negative, no direction) is made safe")

	# --- Clouds.
	var sky_mat: ShaderMaterial = dusk._sky
	check(sky_mat != null, "DuskLight has its own copy of the sky material")
	dusk._show_battle(3) # the clear day, wind 0.3
	await get_tree().process_frame
	var start: Vector2 = dusk.get_cloud_offset()
	var sent: Dictionary = {}
	var frames_n: int = 0
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
		frames_n += 1
		sent[sky_mat.get_shader_parameter("cloud_offset")] = true
	var secs: float = (Time.get_ticks_msec() - t0) / 1000.0
	var moved: Vector2 = dusk.get_cloud_offset() - start
	var want: float = dusk.cloud_drift * (0.4 + looks[2].wind) * secs
	check(absf(moved.length() - want) < want * 0.15, "calm day: the clouds drift %.4f in %.1f s (wanted %.4f)" % [moved.length(), secs, want])
	check(moved.normalized().is_equal_approx(WeatherData.WIND_DIRECTION), "...in the wind's direction")
	check(sent.size() >= 12 and sent.size() <= 20 and frames_n > sent.size() * 2,
			"the sky gets the new place about 8 times a second, not every frame (%d times in %d frames)" % [sent.size(), frames_n])
	dusk._show_battle(2) # the snowstorm, wind 1.6
	start = dusk.get_cloud_offset()
	await wait(1.0)
	var storm: float = (dusk.get_cloud_offset() - start).length()
	check(storm > moved.length() / secs * 2.0, "snowstorm: the clouds drift faster (%.4f per s against %.4f)" % [storm, moved.length() / secs])
	# Paused: nothing drifts.
	get_tree().paused = true
	start = dusk.get_cloud_offset()
	await wait(0.5)
	check(dusk.get_cloud_offset() == start, "paused: the clouds stand still")
	get_tree().paused = false
	# Switched off.
	dusk.cloud_drift = 0.0
	start = dusk.get_cloud_offset()
	await wait(0.5)
	check(dusk.get_cloud_offset() == start, "cloud_drift 0 = the clouds stand still")

	print("TEST V10A DONE: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)
