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

	# --- Wave list ---
	var director: MatchDirector = get_tree().get_first_node_in_group("match_director")
	check(spawner.wave_list.size() == director.waves_to_win, "wave list: one entry per wave (%d)" % spawner.wave_list.size())
	var w2: WaveData = spawner.get_composition(2)
	var w3: WaveData = spawner.get_composition(3)
	check(spawner.get_composition(1).officers == 0 and spawner.get_composition(1).mg_teams == 0, "wave 1: riflemen only")
	check(w2.officers == 1 and w3.mg_teams == 1, "officers from wave 2, a machine-gun team from wave 3")
	for d in ["easy", "normal", "hard"]:
		var dd: DifficultyData = load("res://resources/difficulty/%s.tres" % d)
		check(dd.waves.size() == dd.waves_to_win, "%s: %d waves listed" % [dd.display_name, dd.waves.size()])
	# Spawn a real wave 4 (riflemen + officer + MG team) and check what comes out.
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await frames(3)
	spawner.alive_count = 0
	spawner.wave_number = 3
	spawner.time_between_groups = 0.2
	spawner.set_process(true)
	spawner._phase = WaveSpawner.Phase.WAITING
	spawner._timer = 0.0
	var hud: HUD = game.get_node("HUD")
	await seconds(0.3)
	check(hud.banner_sub.text.contains("1 officer") and hud.banner_sub.text.contains("1 machine-gun team"),
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

	# --- Front reports after each cleared wave ---
	var reports: FrontReports = load("res://resources/front_reports.tres")
	check(reports.dates.size() == 10 and reports.texts.size() == 10 and reports.dates[0] == "21.12.1939" and reports.dates[7] == "28.12.1939" and reports.dates[9] == "01.01.1940",
			"10 front reports, 21.12.1939 … 01.01.1940")
	check(reports.get_report(9)[0] == "31.12.1939" and reports.get_report(10)[1].ends_with("Tilanne rintamalla on vakaa.\""),
			"Hard: wave 9 → 31.12.1939, wave 10 → 01.01.1940")
	check(reports.get_report(11).is_empty(), "no report after wave 11 (none written)")
	check(reports.photos.size() == 10 and reports.get_photo(1) != null and reports.get_photo(7).get_height() > reports.get_photo(7).get_width(),
			"a photo for every day (day 7 is the upright one)")
	check(DayScreen.long_date("21.12.1939") == "21. joulukuuta 1939" and DayScreen.long_date("01.01.1940") == "1. tammikuuta 1940",
			"dates written out in Finnish")
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
	check(day.is_open and day.visible and day.date_label.text == "21. joulukuuta 1939" and day.tele_date.text == "21.12.1939"
			and day.tele_text.text.begins_with("\"Täällä Kannaksen rintama."), "wave 1 cleared: the day screen for 21.12.1939")
	check(day.photo.texture != null and day.frame.visible, "…with its photo")
	check(hud.wave_banner.text == "WAVE 1 COMPLETED" and hud.wave_banner.modulate.a > 0.9 and day.black.color.a < 0.01,
			"first 'WAVE 1 COMPLETED' over the battlefield (screen not dark yet)")
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
	check(day.is_open and day.tele_date.text == "22.12.1939" and day.tele_text.text.contains("vihollispanssareita"), "wave 2 cleared: 22.12.1939")
	spawner.wave_number += 1
	await seconds(1.6)
	check(not day.is_open, "the day screen goes away when the next wave starts")
	director.waves_cleared = 3
	await seconds(0.3)
	check(day.is_open, "wave 3 cleared: day screen")
	director.waves_cleared = director.waves_to_win
	director.end_match(MatchDirector.Result.VICTORY)
	await seconds(0.5)
	check(not day.is_open and hud.end_screen.visible and hud.end_screen.report.visible and hud.end_screen.report.text.begins_with("28.12.1939"),
			"victory on Normal: no day screen, the end screen shows the report of 28.12.1939")
	get_tree().paused = false
	var menu: Control = load("res://ui/settings_menu.tscn").instantiate()
	add_child(menu)
	check(menu.get_node_or_null("Panel/VBox/Grid/FrontReports") == null, "no 'Front reports' switch in Settings any more")
	menu.queue_free()

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
