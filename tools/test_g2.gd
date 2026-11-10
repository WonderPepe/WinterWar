extends Node
## Automated test for G2 "pressure" (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_g2.gd
## Suppression + prone, the officer and his whistle, the DP-27 team, the wave list.

var game: Node
var p: Player
var spawner: WaveSpawner
var terrain: TerrainGenerator
var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ready() -> void:
	await get_tree().process_frame
	run()


func start_game() -> void:
	if game:
		game.queue_free()
		await frames(2)
	get_tree().paused = false
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await frames(5)
	await physics(5)
	p = get_tree().get_first_node_in_group("players")
	spawner = get_tree().get_first_node_in_group("wave_spawner")
	terrain = get_tree().get_first_node_in_group("terrain")
	p.input.set_process(false)
	p.god_mode = true
	spawner.set_process(false) # the test sends the soldiers itself
	var map: RID = p.get_world_3d().navigation_map
	for i in 120:
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			break
		await get_tree().physics_frame
	await physics(10)


func ground(x: float, z: float) -> Vector3:
	return Vector3(x, terrain.get_height(x, z), z)


func spawn(scene: String, pos: Vector3, goal := Vector3.INF) -> Enemy:
	var e: Enemy = load("res://scenes/enemies/%s.tscn" % scene).instantiate()
	e.name = "T_%s_%d" % [scene, Time.get_ticks_usec()]
	e.position = pos + Vector3(0, 0.1, 0)
	e.rotation.y = PI
	e.attack_point = pos if goal == Vector3.INF else goal
	game.get_node("Enemies").add_child(e, true)
	return e


## A bullet from the player's position flying past `e` at `miss` metres.
func shoot_past(e: Enemy, miss: float, w: WeaponData) -> void:
	var target: Vector3 = e.global_position + Vector3(miss, 1.1, 0)
	var origin: Vector3 = e.global_position + Vector3(miss, 1.5, 60)
	get_tree().call_group("enemies", "bullet_near", origin, target + (target - origin).normalized() * 50.0, w.suppression)


func run() -> void:
	await start_game()
	var mosin: WeaponData = load("res://resources/weapons/mosin_m28_30.tres")
	var maxim: WeaponData = load("res://resources/weapons/maxim_m09_21.tres")
	check(mosin.suppression > 0.0 and maxim.suppression > 0.0, "weapons have a suppression value")

	# --- 1. Suppression and prone ---
	var r: Enemy = spawn("soviet_rifleman", ground(-40, 0))
	await physics(5)
	shoot_past(r, 6.0, mosin)
	check(r.suppression == 0.0, "a bullet 6 m away doesn't bother him")
	shoot_past(r, 0.6, mosin)
	await physics(3)
	check(r.suppression > 0.3 and r.is_prone, "a Mosin bullet 0.6 m away throws him flat (suppression %.2f)" % r.suppression)
	var capsule := r.collision.shape as CapsuleShape3D
	check(absf(r.collision.rotation.x - PI / 2.0) < 0.01 and r.eyes.position.y < 0.6, "prone: lying hit capsule, eyes just above the snow")
	var z0: float = r.global_position.z
	r.attack_point = r.global_position + Vector3(0, 0, 30)
	r.state = Enemy.State.PATROL
	await seconds(0.8)
	check(absf(r.global_position.z - z0) < 0.3, "prone soldier doesn't advance")
	for i in 6:
		shoot_past(r, 0.5, maxim)
	check(r.is_pinned(), "a Maxim burst pins him down (suppression %.2f)" % r.suppression)
	# Pinned: no shots.
	r.global_position = ground(-40, 25)
	p.global_position = Vector3(-40, terrain.get_height(-40, 45) + 0.1, 45)
	r.rotation.y = PI
	r._start_attack(p)
	r._can_see_target = true
	r._aim_time = 10.0
	var shots_before: int = r._shots_at_target
	r.suppression = 1.0
	r._last_close_bullet = r._clock + 100.0 # don't recover during the check
	await seconds(1.0)
	check(r._shots_at_target == shots_before, "pinned soldier doesn't shoot")
	check(r._fire_interval_factor() > 1.5, "suppressed: slower fire (×%.1f)" % r._fire_interval_factor())
	r._last_close_bullet = -100.0
	r.data.recovery_delay = 0.0
	var t0 := Time.get_ticks_msec()
	while (r.is_prone or r.suppression >= r.data.prone_threshold * 0.5) and Time.get_ticks_msec() - t0 < 8000:
		await seconds(0.2)
	check(not r.is_prone and r.suppression < r.data.prone_threshold * 0.5, "suppression wears off and he gets up (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	r.data.recovery_delay = 1.2
	# Kept under fire but not pinned: after a while he jumps up and dashes anyway.
	r.state = Enemy.State.PATROL
	r.attack_point = r.global_position + Vector3(0, 0, 20)
	r._prone_patience = 1.0
	r.suppression = 0.6
	await physics(3)
	check(r.is_prone, "suppressed (0.6) and flat")
	var dashed := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		r.suppression = 0.6
		r._last_close_bullet = r._clock
		await physics(1)
		if not r.is_prone:
			dashed = true
			break
	check(dashed, "not pinned: after lying a while he jumps up for a dash")
	r.suppression = 0.0

	# A real player shot past him (host bullet logic) suppresses too.
	r.suppression = 0.0
	r.set_physics_process(false)
	r.global_position = ground(-40, 0)
	await physics(2)
	var origin: Vector3 = r.global_position + Vector3(1.0, 1.4, 50)
	var dir: Vector3 = (r.global_position + Vector3(1.0, 1.1, 0) - origin).normalized()
	p.weapons.resolve_shot(origin, dir, mosin, [] as Array[RID])
	check(r.suppression > 0.1, "player's shot 1 m past him adds suppression (%.2f)" % r.suppression)
	r.set_physics_process(true)
	# Holding at his jump-off point while prone: the rush waits.
	r.suppression = 0.9
	r._last_close_bullet = r._clock + 100.0
	r.state = Enemy.State.PATROL
	r.attack_point = r.global_position
	r._assault_after = 0.5
	await seconds(1.2)
	check(r.state != Enemy.State.ASSAULT, "pinned at the jump-off point: no rush into the trench")
	r.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)

	# --- 3. Officer ---
	var officer: Enemy = spawn("soviet_officer", ground(10, 0))
	var s1: Enemy = spawn("soviet_rifleman", ground(16, 2))
	var s2: Enemy = spawn("soviet_rifleman", ground(4, -3))
	var far_one: Enemy = spawn("soviet_rifleman", ground(80, 0))
	await physics(10)
	check(officer.data.kind == EnemyData.Kind.OFFICER and officer.visual.muzzle.position == SoldierMesh.MUZZLE_PISTOL, "officer scene: officer data, pistol")
	check(officer.visual._mesh.mesh != s1.visual._mesh.mesh, "officer has his own body (cap, belts, map case)")
	officer._whistle_timer = 100.0
	await seconds(0.3)
	s1.suppression = 0.0
	far_one.suppression = 0.0
	s1.add_suppression(0.5)
	far_one.add_suppression(0.5)
	check(s1.suppression < far_one.suppression - 0.1, "near the officer he is steadier (%.2f vs %.2f)" % [s1.suppression, far_one.suppression])
	# Pinned soldiers near him: he whistles them back up.
	s1.suppression = 0.9
	s1._last_close_bullet = s1._clock + 100.0
	officer._whistle_timer = 0.0
	var whistles: int = officer.whistle_count
	await seconds(0.6)
	check(officer.whistle_count > whistles, "officer whistles when his men are pinned (%d)" % officer.whistle_count)
	check(s1.suppression < 0.6, "the whistle takes suppression off (%.2f)" % s1.suppression)
	s1._last_close_bullet = -100.0
	# Pistol only close up.
	officer.global_position = ground(-40, 0)
	p.global_position = ground(-40, 60) + Vector3(0, 0.1, 0)
	officer._target = p
	check(not officer._in_fire_range(), "officer doesn't fire his pistol at 60 m")
	p.global_position = ground(-40, 30) + Vector3(0, 0.1, 0)
	check(officer._in_fire_range(), "officer fires his pistol at 30 m")
	officer.global_position = ground(10, 0)
	p.global_position = Vector3(-30, -1.3, 61)
	await physics(3)
	# Group rush: at the jump-off point he whistles and the men go together.
	for e in [officer, s1, s2]:
		e.state = Enemy.State.PATROL
		e.attack_point = e.global_position
		e.suppression = 0.0
	s1._assault_after = 100.0
	s2._assault_after = 100.0
	officer._assault_after = 0.3
	officer._hold_time = 0.0
	await seconds(1.5)
	check(officer.state == Enemy.State.ASSAULT and s1.state == Enemy.State.ASSAULT and s2.state == Enemy.State.ASSAULT,
			"officer's whistle sends his men into the trench together (%s %s %s)" % [Enemy.State.keys()[officer.state], Enemy.State.keys()[s1.state], Enemy.State.keys()[s2.state]])
	for e in [s1, s2]:
		e.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	officer.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	# Officer killed: the men around him hesitate.
	var o2: Enemy = spawn("soviet_officer", ground(-60, -20))
	var s3: Enemy = spawn("soviet_rifleman", ground(-56, -20))
	await physics(5)
	var hold_before: float = s3._assault_after
	o2.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	await physics(2)
	check(s3._assault_after > hold_before + 5.0 and s3._leaderless_until > s3._clock,
			"officer killed: his men hesitate (rush delayed %.0f → %.0f s)" % [hold_before, s3._assault_after])
	s3._officer_near = false
	s3.suppression = 0.0
	s3.add_suppression(0.3)
	check(s3.suppression > 0.3 * 1.3, "…and are easier to pin down (%.2f)" % s3.suppression)
	s3.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	far_one.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	check(ResourceLoader.exists("res://assets/audio/officer_whistle_placeholder.wav"), "whistle sound (placeholder) exists")

	# --- 4. DP-27 team ---
	var gun_spot: Vector3 = ground(-30, -40)
	var gunner: Enemy = spawn("soviet_mg_gunner", ground(-30, -60), gun_spot)
	var helper: Enemy = spawn("soviet_rifleman", ground(-28, -61), gun_spot + Vector3(1.3, 0, 0.5))
	gunner.mg_assistant = helper
	helper.mg_gunner = gunner
	helper.home_point = ground(-36, 38)
	await physics(5)
	check(gunner.visual.muzzle.position == SoldierMesh.MUZZLE_DP27 and gunner.mg_ammo == 47, "gunner scene: DP-27, 47-round pan")
	# Player out in the open 100 m in front of them.
	p.global_position = ground(-30, 60) + Vector3(0, 0.2, 0)
	p.global_position = ground(-30, 40) + Vector3(0, 0.2, 0)
	gunner.state = Enemy.State.PATROL
	helper.state = Enemy.State.PATROL
	t0 = Time.get_ticks_msec()
	while not gunner.is_deployed() and Time.get_ticks_msec() - t0 < 15000:
		await seconds(0.2)
	await physics(3)
	check(gunner.is_deployed() and gunner.is_prone, "gunner lies down with the gun (%.0f m from the player)" % gunner.global_position.distance_to(p.global_position))
	t0 = Time.get_ticks_msec()
	while gunner.state != Enemy.State.ATTACK and Time.get_ticks_msec() - t0 < 10000:
		await seconds(0.2)
	var ammo0: int = gunner.mg_ammo
	await seconds(5.0)
	var fired: int = ammo0 - gunner.mg_ammo
	check(gunner.state == Enemy.State.ATTACK and fired >= 8, "gunner fires bursts (%d rounds in 5 s)" % fired)
	t0 = Time.get_ticks_msec()
	while not helper.is_prone and Time.get_ticks_msec() - t0 < 10000:
		await seconds(0.2)
	check(helper.is_prone and helper.global_position.distance_to(gunner.global_position) < 4.5,
			"helper lies down next to the gun (%.1f m)" % helper.global_position.distance_to(gunner.global_position))
	gunner.mg_ammo = 1
	await seconds(2.5)
	check(gunner.mg_ammo == 47 and gunner._mg_reload_until > gunner._clock, "empty pan: a new one, a pause while changing it")
	helper._assault_after = 0.1
	helper._hold_time = 10.0
	await seconds(0.5)
	check(helper.state != Enemy.State.ASSAULT and gunner.state != Enemy.State.ASSAULT, "the gun team doesn't rush the trench")
	gunner.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	await physics(3)
	check(helper.mg_gunner == null and helper.attack_point.distance_to(helper.home_point) < 0.01 and not helper.is_deployed(),
			"gunner killed: the helper goes on as a rifleman")
	check(gunner.is_prone and gunner.state == Enemy.State.DEAD, "dead gunner stays lying (no fall-over)")
	helper.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)

	# --- 4b. DP-27 team close behind the riflemen, sent forward when the riflemen are dead (owner) ---
	var points := get_tree().get_nodes_in_group("attack_point")
	var near_ok: bool = true
	for i in 6:
		var aim: Node3D = points[(spawner._mg_count * 3 + 1) % points.size()]
		var count0: int = spawner.alive_count
		spawner._spawn_mg_team(ground(0, -100), points)
		var g: Enemy = spawner.enemies_root.get_child(spawner.enemies_root.get_child_count() - 2) as Enemy # gunner, then helper
		var back: float = aim.global_position.z - g.attack_point.z # (± 2 m random spread per soldier)
		near_ok = near_ok and g.data.kind == EnemyData.Kind.MG_GUNNER and back >= 3.0 and back <= 12.0
		g.queue_free()
		g.mg_assistant.queue_free()
		spawner.alive_count = count0
	check(near_ok, "the gun is set up 5–10 m behind the riflemen's attack point (not 35 m)")
	await frames(2)
	var normal_gunner: EnemyData = load("res://resources/enemies/soviet_mg_gunner.tres")
	check(normal_gunner.mg_fire_range_min_m == 80.0 and normal_gunner.mg_fire_range_max_m == 130.0
			and normal_gunner.mg_follow_back_min_m == 5.0 and normal_gunner.mg_follow_back_max_m == 10.0,
			"gun teams: fire from 80–130 m off the trench, follow 5–10 m behind the riflemen")
	var g2: Enemy = spawn("soviet_mg_gunner", ground(10, -30), ground(10, 25))
	var h2: Enemy = spawn("soviet_rifleman", ground(12, -31), ground(11, 25))
	g2.mg_assistant = h2
	h2.mg_gunner = g2
	g2.home_point = ground(9, 35)
	h2.home_point = ground(11, 35)
	var rifleman: Enemy = spawn("soviet_rifleman", ground(20, -30))
	await physics(3)
	g2._deploy()
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en != g2 and en != h2 and en != rifleman and en.state != Enemy.State.DEAD:
			en.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	spawner._left_to_spawn = 0
	check(spawner.release_mg_teams_if_alone() == 0 and not g2.mg_released and g2.is_deployed(),
			"a rifleman still fights: the gun team stays in position")
	rifleman.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	check(spawner.release_mg_teams_if_alone() == 1 and g2.mg_released and not g2.is_deployed()
			and g2.attack_point.distance_to(g2.home_point) < 0.01 and h2.mg_gunner == null
			and h2.attack_point.distance_to(h2.home_point) < 0.01,
			"riflemen all dead: gunner and helper get up and go for the trench")
	check(not g2.is_mg_team_member() and not h2.is_mg_team_member() and spawner.release_mg_teams_if_alone() == 0,
			"…once (they count as riflemen now)")
	g2.state = Enemy.State.PATROL
	h2.state = Enemy.State.PATROL
	var gz0: float = g2.global_position.z
	t0 = Time.get_ticks_msec()
	while g2.global_position.z < gz0 + 4.0 and Time.get_ticks_msec() - t0 < 15000:
		await seconds(0.2)
	check(g2.global_position.z > gz0 + 4.0, "the gunner walks forward (z %.0f → %.0f)" % [gz0, g2.global_position.z])
	check(g2.can_join_assault() or g2.is_pinned(), "an officer could now send him into the trench too")
	g2._hold_time = 0.0
	g2._assault_after = 0.0
	g2.global_position = g2.home_point + Vector3(0, 0.1, 0)
	g2.suppression = 0.0
	g2.is_prone = false
	await physics(2)
	g2._hold_at_goal(0.1)
	check(g2.state == Enemy.State.ASSAULT, "at the trench he rushes in like a rifleman (%s)" % Enemy.State.keys()[g2.state])
	g2.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	h2.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)

	# --- 4c. Fire, then move up (owner): open fire 80–130 m from the trench, catch up with the riflemen ---
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Enemy).state != Enemy.State.DEAD:
			(e as Enemy).take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	p.global_position = ground(-30, 40) + Vector3(0, 0.2, 0)
	var g3: Enemy = spawn("soviet_mg_gunner", ground(-30, -62), ground(-30, 30))
	var h3: Enemy = spawn("soviet_rifleman", ground(-28, -63), ground(-29, 30))
	g3.mg_assistant = h3
	h3.mg_gunner = g3
	await physics(3)
	check(g3._mg_fire_range >= 80.0 and g3._mg_fire_range <= 130.0 and g3._mg_follow_back >= 5.0 and g3._mg_follow_back <= 10.0,
			"each team gets its own fire range (%.0f m) and distance behind (%.1f m)" % [g3._mg_fire_range, g3._mg_follow_back])
	g3._mg_fire_range = 120.0
	g3.state = Enemy.State.PATROL
	h3.state = Enemy.State.PATROL
	t0 = Time.get_ticks_msec()
	while not g3.is_deployed() and Time.get_ticks_msec() - t0 < 15000:
		await seconds(0.2)
	check(g3.is_deployed() and g3.distance_to_trench() > 95.0,
			"sees a Finn within his range: the gun opens up far out (%.0f m from the trench)" % g3.distance_to_trench())
	var g4: Enemy = spawn("soviet_mg_gunner", ground(-50, -100), ground(-50, 30))
	await physics(3)
	g4._mg_fire_range = 100.0
	g4.state = Enemy.State.PATROL
	var deployed_far: bool = false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		if g4.is_deployed() and g4.distance_to_trench() > 101.0:
			deployed_far = true
		await seconds(0.2)
	check(not deployed_far and g4.global_position.z > -98.0,
			"further out than his range: no fire yet, he walks on (%.0f m from the trench)" % g4.distance_to_trench())
	g4.take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)
	# His riflemen are 30 m further forward: the team gets up and catches up.
	var lead: Enemy = spawn("soviet_rifleman", ground(-30, g3.global_position.z + 32.0))
	await physics(3)
	lead.set_physics_process(false) # stands still: an easy rifleman to follow
	var z_fire: float = g3.global_position.z
	t0 = Time.get_ticks_msec()
	while g3.is_deployed() and Time.get_ticks_msec() - t0 < 5000:
		await seconds(0.2)
	await seconds(1.2)
	check(not g3.is_deployed() and g3.attack_point.z > z_fire + 15.0 and not h3.is_deployed()
			and h3.attack_point.distance_to(g3.attack_point) < 3.0,
			"riflemen 30 m ahead: gunner and helper get up and follow (goal z %.0f, gun was at %.0f)" % [g3.attack_point.z, z_fire])
	t0 = Time.get_ticks_msec()
	while not (g3.is_deployed() and g3.global_position.z > z_fire + 15.0) and Time.get_ticks_msec() - t0 < 25000:
		await seconds(0.2)
	var behind: float = lead.global_position.z - g3.global_position.z
	check(g3.is_deployed() and behind > 2.0 and behind < 14.0,
			"…and set up the gun again behind them (%.1f m behind the rifleman)" % behind)
	for e in [g3, h3, lead]:
		(e as Enemy).take_damage(500.0, 1, Vector3.ZERO, Vector3.UP)

	# --- Wave list ---
	var director: MatchDirector = get_tree().get_first_node_in_group("match_director")
	check(spawner.wave_list.size() == director.waves_to_win, "wave list: one entry per wave (%d)" % spawner.wave_list.size())
	var w2: WaveData = spawner.get_composition(2)
	var w3: WaveData = spawner.get_composition(3)
	check(spawner.get_composition(1).officers == 1 and spawner.get_composition(1).mg_teams == 0, "wave 1: riflemen and one officer")
	check(w2.mg_teams == 2 and w3.mg_teams == 0 and w3.tanks == 2, "machine-gun teams in wave 2, two tanks in wave 3")
	for d in ["easy", "normal", "hard"]:
		var dd: DifficultyData = load("res://resources/difficulty/%s.tres" % d)
		check(dd.waves.size() == dd.waves_to_win, "%s: %d waves listed" % [dd.display_name, dd.waves.size()])
		check(dd.waves_to_win == 10, "%s: 10 waves" % dd.display_name)
	# Easy = Normal with fewer riflemen; officers, MG teams and barrages unchanged (owner).
	var easy: DifficultyData = load("res://resources/difficulty/easy.tres")
	var normal: DifficultyData = load("res://resources/difficulty/normal.tres")
	var same_rest := true
	var fewer_riflemen := true
	for i in normal.waves.size():
		var a: WaveData = easy.waves[i]
		var b: WaveData = normal.waves[i]
		same_rest = same_rest and a.officers == b.officers and a.mg_teams == b.mg_teams and a.barrage == b.barrage
		fewer_riflemen = fewer_riflemen and a.riflemen < b.riflemen
	check(same_rest, "Easy: same officers, MG teams and barrages as Normal")
	check(fewer_riflemen, "Easy: fewer riflemen than Normal in every wave")
	check(easy.enemy_damage_multiplier < 1.0 and is_equal_approx(normal.enemy_damage_multiplier, 1.0), "Easy: enemy damage lowered")
	# Spawn a real wave 4 (riflemen + officer + MG team) and check what comes out.
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await frames(3)
	spawner.alive_count = 0
	spawner.wave_number = 3
	spawner.max_alive = 100 # wave 4 is bigger than the web limit
	spawner.time_between_groups = 0.2
	spawner.set_process(true)
	spawner._phase = WaveSpawner.Phase.WAITING
	spawner._timer = 0.0
	var hud: HUD = game.get_node("HUD")
	await seconds(0.3)
	check(hud.banner_sub.text.contains("1 officer") and hud.banner_sub.text.contains("2 machine-gun teams"),
			"HUD tells what is coming: '%s'" % hud.banner_sub.text.replace("\n", " / "))
	t0 = Time.get_ticks_msec()
	while spawner._left_to_spawn > 0 and Time.get_ticks_msec() - t0 < 10000:
		await seconds(0.2)
	var kinds := {0: 0, 1: 0, 2: 0}
	var teamed := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		kinds[(e as Enemy).data.kind] += 1
		if (e as Enemy).mg_gunner != null:
			teamed += 1
	var w4: WaveData = spawner.get_composition(4)
	check(kinds[1] == w4.officers and kinds[2] == w4.mg_teams and kinds[0] == w4.riflemen + w4.mg_teams and teamed == w4.mg_teams,
			"wave 4 spawns %d riflemen + %d officer + %d gun team (got R%d O%d G%d, %d helpers)" % [w4.riflemen, w4.officers, w4.mg_teams, kinds[0], kinds[1], kinds[2], teamed])
	check(spawner.alive_count == w4.total_soldiers(), "alive count %d = wave size" % spawner.alive_count)

	# --- Battle briefings (B1): the next battle's briefing after each cleared wave ---
	var reports: FrontReports = load("res://resources/front_reports.tres")
	check(reports.dates.size() == 10 and reports.texts.size() == 10 and reports.weathers.size() == 10 and reports.dates[0] == "30 November 1939"
			and reports.dates[8] == "13 February 1940" and reports.dates[9] == "15 February 1940",
			"10 briefings, 30 November 1939 … 15 February 1940")
	check(reports.get_report(9)[0] == "13 February 1940" and reports.get_report(10)[1].ends_with("wounded to escape.")
			and reports.get_weather(7).contains("Dense Fog") and reports.get_weather(2).contains("Visibility: Poor"),
			"battle 9 → 13 February 1940, battle 10 → 15 February 1940, weather lines")
	check(reports.get_weather(10) == "Weather: Dusk" and not reports.get_weather(10).contains("Snow"), "battle 10 briefing: dusk, no snowfall (the game has none then)")
	check(reports.get_report(9)[1] == reports.get_report(8)[1], "battle 9 text = battle 8 text (until the owner writes his own)")
	check(reports.get_report(11).is_empty(), "no briefing for battle 11")
	check(reports.photos.size() == 10 and reports.get_photo(1) != null and reports.get_photo(7).get_height() > reports.get_photo(7).get_width(),
			"a photo for every day (day 7 is the upright one)")
	var day: DayScreen = hud.day_screen
	check(not day.is_open and not day.visible, "no day screen while a wave is on")
	check(not Settings.has_method("set_show_front_reports"), "front reports always on (no setting)")
	# The countdown to the next wave waits while the day screen is open (host).
	var saved_phase: int = spawner._phase
	var saved_timer: float = spawner._timer
	spawner._phase = WaveSpawner.Phase.WAITING
	spawner._timer = 50.0
	director.waves_cleared = 1
	await seconds(0.4)
	check(day.is_open and day.visible and day.date_label.text == "17 December 1939" and day.day_label.text.ends_with("2")
			and day.tele_date.text.begins_with("Weather: Heavy Snowfall") and day.tele_text.text.begins_with("Enemy activity has increased"),
			"battle 1 cleared: the day screen shows the briefing of battle 2 (17 December 1939)")
	check(day.photo.texture != null and day.frame.visible, "…with its photo")
	check(hud.wave_banner.text == "BATTLE 1 COMPLETED" and hud.wave_banner.modulate.a > 0.9 and day.black.color.a < 0.01,
			"first 'BATTLE 1 COMPLETED' over the battlefield (screen not dark yet)")
	check(spawner.hold, "the next wave's countdown waits")
	var held_at: float = spawner._timer
	await seconds(day.intro_delay + 1.2 - day._t - day.intro_delay)
	check(absf(spawner._timer - held_at) < 0.001, "countdown held (%.2f s)" % spawner._timer)
	check(day.black.color.a > 0.99 and hud.wave_banner.modulate.a < 0.01, "then the fade to black, banner gone")
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX")) < -15.0, "battle sounds turned down behind the screen")
	await seconds(day.type_start + 1.6 - day._t)
	check(day.tele_text.visible_characters > 0 and day.tele_text.visible_characters < day.tele_text.text.length(),
			"telegram types itself out letter by letter (%d / %d)" % [day.tele_text.visible_characters, day.tele_text.text.length()])
	var press := InputEventAction.new()
	press.action = &"jump"
	press.pressed = true
	Input.parse_input_event(press)
	await seconds(1.6)
	check(not day.is_open and not day.visible and not spawner.hold, "Space closes the day screen and releases the countdown")
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX"))) < 0.01, "battle sounds back to normal")
	await seconds(0.5)
	check(spawner._timer < 49.8, "countdown runs again")
	spawner._phase = saved_phase
	spawner._timer = saved_timer
	director.waves_cleared = 2
	await seconds(0.4)
	check(day.is_open and day.date_label.text == "19 December 1939" and day.tele_text.text.contains("Enemy armor has broken through"), "battle 2 cleared: briefing of battle 3, 19 December 1939")
	spawner.wave_number += 1
	await seconds(1.6)
	check(not day.is_open, "the day screen goes away when the next wave starts")
	director.waves_cleared = 3
	await seconds(0.3)
	check(day.is_open, "wave 3 cleared: day screen")
	director.waves_cleared = director.waves_to_win
	director.end_match(MatchDirector.Result.VICTORY)
	await seconds(0.5)
	check(not day.is_open and hud.end_screen.visible and hud.end_screen.report.visible and hud.end_screen.report.text == "15 February 1940",
			"victory on Normal: no day screen, the end screen shows the date of the last battle")
	get_tree().paused = false
	var menu: Control = load("res://ui/settings_menu.tscn").instantiate()
	add_child(menu)
	check(menu.get_node_or_null("Panel/VBox/Grid/FrontReports") == null, "no 'Front reports' switch in Settings any more")
	menu.queue_free()

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
