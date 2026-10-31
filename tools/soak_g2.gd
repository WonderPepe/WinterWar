extends Node
## G2 soak test (not part of the game): real waves at 3× speed against a simple "defender bot"
## in the trench (god mode) that fires a Mosin round every 1.5 s at a random soldier it can
## see – most rounds miss by a little, so suppression, officers and MG teams all get exercised.
##   godot --headless --path . --script tools/run.gd -- tools/soak_g2.gd [waves]

var hits_on_player := 0


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var max_report_waves: int = int(args[1]) if args.size() > 1 else 5
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await get_tree().create_timer(0.5).timeout
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.god_mode = true
	p.global_position = Vector3(-10, -1.3, 61)
	p.hurt_from.connect(func(_s: Vector3) -> void: hits_on_player += 1)
	var director: MatchDirector = get_tree().get_first_node_in_group("match_director")
	var spawner: WaveSpawner = get_tree().get_first_node_in_group("wave_spawner")
	var mosin: WeaponData = load("res://resources/weapons/mosin_m28_30.tres")
	spawner.time_between_groups = 1.5
	Engine.time_scale = 3.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var max_prone := 0
	var whistles := 0
	var mg_deployed := 0
	var mg_rounds := 0
	var t := 0.0
	var report := 0.0
	while t < 1200.0 and not director.is_over() and spawner.wave_number <= max_report_waves:
		await get_tree().create_timer(1.5).timeout
		t += 1.5
		report += 1.5
		# The bot fires one round at a random soldier in the open.
		var targets: Array[Enemy] = []
		var prone := 0
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Enemy
			if e.state == Enemy.State.DEAD:
				continue
			if e.is_prone:
				prone += 1
			if e.global_position.distance_to(p.global_position) < 180.0:
				targets.append(e)
		max_prone = maxi(max_prone, prone)
		if not targets.is_empty():
			var e: Enemy = targets[rng.randi() % targets.size()]
			var origin: Vector3 = p.head.global_position + Vector3(0, 0.4, 0)
			var height: float = 0.3 if e.is_prone else (0.8 if e.is_kneeling else 1.2)
			var aim: Vector3 = e.global_position + Vector3(rng.randf_range(-1.5, 1.5), height + rng.randf_range(-0.4, 0.6), 0)
			p.weapons.resolve_shot(origin, (aim - origin).normalized(), mosin, [] as Array[RID])
		if report >= 15.0:
			report = 0.0
			var states := {}
			var w := 0
			var deployed := 0
			for node in get_tree().get_nodes_in_group("enemies"):
				var e := node as Enemy
				w += e.whistle_count
				if e.data.kind == EnemyData.Kind.MG_GUNNER and e.is_deployed() and e.state != Enemy.State.DEAD:
					deployed += 1
					mg_rounds = maxi(mg_rounds, e.data.mg_magazine - e.mg_ammo)
				if e.state == Enemy.State.DEAD:
					continue
				var k: String = EnemyData.Kind.keys()[e.data.kind].substr(0, 3) + "_" + Enemy.State.keys()[e.state] + ("(prone)" if e.is_prone else "")
				states[k] = states.get(k, 0) + 1
			whistles = maxi(whistles, w)
			mg_deployed = maxi(mg_deployed, deployed)
			print("t=%4ds wave %d alive %2d in_trench %d hits_on_player %3d %s" % [int(director.match_time), spawner.wave_number, spawner.alive_count, director.in_trench, hits_on_player, states])
	Engine.time_scale = 1.0
	print("max prone at once %d, whistles seen %d, MG teams deployed at once %d, result %d" % [max_prone, whistles, mg_deployed, director.result])
	print("RESULT: done")
	get_tree().quit()
