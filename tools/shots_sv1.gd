extends Node
## SV1 screenshots: Soviet soldiers close up (faces, hands, boots) – before/after pictures
## (not part of the game).
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_sv1.gd [prefix]

var _cam: Camera3D
var _walker: Enemy
var _walk_start: Vector3


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[1] if args.size() > 1 else "sv1"
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	game.get_node("HUD").visible = false
	for i in 20:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.set_physics_process(false)
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	for vm in p.weapons._view_models:
		vm.visible = false
	p.weapons.set_process(false)
	p.global_position = Vector3(0, -0.5, 40.0)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.near = 0.05
	get_tree().root.add_child(_cam)
	_cam.make_current()

	var enemies: Node = game.get_node("Enemies")
	var scenes := {"r": "soviet_rifleman", "o": "soviet_officer", "m": "soviet_mg_gunner"}
	# [scene, x, state, kneeling, crouching]
	var lineup := [["r", -3.0, Enemy.State.PATROL, false, false], ["r", -1.5, Enemy.State.ATTACK, false, false],
		["o", 0.0, Enemy.State.PATROL, false, false], ["m", 1.5, Enemy.State.PATROL, false, false],
		["r", 3.0, Enemy.State.ATTACK, false, true], ["r", 4.5, Enemy.State.ATTACK, true, false],
		["r", 6.0, Enemy.State.PATROL, false, false]]
	var s: Array[Enemy] = []
	for i in lineup.size():
		var e: Enemy = load("res://scenes/enemies/%s.tscn" % scenes[lineup[i][0]]).instantiate()
		e.name = "Sv%d" % i
		enemies.add_child(e)
		e.set_physics_process(false)
		var x: float = lineup[i][1]
		e.global_position = Vector3(x, terrain_h(x, 20.0), 20.0)
		e.rotation.y = PI # facing +Z, towards the camera
		e.state = lineup[i][2]
		e.is_kneeling = lineup[i][3]
		e.is_crouching = lineup[i][4]
		s.append(e)
	_walker = s[6]
	_walk_start = _walker.global_position

	await _look(prefix + "_lineup", Vector3(1.5, 1.2, 27.0), Vector3(1.5, 0.8, 20.0), 60)
	await _look(prefix + "_face_front", _head(s[0]) + Vector3(0, 0.0, 0.9), _head(s[0]), 10)
	await _look(prefix + "_face_34", _head(s[0]) + Vector3(0.6, 0.05, 0.65), _head(s[0]), 6)
	await _look(prefix + "_face_side", _head(s[0]) + Vector3(0.9, 0.0, 0.0), _head(s[0]), 6)
	await _look(prefix + "_officer", _head(s[2]) + Vector3(0.35, 0.0, 0.85), _head(s[2]), 6)
	await _look(prefix + "_aim", _head(s[1]) + Vector3(0.5, -0.2, 1.3), _head(s[1]) + Vector3(0, -0.2, 0), 6)
	var c: Vector3 = s[4].global_position
	await _look(prefix + "_crouch_kneel", c + Vector3(3.0, 0.6, 1.8), c + Vector3(0.75, 0.45, 0), 6)
	await _look(prefix + "_feet", c + Vector3(0.75, 0.25, 1.6), c + Vector3(0.75, 0.15, 0), 6)
	var w: Vector3 = _walk_start
	await _look(prefix + "_walk", w + Vector3(3.5, 0.9, 0.5), w + Vector3(0, 0.8, 0.5), 40)
	await _look(prefix + "_hands", _head(s[0]) + Vector3(0.55, -0.55, 0.55), _head(s[0]) + Vector3(0.2, -0.65, 0), 6)
	get_tree().quit()


func _head(e: Enemy) -> Vector3:
	return e.global_position + Vector3(0, 1.6, 0)


func terrain_h(x: float, z: float) -> float:
	return (get_tree().get_first_node_in_group("terrain") as TerrainGenerator).get_height(x, z)


func _process(delta: float) -> void:
	if _walker and is_instance_valid(_walker):
		var off: float = fmod(_walker.global_position.z - _walk_start.z + 1.4 * delta, 3.0)
		_walker.rotation.y = 0.0 # walks away from the camera's side… along -Z/+Z
		_walker.global_position = _walk_start + Vector3(0, 0, off)
		_walker.rotation.y = PI


func _look(n: String, from: Vector3, at: Vector3, frames: int) -> void:
	_cam.look_at_from_position(from, at, Vector3.UP)
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/shots/%s.png" % n)
	print("saved ", n)
