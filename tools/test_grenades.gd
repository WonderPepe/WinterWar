extends Node
## Test for GR1 "Soviet hand grenades" (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_grenades.gd
## The F-1 model, the throw maths, the bounce/rest flight, the blast and what protects you
## (trench wall, bunker, tank wreck), friendly fire, the limits (2 live, 4 s gap), who carries
## how many, when a soldier throws and when not, the bunker throws, a dropped grenade, the HUD icon.

var fails := 0
var game: Node
var manager: GrenadeManager
var terrain: TerrainGenerator
var space: PhysicsDirectSpaceState3D


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _ready() -> void:
	await get_tree().process_frame
	run()


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## The highest solid surface under (x, z) (ground, trench floor, bunker floor…).
func floor_at(x: float, z: float, from_y: float = 5.0) -> float:
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -10, z), 1))
	return (hit.position as Vector3).y if not hit.is_empty() else -99.0


func reset_manager() -> void:
	manager._reserved = 0
	manager._next_allowed = 0.0


## A grenade put down at `pos` (a short drop) that goes off after `fuse` s; waits for the burst.
func blast_at(pos: Vector3, fuse: float = 0.3) -> void:
	reset_manager()
	var before: int = manager.exploded_count
	manager.throw(pos + Vector3.UP * 0.05, Vector3.ZERO, -1, false, fuse)
	var t := 0.0
	while manager.exploded_count == before and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0


func new_soldier(scene: String, at: Vector3, nm: String) -> Enemy:
	var e: Enemy = load(scene).instantiate()
	e.name = nm
	e.position = at
	e.attack_point = at
	game.get_node("Enemies").add_child(e, true)
	return e


func run() -> void:
	Settings.difficulty = 1
	# --- The model.
	var g: Node3D = GrenadeManager.make_grenade(true)
	add_child(g)
	var box := AABB()
	var first := true
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	check(g.find_child("Body", true, false) != null and g.find_child("Lever", true, false) != null, "F-1 in the hand: body + lever")
	check(absf(box.size.y - 0.112) < 0.01 and absf(box.size.x - 0.055) < 0.006, "F-1 is ~55 mm across and ~112 mm tall (got %s)" % box.size)
	var tris := 0
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for si in m.get_surface_count():
			tris += (m.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	check(tris > 0 and tris < 2500, "F-1 model is light: %d triangles" % tris)
	g.free()
	var thrown: Node3D = GrenadeManager.make_grenade(false)
	check(thrown.find_child("Lever", true, false) == null, "a thrown grenade has lost its lever")
	thrown.free()

	# --- Who carries how many.
	var counts := {}
	for i in 40:
		var r: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
		r.data = r.data # (same resource)
		add_child(r)
		counts[r.grenades] = true
		r.free()
	check(counts.keys().all(func(k: int) -> bool: return k >= 1 and k <= 2) and counts.size() == 2, "riflemen carry 1 or 2 grenades (seen %s)" % [counts.keys()])
	var off: Enemy = load("res://scenes/enemies/soviet_officer.tscn").instantiate()
	add_child(off)
	check(off.grenades >= 1 and off.grenades <= 2, "an officer carries 1–2 grenades (%d)" % off.grenades)
	off.free()
	var mg: Enemy = load("res://scenes/enemies/soviet_mg_gunner.tscn").instantiate()
	add_child(mg)
	check(mg.grenades == 0, "the DP-27 gunner carries none")
	mg.free()
	var sync_cfg: SceneReplicationConfig = (load("res://scenes/enemies/soviet_rifleman.tscn").instantiate().get_node("StateSync") as MultiplayerSynchronizer).replication_config
	check(sync_cfg.has_property(NodePath(".:is_throwing")), "is_throwing is synced (StateSync)")

	# --- The game.
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await get_tree().create_timer(0.5).timeout
	manager = get_tree().get_first_node_in_group("grenades") as GrenadeManager
	check(manager != null, "Game/Grenades (GrenadeManager) is there")
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.set_physics_process(false) # he stands where the test puts him
	(get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner).set_process(false)
	terrain = get_tree().get_first_node_in_group("terrain")
	space = p.get_world_3d().direct_space_state
	await frames(5)

	# --- Throw maths: a lob lands where it was aimed (open ground).
	for d in [10.0, 20.0, 28.0]:
		var origin := Vector3(-20.0, terrain.get_height(-20.0, 0.0) + 1.9, 0.0)
		var target := Vector3(-20.0, terrain.get_height(-20.0, d), d)
		var v: Vector3 = manager.solve_throw(origin, target, 40.0)
		var flight: Dictionary = manager.simulate(origin, v, 4.0)
		var path: PackedVector3Array = flight.path
		var landing: Vector3 = GrenadeManager._path_point(path, flight.first_hit)
		check(flight.first_hit > 0.0 and Vector2(landing.x - target.x, landing.z - target.z).length() < 0.8,
				"a %d m lob lands at its aim point (%.2f m off, speed %.1f m/s)" % [d, Vector2(landing.x - target.x, landing.z - target.z).length(), v.length()])
		var rest: Vector3 = flight.rest
		check(rest.distance_to(landing) < 3.0 and absf(rest.y - terrain.get_height(rest.x, rest.z)) < 0.15,
				"…bounces a little on the snow and lies still (%.2f m further)" % rest.distance_to(landing))
	var fast: Vector3 = manager.solve_throw(Vector3(0, 2, 0), Vector3(0, 0, 80), 40.0)
	check(fast.length() <= manager.max_throw_speed + 0.01, "nobody throws faster than %d m/s" % manager.max_throw_speed)

	# --- Limits: 2 live, 4 s apart.
	reset_manager()
	check(manager.reserve(), "first throw allowed")
	check(not manager.reserve(), "a second one right after: no (4 s gap)")
	manager._next_allowed = 0.0
	check(manager.reserve(), "after the gap: allowed")
	manager._next_allowed = 0.0
	check(not manager.reserve(), "a third live grenade: no (max 2)")
	manager.cancel_reservation()
	manager.cancel_reservation()
	check(manager._reserved == 0, "places given back")

	# --- The blast and what protects you. Trench at x = -31 (straight leg, centre z = 61).
	var tx := -31.0
	var floor_y: float = floor_at(tx, 61.0)
	check(floor_y < -1.0, "trench floor found at x = %d (y %.2f)" % [tx, floor_y])
	p.global_position = Vector3(tx, floor_y, 61.0)
	p.is_crouching = false
	p.god_mode = false
	p.health = 100000
	await frames(2)
	var hp: int = p.health
	await blast_at(Vector3(tx + 1.0, floor_y, 61.0))
	check(hp - p.health >= 300, "grenade INSIDE the trench, 1 m away: deadly (%d damage)" % (hp - p.health))
	hp = p.health
	await blast_at(Vector3(tx + 5.0, floor_y, 61.0))
	check(hp - p.health > 20 and hp - p.health < 300, "inside the trench, 5 m along it: badly hurt (%d)" % (hp - p.health))
	# Outside on the parapet, in front of the trench.
	var front_z: float = 61.0
	while front_z > 50.0 and floor_at(tx, front_z) < -0.5:
		front_z -= 0.1
	var out_pos := Vector3(tx, floor_at(tx, front_z - 1.5), front_z - 1.5)
	check(out_pos.y > -0.6, "parapet found in front of the trench (z %.1f)" % out_pos.z)
	p.is_crouching = true
	await frames(2)
	hp = p.health
	await blast_at(out_pos)
	check(hp == p.health, "grenade OUTSIDE on the parapet, Finn crouching in the trench: no damage")
	p.global_position = Vector3(tx, floor_y, front_z + 0.6) # right up against the front wall
	p.is_crouching = false
	await frames(2)
	hp = p.health
	await blast_at(out_pos)
	check(hp > p.health, "…standing up at the wall, head over the edge: hurt (%d)" % (hp - p.health))
	p.is_crouching = false

	# The bunker (room x ±2.5, z 57.25–61.75).
	var bunker_floor: float = floor_at(-1.0, 59.5, 0.5)
	p.global_position = Vector3(-1.0, bunker_floor, 59.5)
	await frames(2)
	check(ArtilleryBarrage.is_in_bunker(p), "player is in the bunker room (floor y %.2f)" % bunker_floor)
	hp = p.health
	await blast_at(Vector3(0.8, bunker_floor, 60.3))
	check(hp - p.health > 50, "grenade INSIDE the bunker: everyone in the room is hurt (%d)" % (hp - p.health))
	hp = p.health
	await blast_at(Vector3(-2.0, floor_at(-2.0, 55.5), 55.5))
	check(hp == p.health, "grenade outside the bunker's front wall (beside the firing hole): nobody inside is hurt")

	# A tank wreck between the burst and the player (open ground).
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	var tank: Tank = spawner.spawn_tank(1)
	tank.set_physics_process(false)
	await frames(2)
	tank.destroy()
	var ox := 60.0
	tank.global_position = Vector3(ox, terrain.get_height(ox, 20.0), 20.0)
	tank.rotation = Vector3(0, PI / 2.0, 0)
	p.global_position = Vector3(ox, terrain.get_height(ox, 22.6), 22.6)
	await frames(3)
	hp = p.health
	await blast_at(Vector3(ox, terrain.get_height(ox, 17.4), 17.4))
	check(hp == p.health, "a tank wreck between: it protects (%d damage)" % (hp - p.health))
	p.global_position = Vector3(ox + 6.0, terrain.get_height(ox + 6.0, 20.0), 20.0)
	await frames(2)
	hp = p.health
	await blast_at(Vector3(ox + 6.0, terrain.get_height(ox + 6.0, 17.4), 17.4))
	check(hp > p.health, "the same distance in the open: hurt (%d)" % (hp - p.health))
	tank.queue_free()

	# Friendly fire: a Soviet next to a burst.
	var sx := -60.0
	var victim: Enemy = new_soldier("res://scenes/enemies/soviet_rifleman.tscn", Vector3(sx, terrain.get_height(sx, 10.0) + 0.05, 10.0), "GrenadeVictim")
	victim.set_physics_process(false)
	var near_one: Enemy = new_soldier("res://scenes/enemies/soviet_rifleman.tscn", Vector3(sx + 8.0, terrain.get_height(sx + 8.0, 10.0) + 0.05, 10.0), "GrenadeNear")
	near_one.set_physics_process(false)
	await frames(3)
	await blast_at(Vector3(sx + 1.2, terrain.get_height(sx + 1.2, 10.0), 10.0))
	check(victim.state == Enemy.State.DEAD, "friendly fire: a Soviet soldier 1.2 m from the burst is killed")
	check(near_one.suppression > 0.0, "…one 7 m away ducks (suppression %.2f)" % near_one.suppression)

	# --- When a soldier throws. The player stands in the trench at x = -31.
	p.global_position = Vector3(tx, floor_y, 61.0)
	p.is_crouching = false
	p.health = 100000
	p.god_mode = true # the throws below may land near him
	var data: EnemyData = (load("res://resources/enemies/soviet_rifleman.tres") as EnemyData).duplicate()
	data.grenade_chance_per_s = 1000.0 # (always, when allowed – the rules are what is tested)
	var at := Vector3(tx, terrain.get_height(tx, 42.0) + 0.05, 42.0)
	var e: Enemy = new_soldier("res://scenes/enemies/soviet_rifleman.tscn", at, "Thrower")
	e.data = data
	e.set_physics_process(false)
	await frames(3)
	e.state = Enemy.State.ATTACK
	e._target = p
	e._seen_target_at = e._now()
	e.grenades = 2
	reset_manager()
	e._consider_grenade(0.2)
	check(e.is_throwing, "a soldier 19 m from a Finn he just saw starts a throw")
	check(e._throw_target.distance_to(p.global_position) <= data.grenade_aim_error_max_m * 1.01 + 0.05,
			"…aimed at most %.1f m from him (%.2f)" % [data.grenade_aim_error_max_m, e._throw_target.distance_to(p.global_position)])
	var thrown_before: int = manager.thrown_count
	e.set_physics_process(true)
	var t := 0.0
	while e.is_throwing and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	check(manager.thrown_count == thrown_before + 1 and e.grenades == 1 and e.grenades_thrown == 1, "…the grenade leaves his hand (he has 1 left)")
	check(t > data.grenade_windup * 0.8 and t < data.grenade_windup + 0.3, "…the throw takes ~%.1f s (%.2f)" % [data.grenade_windup, t])
	var gid: int = manager._next_id
	var landed: Vector3 = Vector3.INF
	t = 0.0
	while manager.position_of(gid) != Vector3.INF and t < 6.0:
		landed = manager.position_of(gid)
		await get_tree().physics_frame
		t += 1.0 / 60.0
	check(landed != Vector3.INF and Vector2(landed.x - tx, landed.z - 61.0).length() < 5.0, "…and it lands near the Finn (%.1f m away)" % Vector2(landed.x - tx, landed.z - 61.0).length())
	e.set_physics_process(false)

	# Not when: too close / a comrade near the aim point / no Finn seen lately / pinned / none left.
	reset_manager()
	e.is_throwing = false
	e.grenades = 2
	e._seen_target_at = e._now()
	var buddy: Enemy = new_soldier("res://scenes/enemies/soviet_rifleman.tscn", Vector3(tx + 2.0, floor_y + 0.05, 61.0), "Buddy")
	buddy.set_physics_process(false)
	await frames(2)
	for i in 20:
		e._consider_grenade(0.2)
	check(not e.is_throwing, "no throw with a comrade near the aim point")
	buddy.free()
	await frames(1)
	e._seen_target_at = -100.0
	e._heard_at = -100.0
	for i in 20:
		e._consider_grenade(0.2)
	check(not e.is_throwing, "no throw at a Finn he hasn't seen or heard for a while")
	e._heard_at = e._now()
	e._heard_pos = p.head.global_position
	e._consider_grenade(0.2)
	check(e.is_throwing, "…but one at a Finn whose gun he just heard")
	e._end_throw(false)
	reset_manager()
	e._seen_target_at = e._now()
	e.suppression = 1.0
	for i in 20:
		e._consider_grenade(0.2)
	check(not e.is_throwing, "no throw while pinned down")
	e.suppression = 0.0
	e.grenades = 0
	for i in 20:
		e._consider_grenade(0.2)
	check(not e.is_throwing, "no throw with no grenades left")
	e.grenades = 2
	e.global_position = Vector3(tx, floor_y, 57.5) # 3.5 m: too close
	await frames(2)
	for i in 20:
		e._consider_grenade(0.2)
	check(not e.is_throwing, "no throw at a Finn closer than %d m" % data.grenade_range_min_m)
	e.global_position = Vector3(tx, terrain.get_height(tx, 20.0) + 0.05, 20.0) # 41 m: too far
	await frames(2)
	for i in 20:
		e._consider_grenade(0.2)
	check(not e.is_throwing, "no throw at a Finn further than %d m" % data.grenade_range_max_m)
	e.global_position = at
	await frames(2)

	# Killed during the wind-up: the live grenade falls at his feet (drop chance 1) – or not (0).
	data.grenade_drop_chance = 1.0
	reset_manager()
	e._seen_target_at = e._now()
	e._consider_grenade(0.2)
	thrown_before = manager.thrown_count
	e.take_damage(1000.0, -1, e.global_position, Vector3.UP)
	check(manager.thrown_count == thrown_before + 1 and manager.position_of(manager._next_id).distance_to(e.global_position) < 3.0,
			"shot during the wind-up: the live grenade falls at his feet")
	var e2: Enemy = new_soldier("res://scenes/enemies/soviet_rifleman.tscn", at + Vector3(4, 0, 0), "Thrower2")
	var data2: EnemyData = data.duplicate()
	data2.grenade_drop_chance = 0.0
	e2.data = data2
	e2.set_physics_process(false)
	await frames(2)
	e2.state = Enemy.State.ATTACK
	e2._target = p
	e2._seen_target_at = e2._now()
	reset_manager()
	e2._consider_grenade(0.2)
	thrown_before = manager.thrown_count
	check(e2.is_throwing and manager._reserved == 1, "a second thrower winds up (his place is kept)")
	e2.take_damage(1000.0, -1, e2.global_position, Vector3.UP)
	check(manager.thrown_count == thrown_before and manager._reserved == 0, "…killed, his grenade stays with him (drop chance 0) and the place is given back")

	# The bunker: a Finn inside – throws go at the firing hole; some get in, most don't.
	var bunker_spot := Vector3(-0.5, bunker_floor, 58.8)
	p.global_position = bunker_spot
	await frames(2)
	var b: Enemy = new_soldier("res://scenes/enemies/soviet_rifleman.tscn", Vector3(1.0, terrain.get_height(1.0, 42.0) + 0.05, 42.0), "BunkerThrower")
	b.data = data
	b.set_physics_process(false)
	await frames(2)
	b.state = Enemy.State.ATTACK
	b._target = p
	var inside := 0
	var tries := 40
	for i in tries:
		reset_manager()
		b.is_throwing = false
		b.grenades = 2
		b._seen_target_at = b._now()
		b._consider_grenade(0.2)
		if not b.is_throwing:
			continue
		var o: Vector3 = b._grenade_release_point(b._throw_target)
		var fl: Dictionary = manager.simulate(o, manager.solve_throw(o, b._throw_target, b._throw_angle), 4.0)
		var r: Vector3 = fl.rest
		if r.y < -0.5 and absf(r.x) < 2.5 and r.z > 57.25 and r.z < 61.75:
			inside += 1
		manager.cancel_reservation()
	check(b._throw_angle == manager.bunker_angle_deg, "Finn in the bunker: a flat throw at the firing hole")
	check(inside > 0 and inside < tries, "…%d of %d throws get into the room" % [inside, tries])

	# --- HUD icon: a live grenade near the local player shows up.
	p.global_position = Vector3(tx, floor_y, 61.0)
	await frames(2)
	reset_manager()
	manager.throw(Vector3(tx + 3.0, floor_y + 0.1, 61.0), Vector3.ZERO, -1, false, 3.0)
	await get_tree().create_timer(0.3).timeout
	var hud := game.get_node("HUD") as HUD
	check(hud.grenade_warning != null and hud.grenade_warning._near_grenades().size() == 1, "HUD: the grenade icon shows a live grenade 3 m away")
	await get_tree().create_timer(3.2).timeout
	check(hud.grenade_warning._near_grenades().is_empty(), "…and is gone after the burst")

	# ================================================================== GR3: round a corner in the trench
	p.god_mode = true
	var ts: Enemy = new_soldier("res://scenes/enemies/soviet_rifleman.tscn", Vector3(-31.0, floor_y + 0.05, 61.0), "TrenchThrower")
	ts.data = data
	ts.set_physics_process(false)
	await frames(3)
	ts.state = Enemy.State.ASSAULT
	ts._target = p
	ts.grenades = 2
	check(ts.is_in_trench(), "a Soviet down in the trench (assault)")
	# A Finn in plain sight along the same straight, 10 m away: he is shot, not bombed.
	p.global_position = Vector3(-31.0 + 0.0, floor_y, 61.0)
	var straight: Vector3 = Vector3(-21.0, floor_y, 58.0) # (another straight; looked for below)
	var corner: Vector3 = Vector3.INF
	# (Standing, a Finn's head shows over the trench edge – soldiers in the trench see it across the
	# flat ground. Crouching round a corner he is out of sight.)
	p.is_crouching = true
	for cand in [Vector3(-19.0, floor_y, 58.0), Vector3(-20.0, floor_y, 58.0), Vector3(-22.0, floor_y, 58.0), Vector3(-13.0, floor_y, 61.0), Vector3(-11.0, floor_y, 61.0)]:
		if floor_at(cand.x, cand.z) > -1.0:
			continue
		p.global_position = cand
		await frames(2)
		ts._update_senses(0.2)
		var dflat: float = Vector2(cand.x + 31.0, cand.z - 61.0).length()
		if not ts._can_see_target and dflat >= 8.0 and corner == Vector3.INF:
			corner = cand
	check(corner != Vector3.INF, "found a crouching Finn round a corner of the trench (%s)" % corner)
	p.global_position = corner
	await frames(2)
	reset_manager()
	ts._update_senses(0.2)
	ts._seen_target_at = ts._now() # he saw him go round the corner a moment ago
	var tries3 := 0
	while not ts.is_throwing and tries3 < 60:
		reset_manager()
		ts._consider_grenade(0.2)
		tries3 += 1
	check(ts.is_throwing, "round the corner (%.0f m): he throws (after %d tries)" % [Vector2(corner.x + 31.0, corner.z - 61.0).length(), tries3])
	if ts.is_throwing:
		var o3: Vector3 = ts._grenade_release_point(ts._throw_target)
		var f3: Dictionary = manager.simulate(o3, manager.solve_throw(o3, ts._throw_target, ts._throw_angle), 4.0)
		var r3: Vector3 = f3.rest
		check(r3.y < -0.85 and r3.distance_to(ts.global_position) >= 6.0, "…and it comes down in the trench, away from him (%.1f m from him)" % r3.distance_to(ts.global_position))
	ts._end_throw(false)
	# In sight → no grenade (he shoots).
	p.global_position = Vector3(-33.5, floor_y, 61.0)
	ts.global_position = Vector3(-28.5, floor_y + 0.05, 61.0)
	await frames(2)
	ts._update_senses(0.2)
	reset_manager()
	for i in 30:
		ts._consider_grenade(0.2)
	check(ts._can_see_target and not ts.is_throwing, "a Finn in sight in the trench: no grenade (he shoots)")
	p.is_crouching = true
	# Round a corner but closer than 8 m → no grenade.
	ts.global_position = Vector3(-31.0, floor_y + 0.05, 61.0)
	p.global_position = Vector3(-25.5, floor_y, 58.0)
	await frames(2)
	ts._update_senses(0.2)
	ts._seen_target_at = ts._now()
	for i in 30:
		reset_manager()
		ts._consider_grenade(0.2)
	check(not ts.is_throwing, "a Finn round a corner only %.1f m away: no grenade" % Vector2(-25.5 + 31.0, 58.0 - 61.0).length())
	ts.queue_free()
	p.god_mode = false
	p.is_crouching = false

	# ================================================================== GR2: throw it back
	p.god_mode = false
	p.health = 100000
	p.is_crouching = false
	p.global_position = Vector3(tx, floor_y, 61.0)
	p.input.look_yaw = 0.0 # looking at the enemy (-z)
	p.input.look_pitch = deg_to_rad(20.0)
	await frames(3)
	reset_manager()
	var gid2: int = manager.throw(Vector3(tx + 0.9, floor_y + 0.1, 61.0), Vector3.ZERO, -1, false, 3.5)
	await get_tree().create_timer(0.4).timeout
	check(hud.grenade_warning.grabbable_index() >= 0, "HUD: a live grenade 0.9 m away can be picked up ([F] on its icon)")
	await get_tree().process_frame
	check(hud.interact_prompt.text == "", "…and the [F] text prompt (ammo box etc.) steps aside")
	var live_before: int = manager.live_count()
	var thrown_now: int = manager.thrown_count
	check(p.grab.try_grab(), "F: the player grabs it")
	check(manager.live_count() == live_before - 1 and manager.position_of(gid2) == Vector3.INF, "…it leaves the ground")
	await get_tree().process_frame
	check(p.grab.is_busy() and p.weapons.get_hand_grips().size() == 2, "…his hands hold it (gun lowered)")
	check(not p.grab.try_grab(), "…no second grab while the first is in the hand")
	await get_tree().create_timer(p.grab.throw_at + 0.1).timeout
	check(manager.thrown_count == thrown_now + 1 and p.grab.thrown_back == 1, "…and throws it back (thrown back: %d)" % p.grab.thrown_back)
	var back_id: int = manager._next_id
	var far_pos: Vector3 = Vector3.INF
	t = 0.0
	while manager.position_of(back_id) != Vector3.INF and t < 5.0:
		far_pos = manager.position_of(back_id)
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var dist: float = Vector2(far_pos.x - tx, far_pos.z - 61.0).length()
	check(far_pos != Vector3.INF and far_pos.z < 61.0 - 8.0, "…towards the enemy, %.0f m away" % dist)
	await get_tree().create_timer(0.7).timeout
	check(not p.grab.is_busy(), "…then the gun is back up")

	# Too far away: F does nothing to it.
	reset_manager()
	var far_id: int = manager.throw(Vector3(tx + 2.3, floor_y + 0.1, 61.0), Vector3.ZERO, -1, false, 2.0)
	await get_tree().create_timer(0.3).timeout
	check(not p.grab.try_grab() and manager.position_of(far_id) != Vector3.INF, "a grenade 2.3 m away can't be grabbed")
	# Not while bandaging / with a lit bottle / on the Maxim.
	p.is_bandaging = true
	var near_id: int = manager.throw(Vector3(tx - 0.8, floor_y + 0.1, 61.0), Vector3.ZERO, -1, false, 1.5)
	await get_tree().create_timer(0.2).timeout
	check(not p.grab.try_grab(), "not while bandaging")
	p.is_bandaging = false
	p.molotov.phase = MolotovHandler.Phase.LIT
	check(not p.grab.try_grab(), "not with a lit Molotov in the hand")
	p.molotov.phase = MolotovHandler.Phase.NONE
	# Two hands at once (co-op): the second finds nothing.
	var pts: Array[Vector3] = [Vector3(tx - 0.8, floor_y + 0.1, 61.0)]
	var first_id: int = manager.find_grabbable(pts, 1.5)
	manager.grab(first_id)
	check(first_id == near_id and manager.find_grabbable(pts, 1.5) == -1, "a grenade can only be grabbed once (the second player finds nothing)")
	await get_tree().create_timer(2.2).timeout # (the far one goes off)

	# The fuse keeps running: grabbed with 0.2 s left, it goes off in the hand.
	reset_manager()
	manager.throw(Vector3(tx + 0.7, floor_y + 0.1, 61.0), Vector3.ZERO, -1, false, 0.45)
	await get_tree().create_timer(0.25).timeout
	hp = p.health
	check(p.grab.try_grab(), "grabbed with ~0.2 s left…")
	await get_tree().create_timer(0.4).timeout
	check(hp - p.health >= 300, "…it goes off in his hand (%d damage)" % (hp - p.health))
	check(p.grab.thrown_back == 1, "…and doesn't count as thrown back")
	await get_tree().create_timer(0.5).timeout

	# A thrown-back grenade that kills a Soviet counts as the player's kill.
	reset_manager()
	var target_e: Enemy = new_soldier("res://scenes/enemies/soviet_rifleman.tscn", Vector3(tx, terrain.get_height(tx, 50.0) + 0.05, 50.0), "BackTarget")
	target_e.set_physics_process(false)
	await frames(2)
	var kills0: int = p.kills
	manager.throw(target_e.global_position + Vector3(0.6, 0.3, 0.0), Vector3.ZERO, p.get_peer_id(), false, 0.3)
	await get_tree().create_timer(0.6).timeout
	check(target_e.state == Enemy.State.DEAD and p.kills == kills0 + 1, "a Soviet killed by a thrown-back grenade counts for the player (kills %d → %d)" % [kills0, p.kills])

	# F through the Player's own key handling (physics on): grabs before the ammo box.
	reset_manager()
	p.set_physics_process(true)
	manager.throw(p.global_position + Vector3(0.6, 0.1, 0.0), Vector3.ZERO, -1, false, 3.0)
	await get_tree().create_timer(0.3).timeout
	var tb: int = p.grab.thrown_back
	p.input.request_interact()
	await get_tree().create_timer(0.7).timeout
	check(p.grab.thrown_back == tb + 1, "F (the real key handling) picks it up and throws it back")
	p.set_physics_process(false)

	# The run save carries the count; the end screen shows it.
	RunSave.totals = {}
	RunSave.active = true
	var save_backup: PackedByteArray = FileAccess.get_file_as_bytes(RunSave.SAVE_PATH) if FileAccess.file_exists(RunSave.SAVE_PATH) else PackedByteArray()
	RunSave.checkpoint(3, 100.0, get_tree().get_nodes_in_group("players"))
	var saved_count: int = p.grab.thrown_back
	p.grab.thrown_back = 0
	RunSave.restore_player(p)
	check(p.grab.thrown_back == saved_count and saved_count > 0, "the saved run keeps the grenades thrown back (%d)" % saved_count)
	if save_backup.is_empty():
		DirAccess.remove_absolute(RunSave.SAVE_PATH)
	else:
		var f := FileAccess.open(RunSave.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(save_backup)
		f.close()
	RunSave.active = false
	var director := get_tree().get_first_node_in_group("match_director") as MatchDirector
	hud.end_screen.open(director, p)
	check(hud.end_screen.stats.text.contains("Grenades thrown back: %d" % saved_count), "the end screen shows the grenades thrown back")
	get_tree().paused = false

	print("\nRESULT: %s (%d failed)" % ["ALL PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
