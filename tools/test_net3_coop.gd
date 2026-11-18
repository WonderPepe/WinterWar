extends Node
## NET3 two-copy test (not part of the game): a host and a headless client on one computer.
## The client watches the walking Soviets for a few seconds and measures how evenly they move
## on his screen (smoothed) compared with the newest network update (= before NET3), and
## how far behind the host's real position they are drawn. Run from the project folder:
##   godot --headless --path . --script tools/run.gd -- tools/test_net3_coop.gd [--lag] [--log=file]
## --lag starts the client with the lag simulator (--net-lag=100 --net-jitter=20 --net-loss=2).

const PORT: int = 7793

var role: String = "host"
var lag: bool = false
var fails := 0
var client_pid: int = -1
var client_id: int = 0
var _result: Dictionary = {}
var _have_result: bool = false
var _quit: bool = false
# client: measuring
var _measuring: bool = false
var _tracks: Dictionary = {} # enemy name -> {shown: [Vector3], raw: [Vector3]}


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func wait_for(cond: Callable, seconds: float) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func sec(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ready() -> void:
	var log_path: String = ProjectSettings.globalize_path("user://net3_client.log")
	for a in OS.get_cmdline_user_args():
		if a == "--role=client":
			role = "client"
		elif a == "--lag":
			lag = true
		elif a.begins_with("--log="):
			log_path = a.get_slice("=", 1)
	await get_tree().process_frame
	if role == "client":
		await _run_client()
	else:
		await _run_host(log_path)


# --- Host --------------------------------------------------------------------------------
func _run_host(log_path: String) -> void:
	Engine.max_fps = 144
	check(NetworkManager.host_coop(PORT) == OK, "host opens the port")
	var extra: String = " --net-lag=100 --net-jitter=20 --net-loss=2" if lag else ""
	var cmd: String = "'%s' --headless --path '%s' --script tools/run.gd -- tools/test_net3_coop.gd --role=client --mute%s > '%s' 2>&1" % [
			OS.get_executable_path(), ProjectSettings.globalize_path("res://"), extra, log_path]
	client_pid = OS.create_process("bash", ["-c", cmd])
	print("client log: ", log_path, "   lag simulator: ", lag)
	if not await wait_for(func() -> bool: return NetworkManager.lobby_peers.size() == 2, 30.0):
		check(false, "client joined")
		_end()
		return
	client_id = NetworkManager.lobby_peers[1]
	NetworkManager.begin_battle(1)
	await wait_for(func() -> bool: return get_tree().get_first_node_in_group("game") != null, 30.0)
	var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	spawner.start_at_wave(1, 1.0)
	await wait_for(func() -> bool: return get_tree().get_nodes_in_group("players").size() == 2, 120.0)
	for p in get_tree().get_nodes_in_group("players"):
		(p as Player).god_mode = true
	# Wait until Soviets are on the field and walking.
	var walking := func() -> bool:
		var n := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if (e as Enemy).velocity.length() > 0.8:
				n += 1
		return n >= 3
	check(await wait_for(walking, 90.0), "Soviets are walking on the host")
	await sec(1.0)
	_measure.rpc_id(client_id, 3.0)
	check(await wait_for(func() -> bool: return _have_result, 20.0), "client sent its measurements")
	var r: Dictionary = _result
	print("client result: ", r)
	# Where the host has them now vs. where the client drew them a moment ago.
	var behind: Array = []
	var shown: Dictionary = r.get("last_shown", {})
	for n: String in shown:
		var e := get_tree().get_first_node_in_group("enemies") as Enemy
		for node in get_tree().get_nodes_in_group("enemies"):
			if node.name == n:
				e = node
		if e and e.name == n:
			behind.append((shown[n] as Vector3).distance_to(e.global_position))
	var tracked: int = r.get("tracked", 0)
	check(tracked >= 3, "client tracked %d walking Soviets" % tracked)
	var smooth: float = r.get("jerk_shown", 99.0)
	var raw: float = r.get("jerk_raw", 0.0)
	check(smooth < raw * 0.5, "smoothed movement is much more even than the raw updates (jerk %.4f vs %.4f m)" % [smooth, raw])
	var delay: float = r.get("delay", 0.0)
	if lag:
		check(delay > 0.04 and delay <= 0.151, "bad connection: drawing delay grows (%d ms, max 150)" % (delay * 1000.0))
	else:
		check(delay >= 0.029 and delay < 0.07, "same network: drawing delay is short (%d ms)" % (delay * 1000.0))
	var ups: float = r.get("updates_per_second", 0.0)
	check(ups > (40.0 if lag else 50.0), "about 60 updates a second arrive (%.0f)" % ups)
	check(r.get("snaps", 99) == 0, "no jumps while walking (%d)" % r.get("snaps", 99))
	check(r.get("own_not_delayed", false), "the client's own soldier is not delayed (own_player)")
	behind.sort()
	var median: float = behind[behind.size() / 2] if not behind.is_empty() else 99.0
	var limit: float = 0.9 if lag else 0.35
	check(median < limit, "drawn close to the host's real position (median %.2f m behind, limit %.2f)" % [median, limit])
	_end()


func _end() -> void:
	if client_id != 0:
		_finish.rpc_id(client_id)
	await sec(2.0)
	if client_pid > 0 and OS.is_process_running(client_pid):
		OS.kill(client_pid)
	NetworkManager.close_connection()
	print("RESULT: %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


@rpc("any_peer", "call_remote", "reliable")
func _report(d: Dictionary) -> void:
	_result = d
	_have_result = true


# --- Client ------------------------------------------------------------------------------
@rpc("authority", "call_remote", "reliable")
func _finish() -> void:
	_quit = true


@rpc("authority", "call_remote", "reliable")
func _measure(seconds: float) -> void:
	_tracks = {}
	_measuring = true
	await sec(seconds)
	_measuring = false
	# "Jerk": how much each frame's step differs from the one before (0 = perfectly even).
	var jerk_shown := 0.0
	var jerk_raw := 0.0
	var count := 0
	var last_shown := {}
	for n: String in _tracks:
		var t: Dictionary = _tracks[n]
		var s: Array = t.shown
		var r: Array = t.raw
		if s.size() < 60:
			continue
		var moved: float = (s[-1] as Vector3).distance_to(s[0])
		if moved < 1.0:
			continue # stood still most of the time
		count += 1
		jerk_shown += _jerk(s)
		jerk_raw += _jerk(r)
		last_shown[n] = s[-1]
	var d := {"tracked": count, "jerk_shown": jerk_shown / maxf(count, 1), "jerk_raw": jerk_raw / maxf(count, 1),
			"last_shown": last_shown}
	var delays := 0.0
	var nd := 0
	var snaps := 0
	var ups := 0.0
	var own_ok := false
	for node in get_tree().get_nodes_in_group("net_smoothers"):
		var sm := node as NetSmoother
		if sm.own_player:
			own_ok = sm.get_parent() is Player and (sm.get_parent() as Player).is_local_player()
			continue
		if sm.get_parent() is Enemy and _tracks.has(String(sm.get_parent().name)):
			delays += sm.delay
			nd += 1
			snaps += sm.snaps
			ups = maxf(ups, sm.updates_per_second)
	d.delay = delays / maxf(nd, 1)
	d.snaps = snaps
	d.updates_per_second = ups
	d.own_not_delayed = own_ok
	_report.rpc_id(1, d)


func _jerk(points: Array) -> float:
	var total := 0.0
	for i in range(2, points.size()):
		var a: Vector3 = (points[i] as Vector3) - (points[i - 1] as Vector3)
		var b: Vector3 = (points[i - 1] as Vector3) - (points[i - 2] as Vector3)
		total += (a - b).length()
	return total / maxf(points.size() - 2, 1)


func _process(_delta: float) -> void:
	if not _measuring:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e.state == Enemy.State.DEAD:
			continue
		var sm := e.get_node("Smoother") as NetSmoother
		var n := String(e.name)
		if not _tracks.has(n):
			_tracks[n] = {"shown": [], "raw": []}
		_tracks[n].shown.append(e.global_position)
		_tracks[n].raw.append(sm.net_position) # the newest update = what was drawn before NET3


func _run_client() -> void:
	Engine.max_fps = 144 # like a fast monitor (headless would otherwise run thousands of frames)
	var ok: bool = false
	for attempt in 10:
		NetworkManager.join_coop("127.0.0.1", PORT)
		ok = await wait_for(func() -> bool:
			return multiplayer.multiplayer_peer is ENetMultiplayerPeer \
					and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 3.0)
		if ok:
			break
	if not ok:
		get_tree().quit(1)
		return
	await wait_for(func() -> bool: return _quit, 300.0)
	NetworkManager.leave_game()
	await sec(0.5)
	get_tree().quit(0)
