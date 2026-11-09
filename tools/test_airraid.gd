extends Node
## Test for the air raid (A1; not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_airraid.gd

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
	Settings.difficulty = 1
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await seconds(0.5)
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	var spawner: WaveSpawner = get_tree().get_first_node_in_group("wave_spawner")
	spawner.set_process(false)
	var raid := game.get_node("AirRaid") as AirRaid
	var arty := game.get_node("ArtilleryBarrage") as ArtilleryBarrage
	var hud: HUD = game.get_node("HUD")
	check(raid != null and raid.raid_waves.size() == 2 and raid.raid_waves[0] == 4 and raid.raid_waves[1] == 8, "air raid in battles 4 and 8")
	check(arty.pool_size == 12 and arty._blasts.size() == 12, "12 blasts in the pool")
	check(raid.engine_sound != null and raid.whistle_sound != null and raid._boom_sounds.size() >= 2,
			"sounds set: engine, whistle, %d different booms" % raid._boom_sounds.size())
	check(raid.whistle_sound.get_length() <= raid.fall_time, "the whistle (%.1f s) is not longer than the fall" % raid.whistle_sound.get_length())
	check(raid._plane_nodes.size() == 3 and raid._engines.size() == 3, "three SB-2s with an engine each")

	# Which waves.
	var normal: DifficultyData = load("res://resources/difficulty/normal.tres")
	raid._on_wave_started(3, 5)
	check(not raid.is_active(), "wave 3: no raid")
	raid._on_wave_started(5, 5)
	check(not raid.is_active(), "wave 5: no raid")
	check(normal.waves[3].barrage and normal.waves[7].barrage, "(Normal waves 4 and 8 also have a barrage)")

	# Plan.
	p.global_position = Vector3(-30, -1.3, 61)
	p.input.crouch_held = true
	p.is_crouching = true
	await seconds(0.3)
	Engine.time_scale = 1.0
	raid.start(true)
	await seconds(0.2)
	check(raid.phase == AirRaid.Phase.APPROACH, "raid starts with the approach")
	check(Enemy.barrage_hold_z == raid.hold_z, "the Soviets are held at z %.0f meanwhile" % raid.hold_z)
	check(hud.artillery_label.visible and hud.artillery_label.text.begins_with("AIR RAID"), "HUD: '%s'" % hud.artillery_label.text)
	var n: int = raid._b_time.size()
	check(n >= 16 and n <= 30, "%d bombs planned" % n)
	var inside := 0
	var front := 0
	var near := 0
	var far := 0
	for pos in raid._b_pos:
		if raid.trench_rect.has_point(Vector2(pos.x, pos.z)):
			inside += 1
		if pos.z < 50.0:
			front += 1
		elif pos.z < 90.0:
			near += 1
		else:
			far += 1
	check(inside == 0, "no bomb lands inside the trench")
	check(front > 0 and near > 0 and far > 0, "bombs in front (%d), just behind (%d) and further back (%d)" % [front, near, far])
	check(raid._first_bomb > 8.0 and raid._first_bomb < 14.0, "first bomb lands at %.1f s (engines first)" % raid._first_bomb)
	var p0: Vector3 = raid.plane_position(0, 0.0)
	check(absf(p0.x) > 800.0, "plane 1 starts far away (%.0f m)" % p0.x)
	await seconds(3.0)
	check(raid._engines[0].playing or raid._engines[1].playing or raid._engines[2].playing, "an engine is heard from the start")
	Engine.time_scale = 4.0
	await seconds(4.0) # (timers run on game time) about 8 s into the raid
	check(raid.phase == AirRaid.Phase.BOMBING, "bombs are falling")
	check(not hud.artillery_label.visible, "HUD: no text in the trench while the bombs fall")
	var seen_plane := false
	for node in raid._plane_nodes:
		seen_plane = seen_plane or node.visible
	check(seen_plane, "a plane is drawn")
	var t0 := Time.get_ticks_msec()
	while raid.is_active() and Time.get_ticks_msec() - t0 < 25000:
		await seconds(0.2)
	Engine.time_scale = 1.0
	check(not raid.is_active(), "raid over")
	check(raid.bombs_landed == n, "all %d bombs exploded (%d)" % [n, raid.bombs_landed])
	check(p.health == 100 and not p.is_dead, "crouching in the trench nothing hits you (health %d)" % p.health)
	check(Enemy.barrage_hold_z == INF, "the hold line is gone")

	# In the open: dead.
	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")
	raid.start(true)
	await seconds(0.1)
	var target: Vector3 = raid._b_pos[0]
	p.input.crouch_held = false
	p.is_crouching = false
	p.global_position = target + Vector3(2, 0.3, 0)
	Engine.time_scale = 4.0
	t0 = Time.get_ticks_msec()
	while not p.is_dead and raid.is_active() and Time.get_ticks_msec() - t0 < 25000:
		await seconds(0.2)
	Engine.time_scale = 1.0
	check(p.is_dead, "standing in the open where a bomb lands = dead")
	while raid.is_active():
		await seconds(0.2)

	# Wave 4 has a barrage: the raid waits for it to end, then comes without a hold line.
	raid._on_wave_started(4, 5)
	check(not raid.is_active(), "wave 4 (barrage wave): the raid waits for the artillery")
	arty.barrage_ended.emit()
	await seconds(raid.after_barrage_delay - 1.0)
	check(not raid.is_active(), "...and starts a few seconds after the barrage ended, not at once")
	await seconds(1.5)
	check(raid.is_active() and Enemy.barrage_hold_z == INF, "...then the planes come, the advance is not held")
	raid._finish(false)
	await seconds(0.2)

	# Leaving a match during a raid clears the hold line.
	raid.start(true)
	check(Enemy.barrage_hold_z < INF, "raid started again: hold line set")
	var parent: Node = raid.get_parent()
	parent.remove_child(raid)
	check(Enemy.barrage_hold_z == INF, "match left during a raid -> hold line cleared")
	raid.free()
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
