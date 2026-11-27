extends Node
## Test for EC1 "Soviets crouch in the trench" (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_ec1.gd
## In the trench a Soviet moving towards a Finn who is down low goes mostly crouched (smaller
## hitbox, lower eyes, crouch speed, short upright dashes), fires from the crouch, stands up to
## throw a grenade and towards a Finn up on open ground. `is_crouching` is synced.

var fails := 0
var game: Node
var p: Player
var terrain: TerrainGenerator


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _ready() -> void:
	await get_tree().process_frame
	run()


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func spawn(at: Vector3, frozen: bool) -> Enemy:
	var e: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
	e.name = "EC1Enemy_%d" % Time.get_ticks_usec()
	e.position = at
	e.attack_point = at
	game.get_node("Enemies").add_child(e, true)
	e.grenades = 0
	if frozen:
		e.set_physics_process(false)
	return e


## EC1b: keep apart in the trench, move up on a Finn in sight, no bobbing up and down.
func ec1b() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await physics(2)
	# Two soldiers dropped on the very same spot of the trench floor.
	p.global_position = Vector3(-30.0, -1.4, 61.0)
	var a := spawn(Vector3(-60.0, -1.3, 60.2), false)
	var b := spawn(Vector3(-60.0, -1.3, 60.2), false)
	a.state = Enemy.State.ASSAULT
	b.state = Enemy.State.ASSAULT
	var min_after := INF
	for i in 300: # 5 s
		await get_tree().physics_frame
		if i > 60:
			var d: float = Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()
			min_after = minf(min_after, d)
	check(min_after > 0.8, "two Soviets dropped on one spot: apart after 1 s, never closer than 0.8 m afterwards (%.2f m)" % min_after)
	b.queue_free()

	# A Finn in sight 25 m along the trench: the Soviet gets closer, firing on the way, and
	# does not bob up and down.
	a.global_position = Vector3(-60.0, -1.3, 60.2)
	a.velocity = Vector3.ZERO
	a._bound_until = -100.0
	a._bound_shots_left = 0
	await physics(3)
	var start_d: float = a.global_position.distance_to(p.global_position)
	var shots_before: int = a._shots_at_target
	var switches: Array[float] = []
	var log_lines: Array[String] = []
	var was: bool = a.is_crouching
	var t0: float = a._clock
	var seen_frames := 0
	var upright_frames := 0
	for i in 900: # 15 s
		await get_tree().physics_frame
		if a._can_see_target:
			seen_frames += 1
		if not a.is_crouching:
			upright_frames += 1
		if i % 60 == 0:
			log_lines.append("t=%d pos %s vel %s see %s fin %s next %s blocked %.2f" % [i / 60, a.global_position.snapped(Vector3.ONE * 0.1), a.velocity.snapped(Vector3.ONE * 0.1), a._can_see_target, a.nav_agent.is_navigation_finished(), a.nav_agent.get_next_path_position().snapped(Vector3.ONE * 0.1), a._trench_blocked])
		if a.is_crouching != was:
			was = a.is_crouching
			switches.append(a._clock - t0)
	var end_d: float = a.global_position.distance_to(p.global_position)
	print("      (seen %d / 900 frames, upright %d frames, %d pose changes, %d shots, %.1f -> %.1f m)" % [
			seen_frames, upright_frames, switches.size(), a._shots_at_target - shots_before, start_d, end_d])
	if end_d >= start_d - 8.0:
		for l in log_lines:
			print("      " + l)
	check(end_d < start_d - 8.0, "a Finn %.0f m along the trench: the Soviet comes closer (now %.1f m)" % [start_d, end_d])
	check(a._shots_at_target - shots_before >= 2, "...and fires on the way (%d shots)" % (a._shots_at_target - shots_before))
	var shortest := INF
	for i in range(1, switches.size()):
		shortest = minf(shortest, switches[i] - switches[i - 1])
	check(shortest >= a.data.crouch_min_pose_time - 0.02, "crouched / upright at least %.1f s at a time (shortest %.2f s)" % [a.data.crouch_min_pose_time, shortest])
	a.queue_free()
	await physics(2)


func run() -> void:
	Settings.difficulty = 1
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await get_tree().create_timer(0.5).timeout
	p = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.god_mode = true
	(get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner).set_process(false)
	game.get_node("HUD").day_screen.close_now()
	terrain = get_tree().get_first_node_in_group("terrain")

	# --- Numbers ---
	var e := spawn(Vector3(0.0, terrain.get_height(0.0, 0.0) + 0.05, 0.0), true)
	check(is_equal_approx(e.data.trench_crouch_speed, 2.2) and is_equal_approx(e.data.trench_crouch_share, 0.8),
		"EnemyData: crouch speed 2.2, share 0.8")
	var sync: SceneReplicationConfig = (e.get_node("StateSync") as MultiplayerSynchronizer).replication_config
	var props: Array = sync.get_properties()
	check(props.has(NodePath(".:is_crouching")), "is_crouching is synced")
	check(props[props.size() - 1] == NodePath("Smoother:net_stamp"), "Smoother:net_stamp stays the last synced property")

	# --- Hitbox and hit zones ---
	await physics(2)
	var capsule := e.collision.shape as CapsuleShape3D
	check(is_equal_approx(capsule.height, 1.8), "standing: capsule 1.8 m")
	e.is_crouching = true
	check(is_equal_approx(capsule.height, 1.3) and is_equal_approx(e.eyes.position.y, 1.15),
		"crouching: capsule 1.3 m, eyes 1.15 m (%.2f, %.2f)" % [capsule.height, e.eyes.position.y])
	check(e.hit_zone_at(e.to_global(Vector3(0.2, 1.15, 0))) == Enemy.HitZone.HEAD, "crouching 1.15 m = head")
	check(e.hit_zone_at(e.to_global(Vector3(0.2, 0.85, 0))) == Enemy.HitZone.BODY, "crouching 0.85 m = body")
	check(e.hit_zone_at(e.to_global(Vector3(0.2, 0.4, 0))) == Enemy.HitZone.LEGS, "crouching 0.4 m = legs")
	var suomi: WeaponData = p.weapons.loadout[1]
	p.global_position = Vector3(0.0, terrain.get_height(0.0, 30.0) + 0.05, 30.0)
	var target: Vector3 = e.to_global(Vector3(0.0, 1.17, 0.0))
	var origin: Vector3 = target + Vector3(4.0, 0.3, 0.0)
	await physics(2)
	var before: float = e.health
	p.weapons.resolve_shot(origin, (target - origin).normalized(), suomi, [])
	check(is_equal_approx(before - e.health, suomi.damage * 4.0), "Suomi head shot on a crouching soldier: ×4 (%.0f)" % (before - e.health))
	e.queue_free()

	# --- The crouch / upright-dash rhythm (worked out directly, on his own clock) ---
	e = spawn(Vector3(-60.0, -1.3, 61.0), true)
	await physics(2)
	var low := Vector3(-45.0, -1.4, 61.0)
	var crouched := 0
	var total := 0
	var speeds_ok := true
	var dash_seen := false
	for i in 12000: # 600 s in 0.05 s steps
		e._clock += 0.05
		e._want_crouch = false
		var speed: float = e._trench_move_speed(low)
		total += 1
		if e._want_crouch:
			crouched += 1
			speeds_ok = speeds_ok and is_equal_approx(speed, e.data.trench_crouch_speed)
		else:
			dash_seen = true
			speeds_ok = speeds_ok and is_equal_approx(speed, e.data.hurry_speed)
	var share: float = float(crouched) / total
	check(share > 0.74 and share < 0.86, "towards a Finn down low: crouched %.0f %% of the time (about 80 %%)" % (share * 100.0))
	check(dash_seen, "...with short upright dashes in between")
	check(speeds_ok, "crouched at 2.2 m/s, upright dashes at hurry speed")
	e._want_crouch = false
	var up_speed: float = e._trench_move_speed(Vector3(-45.0, 0.2, 66.0))
	check(not e._want_crouch and is_equal_approx(up_speed, e.data.hurry_speed), "towards a Finn up on open ground: upright, hurry speed")
	e.queue_free()

	# --- In the game: a Soviet in the trench goes for a Finn in the trench ---
	p.global_position = Vector3(-42.0, -1.4, 61.0)
	e = spawn(Vector3(-60.0, -1.3, 61.0), false)
	e.state = Enemy.State.ASSAULT
	await physics(5)
	check(e.is_in_trench(), "the test soldier is in the trench")
	var crouch_frames := 0
	var frames_run := 0
	var start: Vector3 = e.global_position
	for i in 120: # 2 s – the first stretch is always a crouch (4–8 s)
		await get_tree().physics_frame
		frames_run += 1
		if e.is_crouching:
			crouch_frames += 1
	check(crouch_frames == frames_run, "in the trench, going for (or firing at) a Finn down low: crouched all the first 2 s (%d / %d)" % [crouch_frames, frames_run])
	var moved: float = Vector2(e.global_position.x - start.x, e.global_position.z - start.z).length()
	check(moved < 2.2 * 2.0 + 0.5, "no faster than crouch speed (%.1f m in 2 s)" % moved)
	check(is_equal_approx((e.collision.shape as CapsuleShape3D).height, 1.3), "his hitbox is the crouching one")

	# --- He stands up to throw a grenade ---
	e._throw_target = p.global_position
	e._throw_released = false
	e._throw_t = -100.0 # (never reaches the release point during this check)
	e.is_throwing = true
	await physics(3)
	check(not e.is_crouching, "throwing a grenade: he stands up")
	e._end_throw(true)
	await physics(3)

	# --- The Finn climbs out onto open ground: the Soviet stands to see over the edge ---
	p.global_position = Vector3(-50.0, terrain.get_height(-50.0, 70.0) + 0.1, 70.0)
	e._retarget_timer = 0.0
	var stood := false
	for i in 120:
		await get_tree().physics_frame
		if not e.is_crouching:
			stood = true
			break
	check(stood, "a Finn up on open ground: he goes upright")

	# --- Death: no crouch left on the body ---
	e.is_crouching = true
	e.take_damage(10000.0, 1, e.global_position + Vector3.UP, Vector3.UP)
	check(e.state == Enemy.State.DEAD and not e.is_crouching, "killed: not crouching any more")

	await physics(2)
	e.queue_free()
	await ec1b()

	print("RESULT: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)
