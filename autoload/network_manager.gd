extends Node
## NetworkManager (autoload) - creates the connection ("multiplayer peer").
##
## Single player = a host with no clients. Godot starts every game with an
## OfflineMultiplayerPeer, so multiplayer.is_server() is true and our own
## peer id is 1. All game code is written as if it were a network game,
## so adding real hosting/joining later only means filling in the functions below.

signal connection_changed

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
const MAIN_MENU_SCENE: String = "res://ui/main_menu.tscn"


## Start a local game with no network (used by "Single Player").
func start_single_player() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_changed.emit()


## Placeholder for co-op hosting (WebRTC later).
func host_coop() -> Error:
	push_warning("Co-op hosting is not implemented yet.")
	return ERR_UNAVAILABLE


## Placeholder for co-op joining (WebRTC later).
func join_coop(_address: String) -> Error:
	push_warning("Co-op joining is not implemented yet.")
	return ERR_UNAVAILABLE


## Back to the main menu: close any connection and unpause.
func leave_game() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## True when playing alone (no network) - only then may the game pause.
func is_single_player() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer


## True when this computer decides the game state (host or single player).
func is_host() -> bool:
	return multiplayer.is_server()
