class_name TankSpawner
extends Node
## Brings tanks onto the field (host only). Tanks are added under `tanks_root`; the
## MultiplayerSpawner "TankNodeSpawner" then creates them on the other computers too.
##
## T1: only the debug keys use it (F9 = a tank on a random route, F10 = knock out the
## nearest one; editor builds only). T3 will send tanks with the waves.

signal tank_spawned(tank: Tank)

@export var tank_scene: PackedScene
@export var tanks_root: Node3D
@export var crew_scene: PackedScene ## T2: the crew who bail out of a burning tank (riflemen).
@export var crew_root: Node3D ## ...are added here (Game/Enemies, replicated by its spawner).

var _count: int = 0
var _rng := RandomNumberGenerator.new()


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


## Host: a new tank at the start of a route (-1 = a random one). Returns it (or null).
func spawn_tank(route_index: int = -1) -> Tank:
	if not multiplayer.is_server() or tank_scene == null or tanks_root == null:
		return null
	var routes := get_routes()
	if routes.is_empty():
		push_warning("TankSpawner: no Path3D in the group 'tank_route'")
		return null
	if route_index < 0 or route_index >= routes.size():
		route_index = _rng.randi() % routes.size()
	var tank: Tank = tank_scene.instantiate()
	_count += 1
	tank.name = "Tank%d" % _count
	tank.route = routes[route_index]
	tank.crew_scene = crew_scene
	tank.crew_root = crew_root
	tanks_root.add_child(tank, true)
	tank_spawned.emit(tank)
	return tank


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
