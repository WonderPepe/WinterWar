class_name WaveSpawner
extends Node
## Sends waves of enemies across the open ground towards the Finnish trench.
##
## Runs on the host only. Enemies are added under `enemies_root`; the
## MultiplayerSpawner watching that node creates them on every other computer.
## Spawn points are Marker3D nodes in the "enemy_spawn" group, and each soldier
## advances to one of the Marker3D nodes in the "attack_point" group.

signal wave_started(number: int, enemy_count: int)
signal wave_cleared(number: int)

enum Phase { WAITING, SPAWNING, FIGHTING }

@export var enemy_scene: PackedScene
@export var enemies_root: Node3D
@export var first_wave_delay: float = 5.0
@export var base_enemies: int = 6 ## Soldiers in wave 1.
@export var enemies_added_per_wave: int = 2
@export var group_size_min: int = 2
@export var group_size_max: int = 3
@export var time_between_groups: float = 4.0
@export var time_between_waves: float = 20.0
@export var max_alive: int = 16 ## Performance limit for the web version.
@export var spawn_spread_m: float = 5.0 ## Random offset around each spawn point.

# --- Synced to everyone by WaveSync (for the HUD) ---
var wave_number: int = 0
var alive_count: int = 0

var _phase: Phase = Phase.WAITING
var _timer: float = 0.0
var _left_to_spawn: int = 0
var _spawned_total: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("wave_spawner")
	_rng.randomize()
	_timer = first_wave_delay


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_timer -= delta
	match _phase:
		Phase.WAITING:
			if _timer <= 0.0:
				_start_wave()
		Phase.SPAWNING:
			if _timer <= 0.0 and alive_count < max_alive:
				_spawn_group()
				_timer = time_between_groups
			if _left_to_spawn <= 0:
				_phase = Phase.FIGHTING
		Phase.FIGHTING:
			if alive_count <= 0:
				wave_cleared.emit(wave_number)
				_phase = Phase.WAITING
				_timer = time_between_waves


## Seconds until the next wave starts (0 while a wave is running).
func get_time_to_next_wave() -> float:
	return maxf(_timer, 0.0) if _phase == Phase.WAITING else 0.0


func _start_wave() -> void:
	wave_number += 1
	_left_to_spawn = base_enemies + (wave_number - 1) * enemies_added_per_wave
	wave_started.emit(wave_number, _left_to_spawn)
	_phase = Phase.SPAWNING
	_timer = 0.0


func _spawn_group() -> void:
	var spawns := get_tree().get_nodes_in_group("enemy_spawn")
	var targets := get_tree().get_nodes_in_group("attack_point")
	if spawns.is_empty() or targets.is_empty():
		push_warning("WaveSpawner: no enemy_spawn or attack_point markers in the level.")
		_left_to_spawn = 0
		return
	var spawn: Node3D = spawns[_rng.randi() % spawns.size()]
	var count: int = mini(_rng.randi_range(group_size_min, group_size_max), _left_to_spawn)
	count = mini(count, max_alive - alive_count)
	for i in count:
		var target: Node3D = targets[_spawned_total % targets.size()]
		_spawn_enemy(spawn.global_position, target.global_position)
	_left_to_spawn -= count


func _spawn_enemy(near: Vector3, goal: Vector3) -> void:
	var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
	var pos: Vector3 = near + Vector3(_rng.randf_range(-spawn_spread_m, spawn_spread_m), 0.0, _rng.randf_range(-spawn_spread_m, spawn_spread_m))
	goal += Vector3(_rng.randf_range(-3.0, 3.0), 0.0, _rng.randf_range(-2.0, 2.0)) # don't all stand on one spot
	if terrain:
		pos.y = terrain.get_height(pos.x, pos.z) + 0.1
		goal.y = terrain.get_height(goal.x, goal.z)
	_spawned_total += 1
	var enemy: Enemy = enemy_scene.instantiate()
	enemy.name = "Enemy_%d" % _spawned_total
	enemy.position = pos
	enemy.rotation.y = PI # face north, towards the trench
	enemy.attack_point = goal
	enemy.died.connect(_on_enemy_died)
	enemies_root.add_child(enemy, true)
	alive_count += 1


func _on_enemy_died(_enemy: Enemy) -> void:
	alive_count -= 1
