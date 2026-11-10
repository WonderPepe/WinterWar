class_name WaveSpawner
extends Node
## Sends waves of enemies across the open ground towards the Finnish trench.
##
## Runs on the host only. Enemies are added under `enemies_root`; the
## MultiplayerSpawner watching that node creates them on every other computer.
## Spawn points are Marker3D nodes in the "enemy_spawn" group, and each soldier
## advances to one of the Marker3D nodes in the "attack_point" group.
## G2: a wave is a mix of riflemen, officers and DP-27 teams (`wave_list`, from the difficulty).
## Every group of soldiers comes out of the forest together; an officer walks in the middle
## of his group, a machine-gun team (gunner + helper) is a group of its own.
## T3: a wave can bring T-26 tanks (`WaveData.tanks`, sent through the TankSpawner). A wave
## with tanks only ends when its soldiers are dead AND every tank is burning or a wreck.

signal wave_started(number: int, enemy_count: int)
signal wave_cleared(number: int)
signal trench_retaken(number: int) ## L3: the last Soviet holding the trench is dead (host).

enum Phase { WAITING, SPAWNING, FIGHTING, RETAKE } # RETAKE (L3): clearing the captured trench first

@export var enemy_scene: PackedScene ## Rifleman.
@export var officer_scene: PackedScene
@export var mg_gunner_scene: PackedScene
## MG teams set up this far behind the riflemen's attack points (a random distance between the two;
## owner: 5–10 m, close enough to be found – it was 35 m).
@export var mg_position_back_min_m: float = 5.0
@export var mg_position_back_max_m: float = 10.0
@export var mg_release_check: float = 0.5 ## Seconds between "are all the riflemen dead?" checks.
@export var enemies_root: Node3D
@export var first_wave_delay: float = 5.0
@export var base_enemies: int = 6 ## Soldiers in wave 1.
@export var enemies_added_per_wave: int = 2
@export var group_size_min: int = 2
@export var group_size_max: int = 3
@export var time_between_groups: float = 4.0
@export var time_between_waves: float = 5.0 ## "Battle n begins in …" after a cleared battle (held while the day screen is open).
@export var max_alive: int = 16 ## Performance limit for the web version.
@export var spawn_spread_m: float = 5.0 ## Random offset around each spawn point.
@export var max_waves: int = 0 ## Stop after this many waves (0 = endless). Set by the MatchDirector.
@export var first_tank_delay: float = 12.0 ## T3: seconds after the wave starts before the first tank sets off in the forest.
@export var tank_interval: float = 18.0 ## T3: seconds between the tanks of one wave.
## L3: seconds from "Trench Retaken!" until the counterattack comes out of the forest.
@export var retake_pause: float = 8.0

## False = no more waves (the battle is over).
var active: bool = true
## True = the countdown to the next wave waits (host: the day screen between waves is open).
var hold: bool = false
## What each wave is made of (set by the MatchDirector). Empty = riflemen only (old rule).
var wave_list: Array[WaveData] = []

# --- Synced to everyone by WaveSync (for the HUD) ---
var wave_number: int = 0
var alive_count: int = 0
var wave_riflemen: int = 0
var wave_officers: int = 0
var wave_mg_teams: int = 0
var wave_tanks: int = 0 ## T3
## L3: true while the players must first clear the Soviets out of the trench (battle 6).
var retaking: bool = false

var _phase: Phase = Phase.WAITING
var _timer: float = 0.0
var _left_to_spawn: int = 0
var _queue: Array = [] # groups still to come out of the forest: each an Array of "R"/"O"/"MG"
var _mg_count: int = 0
var _spawned_total: int = 0
var _rng := RandomNumberGenerator.new()
var _tank_times: Array[float] = [] # T3: wave clock times when the next tanks set off
var _wave_clock: float = 0.0
var _release_timer: float = 0.0
var _retake_cleared: bool = false # L3: the trench is ours again – waiting `retake_pause` for the wave


func _ready() -> void:
	add_to_group("wave_spawner")
	_rng.randomize()
	_timer = first_wave_delay


func _process(delta: float) -> void:
	if not multiplayer.is_server() or not active:
		return
	if not (hold and _phase == Phase.WAITING):
		_timer -= delta
	if _phase != Phase.WAITING:
		_wave_clock += delta
		_send_tanks()
	match _phase:
		Phase.WAITING:
			if _timer <= 0.0:
				_start_wave()
		Phase.RETAKE:
			_update_retake()
		Phase.SPAWNING:
			if _timer <= 0.0 and alive_count < max_alive:
				if _spawn_group():
					_timer = time_between_groups
			if _left_to_spawn <= 0:
				_phase = Phase.FIGHTING
		Phase.FIGHTING:
			_release_timer -= delta
			if _release_timer <= 0.0:
				_release_timer = mg_release_check
				release_mg_teams_if_alone()
			if alive_count <= 0 and tanks_in_fight() == 0:
				_phase = Phase.WAITING
				_timer = time_between_waves
				if max_waves > 0 and wave_number >= max_waves:
					active = false # that was the last one
				wave_cleared.emit(wave_number)


## Test mode: the next wave to come is `number`, in `delay` seconds.
func start_at_wave(number: int, delay: float) -> void:
	wave_number = number - 1
	_phase = Phase.WAITING
	_timer = delay


## Seconds until the next wave starts (0 while a wave is running).
func get_time_to_next_wave() -> float:
	return maxf(_timer, 0.0) if _phase == Phase.WAITING else 0.0


## L3: true when the coming battle (not started yet) begins with the Soviets in the trench –
## the players then start at the rear (Game).
func next_wave_is_retake() -> bool:
	return _phase == Phase.WAITING and get_composition(wave_number + 1).has_retake()


func _start_wave() -> void:
	wave_number += 1
	var w: WaveData = get_composition(wave_number)
	if w.has_retake():
		_start_retake(w)
		return
	_launch_wave(w)


## L3: the battle starts with the Soviets already holding the west half of the trench.
func _start_retake(w: WaveData) -> void:
	wave_riflemen = w.occupy_riflemen
	wave_officers = w.occupy_officers
	wave_mg_teams = w.occupy_mg_teams
	wave_tanks = 0
	_retake_cleared = false
	retaking = true
	_phase = Phase.RETAKE
	_spawn_occupiers(w)


func _update_retake() -> void:
	if not _retake_cleared:
		if alive_count > 0:
			return
		_retake_cleared = true
		retaking = false
		_timer = retake_pause
		trench_retaken.emit(wave_number)
		return
	if _timer <= 0.0:
		_launch_wave(get_composition(wave_number)) # the counterattack


## L3: puts the occupiers on the `retake_point` markers (west half of the trench, west → east):
## riflemen spread along it, the officer in the middle, the DP-27 teams near the east end (they
## cover the stretch the Finns will come along from the middle). More men than spots: a second
## man stands a little way along the trench (moved onto the navigation mesh).
func _spawn_occupiers(w: WaveData) -> void:
	var points: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group("retake_point"):
		points.append((node as Node3D).global_position)
	if points.is_empty():
		push_warning("WaveSpawner: no retake_point markers - nobody holds the trench.")
		return
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	var kinds: Array[String] = []
	for i in w.occupy_riflemen:
		kinds.append("R")
	for i in w.occupy_officers:
		kinds.insert(mini(kinds.size(), (kinds.size() * (i + 1)) / (w.occupy_officers + 1)), "O")
	# Spots used in this order: every second one first, so they are spread over the whole stretch.
	var order: Array[int] = []
	for i in range(0, points.size(), 2):
		order.append(i)
	for i in range(1, points.size(), 2):
		order.append(i)
	var mg_spots: Array[int] = []
	for i in w.occupy_mg_teams:
		mg_spots.append(clampi(points.size() - 3 - i * 2, 0, points.size() - 1))
	var used: Dictionary = {} # spot index -> men there
	var n: int = 0
	for kind in kinds:
		var idx: int = order[n % order.size()]
		n += 1
		_place_occupier(kind, points[idx], used.get(idx, 0))
		used[idx] = used.get(idx, 0) + 1
	for idx in mg_spots:
		_place_occupier("MG", points[idx], used.get(idx, 0))
		used[idx] = used.get(idx, 0) + 1
		_place_occupier("R", points[idx], used.get(idx, 0))
		used[idx] = used.get(idx, 0) + 1


func _place_occupier(kind: String, spot: Vector3, already: int) -> void:
	var pos: Vector3 = spot
	if already > 0:
		var map: RID = get_tree().root.get_world_3d().navigation_map
		var off := Vector3((1.6 if already % 2 == 1 else -1.6) * ceilf(already / 2.0), 0.0, 0.0)
		var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, spot + off)
		if on_mesh != Vector3.ZERO and on_mesh.distance_to(spot) < 4.0 and on_mesh.y < -0.6:
			pos = Vector3(on_mesh.x, spot.y, on_mesh.z)
	var scene: PackedScene = enemy_scene
	if kind == "O":
		scene = officer_scene
	elif kind == "MG":
		scene = mg_gunner_scene
	_spawned_total += 1
	var enemy: Enemy = scene.instantiate()
	enemy.name = "Enemy_%d" % _spawned_total
	enemy.position = pos + Vector3(0, 0.1, 0)
	enemy.rotation.y = PI # facing the rear (+z), where the counterattack comes from
	enemy.start_holding(pos)
	enemy.died.connect(_on_enemy_died)
	enemies_root.add_child(enemy, true)
	alive_count += 1


## Sends the soldiers (and tanks) of wave `wave_number` out of the forest.
func _launch_wave(w: WaveData) -> void:
	wave_riflemen = w.riflemen
	wave_officers = w.officers
	wave_mg_teams = w.mg_teams
	wave_tanks = w.tanks
	var tank_spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	if tank_spawner:
		tank_spawner.clear_old_wrecks() # normally already done behind the black day screen
	_wave_clock = 0.0
	_tank_times.clear()
	for i in w.tanks:
		_tank_times.append(first_tank_delay + i * tank_interval)
	_queue = _make_groups(w)
	_left_to_spawn = w.total_soldiers()
	wave_started.emit(wave_number, _left_to_spawn)
	_phase = Phase.SPAWNING
	_timer = 0.0


## Host: once every soldier who is NOT in a machine-gun team is dead (and the whole wave is out of
## the forest), the DP-27 teams get up and go for the trench like riflemen (owner) – nobody has
## to hunt for a gun team lying far out in the snow. Returns how many teams were sent.
func release_mg_teams_if_alone() -> int:
	if _left_to_spawn > 0:
		return 0
	var gunners: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.state == Enemy.State.DEAD:
			continue
		if e.is_mg_team_member():
			if e.data.kind == EnemyData.Kind.MG_GUNNER:
				gunners.append(e)
		else:
			return 0 # a rifleman (or officer, or tank crewman) still fights: the guns stay put
	for g in gunners:
		g.advance_as_rifleman()
	return gunners.size()


## T3: tanks of this wave still to come + those still fighting (not burning, not a wreck)
## + burning ones whose crew have not all bailed out yet (the crew count as soldiers then).
func tanks_in_fight() -> int:
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	if spawner == null:
		return 0
	var crew_to_come: int = 0
	for node in get_tree().get_nodes_in_group("tanks"):
		var t := node as Tank
		if t and t.crew_still_inside() > 0:
			crew_to_come += 1 # burning, but its crew are still climbing out
	return _tank_times.size() + spawner.get_living_tanks().size() + crew_to_come


## T3: sends the wave's tanks off when their time has come.
func _send_tanks() -> void:
	if _tank_times.is_empty() or _wave_clock < _tank_times[0]:
		return
	_tank_times.remove_at(0)
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	if spawner:
		spawner.spawn_wave_tank()


## What wave `number` is made of.
func get_composition(number: int) -> WaveData:
	if wave_list.is_empty():
		return WaveData.new().make(base_enemies + (number - 1) * enemies_added_per_wave, 0, 0)
	return wave_list[clampi(number - 1, 0, wave_list.size() - 1)]


## Splits a wave into the groups that come out of the forest one after another.
func _make_groups(w: WaveData) -> Array:
	var rifle_groups: Array = []
	var left: int = w.riflemen
	while left > 0:
		var n: int = mini(_rng.randi_range(group_size_min, group_size_max), left)
		var g: Array = []
		for i in n:
			g.append("R")
		rifle_groups.append(g)
		left -= n
	# Officers walk in the middle of a group (spread over the groups, the first one first).
	for i in w.officers:
		if rifle_groups.is_empty():
			rifle_groups.append(["O"])
			continue
		var g: Array = rifle_groups[(i * rifle_groups.size()) / maxi(w.officers, 1)]
		g.insert(g.size() / 2, "O")
	# Machine-gun teams come after the first group, then between the others.
	var groups: Array = []
	var mg_left: int = w.mg_teams
	for i in rifle_groups.size():
		groups.append(rifle_groups[i])
		if mg_left > 0 and (i % 2 == 0):
			groups.append(["MG"])
			mg_left -= 1
	for i in mg_left:
		groups.append(["MG"])
	return groups


## Brings out the next group (if there is room under max_alive). Returns false to wait.
func _spawn_group() -> bool:
	var spawns := get_tree().get_nodes_in_group("enemy_spawn")
	var targets := get_tree().get_nodes_in_group("attack_point")
	if spawns.is_empty() or targets.is_empty() or _queue.is_empty():
		if spawns.is_empty() or targets.is_empty():
			push_warning("WaveSpawner: no enemy_spawn or attack_point markers in the level.")
		_left_to_spawn = 0
		_queue.clear()
		return true
	var group: Array = _queue[0]
	var size: int = group.size() + (1 if group.has("MG") else 0)
	if alive_count + size > max_alive:
		return false # wait until there is room for the whole group
	_queue.pop_front()
	var spawn: Node3D = spawns[_rng.randi() % spawns.size()]
	for kind: String in group:
		match kind:
			"R":
				var target: Node3D = targets[_spawned_total % targets.size()]
				_spawn_enemy(spawn.global_position, target.global_position)
			"O":
				# Between his men's attack points, a few metres behind them.
				var target: Node3D = targets[_spawned_total % targets.size()]
				_spawn_enemy(spawn.global_position, target.global_position + Vector3(0, 0, -4), officer_scene)
			"MG":
				_spawn_mg_team(spawn.global_position, targets)
	_left_to_spawn -= size
	return true


## A DP-27 gunner and his helper. The gun is set up further back than the riflemen go.
func _spawn_mg_team(near: Vector3, targets: Array) -> void:
	var target: Node3D = targets[(_mg_count * 3 + 1) % targets.size()]
	_mg_count += 1
	var gun_goal: Vector3 = target.global_position + Vector3(0, 0, -_rng.randf_range(mg_position_back_min_m, mg_position_back_max_m))
	var gunner: Enemy = _spawn_enemy(near, gun_goal, mg_gunner_scene)
	var helper: Enemy = _spawn_enemy(near + Vector3(1.5, 0, -1.0), gun_goal + Vector3(1.3, 0, 0.5))
	if gunner and helper:
		gunner.mg_assistant = helper
		helper.mg_gunner = gunner
		var home: Vector3 = target.global_position
		var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
		if terrain:
			home.y = terrain.get_height(home.x, home.z)
		helper.home_point = home
		gunner.home_point = home + Vector3(-1.5, 0.0, 0.0) # where he goes if the team is sent forward


func _spawn_enemy(near: Vector3, goal: Vector3, scene: PackedScene = null) -> Enemy:
	var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
	var pos: Vector3 = near + Vector3(_rng.randf_range(-spawn_spread_m, spawn_spread_m), 0.0, _rng.randf_range(-spawn_spread_m, spawn_spread_m))
	goal += Vector3(_rng.randf_range(-3.0, 3.0), 0.0, _rng.randf_range(-2.0, 2.0)) # don't all stand on one spot
	if terrain:
		pos.y = terrain.get_height(pos.x, pos.z) + 0.1
		goal.y = terrain.get_height(goal.x, goal.z)
	_spawned_total += 1
	var enemy: Enemy = (scene if scene else enemy_scene).instantiate()
	enemy.name = "Enemy_%d" % _spawned_total
	enemy.position = pos
	enemy.rotation.y = PI # face north, towards the trench
	enemy.attack_point = goal
	enemy.died.connect(_on_enemy_died)
	enemies_root.add_child(enemy, true)
	alive_count += 1
	return enemy


## Host: a soldier who did not come out of the forest with a group (T2: the crew of a burning
## tank) joins the battle – he is counted like the others, so the battle only ends when he is
## dead too (and the HUD's "Enemies" count includes him).
func add_enemy(enemy: Enemy) -> void:
	enemy.died.connect(_on_enemy_died)
	alive_count += 1


func _on_enemy_died(_enemy: Enemy) -> void:
	alive_count -= 1
