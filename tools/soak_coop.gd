extends Node
## NET2 co-op scenario (not part of the game): two copies on one computer, the second one
## (the client, "player 2") does everything a player can do, the host checks the result and
## asks the client what its own screen shows. Run from the project folder:
##   godot --headless --path . --script tools/run.gd -- tools/soak_coop.gd [--log=/tmp/coop_client.log]
## The client copy's own output goes to the --log file (default user://coop_client.log), so
## its errors can be read afterwards. Both copies run this same script (matching RPCs).

const PORT: int = 7792

var role: String = "host"
var fails := 0
var client_pid: int = -1
var client_id: int = 0
var cp: Player ## host: the client's player
var _snap: Dictionary = {}
var _snap_n: int = 0
var _quit: bool = false


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


func players() -> Array[Node]:
	return get_tree().get_nodes_in_group("players")


func local_player() -> Player:
	for n in players():
		if (n as Player).is_local_player():
			return n as Player
	return null


func _ready() -> void:
	var log_path: String = ProjectSettings.globalize_path("user://coop_client.log")
	for a in OS.get_cmdline_user_args():
		if a == "--role=client":
			role = "client"
		elif a.begins_with("--log="):
			log_path = a.get_slice("=", 1)
	await get_tree().process_frame
	if role == "client":
		await _run_client()
	else:
		await _run_host(log_path)


# --- Host side ----------------------------------------------------------------------------

## Ask the client to do something with its own player (as if he pressed a key).
func act(what: String, value: Variant = null) -> void:
	_do.rpc_id(client_id, what, value)
	await sec(0.05)


## The client's view of things, fresh.
func snap() -> Dictionary:
	var n: int = _snap_n
	_ask_snapshot.rpc_id(client_id)
	await wait_for(func() -> bool: return _snap_n > n, 5.0)
	return _snap


func ground_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 50, z), Vector3(x, -50, z), 1)
	var hit: Dictionary = cp.get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else 0.0


func place(pos: Vector3, yaw: float = 0.0) -> void:
	cp.respawn(Transform3D(Basis(Vector3.UP, yaw), pos))
	await sec(0.4)


func _run_host(log_path: String) -> void:
	check(NetworkManager.host_coop(PORT) == OK, "host opens the port")
	var cmd: String = "'%s' --headless --path '%s' --script tools/run.gd -- tools/soak_coop.gd --role=client --mute > '%s' 2>&1" % [
			OS.get_executable_path(), ProjectSettings.globalize_path("res://"), log_path]
	client_pid = OS.create_process("bash", ["-c", cmd])
	print("client log: ", log_path)
	if not await wait_for(func() -> bool: return NetworkManager.lobby_peers.size() == 2, 30.0):
		check(false, "client joined")
		_end()
		return
	client_id = NetworkManager.lobby_peers[1]
	NetworkManager.begin_battle(1)
	await wait_for(func() -> bool: return get_tree().get_first_node_in_group("game") != null, 30.0)
	var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	spawner.start_at_wave(1, 6.0)
	if not await wait_for(func() -> bool: return players().size() == 2, 120.0):
		check(false, "both players in the battle")
		_end()
		return
	var game := get_tree().get_first_node_in_group("game") as Game
	cp = game.get_node("Players/%d" % client_id) as Player
	var hp := local_player()
	await sec(1.5)

	# --- What player 2 sees at the start
	var s: Dictionary = await snap()
	print("client snapshot at start: ", s)
	check(s.get("camera_is_mine", false), "client: the view is his own soldier's camera")
	check(s.get("my_view_model", false), "client: his own first-person gun is shown")
	check(not s.get("my_body_visible", true), "client: his own third-person body is hidden")
	check(s.get("host_body_visible", false), "client: the host's soldier body is shown")
	check(not s.get("host_view_model", true), "client: the host's first-person gun is hidden")
	check(String(s.get("next_wave", "")).contains("begins in"), "client: countdown shown (%s)" % s.get("next_wave", ""))
	check(not s.get("paused", true), "client: the game is not paused")
	check(s.get("hud_player", "") == str(client_id), "client: the HUD follows his own soldier")
	check(s.get("mouse_captured", false) or s.get("headless", false), "client: mouse captured (or headless)")
	check(s.get("muted", false), "client: --mute silences his window")
	check(not AudioServer.is_bus_mute(0), "host: not muted (no --mute)")

	# --- Walking
	var start_pos: Vector3 = cp.global_position
	await act("move", Vector2(1, 0)) # along the trench
	await sec(1.5)
	await act("move", Vector2.ZERO)
	await sec(0.3)
	var walked: float = cp.global_position.distance_to(start_pos)
	check(walked > 2.0, "host: player 2 walks with his own keys (%.1f m)" % walked)
	s = await snap()
	check(Vector3(s.get("my_pos", Vector3.ZERO)).distance_to(cp.global_position) < 0.6, "client: his position follows the host's")

	# --- Firing the Mosin
	var ammo0: int = cp.weapons.get_mag_ammo()
	await act("fire", true)
	await sec(0.3)
	await act("fire", false)
	await sec(0.5)
	check(cp.weapons.get_mag_ammo() == ammo0 - 1, "host: one Mosin shot from player 2 (%d → %d)" % [ammo0, cp.weapons.get_mag_ammo()])
	s = await snap()
	check(int(s.get("mag_ammo", -1)) == cp.weapons.get_mag_ammo(), "client: HUD ammo matches (%s)" % s.get("ammo_text", ""))

	# --- Reload, switch to the Suomi
	await act("reload")
	await sec(0.3)
	check(cp.weapons.is_reloading, "host: player 2 reloads")
	await wait_for(func() -> bool: return not cp.weapons.is_reloading, 8.0)
	check(cp.weapons.get_mag_ammo() == ammo0, "host: magazine full again")
	await act("switch", 1)
	await sec(1.0)
	check(cp.weapons.current_slot == 1, "host: switched to the Suomi")
	s = await snap()
	check(int(s.get("slot", -1)) == 1 and String(s.get("weapon_name", "")).contains("Suomi"), "client: HUD shows the Suomi (%s)" % s.get("weapon_name", ""))
	var suomi0: int = cp.weapons.get_mag_ammo()
	await act("fire", true)
	await sec(1.6) # (the first burst of a life starts with cocking the gun, W3)
	await act("fire", false)
	await sec(0.4)
	check(cp.weapons.get_mag_ammo() < suomi0 - 5, "host: a Suomi burst from player 2 (%d → %d)" % [suomi0, cp.weapons.get_mag_ammo()])
	await act("switch", 0)
	await sec(1.0)

	# --- The Maxim
	var gun := get_tree().get_first_node_in_group("mounted_guns") as MountedGun
	if gun:
		await place(gun.exit_point.global_position, gun.global_rotation.y)
		await act("interact")
		await sec(0.6)
		check(cp.get_mounted_gun() == gun and gun.user_id == client_id, "host: player 2 is on the Maxim")
		s = await snap()
		check(s.get("on_gun", false), "client: he is on the Maxim on his own screen")
		check(String(s.get("weapon_name", "")).contains("Maxim"), "client: HUD shows the Maxim (%s)" % s.get("weapon_name", ""))
		var belt: int = gun.ammo
		await act("fire", true)
		await sec(0.8)
		await act("fire", false)
		await sec(0.3)
		check(gun.ammo < belt - 3, "host: player 2 fires the Maxim (%d → %d)" % [belt, gun.ammo])
		s = await snap()
		check(int(s.get("maxim_ammo", -1)) == gun.ammo, "client: Maxim belt count matches (%s / %d)" % [s.get("maxim_ammo", -1), gun.ammo])
		await act("interact")
		await sec(0.6)
		check(cp.get_mounted_gun() == null and gun.is_free(), "host: player 2 leaves the Maxim")
		s = await snap()
		check(not s.get("on_gun", true) and s.get("my_view_model", false), "client: off the gun, his rifle is back")

	# --- Molotov
	var crates := get_tree().get_nodes_in_group("molotov_crates")
	if not crates.is_empty():
		var crate := crates[0] as Node3D
		await place(crate.global_position + crate.global_basis.z * 0.7 + Vector3(0, 0.1, 0))
		await act("interact")
		await sec(0.4)
		check(cp.molotov.count == cp.molotov.max_carry, "host: player 2 took Molotov cocktails (%d)" % cp.molotov.count)
		await act("molotov")
		await sec(0.5)
		check(cp.molotov.phase == MolotovHandler.Phase.HELD, "host: bottle in player 2's hand")
		s = await snap()
		check(int(s.get("molotov_phase", -1)) == MolotovHandler.Phase.HELD and s.get("bottle_shown", false), "client: he sees the bottle in his hand")
		await act("aim", true)
		await wait_for(func() -> bool: return cp.molotov.phase == MolotovHandler.Phase.LIT, 5.0)
		check(cp.molotov.phase == MolotovHandler.Phase.LIT, "host: player 2 lit the bottle (right mouse)")
		await act("look", Vector2(0.0, deg_to_rad(25.0)))
		var thrown0: int = cp.molotov.thrown
		await act("throw")
		await sec(1.0)
		await act("aim", false)
		check(cp.molotov.thrown == thrown0 + 1, "host: player 2 threw it")
		s = await snap()
		check(int(s.get("molotov_count", -1)) == cp.molotov.count, "client: bottles left match (%s)" % s.get("molotov_count", -1))
		await act("look", Vector2(0.0, 0.0))
		await sec(2.5) # let it burn out of the way

	# --- A grenade lands next to player 2: he throws it back
	var gm := get_tree().get_first_node_in_group("grenades") as GrenadeManager
	if gm:
		var gx: float = -20.0
		var gz: float = 61.0
		await place(Vector3(gx, -1.4, gz), 0.0)
		var tb0: int = cp.grab.thrown_back
		var gid: int = gm.throw(cp.global_position + Vector3(0.8, 0.1, 0), Vector3.ZERO, -1, false, 3.8)
		await sec(0.5)
		s = await snap()
		check(int(s.get("grabbable", -1)) >= 0, "client: the [F] mark shows on the grenade near him")
		await act("interact")
		await sec(1.2)
		check(gm.position_of(gid) == Vector3.INF or cp.grab.thrown_back == tb0 + 1, "host: player 2 grabbed it")
		await wait_for(func() -> bool: return cp.grab.thrown_back == tb0 + 1, 3.0)
		check(cp.grab.thrown_back == tb0 + 1, "host: player 2 threw it back (%d)" % cp.grab.thrown_back)
		s = await snap()
		check(int(s.get("thrown_back", -1)) == cp.grab.thrown_back, "client: his 'thrown back' count matches (%s)" % s.get("thrown_back", -1))
		check(cp.health > 0 and not cp.is_dead, "host: player 2 survived his own throw-back")
		await sec(4.0)

	# --- Climbing out of the trench (front wall: in front of him is -z)
	await place(Vector3(-20.0, -1.4, 61.0), 0.0)
	var wall_hit := cp.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(Vector3(-20, -0.4, 61), Vector3(-20, -0.4, 50), 1))
	if not wall_hit.is_empty():
		await place(Vector3(-20.0, -1.4, wall_hit.position.z + 0.45), 0.0)
	await act("move", Vector2(0, -1))
	await sec(0.3)
	await act("jump")
	var climbing: bool = await wait_for(func() -> bool: return cp.is_climbing, 1.5)
	check(climbing, "host: player 2 climbs out of the trench")
	s = await snap()
	check(s.get("climbing", false) or not climbing, "client: he is climbing on his own screen")
	await act("move", Vector2.ZERO)
	await wait_for(func() -> bool: return not cp.is_climbing, 3.0)
	check(cp.global_position.y > -0.5, "host: player 2 got out (y %.1f)" % cp.global_position.y)

	# --- Hurt, bandage
	await place(Vector3(20.0, -1.4, 61.0), 0.0)
	cp.take_damage(55.0, -1, cp.global_position + Vector3(0, 1, -1), Vector3.BACK)
	await sec(0.4)
	s = await snap()
	check(int(s.get("health", -1)) == cp.health, "client: his health bar shows %s (host %d)" % [s.get("health", -1), cp.health])
	check(s.get("hurt_flash", false), "client: he gets the red hurt flash / direction")
	var hb: int = cp.health
	await act("bandage")
	await wait_for(func() -> bool: return cp.health > hb, cp.bandage_time + 2.0)
	check(cp.health > hb, "host: player 2 bandaged himself (%d → %d)" % [hb, cp.health])

	# --- Death and respawn
	cp.take_damage(1000.0, -1, cp.global_position + Vector3(0, 1, -1), Vector3.BACK)
	await sec(0.5)
	check(cp.is_dead, "host: player 2 is dead")
	s = await snap()
	check(s.get("death_screen", false), "client: he sees the death screen")
	check(not s.get("my_view_model", true), "client: no gun in his hands while dead")
	await wait_for(func() -> bool: return not cp.is_dead, game.respawn_time + 3.0)
	check(not cp.is_dead and cp.health == cp.max_health, "host: player 2 came back after %.0f s" % game.respawn_time)
	s = await snap()
	await sec(0.5)
	s = await snap()
	check(not s.get("death_screen", true), "client: death screen gone after the respawn")
	check(s.get("my_view_model", false), "client: his gun is back after the respawn")
	print("client snapshot after respawn: ", s)
	check(Vector3(s.get("my_pos", Vector3.ZERO)).distance_to(cp.global_position) < 1.0, "client: he is where the host put him")

	# --- Both players die at the same moment: they come back on different spots (NET2)
	if hp:
		hp.take_damage(1000.0, -1, hp.global_position, Vector3.UP)
		cp.take_damage(1000.0, -1, cp.global_position, Vector3.UP)
		await wait_for(func() -> bool: return not hp.is_dead and not cp.is_dead, game.respawn_time + 3.0)
		var apart: float = hp.global_position.distance_to(cp.global_position)
		check(not hp.is_dead and not cp.is_dead and apart > 1.5, "both came back, on different spots (%.1f m apart)" % apart)

	# --- The battle is held: day screen on both
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.has_method("take_damage"):
			e.take_damage(10000.0, 1, (e as Node3D).global_position, Vector3.UP)
	for t in get_tree().get_nodes_in_group("tanks"):
		if is_instance_valid(t) and t.has_method("take_damage"):
			t.take_damage(100000.0, 1, (t as Node3D).global_position, Vector3.UP)
	await wait_for(func() -> bool: return spawner.alive_count == 0 and spawner.wave_number >= 1, 10.0)
	var cleared: bool = await wait_for(func() -> bool:
		return (get_tree().get_first_node_in_group("match_director") as MatchDirector).waves_cleared >= 1, 15.0)
	check(cleared, "host: battle 1 held")
	await sec(2.0)
	s = await snap()
	check(s.get("day_screen", false), "client: the day screen opens for him too")
	var host_hud := game.get_node("HUD") as HUD
	check(host_hud.day_screen.is_open, "host: day screen open")
	# NET2: the host presses Space at once; player 2 is still reading → the battle waits for him.
	await wait_for(func() -> bool: return host_hud.day_screen._t >= host_hud.day_screen.skip_after, 10.0)
	host_hud.day_screen.close()
	await wait_for(func() -> bool: return not host_hud.day_screen.is_open, 5.0)
	await sec(0.5)
	var frozen: int = spawner.next_wave_seconds
	await sec(2.0)
	check(spawner.waiting_for_readers and spawner.next_wave_seconds == frozen and frozen > 0,
			"host: the countdown waits while player 2 reads (%d s, waiting %s)" % [spawner.next_wave_seconds, spawner.waiting_for_readers])
	check(String(host_hud.next_wave_label.text).contains("waiting for the others"), "host: HUD says it waits (%s)" % host_hud.next_wave_label.text)
	s = await snap()
	check(s.get("day_screen", false), "client: his day screen is still open")
	await act("close_day")
	await wait_for(func() -> bool: return spawner.next_wave_seconds < frozen, 6.0)
	check(not spawner.waiting_for_readers and spawner.next_wave_seconds < frozen, "host: player 2's Space lets the countdown run")
	s = await snap()
	check(not s.get("day_screen", true), "client: his day screen closed")
	check(String(s.get("next_wave", "")).contains("begins in") or int(s.get("wave", 0)) >= 2, "client: countdown to battle 2 (%s)" % s.get("next_wave", ""))

	# --- Defeat: Soviets fill the trench → end screen on both
	var director := get_tree().get_first_node_in_group("match_director") as MatchDirector
	await wait_for(func() -> bool: return spawner.alive_count >= director.trench_limit + 1, 60.0)
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en and en.state != Enemy.State.DEAD and n <= director.trench_limit:
			en.global_position = Vector3(-30.0 + n * 3.0, -1.4, 61.0)
			n += 1
	var over: bool = await wait_for(func() -> bool: return director.is_over(), 20.0)
	check(over, "host: the line breaks (defeat) with %d Soviets in the trench" % n)
	await sec(1.5)
	s = await snap()
	check(s.get("end_screen", false), "client: the end screen opens for him")
	check(not s.get("again_button", true), "client: no 'Play again' in co-op")
	check(String(s.get("end_note", "")).contains("Waiting for the host"), "client: end screen says the host decides (%s)" % s.get("end_note", ""))
	check(host_hud.end_screen.again_button.visible and host_hud.end_screen.again_button.text == "Retry battle 2",
			"host: 'Retry battle 2' button (%s)" % host_hud.end_screen.again_button.text)
	var hnote := host_hud.end_screen.find_child("CoopNote", true, false) as Label
	check(hnote != null and hnote.text.contains("ends the battle for everyone"), "host: note under Main menu")
	print("client end-screen text: ", s.get("end_text", ""))
	# The host retries: everyone loads battle 2 again.
	var old_game_id: int = game.get_instance_id()
	host_hud.end_screen.again_button.pressed.emit()
	await sec(1.0)
	var back: bool = await wait_for(func() -> bool:
		var g := get_tree().get_first_node_in_group("game")
		return g != null and g.get_instance_id() != old_game_id and players().size() == 2, 120.0)
	check(back, "retry: both players in the new battle")
	var d2 := get_tree().get_first_node_in_group("match_director") as MatchDirector
	check(d2 != null and d2.start_wave == 2 and not d2.is_over(), "retry: the host's battle starts at battle 2 (%d)" % (d2.start_wave if d2 else -1))
	await sec(1.0)
	s = await snap()
	check(int(s.get("start_wave", 0)) == 2 and not s.get("end_screen", true), "client: he is in battle 2 again, end screen gone")
	check(String(s.get("next_wave", "")).contains("Battle 2"), "client: countdown to battle 2 (%s)" % s.get("next_wave", ""))
	_end()


func _end() -> void:
	if client_id != 0:
		_finish_client.rpc_id(client_id)
	await sec(3.0)
	if client_pid > 0 and OS.is_process_running(client_pid):
		OS.kill(client_pid)
	NetworkManager.close_connection()
	print("RESULT: %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


@rpc("any_peer", "call_remote", "reliable")
func _snapshot_reply(d: Dictionary) -> void:
	_snap = d
	_snap_n += 1


# --- Client side --------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _do(what: String, value: Variant) -> void:
	var me := local_player()
	if me == null:
		return
	var inp: PlayerInput = me.input
	inp.set_process(false) # the scenario presses the keys (headless has no mouse capture)
	match what:
		"move": inp.move_dir = value
		"fire": inp.fire_held = value
		"aim": inp.aim_held = value
		"look":
			inp.look_pitch = (value as Vector2).y
		"reload": inp.request_reload.rpc_id(1)
		"switch": inp.request_switch.rpc_id(1, int(value))
		"interact": inp.request_interact.rpc_id(1)
		"molotov": inp.request_molotov.rpc_id(1)
		"throw": inp.request_throw.rpc_id(1)
		"jump": inp.request_jump.rpc_id(1)
		"bandage": inp.request_bandage.rpc_id(1)
		"close_day":
			var g := get_tree().get_first_node_in_group("game")
			if g:
				(g.get_node("HUD") as HUD).day_screen.close() # = Space on his day screen


@rpc("authority", "call_remote", "reliable")
func _ask_snapshot() -> void:
	_snapshot_reply.rpc_id(1, _make_snapshot())


@rpc("authority", "call_remote", "reliable")
func _finish_client() -> void:
	_quit = true


func _make_snapshot() -> Dictionary:
	var d := {}
	var me := local_player()
	var game := get_tree().get_first_node_in_group("game")
	d.paused = get_tree().paused
	d.headless = DisplayServer.get_name() == "headless"
	d.mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	d.muted = AudioServer.is_bus_mute(0)
	if me == null or game == null:
		return d
	var cam := get_viewport().get_camera_3d()
	d.camera_is_mine = cam != null and cam == me.camera
	d.my_pos = me.global_position
	d.health = me.health
	d.slot = me.weapons.current_slot
	d.mag_ammo = me.weapons.get_mag_ammo()
	d.my_view_model = me.weapons.holder.is_visible_in_tree()
	var vis := me.get_node_or_null("BodyMesh") as Node3D
	d.my_body_visible = vis != null and vis.is_visible_in_tree()
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p != me:
			var hv := p.get_node_or_null("BodyMesh") as Node3D
			d.host_body_visible = hv != null and hv.is_visible_in_tree()
			d.host_view_model = p.weapons.holder.is_visible_in_tree()
	d.on_gun = me.get_mounted_gun() != null
	var gun := get_tree().get_first_node_in_group("mounted_guns") as MountedGun
	if gun:
		d.maxim_ammo = gun.ammo
	d.molotov_phase = me.molotov.phase
	d.molotov_count = me.molotov.count
	d.bottle_shown = me.molotov._hand != null and me.molotov._hand.is_visible_in_tree()
	d.thrown_back = me.grab.thrown_back
	d.climbing = me.is_climbing
	var hud := game.get_node("HUD") as HUD
	d.hud_player = String(hud._player.name) if hud._player else ""
	d.next_wave = hud.next_wave_label.text if hud.next_wave_label.visible else ""
	d.weapon_name = hud.weapon_name.text
	d.ammo_text = hud.ammo_label.text
	d.grabbable = hud.grenade_warning.grabbable_index() if hud.grenade_warning else -1
	d.hurt_flash = hud.damage_flash.modulate.a > 0.01 or hud._flash > 0.0
	d.death_screen = hud.death_screen.visible
	d.day_screen = hud.day_screen.is_open
	d.end_screen = hud.end_screen.visible
	var again := hud.end_screen.find_child("AgainButton", true, false) as Button
	d.again_button = again != null and again.visible
	var stats := hud.end_screen.find_child("Stats", true, false) as Label
	d.end_text = stats.text if stats else ""
	var note := hud.end_screen.find_child("CoopNote", true, false) as Label
	d.end_note = note.text if note and note.visible else ""
	var director := get_tree().get_first_node_in_group("match_director") as MatchDirector
	d.start_wave = director.start_wave if director else 0
	var ws := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	d.wave = ws.wave_number if ws else 0
	return d


func _run_client() -> void:
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
	await wait_for(func() -> bool: return _quit, 600.0)
	NetworkManager.leave_game()
	await sec(0.5)
	get_tree().quit(0)
