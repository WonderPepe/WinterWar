extends Node
## Test for T5 "armour stops bullets" (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_t5.gd
## A tank (and a wreck) standing between a Soviet soldier and the player must stop the soldier's
## bullets, his sight, another tank's sight / bullets and the blast of a 45 mm shell.

var fails := 0
var game: Node


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _ready() -> void:
	await get_tree().process_frame
	run()


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run() -> void:
	Settings.difficulty = 1
	check(ProjectSettings.get_setting("layer_names/3d_physics/layer_5", "") == "armour", "physics layer 5 is named \"armour\"")
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await get_tree().create_timer(0.5).timeout
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.set_physics_process(false) # he stands where the test puts him
	(get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner).set_process(false)
	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state

	# Open ground in front of the trench: soldier at z 0, tank at z 15, player at z 30.
	var x: float = 0.0
	p.global_position = Vector3(x, terrain.get_height(x, 30.0) + 0.05, 30.0)
	p.health = 100000
	var e: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
	e.name = "TestEnemy"
	e.position = Vector3(x, terrain.get_height(x, 0.0) + 0.05, 0.0)
	e.attack_point = e.position
	game.get_node("Enemies").add_child(e, true)
	e.set_physics_process(false) # no AI: the test aims and fires for him
	e.set_process(false)
	var tank: Tank = spawner.spawn_tank(1)
	tank.set_physics_process(false) # parked by the test
	var aside := Vector3(x + 30.0, terrain.get_height(x + 30.0, 15.0), 15.0)
	var between := Vector3(x, terrain.get_height(x, 15.0), 15.0)
	tank.global_position = aside
	tank.rotation = Vector3(0, PI / 2.0, 0) # broadside to the line of fire
	await frames(3)

	# --- Layers: nothing that worked before changes.
	check(tank.collision_layer == 0b10100, "tank is on layer 3 (enemies) and layer 5 (armour), got %d" % tank.collision_layer)
	check(e.collision_mask & tank.collision_layer == 0, "soldiers still pass through a tank")
	check(p.collision_mask & tank.collision_layer != 0, "players still bump into a tank")
	check(p.weapons.shot_collision_mask & tank.collision_layer != 0, "the player's bullets still hit a tank")
	check(Tank.SIGHT_MASK & e.collision_layer == 0 and Tank.BULLET_MASK & e.collision_layer == 0, "soldiers don't block each other's sight or bullets")

	# --- Nothing in the way: he sees the player and hits him.
	var chest: Vector3 = p.global_position + Vector3.UP * 1.3
	var head: Vector3 = p.head.global_position
	check(e._has_line_of_sight(head) and e._has_line_of_sight(chest), "open ground: the soldier sees the player")
	e._target = p
	var hp: int = p.health
	for i in 30:
		e._shoot()
	check(p.health < hp, "open ground: his bullets hit (%d damage from 30 shots)" % (hp - p.health))

	# --- A tank in between.
	tank.global_position = between
	await frames(3)
	check(not e._has_line_of_sight(head) and not e._has_line_of_sight(chest), "tank in between: the soldier can't see the player")
	var q := PhysicsRayQueryParameters3D.create(e.muzzle.global_position, chest, Tank.BULLET_MASK)
	q.exclude = [e.get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	check(not hit.is_empty() and hit.collider == tank, "tank in between: a bullet aimed at the chest stops at the armour")
	check(not hit.is_empty() and ImpactEffects.surface_of(hit.collider, hit.normal) == "metal", "…and makes sparks (surface metal)")
	hp = p.health
	for i in 60:
		e._shoot()
	check(p.health == hp, "tank in between: 60 shots, no damage (%d)" % (hp - p.health))

	# --- The same tank knocked out: a wreck is cover too.
	tank.destroy()
	await frames(10)
	check(tank.is_in_group("tank_wrecks") and tank.collision_layer == 0b10100, "the wreck keeps its armour layer")
	check(not e._has_line_of_sight(head) and not e._has_line_of_sight(chest), "wreck in between: the soldier can't see the player")
	hp = p.health
	for i in 60:
		e._shoot()
	check(p.health == hp, "wreck in between: 60 shots, no damage (%d)" % (hp - p.health))

	# --- A second tank behind the wreck: no sight, DT and shell stop at the wreck.
	var t2: Tank = spawner.spawn_tank(0)
	t2.set_physics_process(false)
	t2.global_position = Vector3(x, terrain.get_height(x, 0.0), 0.0)
	t2.rotation = Vector3(0, PI, 0) # nose towards the trench (+z)
	await frames(3)
	check(not t2._can_see(p), "a tank can't see the player through a wreck")
	q = PhysicsRayQueryParameters3D.create(t2.dt_muzzle.global_position, chest, Tank.BULLET_MASK)
	q.exclude = [t2.get_rid()]
	hit = space.intersect_ray(q)
	check(not hit.is_empty() and hit.collider == tank, "the tank's DT / shell line stops at the wreck")
	check(t2._clear_line(t2.eye.global_position, t2.eye.global_position + Vector3(8, 0, 0)), "a tank's own armour doesn't block its own view")
	# Blast of a shell that burst on the far side of the wreck (3 m south of it, 1 m up).
	var burst: Vector3 = between + Vector3(0, 1.0, -3.0)
	check(not t2._clear_line(burst, chest) and not t2._clear_line(burst, head), "the wreck shields the player from a shell burst behind it")
	check(t2._clear_line(burst + Vector3(6, 0, 0), chest) or t2._clear_line(burst + Vector3(6, 0, 0), head), "a burst beside the wreck still reaches him")

	# --- Tank moved away again: everything is as before.
	tank.global_position = aside
	t2.global_position = aside + Vector3(10, 0, 0)
	await frames(3)
	check(e._has_line_of_sight(head), "wreck gone: the soldier sees the player again")
	hp = p.health
	for i in 30:
		e._shoot()
	check(p.health < hp, "wreck gone: his bullets hit again (%d damage)" % (hp - p.health))

	print("TEST T5 DONE: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)
