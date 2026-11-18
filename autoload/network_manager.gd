extends Node
## NetworkManager (autoload) - creates the connection ("multiplayer peer").
##
## Single player = a host with no clients. Godot starts every game with an
## OfflineMultiplayerPeer, so multiplayer.is_server() is true and our own
## peer id is 1. All game code is written as if it were a network game.
##
## NET1: co-op over ENet (Godot's built-in network connection; desktop only - a browser can't
## use it, the web version needs WebRTC later). The flow:
##   1. Host: host_coop() opens port 7777 and waits in the lobby. Join: join_coop(address).
##   2. The host presses Start: begin_battle() tells every computer to load the battle.
##   3. "Load gate": a computer that is still loading can't receive soldiers yet, so the host's
##      Game waits (paused, no players) until every computer reports its battle scene is there
##      (report_loaded). Then the host places all players and the battle runs.
## After the start nobody new can join (refuse_new_connections); one who drops out just leaves.

signal connection_changed
## The lobby list changed (someone joined or left). Read `lobby_peers`.
signal lobby_changed
## Join: the connection to the host is up (we are in his lobby).
signal joined
## Join: the connection could not be made, or the host went away. `text` says what happened.
signal connection_lost(text: String)
## Host: every computer has its battle scene loaded – the Game may place the players.
signal all_loaded

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
const MAIN_MENU_SCENE: String = "res://ui/main_menu.tscn"
const GAME_SCENE: String = "res://scenes/game.tscn"

## Peer ids in the lobby, host (1) first. Host: the truth; clients: a copy sent by the host.
var lobby_peers: Array[int] = []
## True from begin_battle() until back in the menu: this is a co-op battle.
var coop_battle: bool = false
## Host: the peers whose battle scene is loaded (load gate).
var _loaded: Dictionary = {}
## Host: the peers that were in the lobby when the battle started.
var _battle_peers: Array[int] = []
## A message for the main menu after a co-op game ended badly ("The host left").
var last_message: String = ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Start a local game with no network (used by "Single Player").
func start_single_player() -> void:
	_reset_coop()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_changed.emit()


## False in the browser: ENet needs real network sockets, which a web page doesn't have.
static func coop_available() -> bool:
	return not OS.has_feature("web")


## Open a co-op game on `port` and wait in the lobby for others to join.
func host_coop(port: int = DEFAULT_PORT) -> Error:
	if not coop_available():
		return ERR_UNAVAILABLE
	_reset_coop()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	lobby_peers = [1]
	connection_changed.emit()
	lobby_changed.emit()
	return OK


## Join the co-op game at `address` ("127.0.0.1" = this same computer). `joined` or
## `connection_lost` tells how it went.
func join_coop(address: String, port: int = DEFAULT_PORT) -> Error:
	if not coop_available():
		return ERR_UNAVAILABLE
	_reset_coop()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address.strip_edges() if address.strip_edges() != "" else "127.0.0.1", port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	connection_changed.emit()
	return OK


## Close any connection (back to "no network").
func close_connection() -> void:
	_reset_coop()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_changed.emit()


## Back to the main menu: close any connection and unpause.
func leave_game() -> void:
	# Stop the battle first: once the connection is closed this computer counts as "the host"
	# (offline), and the host-only code must not run on a client's battle for the frame that is
	# left before the scene change.
	var scene := get_tree().current_scene
	if scene and scene != self:
		scene.process_mode = Node.PROCESS_MODE_DISABLED
	close_connection()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## True when playing alone (no network) - only then may the game pause.
func is_single_player() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer


## True when this computer decides the game state (host or single player).
func is_host() -> bool:
	return multiplayer.is_server()


## True while connected to a co-op game (lobby or battle).
func is_coop() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer


# --- Lobby ---------------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not is_coop() or not multiplayer.is_server():
		return
	if coop_battle:
		return # the battle already runs (new connections are refused anyway)
	if not lobby_peers.has(id):
		lobby_peers.append(id)
		print("Co-op: soldier %d joined the lobby (peer id %d)." % [lobby_peers.size(), id])
	_send_lobby()


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if lobby_peers.has(id):
		print("Co-op: peer %d left." % id)
	lobby_peers.erase(id)
	_battle_peers.erase(id)
	_loaded.erase(id)
	_send_lobby()
	_check_all_loaded() # the one we were waiting for left


func _send_lobby() -> void:
	lobby_changed.emit()
	if is_coop() and multiplayer.get_peers().size() > 0:
		_lobby_list.rpc(lobby_peers)


## Host → everyone: who is in the lobby.
@rpc("authority", "call_remote", "reliable")
func _lobby_list(ids: Array) -> void:
	lobby_peers.clear()
	for id in ids:
		lobby_peers.append(int(id))
	lobby_changed.emit()


func _on_connected_to_server() -> void:
	joined.emit()


func _on_connection_failed() -> void:
	close_connection()
	connection_lost.emit("Could not reach the host.")


func _on_server_disconnected() -> void:
	var in_battle: bool = coop_battle
	last_message = "The host left the game."
	if in_battle:
		leave_game() # stops the battle, closes the connection, back to the menu
		return
	close_connection()
	connection_lost.emit(last_message)
	last_message = "" # shown in the lobby instead


# --- Starting the battle -------------------------------------------------------------------

## Host: everyone in the lobby loads the battle. `test_wave` > 0 = Test mode (editor / tests).
func begin_battle(test_wave: int = 0) -> void:
	if not is_coop() or not multiplayer.is_server():
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	_battle_peers = lobby_peers.duplicate()
	_loaded.clear()
	_load_battle.rpc(Settings.difficulty, test_wave)


## Host → everyone (and the host itself): load the battle.
@rpc("authority", "call_local", "reliable")
func _load_battle(difficulty: int, test_wave: int) -> void:
	coop_battle = true
	RunSave.active = false # owner 2026-11-18: co-op never touches the single-player saved run
	MatchDirector.test_start_wave = test_wave
	if multiplayer.is_server():
		Settings.difficulty = difficulty
	MainMenu.start_pressed_msec = Time.get_ticks_msec()
	LoadingScreen.go(get_tree(), GAME_SCENE)


## Called by the Game when its scene is in the tree on this computer (load gate).
func report_loaded() -> void:
	if multiplayer.is_server():
		_peer_loaded(1)
	else:
		_peer_loaded.rpc_id(1, multiplayer.get_unique_id())


@rpc("any_peer", "call_remote", "reliable")
func _peer_loaded(id: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 0 and multiplayer.get_remote_sender_id() != id:
		return # a computer can only speak for itself
	_loaded[id] = true
	_check_all_loaded()


func _check_all_loaded() -> void:
	if not coop_battle or not _loaded.has(1):
		return
	for id in _battle_peers:
		if not _loaded.has(id):
			return
	all_loaded.emit()


## Host: the peers that take part in this battle (the Game spawns a player for each).
func battle_peers() -> Array[int]:
	return _battle_peers.duplicate()


## Host: true while the load gate is still waiting for someone.
func waiting_for_peers() -> bool:
	if not coop_battle or not multiplayer.is_server():
		return false
	for id in _battle_peers:
		if not _loaded.has(id):
			return true
	return false


func _reset_coop() -> void:
	coop_battle = false
	lobby_peers.clear()
	_battle_peers.clear()
	_loaded.clear()
