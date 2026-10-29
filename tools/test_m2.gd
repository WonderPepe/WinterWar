extends SceneTree
## Automated weapon test for Milestone 2 (not part of the game).

var p: Player
var wc: WeaponController
var fails := 0
var hits := 0
var kills := 0

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func seconds(s: float) -> void:
	await create_timer(s).timeout

func aim_at(point: Vector3) -> void:
	var d: Vector3 = point - p.camera.global_position
	p.input.look_yaw = atan2(-d.x, -d.z)
	p.input.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())

func target(n: String) -> TargetDummy:
	return root.get_node("Game/Level/ShootingRange/" + n)

func torso(t: TargetDummy) -> Vector3:
	return t.get_node("Body/Torso").global_position

func _initialize() -> void:
	root.add_child(load("res://scenes/game.tscn").instantiate())
	run()

func run() -> void:
	await frames(5)
	p = get_nodes_in_group("players")[0]
	p.input.set_process(false)
	wc = p.weapons
	wc.hit_confirmed.connect(func(killed: bool) -> void:
		hits += 1
		if killed: kills += 1)
	await seconds(1.0)
	check(wc.loadout.size() == 2, "two weapons in loadout")
	check(wc.get_current_weapon().display_name.begins_with("Mosin"), "starts with Mosin")
	check(wc.get_mag_ammo() == 5 and wc.get_reserve_ammo() == 30, "Mosin ammo 5/30")
	check(wc.holder.visible, "weapon holder visible for local player")

	# --- Mosin: aimed shot at 25 m target ---
	var t25 := target("Target_25m")
	p.input.aim_held = true
	aim_at(torso(t25))
	await seconds(0.5)
	check(wc.is_aiming and absf(p.camera.fov - 45.0) < 1.0, "aiming zooms in (fov %.1f)" % p.camera.fov)
	aim_at(torso(t25))
	await frames(2)
	var pitch_before := p.input.look_pitch
	p.input.fire_held = true
	await frames(3)
	check(wc.get_mag_ammo() == 4, "shot used one round (%d left)" % wc.get_mag_ammo())
	check(p.input.look_pitch > pitch_before + deg_to_rad(2.0), "recoil kicks the view up")
	check(hits == 1 and kills == 1, "hit confirmed and 25 m target knocked down (hits %d kills %d)" % [hits, kills])
	await seconds(0.5)
	check(t25.is_down and absf(t25.body.rotation.x) > 1.0, "target fell over")
	var attached := 0
	for c in t25.body.get_children():
		if c is MeshInstance3D and c.visible and c.mesh is QuadMesh:
			attached += 1
	check(attached == 1, "bullet hole attached to the target")

	# Bolt action: holding the trigger must not fire again
	await seconds(0.3)
	check(wc.get_mag_ammo() == 4, "bolt action does not fire while trigger held")
	p.input.fire_held = false
	await frames(2)
	p.input.fire_held = true
	await frames(3)
	check(wc.get_mag_ammo() == 4, "cannot fire again during bolt cycle")
	p.input.fire_held = false
	await seconds(1.3)
	aim_at(torso(target("Target_100m")))
	await frames(2)
	p.input.fire_held = true
	await frames(3)
	p.input.fire_held = false
	check(wc.get_mag_ammo() == 3, "fires again after the bolt cycle")
	check(kills == 2, "100 m target knocked down by aimed Mosin shot")
	await seconds(3.5)
	check(not t25.is_down, "25 m target stood up again")

	# Reload
	p.input.request_reload()
	await frames(3)
	check(wc.is_reloading, "reload started")
	p.input.fire_held = true
	await frames(5)
	p.input.fire_held = false
	check(wc.get_mag_ammo() == 3, "cannot fire while reloading")
	await seconds(3.2)
	check(not wc.is_reloading and wc.get_mag_ammo() == 5 and wc.get_reserve_ammo() == 28, "reload done: %d/%d" % [wc.get_mag_ammo(), wc.get_reserve_ammo()])

	# --- Switch to Suomi ---
	p.input.request_switch(1)
	await seconds(0.6)
	check(wc.current_slot == 1 and wc.get_current_weapon().display_name.begins_with("Suomi"), "switched to Suomi")
	check(wc.get_mag_ammo() == 70 and wc.get_reserve_ammo() == 140, "Suomi ammo 70/140")
	var t50 := target("Target_50m")
	hits = 0
	kills = 0
	var start_ammo := wc.get_mag_ammo()
	p.input.fire_held = true
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		aim_at(torso(t50)) # a steady player correcting for recoil
		await process_frame
	p.input.fire_held = false
	var fired := start_ammo - wc.get_mag_ammo()
	print("  Suomi fired %d rounds in 1.5 s, hits %d, kills %d" % [fired, hits, kills])
	check(fired >= 17 and fired <= 24, "full-auto fire rate about 14 rounds/s")
	check(hits >= 4 and kills >= 1, "50 m target knocked down by the Suomi")

	# Empty magazine -> dry fire -> automatic reload
	wc.mag_ammo[1] = 0
	await seconds(0.2)
	p.input.fire_held = true
	await frames(3)
	p.input.fire_held = false
	await frames(3)
	check(wc.is_reloading, "empty magazine starts a reload automatically")
	await seconds(4.7)
	check(wc.get_mag_ammo() == 70, "Suomi reloaded to 70 (reserve %d)" % wc.get_reserve_ammo())

	# Sprinting blocks aiming and firing
	p.input.aim_held = false
	p.global_position = Vector3(0, 1, 0)
	p.input.move_dir = Vector2(0, -1)
	p.input.sprint_held = true
	await seconds(0.5)
	var ammo := wc.get_mag_ammo()
	p.input.fire_held = true
	await frames(10)
	p.input.fire_held = false
	check(p.is_sprinting and wc.get_mag_ammo() == ammo, "cannot fire while sprinting")
	p.input.sprint_held = false
	p.input.aim_held = true
	await seconds(0.6)
	check(absf(p.get_speed() - p.walk_speed * 0.75) < 0.35, "slower while aiming (%.2f m/s)" % p.get_speed())
	p.input.move_dir = Vector2.ZERO
	p.input.aim_held = false

	# Impact surfaces: shoot the ground (snow)
	var fx: ImpactEffects = get_first_node_in_group("impact_effects")
	p.input.look_pitch = deg_to_rad(-60)
	await seconds(0.3)
	p.input.fire_held = true
	await frames(2)
	p.input.fire_held = false
	var snow_holes := 0
	for c in fx.get_children():
		if c is MeshInstance3D and c.visible and c.material_override == fx._hole_materials["snow"]:
			snow_holes += 1
	check(snow_holes >= 1, "snow bullet holes on the ground (%d)" % snow_holes)

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit()
