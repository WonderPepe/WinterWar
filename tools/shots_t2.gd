extends Node
## Screenshots of the Molotov cocktail (T2, not part of the game). Saved in tools/shots/:
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_t2.gd

var _out: String


func _ready() -> void:
	await get_tree().process_frame
	_out = ProjectSettings.globalize_path("res://tools/shots/")
	DirAccess.make_dir_recursive_absolute(_out)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.god_mode = true
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	await get_tree().create_timer(3.0).timeout # shader warm-up
	var m: MolotovHandler = p.molotov
	var manager: MolotovManager = get_tree().get_first_node_in_group("molotovs")

	# 1. The box in the trench, with the prompt.
	var crate: MolotovCrate = get_tree().get_nodes_in_group("molotov_crates")[1]
	var side: Vector3 = crate.global_basis.z * signf(61.0 - crate.global_position.z) * signf(crate.global_basis.z.z)
	p.global_position = crate.global_position + side * 1.3 + Vector3(0, 0.1, 0)
	await get_tree().create_timer(0.3).timeout
	_look_at(p, crate.global_position + Vector3(0, 0.2, 0))
	await get_tree().create_timer(0.5).timeout
	await _shot("t2_crate")
	p.input.request_interact()
	await get_tree().create_timer(0.3).timeout

	# 2. Bottle in the hand / lighting / lit and aimed, looking out over the parapet.
	p.global_position = Vector3(10, -1.3, 61)
	p.input.look_yaw = deg_to_rad(5.0)
	p.input.look_pitch = deg_to_rad(6.0)
	p.input.request_molotov()
	await get_tree().create_timer(0.6).timeout
	await _shot("t2_held")
	p.input.aim_held = true
	await get_tree().create_timer(0.75).timeout
	await _shot("t2_lighting")
	await get_tree().create_timer(1.2).timeout
	await _shot("t2_lit_aim")
	p.input.aim_held = false
	m.phase = MolotovHandler.Phase.NONE # (put away for the next pictures)

	# 3. A tank parked at the edge; the bottle flies onto its engine deck.
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	var tank: Tank = spawner.spawn_tank(1)
	await get_tree().create_timer(0.3).timeout
	tank._distance = tank._route_length - 0.5
	await get_tree().create_timer(2.0).timeout
	var deck: Vector3 = tank.global_transform * tank.engine_deck.get_center()
	manager.throw(deck + Vector3(-1.0, 3.0, 4.0), Vector3(1.6, -1.0, -6.4), null)
	p.global_position = Vector3(-2, -1.3, 62)
	_look_at(p, tank.global_position + Vector3(0, 1.5, 0))
	await get_tree().create_timer(0.35).timeout
	await _shot("t2_flight")
	await get_tree().create_timer(2.5).timeout
	await _shot("t2_tank_burning")
	await get_tree().create_timer(2.5).timeout
	await _shot("t2_crew")

	# 4. Fuel burning on the snow.
	manager.drop_at(Vector3(3, terrain_y(3, 50), 50), -1)
	_look_at(p, Vector3(3, 0.5, 50))
	await get_tree().create_timer(1.0).timeout
	await _shot("t2_ground_fire")
	get_tree().quit()


func terrain_y(x: float, z: float) -> float:
	return (get_tree().get_first_node_in_group("terrain") as TerrainGenerator).get_height(x, z)


func _look_at(p: Player, target: Vector3) -> void:
	var d: Vector3 = target - p.head.global_position
	p.input.look_yaw = atan2(-d.x, -d.z)
	p.input.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + file + ".png")
	print("saved ", file)
