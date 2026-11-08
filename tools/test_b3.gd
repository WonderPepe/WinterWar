extends Node
## Test for the weather and time of day (B3): ten looks, applied per battle behind the black day
## screen, fog / snow / wind scaled by the look, changes during battles 8 and 10 (not in the
## others), nothing written into the saved scene resources. Not part of the game:
##   godot --headless --path . --script tools/run.gd -- tools/test_b3.gd

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ready() -> void:
	await get_tree().process_frame
	run()


func run() -> void:
	# --- The ten looks ---
	var looks: Array[WeatherData] = []
	for i in 10:
		looks.append(load("res://resources/weather/battle_%02d.tres" % (i + 1)) as WeatherData)
	check(not looks.has(null), "ten weather looks exist")
	check(looks[0].sun_energy < 0.7 and looks[1].sun_energy < 0.7 and looks[0].sun_color.b > looks[0].sun_color.r,
			"battles 1 and 2 are lit by a dim bluish moon")
	check(looks[0].star_strength > 0.0 and looks[1].sun_brightness == 0.0, "battle 1 has stars and a moon, battle 2 a clouded moon")
	check(looks[1].snowfall > looks[0].snowfall and looks[1].fog_scale > 5.0, "battle 2: heavy snowfall, poor visibility")
	check(looks[6].fog_scale > looks[8].fog_scale and looks[8].fog_scale > looks[2].fog_scale, "fog: battle 7 dense > battle 9 moderate > battle 3 clear")
	check(looks[2].snowfall == 0.0 and is_equal_approx(looks[2].fog_scale, 1.0), "battle 3 = the old clear day")
	check(looks[9].snowfall == 0.0 and looks[9].end_look.snowfall == 0.0, "battle 10: dusk without snowfall (owner)")
	check(looks[7].end_look != null and looks[7].end_look.fog_scale < looks[7].fog_scale * 0.25 and looks[7].change_seconds < 120.0,
			"battle 8: fog at the start, clears soon")
	check(looks[9].end_look != null and looks[9].end_look.sun_energy < looks[9].sun_energy and looks[9].end_look.zenith_color.b > looks[9].end_look.zenith_color.g,
			"battle 10: dusk deepens towards violet")
	var changing: int = 0
	for l in looks:
		if l.end_look:
			changing += 1
	check(changing == 2, "only battles 8 and 10 change during the battle")
	var mid: WeatherData = looks[7].mixed(looks[7].end_look, 0.5)
	check(is_equal_approx(mid.fog_scale, (looks[7].fog_scale + looks[7].end_look.fog_scale) * 0.5) and mid.title == looks[7].title and mid.end_look == null,
			"WeatherData.mixed blends numbers and keeps the rest")

	# --- In the game ---
	MatchDirector.test_start_wave = 0
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var dusk := game.get_node("Dusk") as DuskLight
	var director := get_tree().get_first_node_in_group("match_director") as MatchDirector
	var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	spawner.set_process(false)
	var p := get_tree().get_first_node_in_group("players") as Player
	var env: Environment = (get_tree().get_first_node_in_group("world_environment") as WorldEnvironment).environment
	var sun := get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	var preset: Dictionary = Settings.preset()
	check(dusk.battle == 1 and dusk.look.title == looks[0].title, "the game starts with battle 1's look")
	check(is_equal_approx(Enemy.visibility_limit, 150.0), "battle 1: the enemy sees 150 m through the twilight")
	check(is_equal_approx(env.fog_density, preset.fog_density * looks[0].fog_scale), "fog density = quality preset × the look's fog_scale (%.4f)" % env.fog_density)
	check(p.snow_particles.amount == int(round(preset.snow_amount * looks[0].snowfall)) and p.snow_particles.emitting,
			"falling snow = preset × the look's snowfall (%d flakes)" % p.snow_particles.amount)
	check(is_equal_approx(sun.light_energy, looks[0].sun_energy) and is_equal_approx(rad_to_deg(sun.rotation.x), looks[0].sun_pitch_deg),
			"the moon is the level's light (energy %.2f)" % sun.light_energy)
	var saved_env := (load("res://levels/test_level.tscn") as PackedScene)
	check(saved_env != null and ResourceLoader.exists("res://resources/materials/winter_sky.tres"), "scene resources still load (the game works on copies)")
	# A cleared battle: the look waits for the black day screen.
	director.waves_cleared = 2
	await seconds(0.5)
	check(dusk.battle == 1, "battle 2 cleared… the look does not change while the battlefield is visible")
	dusk.wait_for_black = 0.3
	await seconds(0.8)
	check(dusk.battle == 3 and dusk.look.title == looks[2].title, "…then it changes by itself after the timeout (no day screen) – battle 3's look")
	check(p.snow_particles.emitting == false, "battle 3: no falling snow")
	check(Enemy.visibility_limit == INF, "battle 3 (clear): no limit on the enemy's sight")
	# --- Fog limits what the enemy sees (B3) ---
	var enemy: Enemy = spawner._spawn_enemy(Vector3(-30, 0, -60), Vector3(-30, 0, 20))
	p.global_position = Vector3(-30, 0.0, 40) # 100 m south of him, in the open
	await seconds(0.5)
	enemy.global_position = Vector3(-30, enemy.global_position.y, -60)
	enemy.rotation.y = PI
	await seconds(0.2)
	check(enemy._find_visible_player() == p, "clear weather: a soldier sees you at 100 m")
	Enemy.visibility_limit = 150.0
	check(enemy._find_visible_player() == p, "150 m of visibility: still sees you at 100 m")
	Enemy.visibility_limit = 80.0
	check(enemy._find_visible_player() == null, "80 m of visibility (heavy snow): does NOT see you at 100 m")
	p.global_position = Vector3(-30, 0.0, 0.0) # 60 m away
	await seconds(0.2)
	check(enemy._find_visible_player() == p, "…but sees you at 60 m")
	Enemy.visibility_limit = INF
	enemy.queue_free()
	# The tank's sight is limited the same way.
	var tank_spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	var tank: Tank = tank_spawner.spawn_tank(0)
	await seconds(0.3)
	p.global_position = tank.global_position + Vector3(0, 0.0, 90.0)
	await seconds(0.2)
	var tank_sees: bool = tank._can_see(p)
	Enemy.visibility_limit = 60.0
	check(tank_sees and not tank._can_see(p), "tank: sees you at 90 m in clear weather, not with 60 m visibility")
	Enemy.visibility_limit = INF
	tank.queue_free()
	# Fog clears during battle 8, in battle 3 nothing changes.
	director.waves_cleared = 7
	await seconds(1.0)
	check(dusk.battle == 8 and is_equal_approx(Enemy.visibility_limit, 60.0), "battle 8's look: dense fog, the enemy sees 60 m")
	var fog_start: float = env.fog_density
	spawner.wave_number = 8 # the battle has begun
	dusk.set_process(true)
	await seconds(1.0)
	check(env.fog_density <= fog_start and dusk.battle_clock > 0.5, "the battle clock runs while the battle is on")
	dusk.battle_clock = looks[7].change_seconds * 0.5
	await seconds(0.3)
	check(env.fog_density < fog_start * 0.8 and env.fog_density > preset.fog_density * 0.99, "halfway through battle 8 the fog is thinning (%.4f → %.4f)" % [fog_start, env.fog_density])
	check(Enemy.visibility_limit > 100.0 and Enemy.visibility_limit < 900.0, "halfway: the enemy's sight grows with the clearing fog (%.0f m)" % Enemy.visibility_limit)
	dusk.battle_clock = looks[7].change_seconds + 5.0
	await seconds(0.3)
	check(Enemy.visibility_limit == INF, "fog gone: no limit on the enemy's sight")
	check(is_equal_approx(env.fog_density, preset.fog_density * looks[7].end_look.fog_scale), "at the end of the change time the fog is clear (%.4f)" % env.fog_density)
	# Battle 10: dusk deepens, no snow.
	director.waves_cleared = 9
	await seconds(0.5)
	dusk.wait_for_black = 0.1
	await seconds(0.5)
	check(dusk.battle == 10 and not p.snow_particles.emitting, "battle 10: dusk, no falling snow")
	var e_start: float = sun.light_energy
	spawner.wave_number = 10
	dusk.battle_clock = looks[9].change_seconds
	await seconds(0.3)
	check(sun.light_energy < e_start - 0.3, "…the light fades during the battle (%.2f → %.2f)" % [e_start, sun.light_energy])
	# After the last battle is won the look stays.
	director.waves_cleared = 10
	await seconds(0.5)
	check(dusk.battle == 10, "victory: the dusk stays")
	# Quality changes keep the weather.
	Settings.quality = Settings.Quality.LOW
	Settings.apply()
	director.waves_cleared = 1
	dusk.wait_for_black = 0.1
	await seconds(0.5)
	await seconds(0.5)
	check(dusk.battle == 2 and p.snow_particles.amount == int(round(Settings.preset().snow_amount * looks[1].snowfall)),
			"Low quality: battle 2's snow is the preset's amount × weather (%d)" % p.snow_particles.amount)
	Settings.quality = Settings.Quality.HIGH
	Settings.apply()

	game.queue_free()
	await seconds(0.3)
	check(Enemy.visibility_limit == INF, "the limit does not outlive the match")
	print("RESULT: %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
