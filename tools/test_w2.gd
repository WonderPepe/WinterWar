extends Node
## Automated test for W2: first-person arms, closer aiming, Maxim sights/belt/heat (not part of the game).
##   godot --headless --path . --script tools/run.gd -- tools/test_w2.gd

var p: Player
var wc: WeaponController
var arms: FirstPersonArms
var gun: MountedGun
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
	get_tree().root.add_child(load("res://scenes/game.tscn").instantiate())
	get_tree().root.get_node("Game/PauseMenu").free()
	run()


## How far the palm of a mitten is from where it should be (metres).
func hand_error(right: bool, grip: Transform3D) -> float:
	var bone: int = FirstPersonArms.Bone.HAND_R if right else FirstPersonArms.Bone.HAND_L
	var pose: Transform3D = arms.global_transform * arms.skeleton.get_bone_global_pose(bone)
	var contact := FirstPersonArms.PALM_CONTACT
	if not right:
		contact.x = -contact.x
	return (pose * contact).distance_to(grip.origin)


func run() -> void:
	await frames(5)
	p = get_tree().get_first_node_in_group("players")
	wc = p.weapons
	arms = p.camera.get_node_or_null("Arms") as FirstPersonArms
	p.input.set_process(false)
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	p.global_position = Vector3(-30, 0.0, 40.0)
	await physics(3)

	# --- Arms on the hand weapons ---
	check(arms != null, "first-person arms under the camera")
	await seconds(0.5)
	check(arms.visible, "arms shown for your own player")
	check(arms._mesh_instance.mesh.get_surface_count() == 1, "arms are one mesh (one draw call)")
	for slot in [0, 1]:
		wc.current_slot = slot
		for aim in [false, true]:
			p.input.aim_held = aim
			await seconds(0.7)
			var grips: Array[Transform3D] = wc.get_hand_grips()
			check(grips.size() == 2, "slot %d: two grip points" % slot)
			if grips.size() == 2:
				var er: float = hand_error(true, grips[0])
				var el: float = hand_error(false, grips[1])
				check(er < 0.01 and el < 0.01, "slot %d %s: mittens on the grips (%.3f / %.3f m off)" % [slot, "aimed" if aim else "hip", er, el])
	p.input.aim_held = false
	check(is_equal_approx(wc._view_models[0].ads_eye_distance, 0.39) and is_equal_approx(wc._view_models[1].ads_eye_distance, 0.35),
		"aiming closer to the gun (Mosin 0.39 m, Suomi 0.35 m; was 0.42 / 0.40)")

	# Bolt: the right hand goes to the bolt knob and back.
	wc.current_slot = 0
	await seconds(0.6)
	var vm: ViewModel = wc._view_models[0]
	var rest_r: Vector3 = wc.get_hand_grips()[0].origin
	vm.play_bolt_cycle(1.2)
	await seconds(0.5)
	var bolt_r: Vector3 = wc.get_hand_grips()[0].origin
	check(vm.bolt_hand > 0.9 and bolt_r.distance_to(rest_r) > 0.05, "right hand on the bolt while cycling (%.2f m away)" % bolt_r.distance_to(rest_r))
	await seconds(1.0)
	check(vm.bolt_hand < 0.01, "right hand back on the grip")
	vm.play_reload(2.0)
	await seconds(0.5)
	check(vm.reload_hand > 0.5, "a hand goes to the pouch when reloading")
	await seconds(2.0)

	# Suomi drum: the left hand holds it; a reload pulls it out, drops it, puts a new one in.
	wc.current_slot = 1
	await seconds(0.6)
	var svm: ViewModel = wc._view_models[1]
	var drum: Node3D = svm._magazine
	check(drum != null and drum.find_child("SuomiKP31_Drum", true, false) != null, "Suomi drum is a movable part")
	var drum_rest: Vector3 = drum.global_position
	var palm_l: Vector3 = wc.get_hand_grips()[1].origin
	check(palm_l.distance_to(drum_rest) < 0.09 and palm_l.y < drum_rest.y, "left hand under the drum (%.3f m from its centre)" % palm_l.distance_to(drum_rest))
	var dropped_before: int = ViewModel._dropped_magazines.size()
	svm.play_reload(3.0)
	await seconds(0.65) # ~0.22 of the reload: being pulled out
	var off_hand: float = (svm.model.global_transform * (svm._left_hand_on_magazine(svm.magazine_progress) * svm._magazine_in_hand)).origin.distance_to(drum.global_position)
	check(svm.magazine_progress > 0.15 and off_hand < 0.005, "the drum moves with the left hand")
	check(drum.position.distance_to(svm._magazine_rest.origin) > 0.06, "the drum is pulled out of the gun")
	await seconds(0.45) # ~0.37: dropped, hand on the way to the pouch
	check(not drum.visible, "the old drum has left the hand")
	var dropped_now: int = ViewModel._dropped_magazines.size()
	check(dropped_now == dropped_before + 1 or dropped_now == ViewModel.MAX_DROPPED_MAGAZINES, "the old drum is dropped")
	var body: RigidBody3D = ViewModel._dropped_magazines[-1] as RigidBody3D
	var y0: float = body.global_position.y
	await seconds(0.9) # ~0.67: the new drum comes up to the gun
	check(drum.visible, "a new drum in the hand")
	check(body.global_position.y < y0 - 0.2, "the dropped drum falls (%.2f m)" % (y0 - body.global_position.y))
	await seconds(1.3)
	check(svm.magazine_progress < 0.0 and drum.position.distance_to(svm._magazine_rest.origin) < 0.001, "new drum seated in the gun")
	check(hand_error(false, wc.get_hand_grips()[1]) < 0.01, "left hand back on the drum")

	# W3 (open bolt): the cocking handle never moves when firing; a reload ends with the right
	# hand pulling it back and letting it snap forward. Empty cases fly out at every shot.
	var handle: Node3D = svm._cocking_handle
	check(handle != null and handle.find_child("SuomiKP31_Handle", true, false) != null, "Suomi cocking handle is a movable part")
	check(svm._bolt_grip != null and svm._bolt_grip.get_parent() == handle, "BoltGrip rides on the cocking handle")
	for i in 3:
		svm.play_fire(0.025, 2.0)
		await frames(2)
	check(handle.position.length() < 0.0001, "the cocking handle does not move when firing")
	check(svm.cases_in_flight() == 3, "one case flies out per shot (%d)" % svm.cases_in_flight())
	var case_node: Node3D = svm._cases[(svm._next_case + svm._cases.size() - 1) % svm._cases.size()]
	var port: Vector3 = svm._ejection_port.global_position
	await seconds(0.15)
	var case_moved: Vector3 = svm.model.global_basis.orthonormalized().inverse() * (case_node.global_position - port)
	check(case_moved.x > 0.15, "the case flies out to the right (%.2f m)" % case_moved.x)
	for i in 20:
		svm.play_fire(0.025, 2.0)
	check(svm.cases_in_flight() <= ViewModel.CASE_POOL_SIZE and svm._cases.size() == ViewModel.CASE_POOL_SIZE, "cases are reused (pool of %d)" % ViewModel.CASE_POOL_SIZE)
	await seconds(0.6)
	check(svm.cases_in_flight() == 0, "cases are gone after %.1f s" % ViewModel.CASE_LIFETIME)
	svm.play_reload(3.0)
	await seconds(3.0 * 0.85)
	var knob: Vector3 = svm._bolt_grip.global_position
	check(handle.position.z > svm.cocking_travel * 0.8, "the handle is pulled back when cocking (%.3f m)" % handle.position.z)
	check(wc.get_hand_grips()[0].origin.distance_to(knob) < 0.01, "right hand on the cocking handle")
	await seconds(3.0 * 0.05)
	check(handle.position.z < 0.001, "the handle snaps forward")
	await seconds(3.0 * 0.15)
	check(svm.bolt_hand < 0.01 and hand_error(true, wc.get_hand_grips()[0]) < 0.01, "right hand back on the grip after cocking")
	check(svm.anim_offset.length() < 0.001 and svm.anim_rotation.length() < 0.001, "the gun is back at rest after the reload")
	wc.current_slot = 0
	await seconds(0.6)

	# Dead: no arms.
	p.take_damage(1000.0, -1, p.global_position, Vector3.UP)
	await frames(3)
	check(not arms.visible, "arms hidden when dead")
	await seconds(5.5)
	check(not p.is_dead and arms.visible, "arms back after respawning")

	# --- Maxim ---
	gun = get_tree().get_first_node_in_group("mounted_guns")
	check(gun._turn_pivot != null and gun._turn_pivot.get_child_count() >= 20, "turning parts moved to TurnPivot")
	check(gun._belt_anim != null and gun._belt_anim.has_animation(&"feed/belt"), "belt-feed animation re-pointed")
	check(gun.data.heat_per_shot > 0.0, "Maxim heats up (WeaponData)")
	p.global_position = gun.exit_point.global_position
	await physics(3)
	p.input.request_interact()
	await physics(3)
	await frames(3)
	check(p.get_mounted_gun() == gun, "on the Maxim")
	check(arms.visible, "arms shown on the Maxim")
	var grips: Array[Transform3D] = wc.get_hand_grips()
	await frames(2)
	grips = wc.get_hand_grips()
	check(hand_error(true, grips[0]) < 0.01 and hand_error(false, grips[1]) < 0.01, "mittens on the Maxim's spade grips")
	# The parts follow the aim.
	var karabin := gun._turn_pivot.get_node("karabin_001_3") as Node3D
	p.input.add_look(0.0, deg_to_rad(-20.0))
	await frames(3)
	var fwd: Vector3 = -karabin.global_basis.z.normalized()
	var aim_dir: Vector3 = -gun.pivot.global_basis.z
	check(fwd.angle_to(aim_dir) < deg_to_rad(1.0), "the model turns with the aim")
	# Sights: right mouse puts the eye at SightEye.
	p.input.look_yaw = gun.get_base_yaw()
	p.input.look_pitch = 0.0
	p.input.aim_held = true
	await seconds(0.6)
	check(p.camera.global_position.distance_to(gun.sight_eye.global_position) < 0.01, "aiming looks through the Maxim's sights")
	var to_front: Vector3 = (gun.muzzle.global_position - p.camera.global_position)
	check(to_front.normalized().dot(-p.camera.global_basis.z) > 0.98, "the barrel points where the sights look")
	p.input.aim_held = false
	await seconds(0.5)

	# Belt animation plays while firing.
	var cartridge := gun._turn_pivot.get_node("pocisk_5") as Node3D
	var c_rest: Vector3 = cartridge.position
	p.input.fire_held = true
	await seconds(0.05)
	await frames(2)
	var moved: bool = cartridge.position.distance_to(c_rest) > 0.01
	p.input.fire_held = false
	check(moved, "belt moves while firing")

	# Heat: short bursts stay cool, non-stop fire boils it.
	gun.heat = 0.0
	for i in 6:
		p.input.fire_held = true
		await seconds(1.4)
		p.input.fire_held = false
		await seconds(1.6)
		gun.ammo = 250
	check(gun.heat > 0.05 and gun.heat < gun.data.steam_heat and not gun.is_overheated, "short bursts don't overheat (heat %.2f)" % gun.heat)
	gun.heat = 0.99 # (≈390 rounds of non-stop fire; near the top a hot gun heats slowly)
	gun.ammo = 250
	p.input.fire_held = true
	await seconds(1.0)
	check(gun.is_overheated, "long fire overheats the gun")
	check(gun._steam.emitting, "steam from the water jacket")
	var ammo_before: int = gun.ammo
	await seconds(0.5)
	check(gun.ammo == ammo_before, "no firing while overheated")
	p.input.fire_held = false
	var hud: HUD = get_tree().root.get_node("Game/HUD")
	await frames(2)
	check(hud.overheat_label.visible and hud.heat_row.visible, "HUD shows heat and OVERHEATED")
	gun.heat = gun.data.overheat_recover_heat + 0.01
	await seconds(0.5)
	check(not gun.is_overheated, "fires again after cooling to about half")
	var cfg: SceneReplicationConfig = (gun.get_node("GunSync") as MultiplayerSynchronizer).replication_config
	check(cfg.has_property(NodePath(".:heat")) and cfg.has_property(NodePath(".:is_overheated")), "heat is synced to co-op players")

	# Belt reload: right hand to the feed block.
	gun.ammo = 100
	p.input.request_reload()
	await seconds(1.5)
	grips = wc.get_hand_grips()
	check(grips[0].origin.distance_to(gun.belt_grip.global_position) < 0.02, "right hand feeds the new belt")
	# v0.1.3: the gunner stays behind the sights during a new belt.
	p.input.aim_held = true
	await seconds(0.5)
	check(wc.is_aiming and wc._aim_t > 0.99, "aiming through the sights continues during a new belt")
	gun._reload_timer = 0.0
	await seconds(0.3)
	# v0.1.3: no view jolt at every round, and no downward drift at the elevation limit.
	p.input.add_look(deg_to_rad(20.0), 0.0)
	await seconds(0.3)
	gun.heat = 0.0
	gun.ammo = 250
	var pitch0: float = p.input.look_pitch
	var last_cam: Vector3 = p.camera.global_position
	var jolt := 0.0
	p.input.fire_held = true
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await frames(1)
		jolt = maxf(jolt, p.camera.global_position.distance_to(last_cam))
		last_cam = p.camera.global_position
	p.input.fire_held = false
	await seconds(0.8)
	check(wc.is_aiming and jolt < 0.01, "steady sight picture while firing (max %.3f m/frame)" % jolt)
	check(absf(p.input.look_pitch - pitch0) < deg_to_rad(0.2), "recoil doesn't drag the aim down at the elevation limit")
	p.input.aim_held = false

	# Off the gun: camera back, heat bar hidden.
	p.input.request_interact()
	await physics(3)
	await frames(3)
	check(p.get_mounted_gun() == null and p.camera.position.length() < 0.001, "camera back to normal off the gun")
	check(not hud.heat_row.visible, "heat bar only on the Maxim")

	# Bad generated sounds removed (owner's request): reload and hurt use real recordings only.
	for w: WeaponData in [wc.loadout[0], wc.loadout[1], gun.data]:
		check(w.reload_sound == null and not w.recording_name.is_empty(), "%s: no generated reload sound, recordings name '%s'" % [w.display_name, w.recording_name])
	check(hud.hurt_sound.stream == null or RecordedSounds.get_sounds("hurt").size() > 0, "no generated hurt sound")

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
