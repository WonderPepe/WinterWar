extends Node
## Automated test for NET2b: the Finnish soldier body the other players see (not part of the game).
##   godot --headless --path . --script tools/run.gd -- tools/test_net2b.gd

var game: Node
var p: Player   # this computer's own player
var f: Player   # "another player" (peer 2) – his body is shown here
var fails := 0

## Soviet meshes since SV1 (face, hands, feet; was: before NET2b) – size:hash of vertex, normal,
## colour, uv, bones, weights arrays –
## the shared building / IK changes must not change them.
const SOVIET_SUMS: Array[String] = [
	"37340:758458690 37340:4089141141 49784:1737282994 24896:2427581663 49784:3579069488 49784:4136879783 ",
	"36800:3965116961 36800:2483468167 49064:3555122023 24536:4055232797 49064:925592836 49064:1474376202 ",
	"41228:942174889 41228:2951092215 54968:1676514419 27488:1077694273 54968:1459856078 54968:1677021567 ",
]


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	run()


func _sum(m: ArrayMesh) -> String:
	var a: Array = m.surface_get_arrays(0)
	var s := ""
	for i in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		s += str(var_to_bytes(a[i]).size()) + ":" + str(hash(var_to_bytes(a[i]))) + " "
	return s


func _hand(body: PlayerBody, fore: int) -> Vector3:
	var sk: Skeleton3D = body.get_node("Skeleton")
	return sk.global_transform * (sk.get_bone_global_pose(fore) * Vector3(0, -SoldierMesh.ARM_LOWER, 0))


func _bone_y(body: PlayerBody, bone: int) -> float:
	var sk: Skeleton3D = body.get_node("Skeleton")
	return (sk.global_transform * sk.get_bone_global_pose(bone)).origin.y - body.get_parent().global_position.y


func run() -> void:
	await frames(5)
	p = get_tree().get_nodes_in_group("players")[0]
	p.input.set_process(false)
	p.god_mode = true
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	await frames(30)

	# --- the mesh ---
	for k in 3:
		check(_sum(SoldierMesh.get_mesh(k)) == SOVIET_SUMS[k], "Soviet soldier mesh %d is exactly as before" % k)
	for g in [FinnMesh.Gun.MOSIN, FinnMesh.Gun.SUOMI]:
		var m: ArrayMesh = FinnMesh.get_mesh(g)
		var tris: int = (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		check(m.get_surface_count() == 1, "Finn mesh %d is one surface (one draw call)" % g)
		check(tris > 400 and tris < 1100, "Finn mesh %d is low-poly (%d triangles)" % [g, tris])
	check(FinnMesh.get_mesh(0) != FinnMesh.get_mesh(1), "Mosin and Suomi versions are different meshes")
	var cols: PackedColorArray = FinnMesh.get_mesh(0).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = FinnMesh.get_mesh(0).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var elbow_min := 1.0
	var brightest := 0.0
	for i in verts.size():
		if cols[i].a > 0.75:
			brightest = maxf(brightest, cols[i].r)
			if verts[i].distance_to(Vector3(0.22, 1.13, 0.0)) < 0.04:
				elbow_min = minf(elbow_min, cols[i].r)
	check(brightest < 0.85, "smock is dirty off-white, not bright white (max red %.2f)" % brightest)
	check(elbow_min < FinnMesh.SMOCK.r - 0.05, "grime on the elbows (%.2f) vs. clean smock (%.2f)" % [elbow_min, FinnMesh.SMOCK.r])

	# --- own body hidden, another player's shown ---
	check(not p.has_node("BodyMesh"), "the grey capsule is gone")
	check(p.has_node("Body") and p.body is PlayerBody, "Player has its PlayerBody (Body)")
	check(not p.body.visible, "your own body is hidden")
	f = load("res://scenes/player.tscn").instantiate()
	f.name = "2"
	p.get_parent().add_child(f)
	f.set_physics_process(false)
	f.input.set_process(false)
	f.molotov.set_physics_process(false) # (its host rules would message a peer that does not exist)
	f.global_position = Vector3(6.0, 0.0, 22.0)
	await frames(10)
	var b: PlayerBody = f.body
	check(b.visible, "another player's body is shown")
	check(b.get_node("Skeleton/Mesh").mesh == FinnMesh.get_mesh(0), "he starts with the Mosin")
	check(b.get_node("Skeleton").get_bone_count() == 16, "same 16-bone skeleton as the Soviets (SV1: + hands, feet)")
	var cfg: SceneReplicationConfig = (f.get_node("StateSync") as MultiplayerSynchronizer).replication_config
	check(cfg.get_properties().size() == 16, "only NET3's time stamp added to the synced state (StateSync has %d properties)" % cfg.get_properties().size())

	# --- turns with his view ---
	f.input.look_yaw = deg_to_rad(90.0)
	await frames(3)
	var facing: Vector3 = -b.global_basis.z
	check(facing.dot(Vector3(-1, 0, 0)) > 0.99, "the body turns with his view (faces %s)" % str(facing))
	f.input.look_yaw = 0.0
	await frames(30)
	var head_stand: float = _bone_y(b, SoldierMesh.Bone.HEAD)
	check(head_stand > 1.35 and head_stand < 1.6, "standing: head bone at %.2f m" % head_stand)

	# --- looking up raises the gun ---
	var muzzle_level: float = b.muzzle.global_position.y
	f.input.look_pitch = deg_to_rad(40.0)
	await frames(40)
	check(b.muzzle.global_position.y > muzzle_level + 0.2, "looking up raises the muzzle (%.2f → %.2f)" % [muzzle_level, b.muzzle.global_position.y])
	f.input.look_pitch = 0.0
	# --- aiming: shouldered ---
	f.input.aim_held = true
	await frames(40)
	var aim_y: float = b.muzzle.global_position.y - f.global_position.y
	check(aim_y > 1.35, "aiming: the gun is at the shoulder (muzzle at %.2f m)" % aim_y)
	f.input.aim_held = false
	await frames(30)
	var right: Vector3 = _hand(b, SoldierMesh.Bone.FOREARM_R)
	var grip: Vector3 = b.get_node("Skeleton").global_transform * (b.get_node("Skeleton") as Skeleton3D).get_bone_global_pose(SoldierMesh.Bone.RIFLE) * FinnMesh.grip_for(0)
	check(right.distance_to(grip) < 0.08, "right hand on the grip (%.2f m off)" % right.distance_to(grip))

	# --- crouch ---
	f.is_crouching = true
	await frames(40)
	var hips_crouch: float = _bone_y(b, SoldierMesh.Bone.HIPS)
	var head_crouch: float = _bone_y(b, SoldierMesh.Bone.HEAD)
	check(hips_crouch < 0.6, "crouching: hips down to %.2f m" % hips_crouch)
	check(head_crouch < 1.15, "crouching: head down to %.2f m (capsule 1.1 m)" % head_crouch)
	f.is_crouching = false
	await frames(30)

	# --- walking moves the legs ---
	var thigh_before: Quaternion = (b.get_node("Skeleton") as Skeleton3D).get_bone_pose_rotation(SoldierMesh.Bone.THIGH_L)
	var max_swing := 0.0
	for i in 40:
		f.global_position += Vector3(0, 0, -4.0 / 60.0)
		await get_tree().process_frame
		var q: Quaternion = (b.get_node("Skeleton") as Skeleton3D).get_bone_pose_rotation(SoldierMesh.Bone.THIGH_L)
		max_swing = maxf(max_swing, q.angle_to(thigh_before))
	check(max_swing > 0.2, "walking swings the legs (%.2f rad)" % max_swing)
	await frames(30)

	# --- weapon switch ---
	f.weapons.current_slot = 1
	await frames(3)
	check(b.gun == FinnMesh.Gun.SUOMI and b.get_node("Skeleton/Mesh").mesh == FinnMesh.get_mesh(1), "switch to the Suomi changes the gun in his hands")
	check(b.muzzle.position.is_equal_approx(FinnMesh.MUZZLE_SUOMI), "muzzle moves to the Suomi's")
	f.weapons.current_slot = 0
	await frames(3)
	check(b.gun == FinnMesh.Gun.MOSIN, "and back to the Mosin")

	# --- his shot: flash at his gun's muzzle, recoil ---
	var fx: ImpactEffects = get_tree().get_first_node_in_group("impact_effects")
	f.weapons._play_remote_fire_effects()
	check(b._kick > 0.9, "his shot kicks the gun back")
	var near := false
	for c in fx.get_children():
		var n3 := c as Node3D
		if n3 and n3.visible and n3.global_position.distance_to(b.muzzle.global_position) < 0.3:
			near = true
	check(near, "the muzzle flash shows at his gun's muzzle")

	# --- hands busy: the gun goes onto his back ---
	f.molotov.count = 1
	f.molotov.phase = MolotovHandler.Phase.HELD
	await frames(30)
	check(b._hands() == PlayerBody.Hands.BOTTLE, "Molotov in hand: bottle pose")
	check(b._bottle != null and b._bottle.visible, "the bottle shows in his right hand")
	var gun_z: float = (b.get_node("Skeleton") as Skeleton3D).get_bone_pose_position(SoldierMesh.Bone.RIFLE).z
	check(gun_z > 0.1, "the gun is on his back (z %.2f)" % gun_z)
	f.molotov.phase = MolotovHandler.Phase.NONE
	await frames(30)
	check(b._bottle == null or not b._bottle.visible, "bottle gone again")
	f.is_climbing = true
	await frames(5)
	check(b._hands() == PlayerBody.Hands.CLIMB, "climbing pose")
	f.is_climbing = false
	f.is_bandaging = true
	await frames(5)
	check(b._hands() == PlayerBody.Hands.BANDAGE, "bandaging pose")
	f.is_bandaging = false

	# --- on the Maxim: hands on the spade grips ---
	var gun := get_tree().get_first_node_in_group("mounted_guns") as MountedGun
	if gun:
		f.global_position = gun.get_node("SeatPoint").global_position if gun.has_node("SeatPoint") else gun.global_position + gun.global_basis.z * 0.9
		gun.mount(f)
		f.input.look_yaw = gun.get_base_yaw()
		await frames(40)
		check(b._hands() == PlayerBody.Hands.MAXIM, "on the Maxim: Maxim pose")
		var grips: Array[Transform3D] = gun.get_hand_grips()
		var dr: float = _hand(b, SoldierMesh.Bone.FOREARM_R).distance_to(grips[0].origin)
		var dl: float = _hand(b, SoldierMesh.Bone.FOREARM_L).distance_to(grips[1].origin)
		check(dr < 0.12 and dl < 0.12, "hands on the Maxim's grips (%.2f / %.2f m off)" % [dr, dl])
		gun.release()
		await frames(10)
	else:
		check(false, "found the Maxim")

	# --- dead: falls over; respawn: on his feet ---
	f.global_position = Vector3(6.0, 0.0, 22.0)
	f.is_dead = true
	await get_tree().create_timer(1.0).timeout
	check(absf(rad_to_deg(b.rotation.x)) > 80.0, "dead: the body lies in the snow (tipped %.0f°)" % rad_to_deg(b.rotation.x))
	check(b._hands() == PlayerBody.Hands.DEAD, "dead pose")
	f.is_dead = false
	await frames(5)
	check(b.rotation.is_zero_approx(), "respawned: standing again")
	var moved_before: Vector3 = f.global_position
	f.global_position += Vector3(30, 0, 0) # a teleport (respawn) is not a step
	await frames(2)
	check(b._speed < 1.0, "a teleport doesn't make him run (speed %.2f)" % b._speed)
	f.global_position = moved_before

	# --- your own body never shows, even dead ---
	p.is_dead = true
	await frames(5)
	check(not p.body.visible, "your own body stays hidden when you die")
	p.is_dead = false

	f.queue_free()
	await frames(3)
	print("NET2b: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)
