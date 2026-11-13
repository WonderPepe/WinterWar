extends Node
## Automated test for C1: climbing out of the trench (not part of the game).
##   godot --headless --path . --script tools/run.gd -- tools/test_c1.gd

var game: Node
var p: Player
var fails := 0
var xz: Array = []
var depth := 1.4
var post_x: Array = []


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func teleport(pos: Vector3, yaw := 0.0) -> void:
	p.climb.cancel()
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.input.look_yaw = yaw
	p.input.move_dir = Vector2.ZERO
	p.input.crouch_held = false


func pt(i: int) -> Vector2:
	return Vector2(xz[i * 2], xz[i * 2 + 1])


## A spot on the trench floor on a leg that runs east-west (walls to the south and north), away
## from corners, firing positions and exits: [x, z].
func straight_spot(min_len: float, skip := 0) -> Vector2:
	for i in xz.size() / 2 - 1:
		var a := pt(i)
		var b := pt(i + 1)
		if absf(a.y - b.y) < 0.01 and absf(a.x - b.x) >= min_len and absf((a.x + b.x) / 2.0) < 30.0 \
				and absf((a.x + b.x) / 2.0) > 4.0:
			var near_post := false
			for px: float in post_x:
				near_post = near_post or absf(px - (a.x + b.x) / 2.0) < 3.0
			if near_post:
				continue
			if skip > 0:
				skip -= 1
				continue
			return (a + b) / 2.0
	return Vector2.ZERO


## Walk into the wall in front (yaw 0 = facing -z = the enemy side; PI = the rear wall).
func to_wall(spot: Vector2, yaw: float, crouch := false) -> void:
	teleport(Vector3(spot.x, -depth + 0.05, spot.y), yaw)
	await frames(20)
	p.input.crouch_held = crouch
	p.input.move_dir = Vector2(0, -1)
	await frames(50)
	p.input.move_dir = Vector2.ZERO
	await frames(10)


func line_z(x: float) -> float:
	for i in xz.size() / 2 - 1:
		var a := pt(i)
		var b := pt(i + 1)
		if not is_equal_approx(a.x, b.x) and x >= minf(a.x, b.x) - 0.001 and x <= maxf(a.x, b.x) + 0.001:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return 0.0


func _clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


func _ready() -> void:
	await get_tree().process_frame
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	run()


func run() -> void:
	await frames(5)
	p = get_tree().get_nodes_in_group("players")[0]
	p.input.set_process(false)
	p.god_mode = true
	await frames(60)
	var consts: Dictionary = (load("res://tools/build_scenes.gd") as GDScript).get_script_constant_map()
	xz = consts["TRENCH_XZ"]
	depth = consts["DEPTH"]
	post_x = consts["POST_X"]
	var spot := straight_spot(4.0)
	check(spot != Vector2.ZERO, "found a straight trench leg (x %.1f, z %.1f)" % [spot.x, spot.y])
	check(p.has_node("Climb") and p.climb is ClimbHandler, "Player has the Climb node")
	var cfg: SceneReplicationConfig = (p.get_node("StateSync") as MultiplayerSynchronizer).replication_config
	check(cfg.has_property(NodePath(".:is_climbing")), "is_climbing is synced")

	# --- the old problem: a jump alone doesn't get him out ---
	teleport(Vector3(spot.x, -depth + 0.05, spot.y), 0.0)
	await frames(30)
	p.input.request_jump()
	await frames(90)
	check(not p.is_climbing and p.global_position.y < -1.0, "a jump in the middle of the trench is a normal jump (y %.2f)" % p.global_position.y)

	# --- front wall ---
	await to_wall(spot, 0.0)
	var z_before: float = p.global_position.z
	check(p.climb.find_ledge() != null, "at the front wall a ledge is found")
	p.input.request_jump()
	await frames(3)
	check(p.is_climbing, "Space at the front wall starts a climb")
	check(not p.weapons._can_fire_now(), "no shooting while climbing")
	p.input.aim_held = true
	await frames(10)
	check(not p.weapons.is_aiming, "no aiming while climbing")
	p.input.aim_held = false
	var ticks := 3 + 10
	while p.is_climbing and ticks < 300:
		await frames(1)
		ticks += 1
	var secs: float = ticks / float(Engine.physics_ticks_per_second)
	check(absf(secs - p.climb.climb_time) < 0.15, "the climb takes about %.1f s (%.2f)" % [p.climb.climb_time, secs])
	await frames(20)
	check(p.global_position.y > -0.2 and p.global_position.z < z_before - 0.5 and p.is_on_floor(),
		"he stands on the ground in FRONT of the trench (y %.2f, z %.2f -> %.2f)" % [p.global_position.y, z_before, p.global_position.z])
	check(p.weapons._can_fire_now(), "he can shoot again on top")
	# Open ground: Space is a normal jump again.
	p.input.request_jump()
	await frames(8)
	check(not p.is_climbing and p.velocity.y != 0.0 and not p.is_on_floor(), "on open ground Space is a normal jump")
	await frames(60)

	# --- rear wall, from a crouch (owner: crouching + Space climbs too) ---
	await to_wall(spot, PI, true)
	z_before = p.global_position.z
	check(p.is_crouching, "(crouching at the rear wall)")
	p.input.request_jump()
	await frames(3)
	check(p.is_climbing, "crouching + Space at the rear wall starts a climb")
	await frames(90)
	check(not p.is_climbing and p.global_position.y > -0.2 and p.global_position.z > z_before + 0.5,
		"he ends up on the ground BEHIND the trench (y %.2f)" % p.global_position.y)
	p.input.crouch_held = false
	# Crouching on open ground: Space still does nothing.
	teleport(Vector3(spot.x, 0.1, spot.y - 12.0), 0.0)
	await frames(30)
	p.input.crouch_held = true
	await frames(20)
	p.input.request_jump()
	await frames(6)
	check(not p.is_climbing and p.is_on_floor(), "crouching on open ground: Space does nothing (as before)")
	p.input.crouch_held = false

	# --- facing along the trench: no climb ---
	teleport(Vector3(spot.x, -depth + 0.05, spot.y), PI / 2.0)
	await frames(30)
	check(p.climb.find_ledge() == null, "facing along the trench: no ledge")
	# Sideways at the wall (more than 60 degrees off): no climb.
	await to_wall(spot, 0.0)
	p.input.look_yaw = deg_to_rad(75.0)
	await frames(5)
	check(p.climb.find_ledge() == null, "at the wall but looking 75 degrees aside: no ledge")
	p.input.look_yaw = deg_to_rad(40.0)
	await frames(5)
	check(p.climb.find_ledge() != null, "at the wall looking 40 degrees aside: ledge found")

	# --- Molotov: an unlit bottle may come along, a burning one may not (owner) ---
	p.input.look_yaw = 0.0
	p.molotov.count = 2
	p.molotov.phase = MolotovHandler.Phase.LIT
	p.molotov._lit_t = 0.0
	p.input.request_jump()
	await frames(4)
	check(not p.is_climbing, "no climb with a LIT bottle")
	p.molotov.phase = MolotovHandler.Phase.IGNITING
	p.input.aim_held = true
	p.input.request_jump()
	await frames(4)
	check(not p.is_climbing, "no climb while lighting the bottle")
	p.input.aim_held = false
	await frames(4)
	p.molotov.phase = MolotovHandler.Phase.HELD
	p.molotov._rmb_released = true
	await frames(40) # (land from the refused jump)
	await to_wall(spot, 0.0)
	p.input.request_jump()
	await frames(3)
	check(p.is_climbing, "an UNLIT bottle in the hand: he climbs")
	p.input.aim_held = true
	await frames(30)
	check(p.is_climbing and p.molotov.phase == MolotovHandler.Phase.HELD, "the bottle can't be lit during the climb")
	await frames(60)
	check(not p.is_climbing and p.molotov.count == 2 and p.molotov.is_selected(), "the bottle is still in his hand on top")
	await frames(80)
	check(p.molotov.phase == MolotovHandler.Phase.LIT, "on top it can be lit (phase %d)" % p.molotov.phase)
	p.input.aim_held = false
	p.molotov.reset()

	# --- bandaging: no climb ---
	await to_wall(spot, 0.0)
	p.is_bandaging = true
	p._bandage_timer = 3.0
	p.input.request_jump()
	await frames(4)
	check(not p.is_climbing, "no climb while bandaging")
	p.is_bandaging = false
	await frames(50)

	# --- firing position: not out through the sandbag wall ---
	var bay_x: float = post_x[1]
	teleport(Vector3(bay_x, -depth + 0.05, line_z(bay_x)), 0.0)
	await frames(20)
	var z_line: float = p.global_position.z
	p.input.move_dir = Vector2(0, -1)
	await frames(90)
	p.input.move_dir = Vector2.ZERO
	await frames(10)
	var y0: float = p.global_position.y
	p.input.request_jump()
	await frames(4)
	check(p.global_position.z < z_line - 1.5, "(he walked forward into the firing position: z %.1f -> %.1f)" % [z_line, p.global_position.z])
	check(not p.is_climbing and y0 < -1.0 and p.climb.find_ledge() == null, "firing position: no climbing out over the sandbag wall")
	await frames(60)

	# --- killed on the way up: the climb stops ---
	await to_wall(spot, 0.0)
	p.input.request_jump()
	await frames(20)
	check(p.is_climbing, "(climbing)")
	p.god_mode = false
	p.take_damage(500.0, -1, p.global_position, Vector3.UP)
	await frames(5)
	check(p.is_dead and not p.is_climbing, "killed on the wall: the climb stops")

	# --- a second straight leg, and a communication trench ---
	p.respawn(Transform3D(Basis.IDENTITY, Vector3(spot.x, -depth + 0.05, spot.y)))
	p.god_mode = true
	await frames(30)
	var spot2 := straight_spot(3.0, 1)
	if spot2 != Vector2.ZERO:
		await to_wall(spot2, 0.0)
		p.input.request_jump()
		await frames(100)
		check(p.global_position.y > -0.2, "another leg (x %.1f): out at the front" % spot2.x)

	# --- what the climb costs: on top a tank at the trench edge has a clear line to him ---
	var space := p.get_world_3d().direct_space_state
	var eye := Vector3(spot2.x, 2.2, 49.0) # about where a parked tank's "Eye" is
	check(_clear(space, eye, p.global_position + Vector3(0, 1.2, 0)), "on top: clear line from a tank's eye to his chest")
	teleport(Vector3(spot2.x, -depth + 0.05, spot2.y), 0.0)
	p.input.crouch_held = true
	await frames(40)
	check(not _clear(space, eye, p.global_position + Vector3(0, 0.6, 0)), "crouching in the trench: hidden from it (as before)")
	p.input.crouch_held = false
	print("RESULT: %s (%d failed)" % ["ALL PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
