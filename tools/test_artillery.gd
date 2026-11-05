extends Node
## Test for the artillery barrage (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_artillery.gd

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
	var normal: DifficultyData = load("res://resources/difficulty/normal.tres")
	var flags: Array[int] = []
	for i in normal.waves.size():
		if normal.waves[i].barrage:
			flags.append(i + 1)
			check(normal.waves[i].officers > 0, "barrage wave %d has an officer (he whistles at the end)" % (i + 1))
	check(flags == [4, 6, 8, 10], "Normal: barrage before waves %s" % str(flags))

	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await seconds(0.5)
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	var spawner: WaveSpawner = get_tree().get_first_node_in_group("wave_spawner")
	spawner.set_process(false)
	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")
	var arty := game.get_node("ArtilleryBarrage") as ArtilleryBarrage
	var hud: HUD = game.get_node("HUD")
	check(arty != null and arty.sound != null and arty.shell_times.size() == 47, "barrage set up: recording + 47 shells")
	var map: RID = p.get_world_3d().navigation_map
	for i in 120:
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			break
		await get_tree().physics_frame
	await seconds(0.3)

	# Soldiers of the wave: a rifleman and an officer far out, heading for the trench.
	var r: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
	r.name = "ArtyRifleman"
	r.position = Vector3(-20, terrain.get_height(-20, -60) + 0.1, -60)
	r.attack_point = Vector3(-20, terrain.get_height(-20, 38), 38)
	r.rotation.y = PI
	var o: Enemy = load("res://scenes/enemies/soviet_officer.tscn").instantiate()
	o.name = "ArtyOfficer"
	o.position = Vector3(-14, terrain.get_height(-14, -62) + 0.1, -62)
	o.attack_point = Vector3(-14, terrain.get_height(-14, 34), 34)
	o.rotation.y = PI
	game.get_node("Enemies").add_child(r, true)
	game.get_node("Enemies").add_child(o, true)
	await seconds(0.2)
	r.state = Enemy.State.PATROL
	o.state = Enemy.State.PATROL
	o._whistle_timer = 999.0

	# The player waits down in the trench, crouching (so the rifles can't reach him either).
	p.global_position = Vector3(-30, -1.3, 61)
	p.input.crouch_held = true
	await seconds(0.3)
	check(ArtilleryBarrage.is_covered(p), "in the trench, crouching = under cover")
	p.global_position = Vector3(0, -2.5, 66.0)
	check(not ArtilleryBarrage.is_covered(p), "bunker middle = NOT covered")
	p.global_position = Vector3(0, -2.5, 65.2)
	check(not ArtilleryBarrage.is_covered(p), "bunker opening = NOT covered")
	p.global_position = Vector3(-2.0, -2.5, 68.4)
	check(ArtilleryBarrage.is_covered(p), "bunker back corner (left) = covered")
	p.global_position = Vector3(2.0, -2.5, 68.4)
	check(ArtilleryBarrage.is_covered(p), "bunker back corner (right) = covered")
	p.global_position = Vector3(-30, -1.3, 61)
	p.is_crouching = false
	check(not ArtilleryBarrage.is_covered(p) and ArtilleryBarrage.is_in_shelter(p), "standing in the trench = NOT covered (shrapnel)")
	p.is_crouching = true

	# Wave 4 starts → the barrage begins by itself.
	spawner.wave_number = 3
	spawner._start_wave()
	await seconds(0.3)
	check(arty.phase == ArtilleryBarrage.Phase.WARNING, "wave 4 starts with an artillery warning")
	check(hud.artillery_label.visible and hud.artillery_label.text.begins_with("ARTILLERY!"), "HUD: '%s'" % hud.artillery_label.text)
	check(Enemy.barrage_hold_z < INF, "the Soviets may not come closer than z %.0f meanwhile" % Enemy.barrage_hold_z)
	check(arty._warning_audio.playing, "the distant guns are heard during the warning")
	check(is_equal_approx(arty.warning_time, 6.5), "the warning lasts 6.5 s")
	Engine.time_scale = 2.0
	await seconds(7.5) # 6.5 s warning, then the first shells
	check(arty.phase == ArtilleryBarrage.Phase.FIRING and arty.shells_fired > 0, "then the shells fall (%d so far)" % arty.shells_fired)
	check(not hud.artillery_label.visible, "HUD: no text in the trench while the shells fall")
	arty._play_close_burst(p.global_position + Vector3(5, 0, 0))
	check(arty._close_audio.playing, "a shell bursting 5 m away plays the close explosion")
	arty._close_audio.stop()
	arty._play_close_burst(p.global_position + Vector3(60, 0, 0))
	check(not arty._close_audio.playing, "a far shell does not")
	var z_start: float = r.global_position.z
	await seconds(9.0)
	check(p.health == 100 and not p.is_dead, "in the trench nothing hits you (health %d)" % p.health)
	check(r.global_position.z > z_start + 10.0, "the soldiers move up during the barrage (z %.0f → %.0f)" % [z_start, r.global_position.z])
	# Climb out into the open: deadly.
	p.input.crouch_held = false
	p.global_position = Vector3(-30, terrain.get_height(-30, 30) + 0.2, 30)
	await seconds(0.3)
	check(not ArtilleryBarrage.is_covered(p) and hud.artillery_label.text.begins_with("GET INTO"), "out in the open: '%s'" % hud.artillery_label.text)
	var t0 := Time.get_ticks_msec()
	while not p.is_dead and Time.get_ticks_msec() - t0 < 8000:
		await seconds(0.2)
	check(p.is_dead or p.health < 100, "out in the open the shells get you (health %d, dead %s)" % [p.health, p.is_dead])
	t0 = Time.get_ticks_msec()
	while arty.is_active() and Time.get_ticks_msec() - t0 < 20000:
		await seconds(0.2)
	var closest_z: float = maxf(r.global_position.z, o.global_position.z)
	check(not arty.is_active() and arty.shells_fired == 47, "barrage over after all 47 shells")
	check(closest_z <= arty.hold_z + 0.6 and closest_z > -40.0, "…the soldiers wait close, but not too close (z %.1f, limit %.0f)" % [closest_z, arty.hold_z])
	check(Enemy.barrage_hold_z == INF, "the limit is gone")
	await seconds(0.2)
	check(o.whistle_count >= 1, "the officer blows his whistle when it lifts (%d)" % o.whistle_count)
	check(not hud.artillery_label.visible, "no text when the barrage lifts")
	var z_end: float = maxf(r.global_position.z, o.global_position.z)
	await seconds(6.0)
	var z_now: float = maxf(r.global_position.z, o.global_position.z)
	check(z_now > z_end + 3.0, "…and the attack goes on (front man z %.0f → %.0f; %s / %s)" % [z_end, z_now,
			Enemy.State.keys()[r.state], Enemy.State.keys()[o.state]])
	Engine.time_scale = 1.0

	# A wave without a barrage: nothing happens.
	spawner._start_wave() # wave 5
	await seconds(0.3)
	check(not arty.is_active(), "wave 5: no barrage")

	# Bug fix: leaving a match during a barrage (Esc → Main Menu, or losing → Play again) must
	# not leave the hold line behind – the next match's soldiers would stop 50 m short.
	arty.start()
	check(Enemy.barrage_hold_z < INF, "barrage started again: hold line set")
	var parent: Node = arty.get_parent()
	parent.remove_child(arty) # like the game scene being freed
	check(Enemy.barrage_hold_z == INF, "match left during a barrage → hold line cleared")
	arty.free()
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
