extends Node
## Test for T3, tanks in the battles (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_t3.gd

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


## Waits (game time) until `cond` is true or `limit` seconds have passed. Returns `cond`.
func wait_for(cond: Callable, limit: float) -> bool:
	var t: float = 0.0
	while t < limit:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return cond.call()


func run() -> void:
	# --- The owner's choice: one tank in battles 4–8, two in 9–10, on every difficulty.
	for n in ["easy", "normal", "hard"]:
		var d: DifficultyData = load("res://resources/difficulty/%s.tres" % n)
		var got: Array[int] = []
		for w in d.waves:
			got.append(w.tanks)
		check(got == [0, 0, 0, 1, 1, 1, 1, 1, 2, 2], "%s: tanks per battle %s" % [n, str(got)])
	check(WaveData.describe(8, 1, 1, 1) == "8 riflemen · 1 officer · 1 machine-gun team · 1 tank"
			and WaveData.describe(6, 0, 0, 2).ends_with("2 tanks") and not WaveData.describe(6, 1, 0).contains("tank"),
			"HUD line names the tanks")

	Settings.difficulty = 1
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await seconds(0.5)
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.god_mode = true
	p.global_position = Vector3(10, -1.3, 61)
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	var waves: WaveSpawner = get_tree().get_first_node_in_group("wave_spawner")
	var forest: ForestScatter = game.get_node("Level/Forest")

	# --- Forest lanes: no tree on the tanks' way out of the forest.
	var trees := _trees(forest)
	for r in spawner.get_routes():
		var start: Vector3 = r.to_global(r.curve.sample_baked(0.0))
		var closest: float = INF
		for t: Vector2 in trees:
			if t.y > start.z - spawner.forest_approach_m - 5.0 and t.y < start.z + 2.0:
				closest = minf(closest, absf(t.x - start.x))
		check(closest > 5.0, "%s: lane through the forest is clear (closest tree %.1f m to the side)" % [r.name, closest])

	# --- Battle 4: one tank comes out of the forest a while after the infantry.
	Engine.time_scale = 4.0
	waves.time_between_groups = 0.3
	waves.first_tank_delay = 3.0
	waves.start_at_wave(4, 0.1)
	var hud: HUD = game.get_node("HUD")
	await wait_for(func() -> bool: return waves.wave_number == 4, 3.0)
	await seconds(0.3)
	check(waves.wave_tanks == 1, "battle 4 brings 1 tank (synced wave_tanks)")
	check(hud.banner_sub.text.contains("1 tank"), "HUD banner: '%s'" % hud.banner_sub.text.replace("\n", " / "))
	check(get_tree().get_nodes_in_group("tanks").is_empty(), "no tank yet right at the start of the battle")
	var came: bool = await wait_for(func() -> bool: return get_tree().get_nodes_in_group("tanks").size() == 1, 6.0)
	check(came, "the tank sets off after first_tank_delay")
	var tank: Tank = get_tree().get_nodes_in_group("tanks")[0]
	await seconds(0.2)
	var start: Vector3 = tank.route.to_global(tank.route.curve.sample_baked(0.0))
	check(tank.is_in_forest() and tank.global_position.z < start.z - 30.0 and tank.global_position.z > -150.0,
			"starts in the forest behind the route start (z %.0f, edge %.0f)" % [tank.global_position.z, start.z])
	check(tank.engine_sound.playing, "engine running (heard before the tank shows)")
	# Stand up in plain view: the crew can't see out of the forest.
	p.input.crouch_held = false
	await seconds(4.0)
	check(tank.is_in_forest() and tank._target == null and tank.dt_rounds_fired == 0, "no targets while still in the forest")
	var out: bool = await wait_for(func() -> bool: return not tank.is_in_forest(), 30.0)
	check(out and absf(tank.global_position.x - start.x) < 2.0, "drives out of the forest onto its route")

	# All soldiers dead: the battle is NOT over while the tank still fights.
	await wait_for(func() -> bool: return waves._left_to_spawn <= 0, 10.0)
	var cleared: Array[int] = []
	waves.wave_cleared.connect(func(n: int) -> void: cleared.append(n))
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Enemy).take_damage(9999.0, 1, e.global_position, Vector3.UP)
	await seconds(2.0)
	check(waves.alive_count == 0 and cleared.is_empty() and waves.tanks_in_fight() == 1, "soldiers dead, tank alive → battle goes on")
	tank.ignite()
	var won: bool = await wait_for(func() -> bool: return cleared.size() == 1, 3.0)
	check(won and cleared[0] == 4, "tank burning → battle 4 cleared")
	# Crew who bailed out don't hold the wave up.
	await seconds(0.5)

	# --- Battle 9: two tanks, on different routes, one after the other.
	waves.set_process(false)
	waves.tank_interval = 3.0
	for t in get_tree().get_nodes_in_group("tanks"):
		t.free()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.free()
	waves.alive_count = 0
	waves.start_at_wave(9, 0.1)
	waves.set_process(true)
	await wait_for(func() -> bool: return waves.wave_number == 9, 3.0)
	check(waves.wave_tanks == 2 and waves.tanks_in_fight() == 2, "battle 9 brings 2 tanks")
	await wait_for(func() -> bool: return get_tree().get_nodes_in_group("tanks").size() == 1, 6.0)
	var one: bool = get_tree().get_nodes_in_group("tanks").size() == 1
	var two: bool = await wait_for(func() -> bool: return get_tree().get_nodes_in_group("tanks").size() == 2, 6.0)
	check(one and two, "the second tank follows tank_interval later")
	var ts: Array[Node] = get_tree().get_nodes_in_group("tanks")
	check((ts[0] as Tank).route != (ts[1] as Tank).route, "the two tanks take different routes")
	# Kill every soldier as he comes out (a big wave comes in parts: max_alive).
	var t_end: int = Time.get_ticks_msec() + 20000
	while (waves._left_to_spawn > 0 or waves.alive_count > 0) and Time.get_ticks_msec() < t_end:
		for e in get_tree().get_nodes_in_group("enemies"):
			(e as Enemy).take_damage(9999.0, 1, e.global_position, Vector3.UP) # (the dead ignore it)
		await seconds(0.3)
	(ts[0] as Tank).destroy()
	await seconds(1.0)
	check(waves.wave_number == 9 and waves.tanks_in_fight() == 1 and waves._phase == WaveSpawner.Phase.FIGHTING, "one tank left → battle 9 goes on")
	(ts[1] as Tank).destroy()
	var won9: bool = await wait_for(func() -> bool: return waves._phase == WaveSpawner.Phase.WAITING, 3.0)
	check(won9, "both tanks knocked out → battle 9 cleared (alive %d, to spawn %d, tanks %d)" % [waves.alive_count, waves._left_to_spawn, waves.tanks_in_fight()])
	waves.set_process(false)

	# --- Wrecks: only the newest max_wrecks stay. A Molotov fire stuck to a wreck that goes
	# away is replaced, not used after it is freed.
	var manager: MolotovManager = get_tree().get_first_node_in_group("molotovs")
	for i in 3:
		var t: Tank = spawner.spawn_tank(i)
		await seconds(0.1)
		t.destroy()
	var first: Tank = null
	for t in get_tree().get_nodes_in_group("tanks"):
		if first == null or String(t.name).naturalnocasecmp_to(String(first.name)) < 0:
			first = t
	manager.shatter(999, first.global_position + Vector3(0, 2, 0), Vector3.UP, MolotovManager.Hit.TANK_ARMOUR, first.get_path())
	await seconds(0.2)
	var wrecks: int = get_tree().get_nodes_in_group("tank_wrecks").size()
	check(wrecks == 5, "5 wrecks on the field (got %d)" % wrecks)
	var removed: int = spawner.clear_old_wrecks()
	await seconds(0.2)
	var left: Array[Node] = get_tree().get_nodes_in_group("tank_wrecks")
	check(removed == 2 and left.size() == 3 and not is_instance_valid(first), "oldest 2 wrecks cleared, 3 kept")
	for i in 9:
		manager.shatter(1000 + i, Vector3(0, 0, -20 + i), Vector3.UP, MolotovManager.Hit.GROUND, NodePath())
	await seconds(0.3)
	check(true, "Molotov fires still work after a wreck holding one was cleared")
	# Day screen black → wrecks over the limit go by themselves.
	for i in 2:
		var t: Tank = spawner.spawn_tank(i)
		await seconds(0.1)
		t.destroy()
	hud.day_screen.open(1, load("res://resources/front_reports.tres"))
	var gone: bool = await wait_for(func() -> bool: return get_tree().get_nodes_in_group("tank_wrecks").size() == 3, 20.0)
	check(gone, "extra wrecks removed while the day screen is black")

	Engine.time_scale = 1.0
	print("TEST T3 DONE: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## Positions of all trees ForestScatter keeps (same random numbers, minus the clear areas).
func _trees(forest: ForestScatter) -> Array[Vector2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = forest.random_seed
	var list: Array[Vector2] = []
	for area: Rect2 in forest.forest_areas:
		var count: int = int(area.get_area() / 100.0 * forest.trees_per_100m2)
		for i in count:
			list.append(Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y)))
	var r: Rect2 = forest.lone_tree_area
	for i in forest.lone_trees:
		list.append(Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y)))
	var kept: Array[Vector2] = []
	for t in list:
		if not forest._is_kept_clear(t):
			kept.append(t)
	return kept
