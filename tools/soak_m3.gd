extends Node
## Lets a wave play out against a god-mode player standing in the trench, and reports.
func _ready() -> void:
	await get_tree().process_frame # the root can't take new children while it is adding us
	get_tree().root.add_child(load("res://scenes/game.tscn").instantiate())
	get_tree().root.get_node("Game/PauseMenu").free() # tests drive the game directly
	run()
func run() -> void:
	await get_tree().create_timer(0.3).timeout
	var p: Player = get_tree().get_nodes_in_group("players")[0]
	p.input.set_process(false)
	p.god_mode = true
	var shots := [0]
	Engine.time_scale = 4.0
	for i in 12:
		await get_tree().create_timer(10.0).timeout
		var counts := {}
		var dist_sum := 0.0
		var n := 0
		for e: Enemy in get_tree().get_nodes_in_group("enemies"):
			var k: String = Enemy.State.keys()[e.state]
			counts[k] = counts.get(k, 0) + 1
			dist_sum += Vector2(e.global_position.x - e.attack_point.x, e.global_position.z - e.attack_point.z).length()
			n += 1
		print("t=%3ds  states %s  avg distance to goal %.0f m" % [(i + 1) * 10, counts, dist_sum / maxi(n, 1)])
	get_tree().quit()
