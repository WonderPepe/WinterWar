extends Node
## V10c: measures what bodies and living soldiers cost (not part of the game). Needs a GL window:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/bench_v10c.gd bodies 24
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/bench_v10c.gd alive 24
## bodies N: N soldiers fall in front of the trench, then draw calls / triangles / frame time
##   are averaged looking south from the trench (0 bodies first, for comparison).
## alive N: the benchmark flight with N soldiers alive at once; prints its results.
## pose N: N soldiers (no AI) 30–150 m in front of the trench; the script time per frame.


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var mode: String = args[1] if args.size() > 1 else "bodies"
	var n: int = int(args[2]) if args.size() > 2 else 24
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if mode == "alive":
		await _alive(n)
	elif mode == "pose":
		await _pose(n)
	else:
		await _bodies(n)
	get_tree().quit()


func _alive(n: int) -> void:
	var bench: Node = load("res://scenes/benchmark.tscn").instantiate()
	bench.set("enemy_count", n)
	get_tree().root.add_child(bench)
	get_tree().current_scene = bench
	var most: int = 0
	var proc: float = 0.0
	var phys: float = 0.0
	var frames: int = 0
	var start: int = Time.get_ticks_msec()
	while str(bench.get("_results_text")) == "" and Time.get_ticks_msec() - start < 90000:
		await get_tree().process_frame
		if Time.get_ticks_msec() - start > 8000: # the first groups are out by then
			frames += 1
			proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		most = maxi(most, get_tree().get_nodes_in_group("enemies").size())
	print("ALIVE %d: most at once %d   process %.2f ms/frame   physics %.2f ms/frame" % [n, most, proc / maxi(frames, 1), phys / maxi(frames, 1)])


func _bodies(n: int) -> void:
	Settings.quality = Settings.Quality.HIGH
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	game.get_node("HUD").visible = false
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.set_physics_process(false)
	p.health = 100000
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	get_tree().get_first_node_in_group("match_director").set_process(false)
	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")
	var cam_at := Vector3(-10, 0, 62)
	cam_at.y = terrain.get_height(cam_at.x, cam_at.z)
	p.global_position = cam_at
	p.input.look_yaw = 0.0 # looking south (-z)
	p.input.look_pitch = deg_to_rad(-4.0)
	await _wait(2.0)
	var before: Dictionary = await _measure(240)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var x: float = rng.randf_range(-45.0, 30.0)
		var z: float = rng.randf_range(-20.0, 50.0)
		var e: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
		e.name = "Bench%d" % i
		e.position = Vector3(x, terrain.get_height(x, z), z)
		e.attack_point = e.position
		game.get_node("Enemies").add_child(e, true)
		e.set_physics_process(false)
	await _wait(0.5)
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Enemy).take_damage(1000.0, 1, (e as Enemy).global_position, Vector3.UP)
	await _wait(9.0) # handed over, baked, soldier nodes removed
	var after: Dictionary = await _measure(240)
	var keeper := game.get_node_or_null("Bodies")
	var kept: int = keeper.get_bodies().size() if keeper else -1
	print("BODIES %d (kept %d): draw calls %.1f -> %.1f  triangles %.0fk -> %.0fk  frame %.2f -> %.2f ms  process %.2f -> %.2f ms" % [
		n, kept, before.dc, after.dc, before.tri / 1000.0, after.tri / 1000.0, before.ms, after.ms, before.proc, after.proc])


func _measure(frames: int) -> Dictionary:
	var dc: float = 0.0
	var tri: float = 0.0
	var ms: float = 0.0
	var proc: float = 0.0
	for i in frames:
		var t0: int = Time.get_ticks_usec()
		await get_tree().process_frame
		ms += (Time.get_ticks_usec() - t0) / 1000.0
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		tri += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	return {"dc": dc / frames, "tri": tri / frames, "ms": ms / frames, "proc": proc / frames}


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _pose(n: int) -> void:
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.set_physics_process(false)
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	get_tree().get_first_node_in_group("match_director").set_process(false)
	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")
	await _wait(1.0)
	var base: Dictionary = await _measure(600)
	for i in n:
		var x: float = -60.0 + 120.0 * i / n
		var z: float = 30.0 - 120.0 * float(i % 6) / 5.0 # 30 … -90: 30–150 m from the trench
		var e: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
		e.position = Vector3(x, terrain.get_height(x, z), z)
		e.attack_point = e.position
		game.get_node("Enemies").add_child(e, true)
		e.set_physics_process(false)
	await _wait(3.0)
	var with: Dictionary = await _measure(1200)
	print("POSE %d: script time %.3f -> %.3f ms/frame (+%.3f ms for the soldiers)" % [n, base.proc, with.proc, with.proc - base.proc])
