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
@export var respawn_time: float = 5.0 ## Seconds from death to respawn.

var _start_points: Dictionary = {} ## Player name (peer id) -> the spawn point they started the match at.


func _ready() -> void:
	add_to_group("game")
	if not multiplayer.is_server():
		return
	multiplayer.peer_connected.connect(_spawn_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	_spawn_player(multiplayer.get_unique_id()) # the host's own player


func _spawn_player(peer_id: int) -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	var spawn := _pick_spawn_point(players_root.get_child_count())
	_start_points[str(peer_id)] = spawn
	player.position = spawn.global_position
	player.rotation.y = spawn.global_rotation.y
	player.died.connect(_on_player_died)
	players_root.add_child(player, true)


## Host: wait, then bring the player back at a random trench spawn point.
func _on_player_died(player: Player) -> void:
	var death_count: int = player.deaths
	await get_tree().create_timer(respawn_time, false).timeout # false = the countdown stops while the game is paused
	# Already back (a new battle started meanwhile) or died again since: this timer is out of date.
	if not is_instance_valid(player) or not player.is_dead or player.deaths != death_count:
		return
	var points := get_tree().get_nodes_in_group(spawn_points_group)
	var spawn: Node3D = points.pick_random() if not points.is_empty() else self
	player.respawn(spawn.global_transform)


## Host: a new battle (day) begins – everyone back to where they started the match, fresh:
## full health, ammo and bandages, off the Maxim, standing. A dead player comes back at once.
func reset_players_to_start() -> void:
	if not multiplayer.is_server():
		return
	for node in get_players():
		var player := node as Player
		var spawn: Node3D = _start_points.get(String(player.name)) as Node3D
		if not is_instance_valid(spawn):
			spawn = _pick_spawn_point(0)
		player.respawn(spawn.global_transform)


func _remove_player(peer_id: int) -> void:
	var player := players_root.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()


func _pick_spawn_point(index: int) -> Node3D:
	var points := get_tree().get_nodes_in_group(spawn_points_group)
	if points.is_empty():
		push_warning("No spawn points found - spawning at the origin.")
		return self
	return points[index % points.size()] as Node3D


## All players currently in the game (never assume there is only one).
func get_players() -> Array[Node]:
	return get_tree().get_nodes_in_group("players")
