extends Node
## Test for the T-26 tank (T1, not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_t1.gd

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
	Settings.difficulty = 1
	check(InputMap.has_action("debug_spawn_tank") and InputMap.has_action("debug_destroy_tank"), "F9/F10 tank test keys exist")
	for f in ["engine_a", "engine_b"]:
		var s: AudioStreamOggVorbis = load("res://assets/audio/tank/%s.ogg" % f)
		check(s != null and s.loop, "%s.ogg loops" % f)

	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await seconds(0.5)
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	var waves: WaveSpawner = get_tree().get_first_node_in_group("wave_spawner")
	waves.set_process(false)
	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	check(spawner != null, "Game has a TankSpawner")
	var routes: Array[Path3D] = spawner.get_routes()
	check(routes.size() == 3, "3 tank routes in the level (got %d)" % routes.size())

	# --- Routes: from the forest edge to just in front of the trench, clear of the lone trees.
	var trees := _lone_trees(game.get_node("Level/Forest"))
	for r in routes:
		var c: Curve3D = r.curve
		var length: float = c.get_baked_length()
		var start: Vector3 = r.to_global(c.sample_baked(0.0))
		var end: Vector3 = r.to_global(c.sample_baked(length))
		check(start.z < -100.0 and end.z > 45.0 and end.z < 50.5, "%s: forest edge (z %.0f) → trench edge (z %.1f)" % [r.name, start.z, end.z])
		var closest: float = INF
		var d: float = 0.0
		while d <= length:
			var pt: Vector3 = r.to_global(c.sample_baked(d))
			for t: Vector2 in trees:
				closest = minf(closest, t.distance_to(Vector2(pt.x, pt.z)))
			d += 1.0
		check(closest > 3.5, "%s: no lone tree in the way (closest %.1f m)" % [r.name, closest])

	# --- Spawn one on the middle route. The player hides crouching in the trench (god mode).
	p.god_mode = true
	p.global_position = Vector3(10, -1.3, 61)
	p.input.crouch_held = true
	Engine.time_scale = 4.0
	var tank: Tank = spawner.spawn_tank(1)
	check(tank != null and tank.get_parent() == game.get_node("Tanks"), "spawn_tank puts a tank under Game/Tanks")
	await seconds(0.3)
	var start_pos: Vector3 = tank.global_position
	check(tank._turret_mesh != null and tank._turret_mesh.top_level, "turret part follows TurretPivot")
	await wait_for(func() -> bool: return tank.global_position.z > start_pos.z + 12.0, 20.0)
	check(tank.global_position.z > start_pos.z + 12.0, "drives towards the trench (z %.1f → %.1f)" % [start_pos.z, tank.global_position.z])
	check(tank.state == Tank.State.ADVANCE, "nobody in sight → ADVANCE (state %d)" % tank.state)
	var ground: float = terrain.get_height(tank.global_position.x, tank.global_position.z)
	check(absf(tank.global_position.y - ground) < 0.5, "sits on the ground (y %.2f, ground %.2f)" % [tank.global_position.y, ground])
	var fwd: Vector3 = -tank.global_basis.z
	check(fwd.z > 0.8, "hull points towards the trench (+z), forward %s" % str(fwd))

	# --- A player standing out in the open 40 m ahead: SUPPRESS + DT fire that hurts.
	p.god_mode = false
	p.input.crouch_held = false
	var stand: Vector3 = tank.global_position + Vector3(4, 0, 40)
	stand.y = terrain.get_height(stand.x, stand.z) + 0.1
	p.global_position = stand
	tank._next_halt = 1000.0 # no stop for the main gun yet
	var hp: int = p.health
	var ok: bool = await wait_for(func() -> bool: return tank.state == Tank.State.SUPPRESS, 6.0)
	check(ok, "player in sight → SUPPRESS")
	ok = await wait_for(func() -> bool: return tank.state == Tank.State.SUPPRESS and tank.drive_speed <= tank.suppress_speed + 0.01, 8.0)
	check(ok, "drives slower while firing (%.2f m/s)" % tank.drive_speed)
	ok = await wait_for(func() -> bool: return tank.dt_rounds_fired >= 10, 40.0) # slow turret (T4): the hull keeps turning under it
	check(ok, "DT fires at the player (%d rounds)" % tank.dt_rounds_fired)
	check(tank._aim_error_deg(tank.dt_muzzle) < 6.0, "turret turned towards the player (%.1f° off)" % tank._aim_error_deg(tank.dt_muzzle))
	ok = await wait_for(func() -> bool: return p.health < hp or p.is_dead, 10.0)
	check(ok, "DT bullets hurt the player (health %d → %d)" % [hp, p.health])
	p.god_mode = true
	p.health = p.max_health

	# --- Rifle bullets: sparks, no damage, no hit marker.
	var hits := [0]
	p.weapons.hit_confirmed.connect(func(_k: bool) -> void: hits[0] += 1)
	var aim_from: Vector3 = p.head.global_position
	var to_hull: Vector3 = tank.global_position + Vector3(0, 1.0, 0) - aim_from
	var mosin: WeaponData = p.weapons.loadout[0]
	p.weapons.resolve_shot(aim_from, to_hull.normalized(), mosin, [])
	await seconds(0.1)
	check(hits[0] == 0, "bullet on the armour gives no hit marker")
	check(tank.state != Tank.State.DESTROYED, "rifle bullets don't hurt the tank")
	check(ImpactEffects.surface_of(tank, Vector3.UP) == "metal", "tank surface = metal (sparks)")

	# --- Stop and fire the 45 mm gun. (The slow turret may have taken a while: stand 40 m ahead again.)
	p.god_mode = false
	stand = tank.global_position + Vector3(4, 0, 40)
	stand.y = terrain.get_height(stand.x, stand.z) + 0.1
	p.global_position = stand
	p.god_mode = true
	tank._next_halt = 0.0
	ok = await wait_for(func() -> bool: return tank.state == Tank.State.HALT_FIRE, 6.0)
	check(ok, "stops to fire the main gun (HALT_FIRE)")
	ok = await wait_for(func() -> bool: return tank.shells_fired > 0, 12.0)
	check(ok, "fires a 45 mm shell")
	check(tank.drive_speed < 0.06, "standing still when it fires (%.2f m/s)" % tank.drive_speed)
	ok = await wait_for(func() -> bool: return tank.state != Tank.State.HALT_FIRE, 6.0)
	check(ok and tank.state == Tank.State.SUPPRESS, "drives on after the shot (state %d)" % tank.state)

	# --- To the end of the route: stops at the trench edge for good.
	p.global_position = Vector3(10, -1.3, 61)
	p.input.crouch_held = true
	tank._distance = tank._route_length - 6.0
	ok = await wait_for(func() -> bool: return tank.state == Tank.State.AT_TRENCH, 10.0)
	check(ok, "reaches the trench edge → AT_TRENCH")
	var front: Vector3 = tank.global_position - tank.global_basis.z * 2.33
	check(front.z < 56.0, "the nose stays out of the trench (nose z %.1f)" % front.z)
	var parked: Vector3 = tank.global_position
	await seconds(2.0)
	check(tank.global_position.distance_to(parked) < 0.05, "stays parked at the edge")
	# A crouching player down in the trench can't be seen; standing up he can.
	check(not tank._can_see(p), "crouching in the trench = out of sight")
	p.input.crouch_held = false
	await seconds(0.5)
	check(tank._can_see(p), "standing up in the trench = seen")
	var shots_before: int = tank.shells_fired + tank.dt_rounds_fired
	ok = await wait_for(func() -> bool: return tank.shells_fired + tank.dt_rounds_fired > shots_before, 10.0)
	check(ok, "fires into the trench")
	# The blast of a shell: a trench wall shields you from a burst in front of it.
	var blast: Vector3 = Vector3(p.global_position.x, terrain.get_height(p.global_position.x, 50.0), 50.0)
	check(not tank._clear_line(blast + Vector3.UP * 0.3, p.global_position + Vector3.UP * 0.75), "a crouching man in the trench is shielded from a burst in front of it")

	# --- Knocked out (debug key F10 → destroy_nearest).
	check(spawner.destroy_nearest(p.global_position), "destroy_nearest finds the tank")
	await seconds(0.2)
	check(tank.state == Tank.State.DESTROYED and tank.is_in_group("tank_wrecks"), "DESTROYED, now a wreck")
	check(tank.get_node_or_null("WreckSmoke") != null, "the wreck smokes")
	var rounds: int = tank.dt_rounds_fired + tank.shells_fired
	await seconds(3.0)
	check(tank.dt_rounds_fired + tank.shells_fired == rounds, "a wreck no longer fires")
	check(tank.global_position.distance_to(parked) < 0.05, "the wreck stays on the field")
	check(not spawner.destroy_nearest(p.global_position), "nothing left to knock out")

	# --- A second tank and the end of the match (freeze) don't break anything.
	var t2: Tank = spawner.spawn_tank(0)
	await seconds(1.0)
	var director := get_tree().get_first_node_in_group("match_director") as MatchDirector
	director.end_match(MatchDirector.Result.DEFEAT)
	var frozen: Vector3 = t2.global_position
	await seconds(1.0)
	check(t2.global_position.distance_to(frozen) < 0.01, "end of the match freezes the tanks")

	Engine.time_scale = 1.0
	print("TEST T1 DONE: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## Positions of the lone trees out on the open ground (same random numbers as ForestScatter).
func _lone_trees(forest: Node) -> Array[Vector2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = forest.random_seed
	for area: Rect2 in forest.forest_areas:
		var count: int = int(area.get_area() / 100.0 * forest.trees_per_100m2)
		for i in count:
			rng.randf_range(area.position.x, area.end.x)
			rng.randf_range(area.position.y, area.end.y)
	var list: Array[Vector2] = []
	var r: Rect2 = forest.lone_tree_area
	for i in forest.lone_trees:
		list.append(Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y)))
	return list
