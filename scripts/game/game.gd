class_name Game
extends Node3D
## Runs one match: spawns a Player for every connected peer.
##
## Only the host spawns players. The MultiplayerSpawner node then automatically
## creates the same players on every other computer. In single player the
## host is the only peer (id 1), so exactly one player is spawned.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

@export var players_root: Node3D ## Spawned players are added under this node.
@export var spawn_points_group: StringName = &"player_spawn" ## Marker3D nodes in this group.
## L3: players come back (respawn) at the far end of the communication trenches, safe behind
## the line. Marker3D nodes in this group, metadata `side` = "west" / "east".
@export var rear_spawn_group: StringName = &"rear_spawn"
@export var respawn_time: float = 5.0 ## Seconds from death to respawn.

var _start_points: Dictionary = {} ## Player name (peer id) -> the spawn point they started the match at.


func _ready() -> void:
	add_to_group("game")
	set_leave_warning(true) # browser: Ctrl+W / closing the tab asks "Leave site?" during the battle
	if not multiplayer.is_server():
		return
	multiplayer.peer_connected.connect(_spawn_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	_spawn_player(multiplayer.get_unique_id()) # the host's own player


func _spawn_player(peer_id: int) -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	var index: int = players_root.get_child_count()
	var spawn := _start_point(index)
	_start_points[str(peer_id)] = _pick_spawn_point(index) # his trench spot for the normal battles
	player.position = spawn.global_position
	player.rotation.y = spawn.global_rotation.y
	player.died.connect(_on_player_died)
	players_root.add_child(player, true)


## Host: wait, then bring the player back at a random rear spawn point (L3: the far end of a
## communication trench, safe behind the line; old levels without them: a trench spawn point).
func _on_player_died(player: Player) -> void:
	var death_count: int = player.deaths
	await get_tree().create_timer(respawn_time, false).timeout # false = the countdown stops while the game is paused
	# Already back (a new battle started meanwhile) or died again since: this timer is out of date.
	if not is_instance_valid(player) or not player.is_dead or player.deaths != death_count:
		return
	var points := _rear_points()
	if points.is_empty():
		points = get_tree().get_nodes_in_group(spawn_points_group)
	var spawn: Node3D = points.pick_random() if not points.is_empty() else self
	if _coming_battle_is_retake():
		spawn = _farthest_from_enemies(points) # L3: as far from the Soviets in the trench as possible
	player.respawn(spawn.global_transform)


## Host: a new battle (day) begins – everyone back to where they started the match, fresh:
## full health, ammo and bandages, off the Maxim, standing. A dead player comes back at once.
func reset_players_to_start() -> void:
	if not multiplayer.is_server():
		return
	var retake: bool = _coming_battle_is_retake()
	var i: int = 0
	for node in get_players():
		var player := node as Player
		var spawn: Node3D = _start_points.get(String(player.name)) as Node3D
		if retake:
			spawn = _start_point(i) # L3: this battle starts at the rear
		elif not is_instance_valid(spawn):
			spawn = _pick_spawn_point(0)
		i += 1
		player.respawn(spawn.global_transform)


func _remove_player(peer_id: int) -> void:
	var player := players_root.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()


## Where player number `index` starts the coming battle: his trench spot – or, L3, when the
## Soviets hold the west half of the trench (battle 6), the rear end of the west communication trench.
func _start_point(index: int) -> Node3D:
	if _coming_battle_is_retake():
		var west := _rear_points("west")
		if not west.is_empty():
			return west[index % west.size()] as Node3D
	return _pick_spawn_point(index)


func _coming_battle_is_retake() -> bool:
	var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	return spawner != null and (spawner.next_wave_is_retake() or spawner.retaking)


## L3: the rear spawn points. While the trench is being retaken only the west ones (the attack
## goes in from there); `side` "" = all.
func _rear_points(side: String = "") -> Array[Node]:
	var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	if side == "" and spawner != null and spawner.retaking:
		side = "west"
	var list: Array[Node] = []
	for node in get_tree().get_nodes_in_group(rear_spawn_group):
		if side == "" or String(node.get_meta("side", "")) == side:
			list.append(node)
	return list


## L3: the spawn point farthest from every living Soviet.
func _farthest_from_enemies(points: Array[Node]) -> Node3D:
	var best: Node3D = self
	var best_d: float = -1.0
	for node in points:
		var m := node as Node3D
		var nearest: float = INF
		for e in get_tree().get_nodes_in_group("enemies"):
			if (e as Enemy).state != Enemy.State.DEAD:
				nearest = minf(nearest, m.global_position.distance_to((e as Node3D).global_position))
		if nearest > best_d:
			best_d = nearest
			best = m
	return best


func _pick_spawn_point(index: int) -> Node3D:
	var points := get_tree().get_nodes_in_group(spawn_points_group)
	if points.is_empty():
		push_warning("No spawn points found - spawning at the origin.")
		return self
	return points[index % points.size()] as Node3D


## All players currently in the game (never assume there is only one).
func get_players() -> Array[Node]:
	return get_tree().get_nodes_in_group("players")


func _exit_tree() -> void:
	set_leave_warning(false) # back in the menu: the tab may close without asking


## Browser only: while `on`, closing the tab (Ctrl+W – easy to hit with W + Ctrl = forward +
## crouch), reloading or leaving the page first asks "Leave site?". Pages can't block Ctrl+W
## itself; the `beforeunload` handler in export_presets.cfg (`html/head_include`) reads this flag.
static func set_leave_warning(on: bool) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.summaLeaveWarning = %s;" % ("true" if on else "false"), true)
