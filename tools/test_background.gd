extends Node
## Test for the background sounds (plane flying over once per battle). Not part of the game:
##   godot --headless --path . --script tools/run.gd -- tools/test_background.gd

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ready() -> void:
	await get_tree().process_frame
	Settings.difficulty = 1
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await seconds(0.5)
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.god_mode = true
	var spawner: WaveSpawner = get_tree().get_first_node_in_group("wave_spawner")
	spawner.set_process(false)
	var bg := game.get_node("BackgroundSounds") as BackgroundSounds
	check(bg != null and bg.sounds.size() == 1 and bg.sounds[0] != null, "plane sound is set up")
	check(bg.sounds[0].get_length() > 35.0, "plane recording ~39 s (%.1f s)" % bg.sounds[0].get_length())

	# Wave 1 starts: the plane's wave is picked in the middle of the battle (2 … waves_to_win − 1; 10 battles now).
	spawner.wave_number = 1
	spawner.alive_count = 5
	await seconds(0.2)
	var last_middle: int = (get_tree().get_first_node_in_group("match_director") as MatchDirector).waves_to_win - 1
	check(bg._waves[0] >= 2 and bg._waves[0] <= last_middle, "plays in wave %d (middle of the battle)" % bg._waves[0])
	check(bg._at[0] >= bg.earliest_s and bg._at[0] <= bg.latest_s, "at %.0f s into that wave" % bg._at[0])
	await seconds(0.5)
	check(bg.get_child_count() == 0, "not in wave 1")

	# Its wave, its moment: it starts and flies over.
	bg._at[0] = 0.5
	spawner.wave_number = bg._waves[0]
	await seconds(1.0)
	var fly := bg.get_node_or_null("Flyover0") as AudioStreamPlayer3D
	check(fly != null and fly.playing, "the plane sound starts once its moment comes")
	if fly:
		var start: Vector3 = fly.global_position
		var cam: Vector3 = get_viewport().get_camera_3d().global_position
		await seconds(1.0)
		check(fly.global_position.distance_to(start) > 40.0, "it moves across the sky (%.0f m in 1 s)" % fly.global_position.distance_to(start))
		var flat := Vector2(start.x - cam.x, start.z - cam.z).length()
		check(flat > 400.0 and start.y - cam.y > 60.0, "it starts far away (%.0f m) and high up" % flat)
		# Where it will be when the recording is loudest: (almost) over our head.
		var over: Vector3 = start + (fly.global_position - start) / 1.0 * bg.overhead_at[0]
		check(Vector2(over.x - cam.x, over.z - cam.z).length() < 120.0, "at its loudest it is right overhead (%.0f m to the side)" % Vector2(over.x - cam.x, over.z - cam.z).length())
	# Only once.
	spawner.wave_number += 1
	await seconds(1.0)
	var count := 0
	for c in bg.get_children():
		if c is AudioStreamPlayer3D:
			count += 1
	check(count == 1 and bg._played[0], "only once per battle")
	# When the sound has finished, its player is freed: moving the fly-overs must not touch it
	# (error seen in the editor: "Trying to cast a freed object" in _move_flyovers).
	for node in bg.get_children():
		if node is AudioStreamPlayer3D:
			node.free()
	bg._process(0.016)
	check(bg._flying.is_empty(), "a finished fly-over is forgotten without errors")
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
