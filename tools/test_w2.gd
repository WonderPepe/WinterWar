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
	gun._reload_timer = 0.0
	await seconds(0.3)

	# Off the gun: camera back, heat bar hidden.
	p.input.request_interact()
	await physics(3)
	await frames(3)
	check(p.get_mounted_gun() == null and p.camera.position.length() < 0.001, "camera back to normal off the gun")
	check(not hud.heat_row.visible, "heat bar only on the Maxim")

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
