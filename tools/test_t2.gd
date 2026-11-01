extends Node
## Test for the Molotov cocktail (T2, not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_t2.gd

var fails := 0
var p: Player
var m: MolotovHandler
var manager: MolotovManager
var terrain: TerrainGenerator


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func wait_for(cond: Callable, limit: float) -> bool:
	var t: float = 0.0
	while t < limit:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return cond.call()


func _ready() -> void:
	await get_tree().process_frame
	run()


## Light the bottle in the hand: right mouse held until it burns.
func light_it() -> bool:
	p.input.aim_held = true
	var ok: bool = await wait_for(func() -> bool: return m.phase == MolotovHandler.Phase.LIT, 3.0)
	return ok


func ground_at(x: float, z: float) -> Vector3:
	return Vector3(x, terrain.get_height(x, z), z)


func run() -> void:
	Settings.difficulty = 1
	check(InputMap.has_action("molotov"), "G = molotov action exists")
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await seconds(0.5)
	p = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	m = p.molotov
	manager = get_tree().get_first_node_in_group("molotovs")
	terrain = get_tree().get_first_node_in_group("terrain")
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	check(m != null and manager != null, "Player/Molotov and Game/Molotovs exist")
	var map: RID = p.get_world_3d().navigation_map
	for i in 120:
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			break
		await get_tree().physics_frame

	# --- The boxes in the trench.
	var crates := get_tree().get_nodes_in_group("molotov_crates")
	check(crates.size() == 2, "2 boxes of Molotov cocktails in the trench")
	for c: Node3D in crates:
		check(absf(c.global_position.y + 1.4) < 0.05 and c.global_position.z > 56.0 and c.global_position.z < 66.0, "%s on the trench floor %s" % [c.name, str(c.global_position)])
	var crate: MolotovCrate = crates[0]
	check(m.count == 0, "no bottles at the start")
	p.input.request_molotov()
	await seconds(0.2)
	check(m.phase == MolotovHandler.Phase.NONE, "G without bottles does nothing")
	p.global_position = crate.global_position + crate.global_basis.z * 0.7 + Vector3(0, 0.1, 0)
	await seconds(0.2)
	check(p.find_molotov_crate() == crate, "the box is within reach")
	p.input.request_interact()
	await seconds(0.2)
	check(m.count == m.max_carry, "F at the box: %d bottles" % m.count)

	# --- G: bottle in the hand.
	p.input.request_molotov()
	await seconds(0.3)
	check(m.phase == MolotovHandler.Phase.HELD, "G: a bottle in the hand")
	check(not p.weapons.holder.visible, "the gun is put away")
	check(p.weapons.get_hand_grips().size() == 2, "both hands on the bottle / match")
	p.input.request_throw()
	await seconds(0.2)
	check(m.phase == MolotovHandler.Phase.HELD and m.thrown == 0, "left mouse with an unlit bottle: nothing")
	# Right mouse let go too early: the match goes out.
	p.input.aim_held = true
	await seconds(0.4)
	check(m.phase == MolotovHandler.Phase.IGNITING, "right mouse: lighting the rag")
	p.input.aim_held = false
	await seconds(0.2)
	check(m.phase == MolotovHandler.Phase.HELD, "let go early: not lit")
	check(await light_it(), "right mouse held ~1 s: LIT")
	check(not p.weapons.is_aiming, "right mouse aims the bottle, not the gun")
	p.input.request_switch(0)
	await seconds(0.2)
	check(m.phase == MolotovHandler.Phase.LIT, "a lit bottle can't be put away")

	# --- Throw it out over the parapet onto the snow in front of the trench (aimed).
	p.global_position = Vector3(-30, 0.05, 50) # standing on the ground in front of the trench
	p.input.look_yaw = 0.0
	p.input.look_pitch = deg_to_rad(10.0)
	await seconds(0.3)
	var before: int = manager.shatter_count
	p.input.request_throw()
	var ok: bool = await wait_for(func() -> bool: return manager.shatter_count > before, 4.0)
	check(ok, "the bottle flies and breaks")
	check(m.count == 1 and m.thrown == 1, "one bottle less (%d left)" % m.count)
	var fire_at: Vector3 = Vector3.ZERO
	for f in manager._fires:
		fire_at = f.pos
	var dist: float = Vector2(fire_at.x + 30.0, fire_at.z - 50.0).length()
	check(dist > 12.0 and dist < 32.0, "aimed throw lands %.1f m away" % dist)
	check(manager.is_burning_at(fire_at), "the fuel burns where it broke")
	ok = await wait_for(func() -> bool: return m.phase == MolotovHandler.Phase.HELD, 2.0)
	check(ok, "the next bottle comes up (and isn't lit while right mouse is still held)")
	p.input.aim_held = false
	await seconds(0.1)
	# A Soviet soldier standing in the fire burns.
	var r: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
	r.name = "Burner"
	r.position = fire_at + Vector3(0.3, 0.1, 0)
	r.attack_point = fire_at
	game.get_node("Enemies").add_child(r, true)
	await seconds(0.1)
	r.state = Enemy.State.IDLE
	var hp: float = r.health
	await seconds(1.2)
	check(r.health < hp or r.state == Enemy.State.DEAD, "a soldier in the fire is burnt (%.0f → %.0f)" % [hp, r.health])
	r.queue_free()

	# --- Held too long: it burns your hand and slips (forced) at your feet.
	p.global_position = Vector3(10, 0.05, 40)
	await seconds(0.2)
	Engine.time_scale = 4.0
	check(await light_it(), "second bottle lit")
	var health_before: int = p.health
	await seconds(m.warn_time + 0.5)
	check(m.phase == MolotovHandler.Phase.LIT and p.health == health_before, "5–8 s: only a warning, no harm yet (lit %.1f s, health %d → %d)" % [m.get_lit_time(), health_before, p.health])
	m.drop_chance = 0.0
	m.drop_chance_growth = 0.0
	await seconds(m.danger_time - m.warn_time + 1.5)
	check(p.health < health_before, "over 8 s: it burns your hand (%d → %d)" % [health_before, p.health])
	m.drop_chance = 1.0
	ok = await wait_for(func() -> bool: return m.phase == MolotovHandler.Phase.NONE, 3.0)
	check(ok and m.count == 0, "it slips: the bottle is gone, gun back in the hand")
	check(manager.is_burning_at(p.global_position), "the fuel burns at your feet")
	p.global_position = Vector3(10, -1.3, 61)
	p.health = p.max_health
	p.input.aim_held = false
	m.drop_chance = 0.08
	m.drop_chance_growth = 0.06
	await seconds(1.0)

	# --- Tanks. Bottles thrown straight at a parked tank by the host.
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	p.god_mode = true
	var tank: Tank = spawner.spawn_tank(1)
	await seconds(0.3)
	tank._distance = tank._route_length - 0.5
	await wait_for(func() -> bool: return tank.state == Tank.State.AT_TRENCH, 5.0)
	# Front plate (not the engine): blinded for a moment, still running.
	var front: Vector3 = tank.global_transform * Vector3(0, 1.2, -2.2)
	var from_front: Vector3 = tank.global_transform * Vector3(0, 1.6, -6.0)
	manager.throw(from_front, (front - from_front).normalized() * 12.0, null)
	ok = await wait_for(func() -> bool: return tank.is_blinded(), 2.0)
	check(ok and tank.state == Tank.State.AT_TRENCH, "bottle on the front armour: crew blinded, tank not on fire")
	var rounds: int = tank.dt_rounds_fired
	await seconds(1.0)
	check(tank.dt_rounds_fired == rounds, "blinded: the DT is silent")
	# Engine deck: dropped from above onto the louvres.
	var deck: Vector3 = tank.global_transform * tank.engine_deck.get_center()
	manager.throw(deck + Vector3(0, 3.0, 0), Vector3(0, -6.0, 0), null)
	ok = await wait_for(func() -> bool: return tank.state == Tank.State.BURNING, 2.0)
	check(ok, "bottle on the engine deck: the tank BURNS")
	check(tank.get_node_or_null("EngineFire") != null, "engine fire (flames, smoke, light)")
	var parked: Vector3 = tank.global_position
	rounds = tank.dt_rounds_fired + tank.shells_fired
	ok = await wait_for(func() -> bool: return tank.crew_bailed >= 3, 8.0)
	check(ok, "3 crewmen bail out (%d)" % tank.crew_bailed)
	await seconds(1.0)
	var crew: Array[Enemy] = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Node).name.begins_with(tank.name + "Crew"):
			crew.append(e)
	check(crew.size() == 3, "the crew are soldiers on the field (%d)" % crew.size())
	var z0: float = crew[0].global_position.z if crew.size() > 0 else 0.0
	check(crew.size() > 0 and crew[0].is_panicking(), "the crew panic")
	await seconds(3.0)
	check(crew.size() > 0 and crew[0].global_position.z < z0 - 3.0, "they run back towards the forest (z %.1f → %.1f)" % [z0, crew[0].global_position.z if crew.size() > 0 else 0.0])
	check(tank.dt_rounds_fired + tank.shells_fired == rounds, "a burning tank doesn't fire")
	check(tank.global_position.distance_to(parked) < 0.05, "a burning tank doesn't move")
	ok = await wait_for(func() -> bool: return tank.state == Tank.State.DESTROYED, tank.burn_time + 2.0)
	check(ok, "it burns out → DESTROYED (wreck)")
	check(tank.get_node_or_null("EngineFire") == null and tank.get_node_or_null("WreckSmoke") != null, "fire out, the wreck smokes")
	check(manager.shatter_count >= 4, "bottles counted")

	# --- Death with a lit bottle: it falls where he fell. Respawn: no bottles.
	Engine.time_scale = 1.0
	p.god_mode = false
	p.global_position = Vector3(-20, 0.05, 30)
	m.count = 2
	p.input.request_molotov()
	await seconds(0.2)
	check(await light_it(), "lit again")
	var drops: int = manager.shatter_count
	p.take_damage(500.0, -1, p.global_position, Vector3.UP)
	ok = await wait_for(func() -> bool: return manager.shatter_count > drops, 1.0)
	check(ok and m.phase == MolotovHandler.Phase.NONE, "killed holding it: it falls and burns")
	p.input.aim_held = false
	p.respawn(Transform3D(Basis(), Vector3(10, -1.3, 61)))
	await seconds(0.2)
	check(m.count == 0, "after respawn: fetch new bottles")

	print("TEST T2 DONE: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)
