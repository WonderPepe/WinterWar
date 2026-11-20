extends Node
## TR1: measures draw calls and triangles for different ground tile counts (not part of the game).
## Static views + the benchmark flight's camera route, no enemies. Needs a GL window (xvfb):
##   godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/bench_tr1.gd [counts]
## counts e.g. "1,4,6,8" (1 = the old single ground mesh).

const VIEWS: Array = [
	# [name, position (feet), yaw deg, pitch deg]
	["trench_south", Vector3(-30, -1.4, 61), 0.0, 2.0],
	["trench_north", Vector3(-30, -1.4, 61), 180.0, 2.0],
	["trench_east", Vector3(-30, -1.4, 61), -90.0, 2.0],
	["overview", Vector3(0, 60, 150), 0.0, -28.0],
	["field_south", Vector3(10, 0, -60), 180.0, 0.0],
	["field_north", Vector3(10, 0, -60), 0.0, 0.0],
]


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var counts: PackedStringArray = (args[1] if args.size() > 1 else "1,4,6,8").split(",")
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	game.get_node("HUD").visible = false
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.set_physics_process(false)
	p.weapons.set_process(false)
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")
	if terrain == null:
		terrain = game.find_child("Terrain", true, false)
	var posts: Array = get_tree().get_nodes_in_group("fire_post")
	var views: Array = VIEWS.duplicate()
	if not posts.is_empty():
		var fp: Vector3 = (posts[1] as Node3D).global_position
		views.push_front(["firepost_south", fp + Vector3(0, 0, 0.3), 0.0, 0.0])
	for c in counts:
		terrain.tiles_per_side = int(c)
		terrain.build()
		var line: String = "tiles %sx%s:" % [c, c]
		for v in views:
			p.global_position = v[1]
			p.input.look_yaw = deg_to_rad(v[2])
			p.input.look_pitch = deg_to_rad(v[3])
			var r: Vector2 = await _measure()
			line += "  %s %d dc / %dk tri" % [v[0], r.x, r.y / 1000.0]
		# Benchmark flight route (same maths as benchmark.gd), sampled every 0.5 s.
		var sum := Vector2.ZERO
		var mx := Vector2.ZERO
		var k: int = 0
		var t: float = 0.0
		while t <= 60.0:
			_place_on_route(p, terrain, t)
			var r: Vector2 = await _measure()
			sum += r
			mx = Vector2(maxf(mx.x, r.x), maxf(mx.y, r.y))
			k += 1
			t += 0.5
		line += "\n   route: avg %d dc / %dk tri, max %d dc / %dk tri" % [
			sum.x / k, sum.y / k / 1000.0, mx.x, mx.y / 1000.0]
		print(line)
	get_tree().quit()


func _measure() -> Vector2:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return Vector2(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


func _place_on_route(p: Player, terrain: TerrainGenerator, time: float) -> void:
	var route: Array = load("res://scripts/game/benchmark.gd").ROUTE
	var i: int = 0
	while i < route.size() - 2 and time > route[i + 1][0]:
		i += 1
	var a: Array = route[i]
	var b: Array = route[i + 1]
	var t: float = smoothstep(a[0], b[0], time)
	var pos: Vector3 = (a[1] as Vector3).lerp(b[1], t)
	var look: Vector3 = (a[2] as Vector3).lerp(b[2], t)
	pos.y += terrain.get_height(pos.x, pos.z)
	p.global_position = pos
	var to_look: Vector3 = look - (pos + Vector3.UP * 1.6)
	p.input.look_yaw = atan2(-to_look.x, -to_look.z)
	p.input.look_pitch = atan2(to_look.y, Vector2(to_look.x, to_look.z).length())
