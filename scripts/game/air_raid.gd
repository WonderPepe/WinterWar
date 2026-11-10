class_name AirRaid
extends Node3D
## Air raid (A1): three Tupolev SB-2 fast bombers fly over and bomb the positions.
## Happens in the waves listed in `raid_waves` (battle n = wave n). If that wave also has an
## artillery barrage, the raid starts a few seconds AFTER the barrage ends.
##
## 1. APPROACH: "AIR RAID!" warning, the engines are heard far away and get louder.
## 2. BOMBING: the planes pass over the trench line one after another. Each drops a "stick" of
##    bombs along its flight line: one plane in front of the trench, one just behind it, one
##    further back. A bomb whistles for its last seconds, then explodes (big plume, shake).
##    Out in the open you are killed or hurt; crouching in the trench / being in the bunker is safe
##    (the same rule as the artillery, `ArtilleryBarrage.is_covered`). No bomb lands IN the trench.
## 3. LEAVING: the planes fly on and the engines fade. Officers whistle, the attack goes on.
##
## The HOST makes the whole plan (which plane, where and when each bomb lands) and sends it once
## (`begin_raid`). Every computer then flies the planes and lets the bombs fall from its own clock;
## only the host damages players. The explosions use the ArtilleryBarrage's blast effects.
##
## Looks: the camera sees only 600 m, the planes are 1-2 km away at first. So each plane is drawn
## closer to you and smaller, in the same direction (looks identical, `_cheat`). Sounds use the
## real position.

signal raid_started
signal raid_ended

enum Phase { IDLE, APPROACH, BOMBING, LEAVING }

@export var raid_waves: Array[int] = [4, 8, 10] ## The raid happens at the start of these waves (= battles).
@export var after_barrage_delay: float = 5.0 ## If the wave has a barrage: seconds after it ends.
@export var plane_speed: float = 110.0 ## m/s (~400 km/h, an SB-2).
@export var plane_scale: float = 1.7 ## Bigger than real so they are seen against the sky.
@export var altitude: float = 300.0 ## Metres above the ground (the sound makes it feel higher).
@export var fall_time: float = 6.0 ## Seconds a bomb takes to fall.
@export var first_pass: float = 12.5 ## Seconds until the first plane is overhead (the engine recording needs ~11 s run-up).
@export var plane_gap: float = 3.5 ## Seconds between the planes.
@export var bombs_per_plane: int = 8
@export var bomb_spacing: float = 25.0 ## Metres between bombs of one stick.
@export var cheat_distance: float = 480.0 ## Planes farther away are drawn at this distance (smaller).
@export var engine_sound: AudioStream ## Default: the plane recording (loudest `engine_overhead_at` s in).
@export var engine_overhead_at: float = 10.9
@export var engine_volume_db: float = 4.0
@export var engine_unit_size: float = 220.0
@export var whistle_sound: AudioStream ## Falling bomb. Should END at the impact.
@export var boom_sound: AudioStream ## One bomb sound for all bombs (normally empty: the `raid_boom*` recordings are used, a random one per bomb).
@export var close_sound: AudioStream ## Extra crack when a bomb lands close to you.
@export var close_sound_range_m: float = 45.0
@export var blast_scale: float = 2.3
@export var blast_height: float = 1.7
@export var shake_range_m: float = 230.0
@export var kill_radius_m: float = 9.0
@export var harm_radius_m: float = 50.0
@export var near_damage: float = 120.0
@export var hold_z: float = 0.0 ## While the raid comes before the advance, the Soviets come no closer than this.
@export var trench_rect: Rect2 = Rect2(-106.0, 50.0, 212.0, 22.0) ## No bomb lands inside.
@export var lane_front: Vector2 = Vector2(24.0, 40.0) ## z of the plane in front of the trench...
@export var lane_near: Vector2 = Vector2(74.0, 80.0) ## ...just behind it...
@export var lane_far: Vector2 = Vector2(96.0, 115.0) ## ...and further back.

var phase: Phase = Phase.IDLE
var time: float = 0.0 ## Seconds since the raid began (this computer).
var bombs_landed: int = 0

# The plan (identical on every computer).
var _dir: float = 1.0
var _planes: PackedFloat32Array = PackedFloat32Array() # per plane: centre x, lane z, altitude, pass time, pitch
var _b_plane: PackedInt32Array = PackedInt32Array()
var _b_time: PackedFloat32Array = PackedFloat32Array() # landing times
var _b_pos: PackedVector3Array = PackedVector3Array()
var _b_str: PackedFloat32Array = PackedFloat32Array()
var _b_state: PackedInt32Array = PackedInt32Array() # 0 waiting, 1 whistling, 2 landed
var _end_time: float = 0.0
var _first_bomb: float = 0.0
var _last_bomb: float = 0.0
var _held: bool = false
var _rng := RandomNumberGenerator.new()

var _plane_nodes: Array[Node3D] = []
var _engines: Array[AudioStreamPlayer3D] = []
var _engine_started: Array[bool] = []
var _bomb_nodes: Array[MeshInstance3D] = []
var _whistles: Array[AudioStreamPlayer3D] = []
var _booms: Array[AudioStreamPlayer3D] = []
var _next_whistle: int = 0
var _next_boom: int = 0
var _close_audio: AudioStreamPlayer
var _whistle_len: float = 2.6
var _boom_sounds: Array[AudioStream] = []


func _ready() -> void:
	add_to_group("air_raid")
	_rng.randomize()
	if engine_sound == null:
		engine_sound = RecordedSounds.pick("raid_engine")
	if engine_sound == null:
		engine_sound = load("res://assets/audio/background/plane_flyover_viima.ogg") as AudioStream
	if whistle_sound == null:
		whistle_sound = RecordedSounds.pick("raid_whistle")
	if boom_sound:
		_boom_sounds = [boom_sound]
	else:
		_boom_sounds = RecordedSounds.get_sounds("raid_boom")
	if whistle_sound:
		_whistle_len = minf(whistle_sound.get_length(), fall_time)
	_make_nodes()
	if multiplayer.is_server():
		var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
		if spawner:
			spawner.wave_started.connect(_on_wave_started)


func _exit_tree() -> void:
	if _held:
		Enemy.barrage_hold_z = INF # the match is over or left: no hold line for the next one


func is_active() -> bool:
	return phase != Phase.IDLE


# ------------------------------------------------------------------ start (host)
func _on_wave_started(number: int, _count: int) -> void:
	if not raid_waves.has(number):
		return
	var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	var arty := get_tree().get_first_node_in_group("artillery") as ArtilleryBarrage
	if arty and spawner and spawner.get_composition(number).barrage:
		# Artillery first; the bombers come when it has lifted.
		arty.barrage_ended.connect(_after_barrage, CONNECT_ONE_SHOT)
	else:
		start(true)


func _after_barrage() -> void:
	await get_tree().create_timer(after_barrage_delay).timeout
	var director := get_tree().get_first_node_in_group("match_director") as MatchDirector
	if director and director.is_over():
		return
	start(false)


## Host: begin the raid. `hold` = the Soviets wait at `hold_z` meanwhile (only when the raid
## comes before their advance, not after a barrage that has already sent them forward).
func start(hold: bool = true) -> void:
	if not multiplayer.is_server() or is_active():
		return
	_make_plan()
	var arty := get_tree().get_first_node_in_group("artillery") as ArtilleryBarrage
	if hold and (arty == null or not arty.is_active()):
		Enemy.barrage_hold_z = hold_z
		_held = true
	begin_raid.rpc(_dir, _planes, _b_plane, _b_time, _b_pos, _b_str, _end_time)


func _make_plan() -> void:
	var cx: float = 0.0
	var count: int = 0
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if not p.is_dead:
			cx += p.global_position.x
			count += 1
	cx = clampf(cx / maxi(count, 1), -70.0, 70.0)
	_dir = -1.0 if _rng.randf() < 0.5 else 1.0
	var lanes: Array[float] = [
		_rng.randf_range(lane_front.x, lane_front.y),
		_rng.randf_range(lane_near.x, lane_near.y),
		_rng.randf_range(lane_far.x, lane_far.y)]
	lanes.shuffle()
	var pitches: Array[float] = [1.0, 0.94, 1.07]
	pitches.shuffle()
	_planes = PackedFloat32Array()
	_b_plane = PackedInt32Array()
	_b_time = PackedFloat32Array()
	_b_pos = PackedVector3Array()
	_b_str = PackedFloat32Array()
	var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
	var end_time: float = 0.0
	for i in 3:
		var pass_x: float = cx + _rng.randf_range(-30.0, 30.0)
		var t_pass: float = first_pass + i * plane_gap + _rng.randf_range(-0.6, 0.6)
		var alt: float = altitude + _rng.randf_range(-30.0, 40.0)
		_planes.append_array(PackedFloat32Array([pass_x, lanes[i], alt, t_pass, pitches[i]]))
		end_time = maxf(end_time, t_pass + 2000.0 / plane_speed)
		var n: int = bombs_per_plane + _rng.randi_range(-1, 1)
		for j in n:
			var along: float = (j - (n - 1) * 0.5) * bomb_spacing * _rng.randf_range(0.85, 1.15)
			var pos := Vector3(pass_x + _dir * along, 0.0, lanes[i] + _rng.randf_range(-5.0, 5.0))
			if trench_rect.has_point(Vector2(pos.x, pos.z)) or ArtilleryBarrage.in_comm_trench_area(pos):
				continue # straddles the trench: that one goes over
			pos.y = terrain.get_height(pos.x, pos.z) if terrain else 0.0
			_b_plane.append(i)
			_b_time.append(t_pass + along / plane_speed) # the bomb lands right under its plane
			_b_pos.append(pos)
			_b_str.append(_rng.randf_range(0.6, 1.0))
	_end_time = end_time + 1.0


@rpc("authority", "call_local", "reliable")
func begin_raid(dir: float, planes: PackedFloat32Array, b_plane: PackedInt32Array, b_time: PackedFloat32Array,
		b_pos: PackedVector3Array, b_str: PackedFloat32Array, end_time: float) -> void:
	_dir = dir
	_planes = planes
	_b_plane = b_plane
	_b_time = b_time
	_b_pos = b_pos
	_b_str = b_str
	_end_time = end_time
	_b_state = PackedInt32Array()
	_b_state.resize(b_time.size())
	_first_bomb = INF
	_last_bomb = 0.0
	for t in b_time:
		_first_bomb = minf(_first_bomb, t)
		_last_bomb = maxf(_last_bomb, t)
	time = 0.0
	bombs_landed = 0
	for i in 3:
		_engine_started[i] = false
		_plane_nodes[i].visible = false
	for b in _bomb_nodes:
		b.visible = false
	phase = Phase.APPROACH
	raid_started.emit()


@rpc("authority", "call_local", "reliable")
func end_raid() -> void:
	phase = Phase.IDLE
	for i in 3:
		_plane_nodes[i].visible = false
		_engines[i].stop()
	for b in _bomb_nodes:
		b.visible = false
	raid_ended.emit()


## Host: the raid is over. Officers whistle and the attack goes on.
func _finish(whistles: bool) -> void:
	var was_held: bool = _held
	if _held:
		_held = false
		var arty := get_tree().get_first_node_in_group("artillery") as ArtilleryBarrage
		if arty == null or not arty.is_active():
			Enemy.barrage_hold_z = INF
	end_raid.rpc()
	if not whistles or not was_held:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e and e.state != Enemy.State.DEAD and e.data.kind == EnemyData.Kind.OFFICER:
			e.signal_advance()


# ------------------------------------------------------------------ every frame
func _process(delta: float) -> void:
	if phase == Phase.IDLE:
		return
	if multiplayer.is_server():
		var director := get_tree().get_first_node_in_group("match_director") as MatchDirector
		if director and director.is_over():
			_finish(false) # the battle ended: the planes are gone
			return
	time += delta
	_update_phase()
	_update_planes()
	_update_bombs()
	if multiplayer.is_server() and time >= _end_time:
		_finish(true)


func _update_phase() -> void:
	if time >= _last_bomb + 1.0:
		phase = Phase.LEAVING
	elif time >= _first_bomb - fall_time:
		phase = Phase.BOMBING
	else:
		phase = Phase.APPROACH


## Where plane `i` really is at raid time `t`.
func plane_position(i: int, t: float) -> Vector3:
	var o: int = i * 5
	var x: float = _planes[o] + _dir * plane_speed * (t - _planes[o + 3])
	var y: float = _planes[o + 2]
	var after: float = t - _planes[o + 3] - 5.0
	if after > 0.0:
		y += after * 9.0 # climbing away
	return Vector3(x, y, _planes[o + 1])


func _update_planes() -> void:
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else Vector3(0, 1.7, 60)
	for i in 3:
		var o: int = i * 5
		var pos: Vector3 = plane_position(i, time)
		var pitch: float = _planes[o + 4]
		# The engine recording starts so that its loudest moment is when the plane passes.
		if not _engine_started[i] and engine_sound and time >= _planes[o + 3] - engine_overhead_at / pitch:
			_engine_started[i] = true
			_engines[i].pitch_scale = pitch
			_engines[i].play()
		_engines[i].global_position = pos
		var node := _plane_nodes[i]
		node.visible = (pos - eye).length() < 3000.0
		if node.visible:
			var shown: Array = _cheat(eye, pos)
			node.global_position = shown[0]
			node.scale = Vector3.ONE * plane_scale * float(shown[1])
			node.rotation.y = -_dir * PI * 0.5
			node.rotation.z = clampf((time - _planes[o + 3] - 4.0) * 0.08, 0.0, 0.5) * _dir # banks away


## Draws `pos` closer to the camera in the same direction: [position, scale factor].
func _cheat(eye: Vector3, pos: Vector3) -> Array:
	var d: Vector3 = pos - eye
	var dist: float = maxf(d.length(), 0.1)
	var k: float = minf(1.0, cheat_distance / dist)
	return [eye + d * k, k]


func _update_bombs() -> void:
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else Vector3(0, 1.7, 60)
	var arty := get_tree().get_first_node_in_group("artillery") as ArtilleryBarrage
	var slot: int = 0
	for b in _b_time.size():
		var t_land: float = _b_time[b]
		if _b_state[b] == 2:
			continue
		var pos: Vector3 = _b_pos[b]
		if _b_state[b] == 0 and whistle_sound and time >= t_land - _whistle_len:
			_b_state[b] = 1
			var w := _whistles[_next_whistle]
			_next_whistle = (_next_whistle + 1) % _whistles.size()
			w.global_position = pos + Vector3.UP * 3.0
			w.pitch_scale = _rng.randf_range(0.93, 1.07)
			w.play()
		if time >= t_land:
			_b_state[b] = 2
			_land(b, arty)
			continue
		# The falling bomb: released `fall_time` before, in front of where it lands.
		var s: float = (time - (t_land - fall_time)) / fall_time
		if s >= 0.0 and s < 1.0 and slot < _bomb_nodes.size():
			var o: int = _b_plane[b] * 5
			var from_x: float = pos.x - _dir * plane_speed * fall_time
			var p := Vector3(lerpf(from_x, pos.x, s), pos.y + (_planes[o + 2] - pos.y) * (1.0 - s * s), pos.z)
			var shown: Array = _cheat(eye, p)
			var node := _bomb_nodes[slot]
			slot += 1
			node.visible = true
			node.global_position = shown[0]
			node.scale = Vector3.ONE * float(shown[1])
	for k in range(slot, _bomb_nodes.size()):
		_bomb_nodes[k].visible = false


## A bomb lands: every computer shows it; the host hurts the people in the open.
func _land(b: int, arty: ArtilleryBarrage) -> void:
	var pos: Vector3 = _b_pos[b]
	var strength: float = _b_str[b]
	bombs_landed += 1
	if arty:
		arty.show_explosion(pos, strength, blast_scale, shake_range_m, blast_height)
	if not _boom_sounds.is_empty():
		var bm := _booms[_next_boom]
		bm.stream = _boom_sounds[_rng.randi() % _boom_sounds.size()]
		_next_boom = (_next_boom + 1) % _booms.size()
		bm.global_position = pos + Vector3.UP * 2.0
		bm.pitch_scale = _rng.randf_range(0.9, 1.05)
		bm.play()
	for node in get_tree().get_nodes_in_group("players"):
		var pl := node as Player
		if pl.is_local_player() and close_sound:
			var d: float = pl.global_position.distance_to(pos)
			if d < close_sound_range_m:
				_close_audio.volume_db = lerpf(0.0, -12.0, d / close_sound_range_m)
				_close_audio.pitch_scale = _rng.randf_range(0.85, 0.95)
				_close_audio.play()
	if not multiplayer.is_server():
		return
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p.is_dead or ArtilleryBarrage.is_covered(p):
			continue
		if ArtilleryBarrage.is_in_bunker(p) and pos.z > p.global_position.z:
			continue # the gunner at the firing hole is only exposed to bombs in FRONT of the bunker
		var d: float = p.global_position.distance_to(pos)
		if d > harm_radius_m:
			continue
		var dmg: float = 500.0 if d <= kill_radius_m else lerpf(near_damage, 10.0, (d - kill_radius_m) / (harm_radius_m - kill_radius_m))
		p.take_damage(dmg, -1, pos, Vector3.UP)
		p.notify_hurt.rpc_id(p.get_peer_id(), pos)


# ------------------------------------------------------------------ building the nodes
func _make_nodes() -> void:
	for i in 3:
		var plane := _make_plane()
		plane.visible = false
		add_child(plane)
		_plane_nodes.append(plane)
		var a := AudioStreamPlayer3D.new()
		a.name = "Engine%d" % i
		a.bus = &"SFX"
		a.stream = engine_sound
		a.unit_size = engine_unit_size
		a.max_distance = 0.0
		a.volume_db = engine_volume_db
		add_child(a)
		_engines.append(a)
		_engine_started.append(false)
	for i in 8:
		var w := AudioStreamPlayer3D.new()
		w.name = "Whistle%d" % i
		w.bus = &"SFX"
		w.stream = whistle_sound
		w.unit_size = 60.0
		w.max_distance = 0.0
		w.volume_db = 2.0
		add_child(w)
		_whistles.append(w)
		var bm := AudioStreamPlayer3D.new()
		bm.name = "Boom%d" % i
		bm.bus = &"SFX"
		bm.unit_size = 90.0
		bm.max_distance = 0.0
		bm.volume_db = 2.0
		add_child(bm)
		_booms.append(bm)
	_close_audio = AudioStreamPlayer.new()
	_close_audio.name = "CloseBurst"
	_close_audio.bus = &"SFX"
	_close_audio.stream = close_sound
	add_child(_close_audio)
	var bomb_mesh := CapsuleMesh.new()
	bomb_mesh.radius = 0.7
	bomb_mesh.height = 3.4
	var bm_mat := StandardMaterial3D.new()
	bm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm_mat.albedo_color = Color(0.1, 0.1, 0.1)
	bomb_mesh.material = bm_mat
	for i in 24:
		var m := MeshInstance3D.new()
		m.mesh = bomb_mesh
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_bomb_nodes.append(m)


## An SB-2 from boxes and capsules: nose towards -Z, twin tail fins, two engines.
func _make_plane() -> Node3D:
	var root := Node3D.new()
	root.name = "SB2"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.13, 0.15, 0.14)
	var parts: Array = [
		[_capsule(0.95, 12.3), Vector3(0, 0, 0), Vector3(PI * 0.5, 0, 0)], # fuselage
		[_box(Vector3(20.3, 0.45, 3.2)), Vector3(0, -0.25, 0.6), Vector3.ZERO], # wing
		[_capsule(0.7, 5.0), Vector3(-3.6, -0.2, -1.0), Vector3(PI * 0.5, 0, 0)], # engine L
		[_capsule(0.7, 5.0), Vector3(3.6, -0.2, -1.0), Vector3(PI * 0.5, 0, 0)], # engine R
		[_box(Vector3(6.8, 0.25, 1.7)), Vector3(0, 0.5, 5.3), Vector3.ZERO], # tailplane
		[_box(Vector3(0.25, 2.4, 1.9)), Vector3(-2.7, 1.3, 5.4), Vector3.ZERO], # fin L
		[_box(Vector3(0.25, 2.4, 1.9)), Vector3(2.7, 1.3, 5.4), Vector3.ZERO], # fin R
		[_box(Vector3(0.9, 0.6, 1.6)), Vector3(0, 1.0, -1.6), Vector3.ZERO], # gun turret hump
	]
	for part: Array in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = mat
		mi.position = part[1]
		mi.rotation = part[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 8
	c.rings = 3
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
