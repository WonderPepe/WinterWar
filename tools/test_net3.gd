extends Node
## Automated test for NET3: the NetSmoother on its own, fed with made-up network updates, plus
## the scenes' sync settings (not part of the game). The two-copy test is test_net3_coop.gd.
##   godot --headless --path . --script tools/run.gd -- tools/test_net3.gd

var fails := 0
var rng := RandomNumberGenerator.new()


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _ready() -> void:
	rng.seed = 1940
	await get_tree().process_frame
	_scenes()
	await _host_copy()
	_walk("same network", 0.002, 0.004, 0.0, 0.03, 0.06)
	_walk("bad connection", 0.1, 0.02, 0.02, 0.04, 0.151)
	_gap()
	_teleport()
	_own_player()
	_turning()
	_lag_sim()
	print("NET3: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _make(sync_rot := true) -> NetSmoother:
	var parent := Node3D.new()
	add_child(parent)
	var s := NetSmoother.new()
	s.name = "Smoother"
	s.sync_rotation = sync_rot
	parent.add_child(s)
	s.start_guest_for_test()
	return s


## Feeds a soldier walking 2 m/s along x, updates 60 times a second with `lag` ± `jitter`
## and `loss`; draws 144 frames a second. Returns [shown positions, truth at draw time].
func _run(s: NetSmoother, seconds: float, lag: float, jitter: float, loss: float, path: Callable) -> Array:
	var updates: Array = [] # [arrive, stamp]
	var t := 0.0
	while t < seconds:
		if rng.randf() >= loss:
			updates.append([t + lag + rng.randf_range(0.0, jitter), t])
		t += 1.0 / 60.0
	updates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var shown: Array = []
	var truth: Array = []
	var i := 0
	var now := 0.0
	while now < seconds:
		while i < updates.size() and (updates[i][0] as float) <= now:
			var st: float = updates[i][1]
			s.receive(st, path.call(st), Quaternion.IDENTITY, updates[i][0])
			i += 1
		if not s._samples.is_empty() and s._min_offset != INF:
			s.update_shown(now)
			shown.append((s.get_parent() as Node3D).position)
			truth.append(path.call(now - lag))
		now += 1.0 / 144.0
	return [shown, truth]


func _jerk(points: Array) -> float:
	var total := 0.0
	for k in range(2, points.size()):
		total += (((points[k] as Vector3) - points[k - 1]) - ((points[k - 1] as Vector3) - points[k - 2])).length()
	return total / maxf(points.size() - 2, 1)


func _walk(label: String, lag: float, jitter: float, loss: float, dmin: float, dmax: float) -> void:
	var s := _make()
	var walk := func(t: float) -> Vector3: return Vector3(2.0 * t, 0, 0)
	var r: Array = _run(s, 4.0, lag, jitter, loss, walk)
	var shown: Array = r[0].slice(144) # after the first second
	var max_err := 0.0
	for k in shown.size():
		max_err = maxf(max_err, (shown[k] as Vector3).distance_to(r[1][k + 144]) - 2.0 * s.delay)
	# Without NET3 the newest update is drawn: steps of 0 or 3.3 cm.
	var raw: Array = []
	for k in shown.size():
		var now: float = (k + 144) / 144.0
		raw.append(Vector3(2.0 * (floorf((now - lag) * 60.0) / 60.0), 0, 0))
	check(_jerk(shown) < 0.002, "%s: steady walking looks even (jerk %.4f m, raw %.4f m)" % [label, _jerk(shown), _jerk(raw)])
	check(s.delay >= dmin and s.delay <= dmax, "%s: drawing delay %d ms (%d–%d)" % [label, s.delay * 1000.0, dmin * 1000.0, dmax * 1000.0])
	check(max_err < 0.08, "%s: drawn where he was `delay` ago (worst %.3f m off)" % [label, max_err])
	check(s.snaps == 0, "%s: no jumps" % label)
	s.get_parent().queue_free()


func _gap() -> void:
	var s := _make()
	var walk := func(t: float) -> Vector3: return Vector3(2.0 * t, 0, 0)
	_run(s, 1.0, 0.002, 0.003, 0.0, walk)
	var last: Vector3 = s._samples[-1][1]
	var x0: float = last.x
	# No more updates for half a second: he carries on at most 0.15 s worth, then waits.
	for k in 72:
		s.update_shown(1.0 + k / 144.0)
	var x1: float = (s.get_parent() as Node3D).position.x
	check(x1 > x0 + 0.1 and x1 <= x0 + 2.0 * s.max_extrapolate + 0.01, "late update: carries on %.2f m, at most 0.15 s worth (%.2f m)" % [x1 - x0, 2.0 * s.max_extrapolate])
	s.get_parent().queue_free()


func _teleport() -> void:
	var s := _make()
	var path := func(t: float) -> Vector3: return Vector3(0.0 if t < 1.0 else 30.0, 0, 0)
	_run(s, 1.5, 0.002, 0.003, 0.0, path)
	check(s.snaps == 1, "respawn / teleport: shown at once (%d jump)" % s.snaps)
	check((s.get_parent() as Node3D).position.x > 29.9, "and he is there now (x %.1f)" % (s.get_parent() as Node3D).position.x)
	s.get_parent().queue_free()


func _own_player() -> void:
	var s := _make(false)
	s.start_guest_for_test(true)
	s.receive(1.0, Vector3(1, 0, 0), Quaternion.IDENTITY, 1.05)
	s.receive(1.0 + 1.0 / 60.0, Vector3(2, 0, 0), Quaternion.IDENTITY, 1.07)
	check((s.get_parent() as Node3D).position.x == 2.0, "your own soldier: the newest update at once, no delay")
	s.get_parent().queue_free()


func _turning() -> void:
	var s := _make()
	var path := func(t: float) -> Vector3: return Vector3.ZERO
	# Turning 90° a second: the facing glides too.
	var updates := 0
	var t := 0.0
	var max_step := 0.0
	var prev := Quaternion.IDENTITY
	while t < 2.0:
		s.receive(t, Vector3.ZERO, Quaternion(Vector3.UP, t * PI / 2.0), t + 0.002)
		for f in 2:
			var now: float = t + f / 144.0
			if s._min_offset != INF:
				s.update_shown(now + 0.003)
				var q: Quaternion = (s.get_parent() as Node3D).quaternion
				if t > 0.5:
					max_step = maxf(max_step, prev.angle_to(q))
				prev = q
		t += 1.0 / 60.0
	check(max_step < deg_to_rad(1.2), "turning: the facing glides (largest step %.2f°)" % rad_to_deg(max_step))
	s.get_parent().queue_free()


func _lag_sim() -> void:
	var s := _make()
	s._ready_done = true
	NetSmoother.sim_lag = 0.1
	NetSmoother.sim_loss = 0.0
	s.net_position = Vector3(5, 0, 0)
	s.net_stamp = 1.0
	check(s._pending.size() == 1 and s._samples.is_empty(), "lag simulator: the update is held back")
	NetSmoother.sim_lag = 0.0
	s.get_parent().queue_free()


func _scenes() -> void:
	for path in ["res://scenes/enemies/soviet_rifleman.tscn", "res://scenes/enemies/soviet_officer.tscn",
			"res://scenes/enemies/soviet_mg_gunner.tscn", "res://scenes/enemies/soviet_tank.tscn", "res://scenes/player.tscn"]:
		var n: Node = load(path).instantiate()
		var sm := n.get_node_or_null("Smoother") as NetSmoother
		var cfg: SceneReplicationConfig = (n.get_node("StateSync") as MultiplayerSynchronizer).replication_config
		var props: Array = cfg.get_properties()
		var player: bool = n is Player
		check(sm != null, "%s has a Smoother" % path.get_file())
		check(not cfg.has_property(NodePath(".:position")), "%s: the node's own position is no longer sent" % path.get_file())
		check(cfg.has_property(NodePath("Smoother:net_position")), "%s: Smoother position is sent" % path.get_file())
		check(props[-1] == NodePath("Smoother:net_stamp"), "%s: the time stamp is the LAST synced value" % path.get_file())
		if player:
			check(sm and not sm.sync_rotation, "player: facing comes from his view, not the smoother")
		else:
			check(cfg.has_property(NodePath("Smoother:net_quat")) and not cfg.has_property(NodePath(".:rotation")), "%s: facing goes through the Smoother" % path.get_file())
		n.free()


## Host (single player): the Smoother copies the soldier's real position and facing every
## physics frame and never moves him.
func _host_copy() -> void:
	var e: Node3D = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
	add_child(e)
	e.set_physics_process(false)
	await get_tree().physics_frame
	e.position = Vector3(3, 1, -7)
	e.rotation.y = 1.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var sm := e.get_node("Smoother") as NetSmoother
	check(sm.net_position.is_equal_approx(Vector3(3, 1, -7)), "host: the Smoother copies the position")
	check(sm.net_quat.is_equal_approx(e.quaternion), "host: and the facing")
	check(sm.net_stamp > 0.0 and not sm.is_processing(), "host: time-stamped, and it never moves the soldier")
	e.queue_free()
	await get_tree().process_frame
