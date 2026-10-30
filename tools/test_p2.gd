extends Node
## Automated test for P2: effects, sound, soldiers (not part of the game).
##   godot --headless --path . --script tools/run.gd -- tools/test_p2.gd

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
	var fx: ImpactEffects = get_tree().get_first_node_in_group("impact_effects")

	# --- After the warm-up no smoke or spray is left in front of the camera ---
	await get_tree().create_timer(0.5).timeout
	var leftover := false
	for sm in fx._smoke:
		leftover = leftover or sm.visible
	check(not leftover, "no smoke left over from the warm-up")

	# --- Audio buses ---
	var sfx: int = AudioServer.get_bus_index(&"SFX")
	check(sfx > 0 and AudioServer.get_bus_index(&"Ambience") > 0 and AudioServer.get_bus_index(&"UI") > 0, "audio buses SFX / Ambience / UI exist")
	check(sfx > 0 and AudioServer.get_bus_effect(sfx, 0) is AudioEffectReverb, "SFX bus has the outdoor echo")
	check(p.weapons.shot_audio.bus == &"SFX", "gunshots go to the SFX bus")

	# --- Ambience ---
	var amb: Ambience = get_tree().root.get_node("Game/Ambience")
	check(amb._wind.playing and (amb._wind.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "wind plays in a loop")
	amb._timer = 0.0
	await frames(2)
	var far_playing := false
	for a in amb._far:
		far_playing = far_playing or a.playing
	check(far_playing, "distant battle sound played")
	p.global_position = Vector3(-30, -1.4, 61) # in the trench
	p.input.crouch_held = true
	await get_tree().create_timer(1.5).timeout
	p.input.crouch_held = false
	check(amb._muffle.cutoff_hz < 5000.0, "outside sounds muffled in the trench (%.0f Hz)" % amb._muffle.cutoff_hz)

	# --- Player: footsteps, breath, drifting snow ---
	var pfx: PlayerFX = p.get_node("PlayerFX")
	check(pfx.drift.top_level and pfx.drift.emitting, "drifting snow around the player (High)")
	check(pfx.breath.get_parent() == p.camera, "breath vapour in front of the camera")
	p.global_position = Vector3(-10, 0.5, 30)
	await get_tree().physics_frame
	var heard_step := false
	for i in 40:
		p.global_position += Vector3(0.1, 0, 0) # walking 0.1 m per frame
		await get_tree().process_frame
		heard_step = heard_step or pfx.footsteps.playing
	check(FootstepSounds.has_any() or not heard_step, "no footstep recordings yet: silent")
	# With a recording for snow (any sound will do for the test) the steps play.
	pfx._streams["snow"] = [load("res://assets/audio/empty_click.wav")] as Array[AudioStream]
	heard_step = false
	for i in 40:
		p.global_position += Vector3(0.1, 0, 0)
		await get_tree().process_frame
		heard_step = heard_step or pfx.footsteps.playing
	check(heard_step, "footsteps play when there are recordings")
	pfx._breath_timer = 0.0
	await frames(2)
	check(pfx.breath.emitting, "breathing out")
	Settings.set_show_breath(false)
	pfx.breath.emitting = false
	pfx._breath_timer = 0.0
	await frames(2)
	check(not pfx.breath.emitting, "breath vapour can be switched off")
	Settings.set_show_breath(true)

	# --- Soldier ---
	var e: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
	get_tree().root.get_node("Game/Enemies").add_child(e)
	e.global_position = Vector3(0, 0, 20)
	e.set_physics_process(false)
	await frames(2)
	var vis: SoldierVisual = e.visual
	var mesh: ArrayMesh = vis._mesh.mesh
	var tris: int = mesh.surface_get_array_index_len(0) / 3 if mesh.surface_get_array_index_len(0) > 0 else mesh.surface_get_array_len(0) / 3
	check(vis._skeleton.get_bone_count() == 12 and tris > 300 and tris < 1500, "soldier: one skinned mesh, 12 bones, %d triangles" % tris)
	check(mesh.get_surface_count() == 1, "soldier is one draw call")
	check(e.muzzle != null and e.muzzle.is_inside_tree(), "muzzle follows the rifle")
	# Walking moves the legs.
	var thigh: int = SoldierMesh.Bone.THIGH_L
	var angles: Array[float] = []
	for i in 30:
		e.global_position += Vector3(0, 0, 0.05)
		await get_tree().process_frame
		angles.append(vis._skeleton.get_bone_pose_rotation(thigh).get_angle())
	check(angles.max() > 0.15, "legs swing when walking (%.2f rad)" % angles.max())
	# Kneeling to fire.
	e.state = Enemy.State.ATTACK
	e.is_kneeling = true
	await get_tree().create_timer(1.0).timeout
	check(vis._skeleton.get_bone_pose_position(SoldierMesh.Bone.HIPS).y < 0.65, "kneels down to fire")
	var muzzle_before: Vector3 = e.muzzle.global_position
	e.show_shot_effects(Vector3(0, 0, 40), Vector3.UP, "snow")
	await frames(3) # the bone attachment follows the bone one frame later
	check(e.muzzle.global_position.distance_to(muzzle_before) > 0.005, "rifle kicks when firing")

	# --- Bullets flying past you crack ---
	p.god_mode = true
	p.global_position = Vector3(0, 0, 60)
	e.global_position = Vector3(0, 0, 10)
	e._target = p
	e._last_known_position = p.global_position
	e.data = e.data.duplicate()
	e.data.base_spread_deg = 1.5 # miss on purpose (mostly)
	e.data.spread_per_100m_deg = 0.0
	e.data.first_shot_multiplier = 1.0
	var before: int = fx.cracks_played
	for i in 20:
		e._shoot()
		await frames(1)
	check(fx.cracks_played > before, "near misses crack past your head (%d of 20)" % (fx.cracks_played - before))

	# --- Getting hit: indicator points at the shooter, soldiers flinch ---
	var hud: HUD = get_tree().root.get_node("Game/HUD")
	p.god_mode = false
	p.health = 100
	e.data.base_spread_deg = 0.0
	e.data.best_aim_multiplier = 0.0
	var hits_before: int = hud.damage_indicator._hits.size()
	for i in 5:
		e._shoot()
	await frames(2)
	check(hud.damage_indicator._hits.size() > hits_before, "damage indicator shows where the hit came from")
	p.god_mode = true
	e.take_damage(10.0, 1, Vector3.ZERO, Vector3.UP)
	await frames(2)
	check(vis._hit > 0.5, "wounded soldier flinches")
	Settings.set_ambience_volume(0.5)
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Ambience")) - (linear_to_db(0.5) - 3.0)) < 0.1, "ambience volume setting")

	# --- Gun smoke ---
	var smoking := func() -> bool:
		for s in fx._smoke:
			if s.emitting:
				return true
		return false
	await get_tree().create_timer(2.0).timeout
	p.weapons._last_smoke_time = 0.0
	p.weapons._fire(p.weapons.get_current_weapon())
	await frames(1)
	check(smoking.call(), "gun smoke after a shot")

	# --- Browser fallback for particle colours (they would be black in WebGL) ---
	var probe := ImpactEffects.make_smoke_emitter(ImpactEffects.make_soft_texture())
	ImpactEffects.web_fallback(probe, true)
	var probe_mat := (probe.mesh as PrimitiveMesh).material as StandardMaterial3D
	check(probe.color_ramp == null and not probe_mat.vertex_color_use_as_albedo and probe_mat.albedo_color.a > 0.1,
		"particles use a material colour (no black vertex colours) and shrink away")
	check(probe.scale_amount_curve.sample(1.0) < 0.01, "browser fallback: particles shrink to nothing")
	probe.free()

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
