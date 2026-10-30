extends Node
## Automated test for the weapons milestone W1: imported models + the Maxim (not part of the game).
##   godot --headless --path . --script tools/run.gd -- tools/test_w1.gd

var p: Player
var wc: WeaponController
var gun: MountedGun
var fails := 0
var hits := 0
var kills := 0


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


func aim_at(point: Vector3) -> void:
	var d: Vector3 = point - p.camera.global_position
	p.input.look_yaw = atan2(-d.x, -d.z)
	p.input.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	p.input.add_look(0.0, 0.0) # apply the gun's limits


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.add_child(load("res://scenes/game.tscn").instantiate())
	get_tree().root.get_node("Game/PauseMenu").free()
	run()


func run() -> void:
	await frames(5)
	p = get_tree().get_first_node_in_group("players")
	wc = p.weapons
	p.input.set_process(false) # the test presses the buttons
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	wc.hit_confirmed.connect(func(killed: bool) -> void:
		hits += 1
		if killed:
			kills += 1)

	# --- Imported hand weapons ---
	for vm in wc._view_models:
		check(vm.get_node_or_null("Model/Mesh") != null, "%s uses the imported model" % vm.name)
	check(wc._view_models[0].bolt != null and wc._view_models[0].bolt.get_child_count() >= 4, "Mosin bolt parts gathered for the bolt animation")
	var hidden_clip := wc._view_models[0].find_child("LP_Clip", true, false) as Node3D
	check(hidden_clip != null and not hidden_clip.visible, "loose Mosin parts hidden")

	# --- Maxim exists in the bunker ---
	gun = get_tree().get_first_node_in_group("mounted_guns")
	check(gun != null and gun.data != null and gun.data.display_name.begins_with("Maxim"), "Maxim placed in the level")
	check(gun.pivot.find_child("karabin_001_3", true, false) != null, "gun parts turn with the Pivot")
	check(InputMap.has_action("interact") and InputMap.action_get_events("interact")[0].physical_keycode == KEY_F, "F = interact")

	# Too far away: F does nothing.
	p.global_position = Vector3(-30, -1.4, 61)
	await physics(3)
	p.input.request_interact()
	await physics(3)
	check(p.get_mounted_gun() == null, "F far from the gun does nothing")

	# Walk up and press F.
	p.global_position = gun.exit_point.global_position
	await physics(3)
	check(p.find_usable_gun() == gun, "gun usable when standing next to it")
	p.input.request_interact()
	await physics(3)
	await frames(2)
	check(p.get_mounted_gun() == gun and gun.user_id == p.get_peer_id(), "F mounts the Maxim")
	check(p.global_position.distance_to(gun.seat.global_position) < 0.05, "player placed at the gun")
	check(not wc.holder.visible, "hand weapon hidden on the gun")
	check(wc.get_current_weapon() == gun.data and wc.get_mag_ammo() == 250 and wc.get_reserve_ammo() == -1, "HUD reads the Maxim's belt (250 / ∞)")

	# Can't turn further than the mount allows.
	p.input.add_look(deg_to_rad(40.0), deg_to_rad(90.0))
	var rel_yaw: float = rad_to_deg(wrapf(p.input.look_yaw - gun.get_base_yaw(), -PI, PI))
	check(rel_yaw <= gun.traverse_left_deg + 0.01, "traverse limited to the left (%.1f°)" % rel_yaw)
	p.input.add_look(0.0, deg_to_rad(-180.0))
	var right_yaw: float = rad_to_deg(wrapf(p.input.look_yaw - gun.get_base_yaw(), -PI, PI))
	check(right_yaw >= -gun.traverse_right_deg - 0.01, "traverse limited to the right (%.1f°)" % right_yaw)
	rel_yaw = right_yaw
	check(rad_to_deg(p.input.look_pitch) <= gun.elevation_max_deg + 0.01, "elevation limited")
	await frames(2)
	check(absf(rad_to_deg(gun.pivot.rotation.y) - rel_yaw) < 0.5, "gun turns with the view")

	# At the edges of the traverse/elevation the view still goes out of the firing slit.
	var blocked: Array[String] = []
	for corner in [[gun.traverse_left_deg, gun.elevation_max_deg], [gun.traverse_left_deg, gun.elevation_min_deg],
			[-gun.traverse_right_deg, gun.elevation_max_deg], [-gun.traverse_right_deg, gun.elevation_min_deg], [0.0, 0.0]]:
		var dir := Basis.from_euler(Vector3(deg_to_rad(corner[1]), gun.get_base_yaw() + deg_to_rad(corner[0]), 0.0)) * Vector3.FORWARD
		var from: Vector3 = gun.seat.global_position + Vector3(0, 1.6, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 4.0, 0b1)
		q.exclude = [gun.get_rid()]
		var h: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
		if not h.is_empty():
			blocked.append("%s at %.1f m" % [str(corner), from.distance_to(h.position)])
	check(blocked.is_empty(), "every aim the gun allows fits through the slit %s" % str(blocked))

	# Movement keys don't move you off the gun.
	p.input.move_dir = Vector2(0, -1)
	await physics(10)
	check(p.global_position.distance_to(gun.seat.global_position) < 0.05, "can't walk away while on the gun")
	p.input.move_dir = Vector2.ZERO

	# Fire a burst at a target out in front of the bunker.
	var dummy: TargetDummy = load("res://scenes/props/target_dummy.tscn").instantiate()
	get_tree().root.get_node("Game/Level").add_child(dummy)
	dummy.global_position = Vector3(-6, -0.4, 30) # ~36 m in front of the slit
	await physics(3)
	aim_at(dummy.get_node("Body/Torso").global_position)
	await frames(5)
	var before: int = gun.ammo
	p.input.fire_held = true
	await seconds(1.0)
	p.input.fire_held = false
	await frames(5)
	var fired: int = before - gun.ammo
	check(fired >= 7 and fired <= 12, "Maxim fires ~580 rounds/min (%d rounds in 1 s)" % fired)
	check(hits > 0, "bullets go out of the firing slit and hit the target (%d hits)" % hits)
	check(wc.mag_ammo[0] == 5, "hand weapon ammo untouched")

	# New belt.
	p.input.request_reload()
	await frames(3)
	check(gun.is_reloading and wc.is_reloading_now(), "R loads a new belt")
	gun._reload_timer = 0.05
	await seconds(0.2)
	check(not gun.is_reloading and gun.ammo == 250, "belt full again")

	# Leave with F.
	p.input.request_interact()
	await physics(3)
	check(p.get_mounted_gun() == null and gun.is_free(), "F leaves the gun")
	check(p.global_position.distance_to(gun.exit_point.global_position) < 0.1, "placed beside the gun")
	await frames(3)
	check(wc.holder.visible, "hand weapon back")

	# Dying on the gun frees it.
	p.global_position = gun.exit_point.global_position
	await physics(2)
	p.input.request_interact()
	await physics(3)
	p.take_damage(1000.0, -1, p.global_position, Vector3.UP)
	await frames(3)
	check(gun.is_free() and p.get_mounted_gun() == null, "dying frees the gun")

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
