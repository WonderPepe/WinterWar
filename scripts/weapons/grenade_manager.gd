class_name GrenadeManager
extends Node3D
## Hand grenades (GR1): the Soviet F-1 grenades thrown at the Finnish line.
##
## The HOST throws a grenade (`throw()`) and works out its WHOLE flight at once: the arc, the
## bounces on the frozen ground, rolling down a slope into the trench, until the fuse burns
## down. Every computer gets that list of points (`grenade_thrown`) and plays it back, so all
## players see exactly the same grenade – it is like a short recording of the flight.
## When the fuse is done the host decides who is hurt (`_explode`) and tells everyone to show
## the burst (`grenade_exploded`).
##
## The blast only hurts someone if there is a clear line from the burst to his chest or head
## (the same rule as the tank's 45 mm shell): trench walls, sandbags, the bunker walls and tank
## wrecks protect – a grenade that lands next to you INSIDE the trench does not.
## Soviet soldiers are hurt by the same rule (owner: friendly fire, yes).
##
## Not too many at once: at most `max_live` grenades are live and the next throw waits
## `min_gap_s` (for the whole battlefield). A soldier asks for a place first (`reserve()`).

const GRAVITY := 9.8
const BOUNCE_MASK := 0b10001 ## world + armour: grenades bounce off the ground, walls, tanks and wrecks.
const STEP := 1.0 / 60.0 ## The flight is worked out in steps this long...
const SAMPLE_EVERY := 2 ## ...and every 2nd step is kept (30 points per second, the rest is in between).
const RADIUS := 0.03 ## The grenade is ~55 mm across.
const MODEL_PATH := "res://assets/models/weapons/f1_grenade/model.gltf"

@export var max_live: int = 2 ## At most this many grenades live at the same time...
@export var min_gap_s: float = 4.0 ## ...and at least this long between two throws.
@export var fuse_min: float = 3.5 ## The F-1's fuse burns 3.2–4.2 s; a random time between these.
@export var fuse_max: float = 4.0
@export_group("Blast")
@export var kill_radius_m: float = 2.0 ## Anyone this close (and reachable) is killed...
@export var harm_radius_m: float = 9.0 ## ...and hurt up to this far, less and less:
@export var near_damage: float = 95.0 ## just outside the kill radius...
@export var far_damage: float = 5.0 ## ...down to this at the edge.
@export var suppression_radius_m: float = 12.0 ## Soviet soldiers this close duck (suppression)...
@export var suppression_amount: float = 0.6 ## ...this much right next to it.
@export var shake_range_m: float = 30.0 ## Your camera shakes if you are this close.
@export_group("Bounce")
@export var restitution: float = 0.12 ## How high it bounces off snow (0 = not at all, 1 = like a rubber ball)...
@export var tangent_keep: float = 0.35 ## ...and how much of the speed along the ground stays at each touch (snow is soft).
@export var hard_restitution: float = 0.3 ## The same on wood and metal (logs, bunker, tanks):
@export var hard_tangent_keep: float = 0.6 ## a grenade bounces and skids further there.
@export var rest_speed: float = 0.15 ## Slower than this on flat ground = it lies still.
@export_group("Throwing")
@export var lob_angle_deg: float = 40.0 ## A lob over the parapet...
@export var bunker_angle_deg: float = 14.0 ## ...a flatter throw at the bunker's firing hole or door.
@export var max_throw_speed: float = 18.0 ## A strong man throws ~20 m/s.

var thrown_count: int = 0 ## Statistics / tests (host).
var exploded_count: int = 0

# Host: live grenades [{id, path, start, fuse, thrower, first_hit}].
var _live: Array[Dictionary] = []
var _reserved: int = 0
var _next_allowed: float = 0.0
var _next_id: int = 0
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()
# Every computer: visual pool [{node, id, path, t, fuse, first_hit, landed, spin_axis}].
var _visuals: Array[Dictionary] = []
var _audio: Array[AudioStreamPlayer3D] = []
var _next_audio: int = 0

static var _model: PackedScene


func _ready() -> void:
	add_to_group("grenades")
	_rng.randomize()
	for i in 6:
		var g := make_grenade(false)
		g.visible = false
		add_child(g)
		_visuals.append({"node": g, "id": -1, "path": PackedVector3Array(), "t": 0.0, "fuse": 0.0,
				"first_hit": -1.0, "landed": false, "spin_axis": Vector3.RIGHT})
	for i in 3:
		var a := AudioStreamPlayer3D.new()
		a.bus = &"SFX"
		add_child(a)
		_audio.append(a)


# ------------------------------------------------------------------ host: throwing
## Host: may a soldier start a throw now? If yes, a place is kept for his grenade (give it
## back with `cancel_reservation()` if he doesn't throw after all).
func reserve() -> bool:
	if not multiplayer.is_server():
		return false
	if _live.size() + _reserved >= max_live or _clock < _next_allowed:
		return false
	_reserved += 1
	_next_allowed = _clock + min_gap_s
	return true


func cancel_reservation() -> void:
	_reserved = maxi(_reserved - 1, 0)


## Host: a grenade leaves `origin` with `velocity`. `thrower` = the player's peer id (GR2) or -1
## for a Soviet soldier. `reserved` = the thrower got a place with `reserve()`. Returns its id.
func throw(origin: Vector3, velocity: Vector3, thrower: int = -1, reserved: bool = true, fuse: float = -1.0) -> int:
	if not multiplayer.is_server():
		return -1
	if reserved:
		cancel_reservation()
	if fuse < 0.0:
		fuse = _rng.randf_range(fuse_min, fuse_max)
	var flight: Dictionary = simulate(origin, velocity, fuse)
	_next_id += 1
	thrown_count += 1
	_live.append({"id": _next_id, "path": flight.path, "start": _clock, "fuse": fuse, "thrower": thrower,
			"first_hit": flight.first_hit})
	grenade_thrown.rpc(_next_id, flight.path, fuse, flight.first_hit)
	return _next_id


## Host: a live grenade falls out of a soldier's hand (shot during his wind-up).
func drop(hand: Vector3, reserved: bool = true) -> int:
	var v := Vector3(_rng.randf_range(-0.6, 0.6), 0.5, _rng.randf_range(-0.6, 0.6))
	return throw(hand, v, -1, reserved)


## Every computer can use this (no side effects): the velocity that throws from `origin` to
## `target` leaving the hand `angle_deg` upwards. A target that can't be reached at that angle
## gets a steeper throw; the speed is never more than `max_throw_speed`.
func solve_throw(origin: Vector3, target: Vector3, angle_deg: float) -> Vector3:
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var d: float = flat.length()
	var dir: Vector3 = flat / d if d > 0.01 else Vector3.FORWARD
	var dy: float = target.y - origin.y
	var angle: float = deg_to_rad(angle_deg)
	var speed: float = max_throw_speed
	for i in 8:
		# Ballistics (no air): v² = g·d² / (2·cos²θ·(d·tanθ − dy)).
		var below: float = 2.0 * cos(angle) * cos(angle) * (d * tan(angle) - dy)
		if below > 0.001:
			speed = minf(sqrt(GRAVITY * d * d / below), max_throw_speed)
			break
		angle = minf(angle + deg_to_rad(8.0), deg_to_rad(75.0))
	return (dir * cos(angle) + Vector3.UP * sin(angle)) * speed


## The whole flight from `origin` with `velocity` for `duration` seconds: the arc, bounces,
## sliding down slopes, lying still. Returns {path: points every STEP·SAMPLE_EVERY s,
## first_hit: seconds until it first touches something (-1 = never), rest: where it ends}.
func simulate(origin: Vector3, velocity: Vector3, duration: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var pos: Vector3 = origin
	var v: Vector3 = velocity
	var path := PackedVector3Array([pos])
	var first_hit: float = -1.0
	var resting: bool = false
	var steps: int = int(ceil(duration / STEP))
	for i in steps:
		if not resting:
			v.y -= GRAVITY * STEP
			var to: Vector3 = pos + v * STEP
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(pos, to, BOUNCE_MASK))
			if hit.is_empty():
				pos = to
			else:
				if first_hit < 0.0:
					first_hit = (i + 1) * STEP
				var n: Vector3 = hit.normal
				pos = hit.position + n * RADIUS
				var into: float = v.dot(n)
				if into < 0.0:
					var along: Vector3 = v - n * into
					var hard: bool = ImpactEffects.surface_of(hit.collider, n) in ["wood", "metal"]
					v = along * (hard_tangent_keep if hard else tangent_keep) - n * into * (hard_restitution if hard else restitution)
				if n.y > 0.85 and v.length() < rest_speed:
					resting = true # lies still on (nearly) flat ground
					v = Vector3.ZERO
			if pos.y < -60.0:
				break # fell off the world
		if (i + 1) % SAMPLE_EVERY == 0 or i == steps - 1:
			path.append(pos)
	return {"path": path, "first_hit": first_hit, "rest": pos}


func _physics_process(delta: float) -> void:
	_clock += delta
	if not multiplayer.is_server():
		return
	for g in _live.duplicate():
		if _clock - float(g.start) >= float(g.fuse):
			_explode(g)


## Host: where a live grenade is right now (tests, GR2).
func position_of(id: int) -> Vector3:
	for g in _live:
		if g.id == id:
			return _path_point(g.path, _clock - float(g.start))
	return Vector3.INF


func live_count() -> int:
	return _live.size()


## The manager's game clock (seconds).
func clock() -> float:
	return _clock


## GR2, host: the id of the nearest live grenade within `radius` of any of `points`, or -1.
func find_grabbable(points: Array[Vector3], radius: float) -> int:
	var best: int = -1
	var best_d: float = radius
	for g in _live:
		var pos: Vector3 = _path_point(g.path, _clock - float(g.start))
		for pt in points:
			var d: float = pt.distance_to(pos)
			if d <= best_d:
				best_d = d
				best = int(g.id)
	return best


## GR2, host: a player picks the grenade up. It leaves the field (his hand shows it) and the
## fuse time it has left is returned (he throws it on with that, see GrenadeGrabHandler).
func grab(id: int) -> float:
	for g in _live:
		if g.id == id:
			_live.erase(g)
			grenade_grabbed.rpc(id)
			return maxf(float(g.fuse) - (_clock - float(g.start)), 0.0)
	return 0.0


## Host: the fuse is done. Who is hurt, then the burst on every computer.
func _explode(g: Dictionary) -> void:
	_live.erase(g)
	exploded_count += 1
	var path: PackedVector3Array = g.path
	var pos: Vector3 = path[path.size() - 1]
	var blast_from: Vector3 = pos + Vector3.UP * 0.15
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p.is_dead:
			continue
		var chest: Vector3 = p.global_position + Vector3.UP * (0.75 if p.is_crouching else 1.3)
		var d: float = minf(p.global_position.distance_to(pos), chest.distance_to(pos))
		if d > harm_radius_m or not (_reaches(blast_from, chest) or _reaches(blast_from, p.head.global_position)):
			continue
		p.take_damage(blast_damage(d), -1, pos, Vector3.UP)
		p.notify_hurt.rpc_id(p.get_peer_id(), pos)
	var thrower: Player = null
	for node in get_tree().get_nodes_in_group("players"):
		if (node as Player).get_peer_id() == int(g.thrower):
			thrower = node
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.state == Enemy.State.DEAD:
			continue
		var body: Vector3 = e.global_position + Vector3.UP * (0.3 if e.is_prone else (0.7 if e.is_kneeling else 1.1))
		var head: Vector3 = e.eyes.global_position
		var d: float = minf(e.global_position.distance_to(pos), body.distance_to(pos))
		if d > suppression_radius_m:
			continue
		var reached: bool = _reaches(blast_from, body) or _reaches(blast_from, head)
		if reached and d <= harm_radius_m:
			if e.take_damage(blast_damage(d), int(g.thrower), pos, Vector3.UP) and thrower:
				thrower.kills += 1 # GR2: a grenade thrown back
		if reached and e.state != Enemy.State.DEAD:
			e.add_suppression(suppression_amount * (1.0 - d / suppression_radius_m))
	grenade_exploded.rpc(int(g.id), pos)


## Damage at `d` metres from the burst (if the blast reaches you).
func blast_damage(d: float) -> float:
	if d <= kill_radius_m:
		return 300.0
	return lerpf(near_damage, far_damage, clampf((d - kill_radius_m) / (harm_radius_m - kill_radius_m), 0.0, 1.0))


## A clear line for the blast (nothing of the world or a tank/wreck in between)?
func _reaches(from: Vector3, to: Vector3) -> bool:
	return get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, Tank.SIGHT_MASK)).is_empty()


## A point of a recorded flight `t` seconds after the throw (between two kept points).
static func _path_point(path: PackedVector3Array, t: float) -> Vector3:
	var f: float = maxf(t, 0.0) / (STEP * SAMPLE_EVERY)
	var i: int = int(f)
	if i >= path.size() - 1:
		return path[path.size() - 1]
	return path[i].lerp(path[i + 1], f - i)


# ------------------------------------------------------------------ every computer
@rpc("authority", "call_local", "reliable")
func grenade_thrown(id: int, path: PackedVector3Array, fuse: float, first_hit: float) -> void:
	for v in _visuals:
		if v.id == -1:
			v.id = id
			v.path = path
			v.t = 0.0
			v.fuse = fuse
			v.first_hit = first_hit
			v.landed = false
			v.spin_axis = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1, 1)).normalized()
			var node := v.node as Node3D
			node.global_position = path[0]
			node.visible = true
			return


## GR2: picked up – the flying / lying grenade disappears (it is in someone's hand now).
@rpc("authority", "call_local", "reliable")
func grenade_grabbed(id: int) -> void:
	for v in _visuals:
		if v.id == id:
			v.id = -1
			(v.node as Node3D).visible = false


@rpc("authority", "call_local", "reliable")
func grenade_exploded(id: int, pos: Vector3) -> void:
	for v in _visuals:
		if v.id == id:
			v.id = -1
			(v.node as Node3D).visible = false
	var arty := get_tree().get_first_node_in_group("artillery") as ArtilleryBarrage
	if arty:
		arty.show_explosion(pos, 0.0, 0.55, shake_range_m, 0.8)
	else:
		for node in get_tree().get_nodes_in_group("players"):
			var pl := node as Player
			if pl.is_local_player():
				pl.add_shake(clampf(1.0 - pl.global_position.distance_to(pos) / shake_range_m, 0.0, 1.0) * 0.6)
	var boom: AudioStream = RecordedSounds.pick("grenade_boom")
	if boom:
		_play(boom, pos, 0.0, 1.0, 30.0)
	else:
		# Placeholder until a real grenade recording: the air-raid bomb, higher and quieter.
		_play(RecordedSounds.pick("raid_boom"), pos, -4.0, 1.4, 26.0)


func _process(delta: float) -> void:
	for v in _visuals:
		if v.id == -1:
			continue
		var before: Vector3 = _path_point(v.path, v.t)
		v.t += delta
		var pos: Vector3 = _path_point(v.path, v.t)
		var node := v.node as Node3D
		node.global_position = pos
		# Tumbling in the air, rolling on the ground, lying still at the end.
		var speed: float = before.distance_to(pos) / maxf(delta, 0.0001)
		if speed > 0.02:
			node.rotate(v.spin_axis, minf(speed / 0.04, 14.0) * delta)
		if not v.landed and v.first_hit >= 0.0 and v.t >= v.first_hit:
			v.landed = true
			_play(RecordedSounds.pick("grenade_land"), pos, -2.0, 1.0, 6.0)
		if v.t > v.fuse + 1.0:
			v.id = -1 # (the host's "exploded" got lost? never hang around)
			node.visible = false


## Every computer: the live grenades it shows right now (HUD warning icon).
## [{pos: Vector3, fuse_left: float}]
func get_visible_grenades() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v in _visuals:
		if v.id != -1:
			out.append({"pos": (v.node as Node3D).global_position, "fuse_left": float(v.fuse) - float(v.t)})
	return out


func _play(stream: AudioStream, pos: Vector3, volume_db: float, pitch: float, unit: float) -> void:
	if stream == null:
		return
	var a := _audio[_next_audio]
	_next_audio = (_next_audio + 1) % _audio.size()
	a.stream = stream
	a.volume_db = volume_db
	a.pitch_scale = pitch
	a.unit_size = unit
	a.global_position = pos
	a.play()


# ------------------------------------------------------------------ looks
## The F-1 grenade (`tools/import_weapons.py --f1`): origin = the middle of the body, fuze up.
## `with_lever` = the safety lever still on (in a hand); a thrown grenade has lost it.
static func make_grenade(with_lever: bool) -> Node3D:
	if _model == null:
		_model = load(MODEL_PATH)
	var g: Node3D = _model.instantiate()
	g.name = "F1Grenade"
	var lever := g.find_child("Lever", true, false)
	if lever and not with_lever:
		lever.free()
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g
