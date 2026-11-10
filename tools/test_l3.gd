extends Node
## Automated test for L3: the two communication trenches, the rear spawn points and battle 6
## "retake the trench" (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_l3.gd

var game: Node
var p: Player
var director: MatchDirector
var spawner: WaveSpawner
var hud: HUD
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
	director = get_tree().get_first_node_in_group("match_director")
	spawner = get_tree().get_first_node_in_group("wave_spawner")
	hud = game.get_node("HUD")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	spawner.set_process(false)


func teleport(pos: Vector3, yaw := 0.0) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.input.look_yaw = yaw


func ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	return p.get_world_3d().direct_space_state.intersect_ray(q)


func path_length(from: Vector3, to: Vector3) -> Array:
	var map: RID = p.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var plen := 0.0
	for i in range(1, path.size()):
		plen += path[i - 1].distance_to(path[i])
	return [path, plen]


func occupiers() -> Array[Enemy]:
	var list: Array[Enemy] = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e and e.state != Enemy.State.DEAD:
			list.append(e)
	return list


func run() -> void:
	Settings.difficulty = 1
	MatchDirector.test_start_wave = 0
	await start_game()

	# --- The two communication trenches ---
	var rear := get_tree().get_nodes_in_group("rear_spawn")
	var west := 0
	for m in rear:
		if String(m.get_meta("side", "")) == "west":
			west += 1
	check(rear.size() == 8 and west == 4, "8 rear spawn points, 4 at each communication trench (%d, west %d)" % [rear.size(), west])
	var floor_ok := true
	for m: Node3D in rear:
		var h := ray(m.global_position + Vector3(0, 0.5, 0), m.global_position + Vector3(0, -2, 0))
		floor_ok = floor_ok and not h.is_empty() and absf(h.position.y + 1.4) < 0.15 and m.global_position.z > 95.0
		# and walls on both sides (it really stands in a trench)
		var up := m.global_position + Vector3(0, 0.6, 0)
		floor_ok = floor_ok and (not ray(up, up + Vector3(3, 0, 0)).is_empty() or not ray(up, up + Vector3(0, 0, 3)).is_empty())
	check(floor_ok, "every rear spawn stands on the trench floor (y -1.4) far behind the line (z > 95)")
	for x in [-40.0, 40.0]:
		var res: Array = path_length(Vector3(x, -1.0, 105.5), Vector3(x * 0.75, -1.0, 61.0))
		var path: PackedVector3Array = res[0]
		var low := true
		for v in path:
			low = low and v.y < -0.4
		check(path.size() > 1 and path[path.size() - 1].distance_to(Vector3(x * 0.75, -1.0, 61.0)) < 1.5 and low and res[1] < 75.0,
				"x = %d: a path along the trench floor from the rear spawn to the line (%.0f m, %d points)" % [x, res[1], path.size()])
		# The zigzag: no straight look from the junction to the far end.
		var eye := Vector3(x, -0.5, 68.0) # chest height in the trench
		check(not ray(eye, Vector3(x, -0.5, 104.0)).is_empty(), "x = %d: zigzag – no straight line of sight down the trench" % x)
		# The ramp at the far end leads out onto the ground.
		teleport(Vector3(x, -1.3, 105.5), PI)
		await physics(20)
		p.input.move_dir = Vector2(0, -1)
		await physics(240)
		p.input.move_dir = Vector2.ZERO
		check(p.global_position.z > 111.0 and p.global_position.y > -0.3,
				"x = %d: the ramp at the far end leads up to the ground (z %.1f, y %.1f)" % [x, p.global_position.z, p.global_position.y])
	# No trees grow in them; shells don't land in them; crouching in them is covered.
	check(ArtilleryBarrage.in_comm_trench_area(Vector3(-40, 0, 90)) and ArtilleryBarrage.in_comm_trench_area(Vector3(40, 0, 90))
			and not ArtilleryBarrage.in_comm_trench_area(Vector3(0, 0, 90)), "the strips of the communication trenches are known to the artillery")
	teleport(Vector3(-38, -1.3, 88.0))
	p.input.crouch_held = true
	await physics(30)
	check(ArtilleryBarrage.is_covered(p), "crouching in a communication trench = covered from shells and bombs")
	p.input.crouch_held = false
	await physics(10)
	var clear := false
	for r: Rect2 in ForestScatter.new().keep_clear:
		clear = clear or (r.has_point(Vector2(-40, 90)) and r.has_point(Vector2(-44, 112)))
	check(clear, "no trees may grow in the west communication trench")

	# --- Respawn: at the rear, not in the trench line ---
	teleport(Vector3(-10, -1.3, 61.0))
	await physics(5)
	p.take_damage(1000.0, -1, p.global_position, Vector3.UP)
	await seconds(game.respawn_time + 0.6)
	check(not p.is_dead and p.global_position.z > 95.0, "after dying the player comes back at a rear spawn (z %.1f)" % p.global_position.z)

	# --- Difficulty: who holds the trench in battle 6 ---
	var counts: Array = []
	for d: DifficultyData in director.difficulties:
		var w6: WaveData = d.waves[5]
		counts.append([w6.occupy_riflemen, w6.occupy_officers, w6.occupy_mg_teams])
		var others := true
		for i in d.waves.size():
			if i != 5:
				others = others and not d.waves[i].has_retake()
		check(others, "%s: only battle 6 starts in a captured trench" % d.display_name)
	check(counts == [[7, 1, 1], [8, 1, 1], [9, 1, 1]], "occupiers Easy/Normal/Hard: 7/8/9 riflemen, 1 officer, 1 DP-27 team (%s)" % str(counts))

	# --- Battle 6: start at the rear, retake the trench ---
	Settings.difficulty = 0
	MatchDirector.test_start_wave = 6
	await start_game()
	check(spawner.next_wave_is_retake(), "battle 6 is a retake battle")
	check(p.global_position.z > 95.0 and p.global_position.x < -35.0,
			"battle 6: the player starts at the rear of the WEST communication trench (%.1f, %.1f)" % [p.global_position.x, p.global_position.z])
	p.god_mode = true
	spawner.set_process(true)
	await seconds(director.test_first_wave_delay + 0.6)
	var occ := occupiers()
	var in_west := true
	var holding := true
	for e in occ:
		in_west = in_west and e.is_in_trench() and e.global_position.x < -5.0 and e.global_position.z < 70.0
		holding = holding and e.state == Enemy.State.HOLD
	check(spawner.retaking and spawner.wave_number == 6 and occ.size() == 10 and spawner.alive_count == 10,
			"Easy: 10 Soviets hold the trench (7 riflemen + officer + gunner & helper) (%d)" % occ.size())
	check(in_west and holding, "they all stand in the west half of the trench, in the HOLD state")
	var kinds := {}
	for e in occ:
		kinds[e.data.kind] = kinds.get(e.data.kind, 0) + 1
	check(kinds.get(EnemyData.Kind.OFFICER, 0) == 1 and kinds.get(EnemyData.Kind.MG_GUNNER, 0) == 1, "one officer and one DP-27 gunner among them")
	await seconds(3.0)
	check(director.result == MatchDirector.Result.PLAYING and director.in_trench == 0,
			"no 'line broken' defeat while they hold it (in_trench %d)" % director.in_trench)
	check(hud.trench_label.visible and hud.trench_label.text.begins_with("RETAKE THE TRENCH"), "HUD: '%s'" % hud.trench_label.text)
	check(hud.banner_sub.text.begins_with("Retake the trench!"), "battle banner says 'Retake the trench!' ('%s')" % hud.banner_sub.text.replace("\n", " / "))
	var stayed := true
	for e in occ:
		stayed = stayed and Vector2(e.global_position.x - e.hold_point.x, e.global_position.z - e.hold_point.z).length() < 2.5
	check(stayed, "with nobody near, they stay at their spots")
	var arty: ArtilleryBarrage = game.get_node("ArtilleryBarrage")
	check(not arty.is_active(), "no barrage while the trench is being retaken")

	# A Finn appears in the trench at the east end of their stretch: they fire at him.
	var near_one: Enemy = occ[0]
	for e in occ:
		if e.global_position.x > near_one.global_position.x:
			near_one = e
	teleport(Vector3(near_one.global_position.x + 7.0, -1.3, 61.0), 0.0)
	await seconds(4.0)
	var fired := 0
	for e in occ:
		if is_instance_valid(e) and e._shots_at_target > 0:
			fired += 1
	check(fired > 0, "Soviets in sight fire at the Finn in the trench (%d of them fired)" % fired)
	var went_far := false
	for e in occ:
		if is_instance_valid(e) and e.global_position.distance_to(e.hold_point) > e.hold_leash_m + 3.0:
			went_far = true
	check(not went_far, "nobody leaves his stretch of the trench")

	# Shot one by one (the player's peer id = 1): the trench is retaken.
	for e in occ:
		if is_instance_valid(e) and e.state != Enemy.State.DEAD:
			e.take_damage(1000.0, 1, e.global_position, Vector3.UP)
	await frames(3)
	await physics(3)
	await frames(3)
	check(not spawner.retaking, "all occupiers dead = trench retaken")
	check(hud.wave_banner.text == "Trench Retaken!" and hud.banner_sub.text == "Prepare for Counterattack!" and hud.wave_banner.modulate.a > 0.5,
			"banner: 'Trench Retaken! Prepare for Counterattack!' ('%s' / '%s')" % [hud.wave_banner.text, hud.banner_sub.text])
	check(not hud.trench_label.visible, "the 'retake' line is gone")
	await seconds(spawner.retake_pause * 0.5)
	check(spawner.alive_count == 0 and spawner._phase == WaveSpawner.Phase.RETAKE, "a pause before the counterattack")
	await seconds(spawner.retake_pause * 0.5 + 1.5)
	check(spawner._phase == WaveSpawner.Phase.SPAWNING or spawner._phase == WaveSpawner.Phase.FIGHTING,
			"then the counterattack comes out of the forest (phase %d, alive %d)" % [spawner._phase, spawner.alive_count])
	check(spawner.wave_riflemen == 14 and spawner.wave_officers == 2 and spawner.wave_mg_teams == 1 and spawner.wave_number == 6,
			"the counterattack is battle 6's normal Easy wave (14 riflemen, 2 officers, 1 MG team)")
	check(arty.is_active(), "and the barrage starts with it")

	# The next battle starts in the trench line again.
	spawner.set_process(false)
	for e in occupiers():
		e.take_damage(1000.0, 1, e.global_position, Vector3.UP)
	spawner._phase = WaveSpawner.Phase.WAITING
	game.reset_players_to_start()
	await physics(3)
	check(p.global_position.z < 70.0 and p.global_position.y < -0.8, "battle 7 starts in the trench line again (z %.1f)" % p.global_position.z)
	MatchDirector.test_start_wave = 0
	Settings.difficulty = 1

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
