extends Node
## Automated enemy AI / wave test for Milestone 3 (not part of the game).

var p: Player
var waves: WaveSpawner
var fails := 0

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout

func enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for n in get_tree().get_nodes_in_group("enemies"):
		out.append(n as Enemy)
	return out

func living() -> Array[Enemy]:
	return enemies().filter(func(e: Enemy) -> bool: return e.state != Enemy.State.DEAD)

func _ready() -> void:
	await get_tree().process_frame # the root can't take new children while it is adding us
	get_tree().root.add_child(load("res://scenes/game.tscn").instantiate())
	get_tree().root.get_node("Game/PauseMenu").free() # tests drive the game directly
	run()

func run() -> void:
	await seconds(0.3)
	p = get_tree().get_nodes_in_group("players")[0]
	p.input.set_process(false)
	waves = get_tree().get_first_node_in_group("wave_spawner")
	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")

	# Navigation path from a spawn point to an attack point
	var map: RID = p.get_world_3d().navigation_map
	for i in 120: # wait until the navigation map has been built (it syncs on a physics frame)
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			break
		await get_tree().physics_frame
	await get_tree().physics_frame
	var from := Vector3(-60, terrain.get_height(-60, -118), -118)
	var to := Vector3(-12, terrain.get_height(-12, 38), 38)
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	for i in 120: # the level's navigation region may join the map a few frames later
		if path.size() > 1:
			break
		await get_tree().physics_frame
		path = NavigationServer3D.map_get_path(map, from, to, true)
	check(path.size() > 1 and path[path.size() - 1].distance_to(to) < 1.5, "navigation path spawn -> attack point (%d points)" % path.size())
	var into_trench := NavigationServer3D.map_get_closest_point(map, Vector3(-30, -1.4, 61))
	print("  closest navmesh point to trench floor: ", into_trench)

	# --- Wave 1 spawns ---
	p.god_mode = true
	await seconds(5.5)
	check(waves.wave_number == 1, "wave 1 started")
	await seconds(12.0)
	check(waves.alive_count == 6 and living().size() == 6, "wave 1 has 6 soldiers (alive %d)" % waves.alive_count)
	var e0: Enemy = living()[0]
	check(e0.global_position.z < -80, "spawned at the southern forest edge (z=%.0f)" % e0.global_position.z)

	# They advance
	Engine.time_scale = 4.0
	var z_before := e0.global_position.z
	await seconds(4.0)
	print("  enemy 0 state %s, z %.1f -> %.1f" % [Enemy.State.keys()[e0.state], z_before, e0.global_position.z])
	check(e0.global_position.z > z_before + 4.0, "soldiers advance towards the trench")

	# Hearing: a shot alerts patrolling soldiers within earshot
	for e in living():
		e.state = Enemy.State.PATROL
	var near: Enemy = living()[0]
	p.global_position = near.global_position + Vector3(30, 0.5, 0)
	await seconds(0.5)
	get_tree().call_group("enemies", "hear_noise", p.global_position, p.global_position, 150.0)
	await get_tree().physics_frame
	check(near.state == Enemy.State.ALERT or near.state == Enemy.State.ATTACK, "shot alerts nearby soldier (%s)" % Enemy.State.keys()[near.state])

	# Line of sight: standing in the trench visible, crouching hidden
	Engine.time_scale = 1.0
	for e in living():
		e.set_physics_process(false)
	var watcher: Enemy = living()[1]
	watcher.global_position = Vector3(-30, terrain.get_height(-30, 20), 20)
	watcher.rotation.y = PI
	p.global_position = Vector3(-30, -1.4, 61)
	p.velocity = Vector3.ZERO
	p.input.crouch_held = false
	await seconds(1.0)
	check(watcher._find_visible_player() == p, "standing player in trench is visible from 40 m")
	p.input.crouch_held = true
	await seconds(1.0)
	check(watcher._find_visible_player() == null, "crouching player in trench is hidden by the parapet")
	watcher.rotation.y = 0.0
	p.input.crouch_held = false
	await seconds(1.0)
	check(watcher._find_visible_player() == null, "player behind the soldier's back is not seen")
	watcher.rotation.y = PI
	for e in living():
		e.set_physics_process(true)

	# Attack: soldier notices, kneels and fires; god mode protects, then health drops
	watcher.state = Enemy.State.PATROL
	watcher.attack_point = watcher.global_position
	await seconds(4.0)
	check(watcher.state == Enemy.State.ATTACK, "soldier switches to ATTACK (%s)" % Enemy.State.keys()[watcher.state])
	check(watcher.is_kneeling, "soldier kneels to fire")
	check(p.health == 100, "god mode: no damage")
	p.god_mode = false
	var t0 := Time.get_ticks_msec()
	while p.health == 100 and Time.get_ticks_msec() - t0 < 60000:
		await seconds(0.5)
	check(p.health < 100, "enemy fire damages the player (health %d after %.0f s)" % [p.health, (Time.get_ticks_msec() - t0) / 1000.0])
	p.god_mode = true

	# Player's shot kills; dead soldier stops colliding; alive count drops
	var victim: Enemy = living()[0]
	var count_before: int = waves.alive_count
	victim.take_damage(150.0, 1, victim.global_position, Vector3.UP)
	await seconds(0.2)
	check(victim.state == Enemy.State.DEAD and victim.collision.disabled, "killed soldier is DEAD and stops colliding")
	check(waves.alive_count == count_before - 1, "alive count goes down")

	# Clear the wave -> next wave starts after the break
	waves.time_between_waves = 2.0
	for e in living():
		e.take_damage(500.0, 1, e.global_position, Vector3.UP)
	await seconds(0.5)
	check(waves.alive_count == 0, "wave 1 cleared")
	await seconds(2.5)
	check(waves.wave_number == 2, "wave 2 started")
	Engine.time_scale = 3.0
	await seconds(15.0)
	Engine.time_scale = 1.0
	check(waves.alive_count == 8, "wave 2 has 8 soldiers (alive %d)" % waves.alive_count)

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
