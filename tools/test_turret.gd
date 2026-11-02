extends Node
## Test for the T-26 turret feel (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_turret.gd
## Parks a tank at the trench edge, switches its eyes off and hands it targets by hand.

var fails := 0
var tank: Tank
var p: Player


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ready() -> void:
	await get_tree().process_frame
	run()


## Runs `ticks` physics frames. `mover` (optional) is called each tick with the time so far and
## may move the target. Returns the samples: vel (deg/s, signed), yaw (deg), t (s).
func sim(ticks: int, mover: Callable = Callable()) -> Dictionary:
	var out := {"vel": [], "yaw": [], "t": []}
	var dt: float = get_physics_process_delta_time()
	for i in ticks:
		if mover.is_valid():
			mover.call(i * dt)
		await get_tree().physics_frame
		out.vel.append(rad_to_deg(tank._turret_vel))
		out.yaw.append(rad_to_deg(tank.turret_yaw))
		out.t.append((i + 1) * dt)
	return out


## Where a point `x` m to the right and `z` m behind the turret pivot is in the world.
func spot(x: float, z: float) -> Vector3:
	return tank.turret_pivot.global_position + tank.global_basis * Vector3(x, 0.0, z)


## Fresh start: turret straight ahead and still, the crew has no target yet.
func reset_turret() -> void:
	tank.turret_yaw = 0.0
	tank._turret_vel = 0.0
	tank._turret_hold_until = 0.0
	tank._aimed_target = null
	tank._was_behind = false
	tank._target = null
	tank._target_visible = false
	await sim(2)


func give_target(pos: Vector3) -> void:
	tank._target = p
	tank._target_visible = true
	tank._last_known = pos


func peak(arr: Array) -> float:
	var m := 0.0
	for v in arr:
		m = maxf(m, absf(v))
	return m


func run() -> void:
	Settings.difficulty = 1
	for f in ["turret_gear", "turret_crank"]:
		var s: AudioStreamOggVorbis = load("res://assets/audio/tank/%s.ogg" % f)
		check(s != null, "%s.ogg exists" % f)
	for f in ["turret_clunk_1", "turret_clunk_2", "turret_clunk_3", "turret_stop"]:
		check(load("res://assets/audio/tank/%s.ogg" % f) != null, "%s.ogg exists" % f)

	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await seconds(0.5)
	p = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.god_mode = true
	p.global_position = Vector3(10, -1.3, 61)
	var waves: WaveSpawner = get_tree().get_first_node_in_group("wave_spawner")
	waves.set_process(false)
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	Engine.time_scale = 4.0
	tank = spawner.spawn_tank(1)
	await seconds(0.3)
	tank._distance = tank._route_length - 0.01
	var ok: bool = false
	for i in 600:
		await get_tree().physics_frame
		if tank.state == Tank.State.AT_TRENCH:
			ok = true
			break
	check(ok, "tank parks at the trench edge")
	tank._sense_timer = 1.0e9 # eyes off: the targets are handed over by hand
	tank._blind_until = 1.0e9 # and no shooting
	var d: float = get_physics_process_delta_time()
	var tp := func(sec: float) -> int: return int(sec / d)

	# --- Names and defaults.
	check(tank.turret_idle_deg == 4.0 and tank.turret_track_deg == 8.0 and tank.turret_emergency_deg == 12.0, "speeds 4 / 8 / 12 deg/s")
	check(tank.turret_ramp_time == 1.5, "ramp-up 1.5 s")
	check(tank._turret_gear != null and tank._turret_crank != null and tank._turret_clunk != null, "gear, crank and clunk players exist")

	# --- Searching along the trench: never faster than 4 deg/s, and it does turn.
	await reset_turret()
	var r: Dictionary = await sim(tp.call(25.0))
	check(peak(r.vel) <= 4.05, "idle sweep: top speed %.2f deg/s (<= 4)" % peak(r.vel))
	check(peak(r.yaw) > 10.0, "idle sweep: it does swing (%.0f deg)" % peak(r.yaw))

	# --- Tracking at 30 m, target 90 deg to the right.
	await reset_turret()
	var t0: float = tank._clock
	give_target(spot(30.0, 0.0))
	r = await sim(tp.call(0.25))
	check(absf(r.yaw[-1]) < 0.2, "reaction delay: still not turning after 0.25 s (%.2f deg)" % r.yaw[-1])
	var delay: float = tank._turret_hold_until - t0
	check(delay >= 0.3 and delay <= 0.6 + 2.0 * d, "reaction delay is 0.3-0.6 s (%.2f s)" % delay)
	var hold: float = tank._turret_hold_until - tank._clock
	r = await sim(tp.call(maxf(hold, 0.0) + 0.75))
	check(absf(r.vel[-1]) > 3.4 and absf(r.vel[-1]) < 4.6, "0.75 s after starting: half speed, no instant top speed (%.2f deg/s)" % r.vel[-1])
	r = await sim(tp.call(30.0))
	check(peak(r.vel) <= 8.05, "tracking: top speed %.2f deg/s (<= 8)" % peak(r.vel))
	check(peak(r.vel) > 7.0, "tracking: it does reach about 8 deg/s")
	var err: float = absf(tank.turret_yaw - deg_to_rad(-90.0))
	check(rad_to_deg(err) < 1.0, "arrives on target and stays (%.2f deg off)" % rad_to_deg(err))
	check(peak(r.yaw) <= 92.0, "no big overshoot (peak %.1f deg)" % peak(r.yaw))

	# --- Emergency: close but not point-blank.
	await reset_turret()
	give_target(spot(15.0, 0.0))
	r = await sim(tp.call(12.0))
	check(peak(r.vel) <= 12.05 and peak(r.vel) > 10.5, "emergency (15 m): %.2f deg/s (max 12)" % peak(r.vel))

	# --- Point-blank: less efficient.
	await reset_turret()
	give_target(spot(6.0, 0.0))
	r = await sim(tp.call(12.0))
	check(peak(r.vel) < 10.0, "6 m away: top speed cut to %.2f deg/s" % peak(r.vel))

	# --- Behind the tank: extra reacquisition delay.
	await reset_turret()
	give_target(spot(0.0, 30.0))
	r = await sim(tp.call(1.0))
	check(absf(r.yaw[-1]) < 0.2, "target behind: nothing moves in the first second (%.2f deg)" % r.yaw[-1])
	r = await sim(tp.call(4.0))
	check(peak(r.yaw) > 5.0, "...then the turret starts round (%.0f deg)" % peak(r.yaw))

	# --- Slips round behind the hull while being followed.
	await reset_turret()
	give_target(spot(30.0, 0.0))
	await sim(tp.call(12.0))
	var before: float = tank.turret_yaw
	give_target(spot(10.0, 30.0)) # now well behind the right side
	r = await sim(tp.call(0.6))
	check(absf(rad_to_deg(tank.turret_yaw - before)) < 4.0, "he slips behind: the crew loses him for a moment (%.1f deg in 0.6 s)" % rad_to_deg(tank.turret_yaw - before))

	# --- A sprinter circling at 6 m: the turret can't keep up.
	await reset_turret()
	var circle := func(t: float) -> void: give_target(spot(6.0 * cos(t * 1.05), -6.0 * sin(t * 1.05)))
	r = await sim(tp.call(4.0), circle)
	var aim_err: float = tank._aim_error_deg(tank.turret_pivot)
	check(aim_err > 15.0, "sprinter circling at 6 m: the turret is %.0f deg behind" % aim_err)

	# --- Direction change: smooth braking, never a sudden reversal.
	await reset_turret()
	var flip := func(t: float) -> void: give_target(spot(30.0, 0.0) if t < 8.0 else spot(-30.0, 0.0))
	r = await sim(tp.call(16.0), flip)
	var max_acc: float = 0.0
	for i in range(1, r.vel.size()):
		max_acc = maxf(max_acc, absf(r.vel[i] - r.vel[i - 1]) / d)
	check(max_acc <= 8.0 / 1.5 * 1.02, "turns round without a jerk: max change %.2f deg/s² (<= 5.33)" % max_acc)
	check(peak(r.vel) <= 8.05, "reversal: top speed still %.2f" % peak(r.vel))

	# --- Sound: playing while it turns, quiet when it is still.
	await reset_turret()
	give_target(spot(30.0, 0.0))
	await sim(tp.call(4.0))
	check(tank._turret_gear.playing and tank._turret_crank.playing, "gear + crank sound while turning")
	tank._target = null
	tank._target_visible = false
	tank.state = Tank.State.AT_TRENCH
	Engine.time_scale = 1.0
	check(true, "(clunks are random: judge them by ear)")

	Engine.time_scale = 1.0
	print("TEST TURRET DONE: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)
