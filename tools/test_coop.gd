extends Node
## NET1 automated co-op test (not part of the game): two copies of the game on one computer,
## connected over ENet (localhost). This copy is the host; it starts the second copy (the
## client) itself with the same script and `--role=client`:
##   godot --headless --path . --script tools/run.gd -- tools/test_coop.gd
## Checks: lobby, load gate, both players on both computers, Soviets made on the client,
## the client's own player follows the host, a shot from the client kills a Soviet (credited
## to the client), and the client's player goes away when he leaves.
## Both copies run this same script, so its RPCs match (they live at /root/TestRunner).

const PORT: int = 7791
const TIMEOUT: float = 120.0

var role: String = "host"
var fails := 0
var client_pid: int = -1
var _client_lines: PackedStringArray = []
var _client_done: bool = false
var _shoot_request: String = ""
var _finish: bool = false


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + ("[%s] " % role) + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Wait until `cond` is true (or `seconds` have gone). Returns the last value.
func wait_for(cond: Callable, seconds: float) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func players() -> Array[Node]:
	return get_tree().get_nodes_in_group("players")


func local_player() -> Player:
	for n in players():
		if (n as Player).is_local_player():
			return n as Player
	return null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--role=client":
			role = "client"
	await get_tree().process_frame
	if role == "client":
		await _run_client()
	else:
		await _run_host()


# --- Host ------------------------------------------------------------------------------------

func _run_host() -> void:
	check(NetworkManager.host_coop(PORT) == OK, "host opens port %d" % PORT)
	check(NetworkManager.lobby_peers == [1], "lobby lists only the host at first")
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "tools/run.gd", "--", "tools/test_coop.gd", "--role=client"])
	client_pid = OS.create_process(OS.get_executable_path(), args)
	check(client_pid > 0, "client copy started (pid %d)" % client_pid)
	var joined: bool = await wait_for(func() -> bool: return NetworkManager.lobby_peers.size() == 2, 30.0)
	check(joined, "client joined the lobby")
	if not joined:
		_end()
		return
	var client_id: int = NetworkManager.lobby_peers[1]
	await frames(10)
	NetworkManager.begin_battle(1) # Test mode battle 1: the wave comes after 3 s
	check((multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections, "no new connections once the battle starts")
	# The load gate: the host's battle waits with nobody in it until the client is loaded.
	var gated: bool = await wait_for(func() -> bool: return get_tree().get_first_node_in_group("game") != null, 30.0)
	check(gated, "host loaded the battle")
	var two: bool = await wait_for(func() -> bool: return players().size() == 2, TIMEOUT)
	check(two, "both players exist on the host (load gate opened)")
	if not two:
		_end()
		return
	var cp := get_tree().get_first_node_in_group("game").get_node("Players/%d" % client_id) as Player
	check(cp != null and cp.get_peer_id() == client_id, "the client's player is named after his peer id")
	check(cp != null and not cp.is_local_player(), "the client's player is not the host's local player")
	check(not get_tree().paused, "host's battle runs once everyone is in")
	# Soviets come.
	var enemies: bool = await wait_for(func() -> bool: return get_tree().get_nodes_in_group("enemies").size() > 0, 40.0)
	check(enemies, "Soviets spawned on the host")
	if not enemies or cp == null:
		_end()
		return
	await get_tree().create_timer(1.5).timeout
	# Stage a shot: the client's soldier stands in the open field, a Soviet 8 m in front of him.
	var ground := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 50, z), Vector3(x, -50, z), 1)
		var hit: Dictionary = cp.get_world_3d().direct_space_state.intersect_ray(q)
		return float(hit.position.y) if not hit.is_empty() else 0.0
	var px: float = 0.0
	var pz: float = 25.0
	cp.respawn(Transform3D(Basis.IDENTITY, Vector3(px, ground.call(px, pz) + 0.1, pz))) # facing -z (the field)
	var enemy: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and (e as Enemy).state != Enemy.State.DEAD and not (e as Enemy).is_in_group("tanks"):
			enemy = e
			break
	check(enemy != null, "a living Soviet to aim at")
	if enemy == null:
		_end()
		return
	var ez: float = pz - 8.0
	enemy.global_position = Vector3(px, ground.call(px, ez) + 0.05, ez)
	enemy.velocity = Vector3.ZERO
	enemy.set_physics_process(false) # stand still for the shot (his StateSync still runs)
	await get_tree().create_timer(0.6).timeout
	_shoot.rpc_id(client_id, String(enemy.name))
	var dead: bool = await wait_for(func() -> bool: return not is_instance_valid(enemy) or enemy.state == Enemy.State.DEAD, 15.0)
	check(dead, "a shot from the client killed the Soviet (host decides)")
	check(cp.kills >= 1, "the kill counts for the client (%d)" % cp.kills)
	var reported: bool = await wait_for(func() -> bool: return _client_done, 20.0)
	check(reported, "client sent its report")
	for line in _client_lines:
		print(line)
		if line.begins_with("FAIL"):
			fails += 1
	# The client leaves: his player goes away on the host.
	_quit_client.rpc_id(client_id)
	var gone: bool = await wait_for(func() -> bool: return players().size() == 1, 15.0)
	check(gone, "the client's player is removed when he leaves")
	_end()


@rpc("any_peer", "call_remote", "reliable")
func _client_report(lines: PackedStringArray) -> void:
	_client_lines = lines
	_client_done = true


func _end() -> void:
	if client_pid > 0 and OS.is_process_running(client_pid):
		await get_tree().create_timer(2.0).timeout
		if OS.is_process_running(client_pid):
			OS.kill(client_pid)
	NetworkManager.close_connection()
	print("RESULT: %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


# --- Client ----------------------------------------------------------------------------------

var _lines: PackedStringArray = []


func ccheck(cond: bool, msg: String) -> void:
	var line: String = ("PASS  " if cond else "FAIL  ") + "[client] " + msg
	print(line)
	_lines.append(line)


@rpc("authority", "call_remote", "reliable")
func _shoot(enemy_name: String) -> void:
	_shoot_request = enemy_name


@rpc("authority", "call_remote", "reliable")
func _quit_client() -> void:
	_finish = true


func _run_client() -> void:
	# The host may still be opening its port: try a few times.
	var connected: bool = false
	for attempt in 10:
		NetworkManager.join_coop("127.0.0.1", PORT)
		connected = await wait_for(func() -> bool:
			return multiplayer.multiplayer_peer is ENetMultiplayerPeer \
					and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 3.0)
		if connected:
			break
	ccheck(connected, "connected to the host")
	if not connected:
		get_tree().quit(1)
		return
	var lobby: bool = await wait_for(func() -> bool: return NetworkManager.lobby_peers.size() == 2, 10.0)
	ccheck(lobby, "client sees both soldiers in the lobby")
	var started: bool = await wait_for(func() -> bool: return NetworkManager.coop_battle, 30.0)
	ccheck(started, "host's Start reached the client")
	var both: bool = await wait_for(func() -> bool: return players().size() == 2, TIMEOUT)
	ccheck(both, "both players exist on the client")
	var me := local_player()
	ccheck(me != null and me.get_peer_id() == multiplayer.get_unique_id(), "the client has its own local player")
	ccheck(me != null and me.input.is_multiplayer_authority(), "the client controls its own input")
	var enemies: bool = await wait_for(func() -> bool: return get_tree().get_nodes_in_group("enemies").size() > 0, 40.0)
	ccheck(enemies, "Soviets appear on the client (MultiplayerSpawner)")
	var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	var synced: bool = await wait_for(func() -> bool: return spawner != null and spawner.wave_number >= 1, 10.0)
	ccheck(synced, "wave number is synced to the client (WaveSync)")
	var asked: bool = await wait_for(func() -> bool: return _shoot_request != "", 60.0)
	ccheck(asked, "host asked for the test shot")
	if asked and me != null:
		var game := get_tree().get_first_node_in_group("game")
		var enemy := game.get_node_or_null("Enemies/" + _shoot_request) as Enemy
		ccheck(enemy != null, "the Soviet exists on the client under the same name")
		# Own position comes from the host (respawn into the field at z = 25).
		var moved: bool = await wait_for(func() -> bool: return absf(me.global_position.z - 25.0) < 1.0, 5.0)
		ccheck(moved, "the host moved the client's soldier (synced position %s)" % str(me.global_position))
		if enemy:
			await wait_for(func() -> bool: return enemy.global_position.distance_to(me.global_position) < 10.0, 5.0)
			var tries: int = 0
			while tries < 12 and is_instance_valid(enemy) and enemy.state != Enemy.State.DEAD:
				var origin: Vector3 = me.camera.global_position
				var target: Vector3 = enemy.global_position + Vector3.UP * 1.1
				me.weapons.server_fire.rpc_id(1, origin, (target - origin).normalized())
				tries += 1
				await get_tree().create_timer(1.6).timeout # Mosin bolt time
			ccheck(not is_instance_valid(enemy) or enemy.state == Enemy.State.DEAD, "the client sees the Soviet die (after %d shots)" % tries)
	_client_report.rpc_id(1, _lines)
	await wait_for(func() -> bool: return _finish, 30.0)
	NetworkManager.leave_game() # like the pause menu's "Main menu"
	await frames(10)
	get_tree().quit(0)
