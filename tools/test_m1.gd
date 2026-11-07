extends Node
## Automated movement test for Milestone 1 (not part of the game).

var game: Node
var p: Player
var fails := 0

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func set_input(dir: Vector2, sprint := false, crouch := false) -> void:
	p.input.move_dir = dir
	p.input.sprint_held = sprint
	p.input.crouch_held = crouch

func teleport(pos: Vector3, yaw := 0.0) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.input.look_yaw = yaw

func _ready() -> void:
	await get_tree().process_frame # the root can't take new children while it is adding us
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free() # tests drive the game directly
	run()

func run() -> void:
	await frames(5)
	var players := get_tree().get_nodes_in_group("players")
	check(players.size() == 1, "exactly one player spawned (got %d)" % players.size())
	p = players[0]
	p.input.set_process(false) # headless: drive input from the test
	check(p.name == "1", "player named after peer id 1")
	check(p.camera.current, "local camera is current")
	await frames(60)
	check(p.is_on_floor(), "player standing on trench floor")
	check(absf(p.global_position.y + 1.4) < 0.15, "spawn y on trench floor (y=%.2f)" % p.global_position.y)

	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")
	var lo := 999.0
	var hi := -999.0
	for x in range(-150, 151, 5):
		for z in range(-150, 151, 5):
			var h := terrain.get_height(x, z)
			lo = minf(lo, h); hi = maxf(hi, h)
	print("terrain height range %.2f .. %.2f" % [lo, hi])

	# Walk along the trench (x direction) -> yaw -90deg faces +x
	# (L1: the trench has short legs now - start at the west end of the 6 m straight at x = -34 … -28)
	teleport(Vector3(-33.6, -1.3, 61), 0.0)
	await frames(20)
	set_input(Vector2(1, 0))  # strafe right = +x
	await frames(36)
	check(absf(p.get_speed() - p.walk_speed) < 0.4, "walk speed %.2f" % p.get_speed())

	# Sprint forward in open field
	teleport(Vector3(0, terrain.get_height(0, 0) + 0.5, 0), 0.0)
	await frames(30)
	var st0 := p.stamina
	set_input(Vector2(0, -1), true)
	await frames(60)
	check(p.is_sprinting and absf(p.get_speed() - p.sprint_speed) < 0.5, "sprint speed %.2f" % p.get_speed())
	check(p.stamina < st0 - 15.0, "stamina drains (%.1f -> %.1f)" % [st0, p.stamina])
	await frames(300)
	check(not p.is_sprinting, "sprint stops when stamina runs out (stamina %.1f)" % p.stamina)
	set_input(Vector2.ZERO)
	await frames(150)
	check(p.stamina > 20.0, "stamina regenerates (%.1f)" % p.stamina)

	# Crouch
	set_input(Vector2(0, -1), false, true)
	await frames(60)
	var cap := p.collision.shape as CapsuleShape3D
	check(p.is_crouching and absf(p.get_speed() - p.crouch_speed) < 0.3, "crouch speed %.2f" % p.get_speed())
	check(absf(cap.height - p.crouch_height) < 0.01, "capsule shrinks to %.2f" % cap.height)
	set_input(Vector2.ZERO)
	await frames(60)
	check(not p.is_crouching and absf(cap.height - p.stand_height) < 0.01, "stands up again")

	# Jump
	await frames(10)
	p.input.request_jump()
	await frames(10)
	check(not p.is_on_floor() and p.velocity.y > 0.5, "jump leaves the ground")
	await frames(90)
	check(p.is_on_floor(), "lands again")

	# Deep snow zone at (-45, -20)
	teleport(Vector3(-45, terrain.get_height(-45, -20) + 0.3, -20), 0.0)
	await frames(30)
	check(p.is_in_deep_snow(), "detects deep snow")
	set_input(Vector2(0, -1))
	await frames(40)
	check(absf(p.get_speed() - p.walk_speed * p.deep_snow_multiplier) < 0.3, "deep snow speed %.2f" % p.get_speed())
	set_input(Vector2.ZERO)
	teleport(Vector3(-45, terrain.get_height(-45, 20) + 0.3, 20))
	await frames(20)
	check(not p.is_in_deep_snow(), "leaves deep snow")

	# Exit ramp at x=40: from the trench, walk toward +z (yaw 180deg faces +z)
	teleport(Vector3(40, -1.3, 63.5), PI)
	await frames(20)
	set_input(Vector2(0, -1))
	await frames(240)
	print("  ramp end position ", p.global_position)
	check(p.global_position.z > 71.0 and absf(p.global_position.y - terrain.get_height(p.global_position.x, p.global_position.z)) < 0.2, "climbs out via exit ramp onto the ground")
	set_input(Vector2.ZERO)

	# Bunker at x=0: standing should be blocked by the low entrance, crouching gets in
	teleport(Vector3(0, -1.3, 63.2), PI)
	await frames(20)
	set_input(Vector2(0, -1))
	await frames(120)
	print("  standing in front of bunker: z=%.2f" % p.global_position.z)
	check(p.global_position.z < 65.2, "standing player blocked by bunker entrance")
	set_input(Vector2(0, -1), false, true)
	await frames(180)
	print("  crouching: z=%.2f y=%.2f" % [p.global_position.z, p.global_position.y])
	check(p.global_position.z > 66.5, "crouching player enters bunker")
	set_input(Vector2.ZERO)
	await frames(60)
	check(not p.is_crouching, "can stand up inside bunker (roof high enough)")

	# Trench walls block walking out the front
	teleport(Vector3(-30, -1.3, 61), 0.0)
	await frames(20)
	set_input(Vector2(0, -1))
	await frames(120)
	check(p.global_position.z > 58.0 and p.global_position.y < -1.0, "front trench wall blocks (z=%.2f)" % p.global_position.z)

	print("TREES: ", get_tree().get_first_node_in_group("terrain").get_parent().get_node("Forest").get_child_count(), " forest nodes")
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
