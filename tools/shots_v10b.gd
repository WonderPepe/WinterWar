extends Node
## Screenshots for V10b (bodies stay, tank tracks; not part of the game). Saved in tools/shots/:
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_v10b.gd [prefix]
## Views: tracks from the trench / from the field / close up; bodies fresh / after a night; both
## in the dark of battle 6.

var _out: String
var _prefix: String = "v10b_"
var _terrain: TerrainGenerator
var _game: Node
var _cam: Camera3D


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		_prefix = args[1]
	_out = ProjectSettings.globalize_path("res://tools/shots/")
	DirAccess.make_dir_recursive_absolute(_out)
	_game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(_game)
	_game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.god_mode = true
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	get_tree().get_first_node_in_group("match_director").set_process(false)
	_terrain = get_tree().get_first_node_in_group("terrain")
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	var keeper := _game.get_node("Bodies") as BodyKeeper
	var dusk := _game.get_node("Dusk") as DuskLight
	dusk.set_process(false) # the script chooses the look
	dusk._show_battle(3) # the clear freezing day
	_game.get_node("HUD").visible = false
	await get_tree().create_timer(3.0).timeout # shader warm-up

	# A tank drives a long bend from the forest edge towards the trench (the script drives it).
	var tank: Tank = spawner.spawn_tank(1)
	tank.set_physics_process(false)
	var pts: Array[Vector3] = []
	for i in 400:
		var t: float = i / 399.0
		pts.append(Vector3(lerpf(-25.0, 12.0, t) + sin(t * 5.0) * 6.0, 0.0, lerpf(-70.0, 28.0, t)))
	for i in pts.size():
		var here: Vector3 = pts[i]
		var ahead: Vector3 = pts[mini(i + 3, pts.size() - 1)]
		if i < pts.size() - 3:
			tank._yaw = tank._heading_to(here, ahead)
		tank._place_on_ground(here, 0.0)
		await get_tree().process_frame
	# Fallen soldiers out in front of the trench.
	var spots: Array[Vector3] = [Vector3(-6, 0, 34), Vector3(-2, 0, 38), Vector3(3, 0, 36), Vector3(7, 0, 41),
			Vector3(-9, 0, 42), Vector3(0, 0, 44), Vector3(5, 0, 31), Vector3(-4, 0, 29)]
	var i_spot: int = 0
	for s in spots:
		var e: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
		e.name = "Shot%d" % i_spot
		i_spot += 1
		e.position = Vector3(s.x, _terrain.get_height(s.x, s.z), s.z)
		e.rotation.y = PI + (i_spot % 3 - 1) * 0.5
		e.attack_point = e.position
		_game.get_node("Enemies").add_child(e, true)
		e.set_physics_process(false)
	await get_tree().create_timer(0.3).timeout
	for n in get_tree().get_nodes_in_group("enemies"):
		(n as Enemy).take_damage(1000.0, 1, (n as Enemy).global_position, Vector3.UP)
	await get_tree().create_timer(3.6).timeout
	print("bodies kept: ", keeper.get_bodies().size(), "  strips: ", (_game.get_node("TankTracks") as TankTracks).strips_laid)

	# 1. From a firing position in the trench.
	p.global_position = Vector3(2, -1.3, 53.5)
	_look_at(p, tank.global_position + Vector3(-6, 0.5, -20))
	await get_tree().create_timer(0.4).timeout
	await _shot("trench")
	# 2.-4. Free camera.
	_cam = Camera3D.new()
	_game.add_child(_cam)
	_cam.fov = 60
	_cam.current = true
	await _view("field", tank.global_position + Vector3(9, 2.2, 8), tank.global_position + Vector3(-4, 0, -14))
	await _view("behind_tank", tank.global_position + tank.global_basis.z * 7.0 + Vector3(0, 2.6, 0), tank.global_position)
	await _view("tracks_close", pts[330] + Vector3(3.5, 1.7, 2.0), pts[320])
	await _view("tracks_far", pts[150] + Vector3(30, 1.7, 40), pts[150])
	await _view("bodies", Vector3(1, _terrain.get_height(1, 47) + 1.7, 47), Vector3(0, 0, 37))
	await _view("body_close", Vector3(-4.5, _terrain.get_height(-4.5, 40.5) + 1.5, 40.5), Vector3(-2, _terrain.get_height(-2, 38), 38))
	# After a night: snow on the bodies, tracks gone.
	keeper.new_day()
	await _view("bodies_next_day", Vector3(1, _terrain.get_height(1, 47) + 1.7, 47), Vector3(0, 0, 37))
	await _view("body_close_next_day", Vector3(-4.5, _terrain.get_height(-4.5, 40.5) + 1.5, 40.5), Vector3(-2, _terrain.get_height(-2, 38), 38))
	keeper.new_day()
	await _view("body_close_two_nights", Vector3(-4.5, _terrain.get_height(-4.5, 40.5) + 1.5, 40.5), Vector3(-2, _terrain.get_height(-2, 38), 38))
	# The dark morning of battle 6 and the snowstorm of battle 2.
	dusk._show_battle(6)
	await _view("dark_field", tank.global_position + Vector3(9, 2.2, 8), tank.global_position + Vector3(-4, 0, -14))
	dusk._show_battle(2)
	await _view("storm_tracks", pts[330] + Vector3(3.5, 1.7, 2.0), pts[320])
	dusk._show_battle(10)
	await _view("dusk_field", tank.global_position + Vector3(9, 2.2, 8), tank.global_position + Vector3(-4, 0, -14))
	get_tree().quit()


func _view(file: String, from: Vector3, to: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(to)
	await get_tree().create_timer(0.4).timeout
	await _shot(file)


func _look_at(p: Player, target: Vector3) -> void:
	var d: Vector3 = target - p.head.global_position
	p.input.look_yaw = atan2(-d.x, -d.z)
	p.input.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + _prefix + file + ".png")
	print("saved ", file)
