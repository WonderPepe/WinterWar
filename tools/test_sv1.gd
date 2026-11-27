extends Node
## Automated test for SV1: the Soviet soldier's face, and hand and foot bones (not part of the game).
##   godot --headless --path . --script tools/run.gd -- tools/test_sv1.gd

const B := SoldierMesh.Bone

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.add_child(load("res://scenes/game.tscn").instantiate())
	get_tree().root.get_node("Game/PauseMenu").free()
	run()


func run() -> void:
	await frames(10)
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)

	# --- Skeleton: 4 new bones at the end, the old numbers unchanged ---
	check(SoldierMesh.BONE_NAMES.size() == 16 and SoldierMesh.BONE_PARENTS.size() == 16 and SoldierMesh.BONE_REST.size() == 16,
			"16 bones (12 + hands + feet)")
	check(B.HEAD == 2 and B.SHIN_R == 10 and B.RIFLE == 11, "old bone numbers unchanged")
	check(SoldierMesh.BONE_PARENTS[B.HAND_L] == B.FOREARM_L and SoldierMesh.BONE_PARENTS[B.HAND_R] == B.FOREARM_R,
			"hands hang on the forearms")
	check(SoldierMesh.BONE_PARENTS[B.FOOT_L] == B.SHIN_L and SoldierMesh.BONE_PARENTS[B.FOOT_R] == B.SHIN_R,
			"feet hang on the shins")
	var ankle: Vector3 = SoldierMesh.rest_global(B.FOOT_L)
	check(absf(ankle.y - 0.1) < 0.01, "ankle 0.1 m above the ground (%.3f)" % ankle.y)

	# --- The meshes ---
	for k in 3:
		var m: ArrayMesh = SoldierMesh.get_mesh(k)
		var a: Array = m.surface_get_arrays(0)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var idx: Variant = a[Mesh.ARRAY_INDEX]
		var tris: int = ((idx as PackedInt32Array).size() if idx != null else verts.size()) / 3
		check(m.get_surface_count() == 1, "kind %d: one surface (one draw call)" % k)
		check(tris > 800 and tris <= 1450, "kind %d: %d triangles (budget ≤ 1 450, SV1b)" % [k, tris])
		var face_front := 0
		var face_back_ok := true
		var on_bone := {}
		var neck_blend := false
		for i in verts.size():
			if absf(cols[i].a - SoldierMesh.FACE.a) < 0.01:
				if verts[i].z < -0.06 and uvs[i].x > 0.0 and uvs[i].x < 1.0 and uvs[i].y > 0.0 and uvs[i].y < 1.0:
					face_front += 1
				if verts[i].z > 0.0 and uvs[i] != Vector2(-1, -1):
					face_back_ok = false
			for j in 4:
				if weights[i * 4 + j] > 0.0:
					on_bone[bones[i * 4 + j]] = true
			var on_spine := false
			var on_head := false
			for j in 4:
				if weights[i * 4 + j] > 0.05:
					on_spine = on_spine or bones[i * 4 + j] == B.SPINE
					on_head = on_head or bones[i * 4 + j] == B.HEAD
			neck_blend = neck_blend or (on_spine and on_head)
		check(face_front > 30, "kind %d: the face is mapped onto the face texture (%d corners)" % [k, face_front])
		check(face_back_ok, "kind %d: nothing painted on the back of the head" % k)
		check(on_bone.has(B.HAND_L) and on_bone.has(B.HAND_R) and on_bone.has(B.FOOT_L) and on_bone.has(B.FOOT_R),
				"kind %d: hands and feet move with their own bones" % k)
		check(neck_blend, "kind %d: the neck blends from the chest to the head" % k)

	# --- The face texture ---
	var mat: ShaderMaterial = load("res://resources/materials/soldier.tres")
	var tex: Texture2D = mat.get_shader_parameter("face_texture")
	check(tex != null, "soldier material has the face texture")
	if tex:
		var img: Image = tex.get_image()
		if img.is_compressed():
			img.decompress()
		check(img.get_width() == 128 and img.get_height() == 128, "face texture 128 × 128")
		check(img.get_pixel(0, 0).a < 0.01 and img.get_pixel(127, 127).a < 0.01 and img.get_pixel(127, 0).a < 0.01,
				"face texture is empty at its edges (the rest of the head stays plain skin)")
		var eye: Vector2 = SoldierMesh.face_uv(Vector3(0.033, 1.6168, -0.1)) * 128.0
		check(img.get_pixel(int(eye.x), int(eye.y)).a > 0.9 and img.get_pixel(int(eye.x), int(eye.y)).get_luminance() < 0.3,
				"the eyes are painted where the eye sockets are")

	# --- The feet bend at the ankle ---
	var q: Quaternion = SoldierMesh.foot_pose(Quaternion(Vector3.RIGHT, 1.1), Quaternion(Vector3.RIGHT, -1.8), 1.0)
	check(absf(q.get_euler().x - SoldierMesh.ANKLE_UP) < 0.001, "deep crouch: toes up only as far as the ankle goes")
	q = SoldierMesh.foot_pose(Quaternion(Vector3.RIGHT, 0.3), Quaternion(Vector3.RIGHT, -0.5), 1.0)
	check(absf(q.get_euler().x - 0.2) < 0.001, "slightly bent leg: sole flat (%.2f)" % q.get_euler().x)

	var scene: PackedScene = load("res://scenes/enemies/soviet_rifleman.tscn")
	var e: Enemy = scene.instantiate()
	get_tree().root.get_node("Game/Enemies").add_child(e)
	e.set_physics_process(false)
	var ground: float = (get_tree().get_first_node_in_group("terrain") as TerrainGenerator).get_height(0, 20)
	e.global_position = Vector3(0, ground, 20)
	e.state = Enemy.State.ATTACK
	await frames(40)
	var vis: SoldierVisual = e.visual
	check(vis._skeleton.get_bone_count() == 16, "soldier skeleton has 16 bones")
	var stand_toe: float = _toe_dir(vis, B.FOOT_L).y
	check(absf(stand_toe) < 0.1, "standing: feet flat (toe direction y %.2f)" % stand_toe)
	e.is_crouching = true
	await frames(60)
	var crouch_toe: float = _toe_dir(vis, B.FOOT_L).y
	check(absf(crouch_toe) < 0.35, "crouching: soles nearly flat, not stuck into the snow (toe y %.2f)" % crouch_toe)
	var low: float = _lowest_boot(vis) - ground
	check(low > -0.06, "crouching: boots stay on the snow (lowest point %.3f m)" % low)
	e.is_crouching = false
	e.is_kneeling = true
	await frames(60)
	check(_toe_dir(vis, B.FOOT_R).y < -0.6, "kneeling: the back foot rests on its toes (toe y %.2f)" % _toe_dir(vis, B.FOOT_R).y)
	check(absf(_toe_dir(vis, B.FOOT_L).y) < 0.15, "kneeling: the front foot flat (toe y %.2f)" % _toe_dir(vis, B.FOOT_L).y)
	e.is_kneeling = false
	# Walking: the toes push off behind.
	var lowest_toe := 1.0
	for i in 60:
		e.global_position += Vector3(0, 0, 0.05)
		await get_tree().process_frame
		lowest_toe = minf(lowest_toe, _toe_dir(vis, B.FOOT_L).y)
	check(lowest_toe < -0.2, "walking: toes push off (toe y down to %.2f)" % lowest_toe)

	# --- A body is still baked (V10c) with the new bones ---
	var src: Array = SoldierMesh.get_mesh(0).surface_get_arrays(0)
	var vcount: int = (src[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if src[Mesh.ARRAY_INDEX] != null \
			else (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	vis.become_body(170.0, false) # (the BodyKeeper does this first)
	vis.bake_body()
	check(vis.baked.size() == Mesh.ARRAY_MAX and (vis.baked[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == vcount,
			"a body is still frozen into a plain shape (%d corners)" % vcount)
	e.queue_free()

	# --- The Finns (co-op) share the skeleton; their boots bend too ---
	var fm: Array = FinnMesh.get_mesh(0).surface_get_arrays(0)
	var finn_foot := false
	for b in (fm[Mesh.ARRAY_BONES] as PackedInt32Array):
		finn_foot = finn_foot or b == B.FOOT_L
	check(finn_foot, "the Finn's boots hang on the foot bones")
	check(p.body.get_node("Skeleton").get_bone_count() == 16, "the Finn's body has the same 16 bones")

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


## Direction the toes point (world), from the foot bone.
func _toe_dir(vis: SoldierVisual, bone: int) -> Vector3:
	var sk: Skeleton3D = vis._skeleton
	return ((sk.global_transform * sk.get_bone_global_pose(bone)).basis * Vector3.FORWARD).normalized()


## Lowest point of the boot soles as he is posed now (world height).
func _lowest_boot(vis: SoldierVisual) -> float:
	var posed: ArrayMesh = vis._pose_on_cpu()
	var verts: PackedVector3Array = posed.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = vis._mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_BONES]
	var xf: Transform3D = vis._mesh.global_transform
	var low := INF
	for i in verts.size():
		if bones[i * 4] == B.FOOT_L or bones[i * 4] == B.FOOT_R:
			low = minf(low, (xf * verts[i]).y)
	return low
