class_name TankSpawner
extends Node
## Brings tanks onto the field (host only). Tanks are added under `tanks_root`; the
## MultiplayerSpawner "TankNodeSpawner" then creates them on the other computers too.
##
## T1: the debug keys use it (F9 = a tank on a random route, F10 = knock out the nearest
## one; editor builds only). T3: the WaveSpawner sends tanks with the waves (WaveData.tanks);
## they start in the forest. Old wrecks are cleared away while the day screen is black.

signal tank_spawned(tank: Tank)

@export var tank_scene: PackedScene
@export var tanks_root: Node3D
@export var crew_scene: PackedScene ## T2: the crew who bail out of a burning tank (riflemen).
@export var crew_root: Node3D ## ...are added here (Game/Enemies, replicated by its spawner).
@export var forest_approach_m: float = 40.0 ## T3: wave tanks start this far back in the forest.
@export var max_wrecks: int = 3 ## T3: older wrecks are removed (behind the black day screen).

var _count: int = 0
var _rng := RandomNumberGenerator.new()
var _wreck_check: float = 0.0


func _ready() -> void:
	add_to_group("tank_spawner")
	_rng.randomize()


## All drawn tank routes (Path3D nodes in the group "tank_route"), in name order.
func get_routes() -> Array[Path3D]:
	var list: Array[Path3D] = []
	for node in get_tree().get_nodes_in_group("tank_route"):
		if node is Path3D:
			list.append(node)
	list.sort_custom(func(a: Path3D, b: Path3D) -> bool: return String(a.name) < String(b.name))
	return list


## Host: a new tank at the start of a route (-1 = a random free one). `approach_m` > 0 starts
## it that far back in the forest (T3 wave tanks). Returns it (or null).
func spawn_tank(route_index: int = -1, approach_m: float = 0.0) -> Tank:
	if not multiplayer.is_server() or tank_scene == null or tanks_root == null:
		return null
	var routes := get_routes()
	if routes.is_empty():
		push_warning("TankSpawner: no Path3D in the group 'tank_route'")
		return null
	if route_index < 0 or route_index >= routes.size():
		route_index = _pick_route(routes)
	var tank: Tank = tank_scene.instantiate()
	_count += 1
	tank.name = "Tank%d" % _count
	tank.route = routes[route_index]
	tank.forest_approach_m = approach_m
	tank.crew_scene = crew_scene
	tank.crew_root = crew_root
	tanks_root.add_child(tank, true)
	tank_spawned.emit(tank)
	return tank


## A random route that no tank still in the fight is using (any route if all are taken).
func _pick_route(routes: Array[Path3D]) -> int:
	var free: Array[int] = []
	for i in routes.size():
		var used: bool = false
		for t in get_living_tanks():
			if t.route == routes[i]:
				used = true
		if not used:
			free.append(i)
	if free.is_empty():
		return _rng.randi() % routes.size()
	return free[_rng.randi() % free.size()]


## Host: a wave tank (T3): from the forest, on a free route.
func spawn_wave_tank() -> Tank:
	return spawn_tank(-1, forest_approach_m)


## Tanks still in the fight (not burning, not a wreck).
func get_living_tanks() -> Array[Tank]:
	var list: Array[Tank] = []
	for node in get_tree().get_nodes_in_group("tanks"):
		var t := node as Tank
		if t and not t.is_queued_for_deletion() and not t.is_knocked_out():
			list.append(t)
	return list


## Host (T3): keeps at most `max_wrecks` wrecks on the field. The oldest go while the day
## screen is black, so nobody sees them vanish (or at once with `now`, e.g. a new wave).
func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_wreck_check -= delta
	if _wreck_check > 0.0:
		return
	_wreck_check = 0.5
	var screen: Node = get_tree().get_first_node_in_group("day_screen")
	if screen and screen.has_method("is_black") and screen.is_black():
		clear_old_wrecks()


## Host: removes the oldest wrecks above `max_wrecks`. Returns how many were removed.
func clear_old_wrecks() -> int:
	var wrecks: Array[Tank] = []
	for node in get_tree().get_nodes_in_group("tanks"):
		var t := node as Tank
		if t and t.is_destroyed() and not t.is_queued_for_deletion():
			wrecks.append(t)
	if wrecks.size() <= max_wrecks:
		return 0
	# Tank names count up (Tank1, Tank2…): the lowest numbers are the oldest.
	wrecks.sort_custom(func(a: Tank, b: Tank) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	var removed: int = 0
	for i in wrecks.size() - max_wrecks:
		wrecks[i].queue_free() # the MultiplayerSpawner removes it on the other computers too
		removed += 1
	return removed


## Host (debug): knock out the living tank nearest to `pos`. Returns true if there was one.
func destroy_nearest(pos: Vector3) -> bool:
	if not multiplayer.is_server():
		return false
	var best: Tank = null
	var best_d: float = INF
	for node in get_tree().get_nodes_in_group("tanks"):
		var t := node as Tank
		if t and not t.is_destroyed() and t.global_position.distance_to(pos) < best_d:
			best = t
			best_d = t.global_position.distance_to(pos)
	if best:
		best.destroy()
	return best != null
