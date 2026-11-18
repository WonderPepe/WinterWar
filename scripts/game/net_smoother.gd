class_name NetSmoother
extends Node
## NET3: makes things the host moves (Soviet soldiers, tanks, other players) glide on the
## OTHER computers instead of jumping from one network update to the next. Picture only – the
## host still decides where everything really is.
##
## How (the usual trick in online games, "interpolation"):
## - HOST: every physics frame this node copies its parent's position (and facing) into
##   `net_position` / `net_quat` and stamps them with the host's clock (`net_stamp`). The
##   parent's StateSync sends these three instead of the parent's own position / rotation.
## - GUEST: every update that arrives is kept in a short list. The parent is drawn a little in
##   the PAST (`delay`, about 35 ms on the same network, up to 150 ms on a bad connection),
##   gliding between the two updates around that moment. If no newer update has come, he
##   carries on in the same direction for at most `max_extrapolate` s, then waits. A jump of
##   more than `snap_distance` (respawn, teleport) is shown at once.
## - Your OWN player on your own computer is never delayed: the newest update is used at once
##   (`own_player`), exactly as before NET3.
##
## Lag simulator for tests (guest only, these updates only – reliable messages are untouched):
##   --net-lag=100 --net-jitter=20 --net-loss=2   (ms, ms, % of updates dropped)

## Also smooth the facing (Soviets, tanks). Players turn by their synced view instead.
@export var sync_rotation: bool = true
## A jump larger than this (m) is shown at once instead of gliding (respawn, teleport).
@export var snap_distance: float = 1.5
## How far past the newest update he may carry on in the same direction (s).
@export var max_extrapolate: float = 0.15
@export var min_delay: float = 0.03 ## Shortest drawing delay (s).
@export var max_delay: float = 0.15 ## Longest drawing delay (s), for a bad connection.

# --- Synced by the parent's StateSync (host → everyone). net_stamp must come LAST in the list:
# when it arrives, the position and facing of the same update are already here.
var net_position: Vector3 = Vector3.ZERO
var net_quat: Quaternion = Quaternion.IDENTITY
var net_stamp: float = 0.0:
	set = _set_stamp

## Guest: how far in the past things are drawn now (s), how many updates came in the last
## second, how many times a jump was shown at once (debug overlay, tests).
var delay: float = 0.05
var updates_per_second: float = 0.0
var snaps: int = 0
## True when this node smooths for the player of THIS computer (no delay, newest at once).
var own_player: bool = false

const MAX_SAMPLES := 32
const OFFSET_WINDOW := 2.0 ## Seconds of updates used to work out the clock difference.

var _target: Node3D
var _samples: Array = [] # [stamp, position, quaternion], oldest first
var _offsets: Array = [] # [local receive time, receive time − stamp]
var _min_offset: float = INF
var _interval: float = 1.0 / 60.0 # average time between updates (host clock)
var _jitter: float = 0.0
var _pending: Array = [] # lag simulator: [release time, stamp, position, quaternion]
var _recv_times: Array = [] # for updates_per_second
var _ready_done: bool = false
var _rng := RandomNumberGenerator.new()
var _is_host: bool = true

# Lag simulator settings (read once from the launch options).
static var sim_lag: float = 0.0
static var sim_jitter: float = 0.0
static var sim_loss: float = 0.0
static var _sim_read: bool = false


## Host clock / this computer's clock in seconds (monotonic).
static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0


static func _read_sim_options() -> void:
	if _sim_read:
		return
	_sim_read = true
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for a: String in args:
		if a.begins_with("--net-lag="):
			sim_lag = a.get_slice("=", 1).to_float() / 1000.0
		elif a.begins_with("--net-jitter="):
			sim_jitter = a.get_slice("=", 1).to_float() / 1000.0
		elif a.begins_with("--net-loss="):
			sim_loss = a.get_slice("=", 1).to_float() / 100.0
	if sim_lag > 0.0 or sim_jitter > 0.0 or sim_loss > 0.0:
		print("NET3 lag simulator: %d ms lag, %d ms jitter, %.0f %% lost" % [sim_lag * 1000.0, sim_jitter * 1000.0, sim_loss * 100.0])


func _ready() -> void:
	_read_sim_options()
	_rng.randomize()
	_target = get_parent() as Node3D
	_is_host = multiplayer.is_server()
	process_priority = -50 # before the soldier pictures read the position this frame
	process_physics_priority = 100 # host: after the parent has moved this frame
	set_physics_process(_is_host)
	set_process(not _is_host)
	if _is_host:
		_copy_from_target()
	else:
		var p := _target as Player
		own_player = p != null and p.is_local_player()
		if net_stamp > 0.0: # the spawn state has already arrived: start there
			_samples = [[net_stamp, net_position, net_quat]]
			_apply(net_position, net_quat)
	_ready_done = true


## Tests: act as a guest's smoother (fed by receive(), drawn by update_shown()).
func start_guest_for_test(own: bool = false) -> void:
	_is_host = false
	own_player = own
	set_physics_process(false)
	set_process(false) # the test calls update_shown() with its own clock
	_samples = []
	_offsets = []
	_min_offset = INF


func _physics_process(_delta: float) -> void:
	_copy_from_target() # host


func _copy_from_target() -> void:
	net_position = _target.position
	if sync_rotation:
		net_quat = _target.quaternion
	net_stamp = now()


func _set_stamp(value: float) -> void:
	net_stamp = value
	if not _ready_done or _is_host:
		return
	if sim_loss > 0.0 and _rng.randf() < sim_loss:
		return # lag simulator: this update is lost
	if sim_lag > 0.0 or sim_jitter > 0.0:
		var hold: float = maxf(sim_lag + _rng.randf_range(-sim_jitter, sim_jitter), 0.0)
		_pending.append([now() + hold, value, net_position, net_quat])
		return
	receive(value, net_position, net_quat, now())


## Guest: one update from the host (also called directly by the tests).
func receive(stamp: float, pos: Vector3, quat: Quaternion, recv_time: float) -> void:
	if not _samples.is_empty() and stamp <= (_samples[-1][0] as float):
		return # older than what we have (arrived out of order): not needed
	if not _samples.is_empty():
		var dt: float = stamp - (_samples[-1][0] as float)
		_interval = lerpf(_interval, clampf(dt, 0.001, 0.5), 0.1)
	# Clock difference: the smallest (receive − stamp) of the last seconds = the fastest trip.
	var offset: float = recv_time - stamp
	_offsets.append([recv_time, offset])
	while (_offsets[0][0] as float) < recv_time - OFFSET_WINDOW:
		_offsets.pop_front()
	_min_offset = INF
	for o in _offsets:
		_min_offset = minf(_min_offset, o[1])
	_jitter = lerpf(_jitter, offset - _min_offset, 0.1)
	delay = clampf(_interval * 1.5 + _jitter * 2.0 + 0.005, min_delay, max_delay)
	_recv_times.append(recv_time)
	while (_recv_times[0] as float) < recv_time - 1.0:
		_recv_times.pop_front()
	updates_per_second = _recv_times.size()

	if own_player:
		_samples = [[stamp, pos, quat]]
		_apply(pos, quat) # your own soldier: at once, as before NET3
		return
	# A big jump (respawn, teleport): show it at once, forget the old path.
	var shown: Vector3 = _target.position
	if _samples.is_empty() or shown.distance_to(pos) > snap_distance and \
			(_samples[-1][1] as Vector3).distance_to(pos) > snap_distance:
		if not _samples.is_empty():
			snaps += 1
		_samples = [[stamp, pos, quat]]
		_apply(pos, quat)
		return
	_samples.append([stamp, pos, quat])
	if _samples.size() > MAX_SAMPLES:
		_samples.pop_front()


func _process(_delta: float) -> void:
	_release_pending()
	if own_player or _samples.is_empty() or _min_offset == INF:
		return
	update_shown(now())


## Guest: draw the parent where it was `delay` seconds ago (in host time).
func update_shown(local_now: float) -> void:
	var t: float = local_now - _min_offset - delay
	var newest: Array = _samples[-1]
	if t >= (newest[0] as float):
		if _samples.size() < 2:
			_apply(newest[1], newest[2])
			return
		# Past the newest update: carry on in the same direction for a short while.
		var prev: Array = _samples[-2]
		var span: float = maxf((newest[0] as float) - (prev[0] as float), 0.001)
		var ahead: float = minf(t - (newest[0] as float), max_extrapolate)
		var k: float = ahead / span
		var pos: Vector3 = (newest[1] as Vector3) + ((newest[1] as Vector3) - (prev[1] as Vector3)) * k
		_apply(pos, (newest[2] as Quaternion))
		return
	if t <= (_samples[0][0] as float):
		_apply(_samples[0][1], _samples[0][2])
		return
	for i in range(_samples.size() - 1, 0, -1):
		var a: Array = _samples[i - 1]
		if (a[0] as float) <= t:
			var b: Array = _samples[i]
			var w: float = (t - (a[0] as float)) / maxf((b[0] as float) - (a[0] as float), 0.0001)
			_apply((a[1] as Vector3).lerp(b[1], w), (a[2] as Quaternion).slerp(b[2], w))
			# Old updates that can never be needed again.
			while _samples.size() > 2 and (_samples[1][0] as float) < t:
				_samples.pop_front()
			return


func _release_pending() -> void:
	if _pending.is_empty():
		return
	var t: float = now()
	var keep: Array = []
	for p in _pending:
		if (p[0] as float) <= t:
			receive(p[1], p[2], p[3], p[0])
		else:
			keep.append(p)
	_pending = keep


func _apply(pos: Vector3, quat: Quaternion) -> void:
	_target.position = pos
	if sync_rotation:
		_target.quaternion = quat.normalized()


## Debug overlay: one line about the smoothing on this computer (guests).
static func debug_line(tree: SceneTree) -> String:
	if tree.get_multiplayer().is_server():
		return ""
	var n := 0
	var d := 0.0
	var ups := 0.0
	var sn := 0
	for node in tree.get_nodes_in_group("net_smoothers"):
		var s := node as NetSmoother
		if s and not s.own_player and s.is_processing():
			n += 1
			d += s.delay
			ups = maxf(ups, s.updates_per_second)
			sn += s.snaps
	if n == 0:
		return ""
	return "Net: %d smoothed, %d updates/s, delay %d ms, jumps %d%s" % [n, ups, d / n * 1000.0, sn,
			"   (lag sim %d/%d ms, %.0f %%)" % [sim_lag * 1000.0, sim_jitter * 1000.0, sim_loss * 100.0] if sim_lag + sim_jitter + sim_loss > 0.0 else ""]


func _enter_tree() -> void:
	add_to_group("net_smoothers")
