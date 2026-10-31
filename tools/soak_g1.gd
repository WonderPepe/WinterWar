extends Node
## Soak test for G1: real waves against a god-mode player standing in the trench, at 3× speed.
## Prints what the soldiers are doing and whether the line breaks (not part of the game).
##   godot --headless --path . --script tools/run.gd -- tools/soak_g1.gd

func _ready() -> void:
	await get_tree().process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await get_tree().create_timer(0.5).timeout
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.god_mode = true
	p.global_position = Vector3(-10, -1.3, 61)
	var director: MatchDirector = get_tree().get_first_node_in_group("match_director")
	var spawner: WaveSpawner = get_tree().get_first_node_in_group("wave_spawner")
	spawner.time_between_groups = 1.0
	Engine.time_scale = 3.0
	for i in 40:
		await get_tree().create_timer(15.0, true, false, true).timeout # 15 s game time
		var states := {}
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Enemy
			var k: String = Enemy.State.keys()[e.state] + ("(in trench)" if e.is_in_trench() and e.state != Enemy.State.DEAD else "")
			states[k] = states.get(k, 0) + 1
		print("t=%3ds wave %d alive %d in_trench %d result %d %s" % [int(director.match_time), spawner.wave_number, spawner.alive_count, director.in_trench, director.result, states])
		if director.is_over():
			break
	Engine.time_scale = 1.0
	print("RESULT: done")
	get_tree().quit()
