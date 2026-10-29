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


func _ready() -> void:
	if not multiplayer.is_server():
		return
	multiplayer.peer_connected.connect(_spawn_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	_spawn_player(multiplayer.get_unique_id()) # the host's own player


func _spawn_player(peer_id: int) -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	var spawn := _pick_spawn_point(players_root.get_child_count())
	player.position = spawn.global_position
	player.rotation.y = spawn.global_rotation.y
	players_root.add_child(player, true)


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
