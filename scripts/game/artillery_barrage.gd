class_name ArtilleryBarrage
extends Node3D
## Soviet artillery preparation before some waves (WaveData.barrage).
##
## 1. WARNING: "ARTILLERY! GET DOWN INTO THE TRENCH!" for a few seconds.
## 2. FIRING: the recording plays (assets/audio/artillery/barrage.ogg) and a shell lands at
##    every bang in it (`shell_times`, found in the recording; louder bang = closer to you).
##    Anyone out in the open near a shell is hurt or killed; in the trench or the bunker you
##    are safe. Meanwhile the Soviets of the wave advance, but no closer than `hold_z`.
## 3. END: "The barrage lifts" – every officer blows his whistle and the attack goes on.
##
## The HOST decides everything (when, where shells land, who is hit); every computer shows the
## explosions and plays the sound (RPCs). Explosion visuals are pooled and made in code.

signal barrage_started
signal barrage_ended

enum Phase { IDLE, WARNING, FIRING }

@export var sound: AudioStream ## The barrage recording.
@export var shell_times: PackedFloat32Array = PackedFloat32Array() ## Seconds into the recording of each bang.
@export var shell_strengths: PackedFloat32Array = PackedFloat32Array() ## 0..1, how loud each bang is.
@export var warning_time: float = 4.0 ## Seconds of "ARTILLERY!" before the first shell.
@export var hold_z: float = 0.0 ## The Soviets come no closer than this while it lasts (trench front at z ≈ 52).
@export var zone_min: Vector2 = Vector2(-115.0, 16.0) ## Shells land inside this x/z area...
@export var zone_max: Vector2 = Vector2(115.0, 110.0)
@export var trench_rect: Rect2 = Rect2(-106.0, 50.0, 212.0, 22.0) ## ...but never inside the trench itself.
@export var kill_radius_m: float = 3.5 ## Out in the open, this close = dead.
@export var harm_radius_m: float = 12.0 ## Hurt up to this far.
@export var near_damage: float = 90.0 ## Damage just outside the kill radius (falls to ~10 at the edge).
@export var aimed_share: float = 0.45 ## Part of the shells aimed at people standing in the open.
@export var near_m: float = 10.0 ## The loudest bangs land this far from you (in the trench)...
@export var far_m: float = 55.0 ## ...the quietest ones this far.
@export var scorch_fade_time: float = 25.0 ## After the barrage the marks in the snow fade away.

## Synced by the RPCs: what the barrage is doing now (the HUD reads it).
var phase: Phase = Phase.IDLE
var shells_fired: int = 0

var _time: float = 0.0
var _next_shell: int = 0
var _length: float = 28.0
var _rng := RandomNumberGenerator.new()
var _audio: AudioStreamPlayer
var _blasts: Array = [] # pooled [flash quad, light, earth, snow, smoke, plume]
var _next_blast: int = 0
var _scorches: Array[MeshInstance3D] = []
var _next_scorch: int = 0
var _scorch_fade: float = -1.0
var _flash_time: Array[float] = []


func _ready() -> void:
	add_to_group("artillery")
	_rng.randomize()
	_audio = AudioStreamPlayer.new()
	_audio.name = "BarrageSound"
	_audio.bus = &"SFX"
	_audio.stream = sound
	add_child(_audio)
	if sound:
		_length = sound.get_length()
	_make_pool()
	if multiplayer.is_server():
		var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
		if spawner:
			spawner.wave_started.connect(_on_wave_started)


func is_active() -> bool:
	return phase != Phase.IDLE


## Down in the trench or inside the bunker = safe from the shells.
static func is_covered(p: Player) -> bool:
	var pos: Vector3 = p.global_position
	return pos.y < -0.5 and pos.z > 48.0 and pos.z < 76.0 and absf(pos.x) < 108.0


func _on_wave_started(number: int, _count: int) -> void:
	var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	if spawner and spawner.get_composition(number).barrage:
		start()


## Host: begin the warning (then the barrage itself).
func start() -> void:
	if not multiplayer.is_server() or is_active():
		return
	Enemy.barrage_hold_z = hold_z # the Soviets advance behind the shells, but not into them
	_time = 0.0
	_next_shell = 0
	begin_warning.rpc()


func _process(delta: float) -> void:
	_update_visuals(delta)
	if not multiplayer.is_server() or phase == Phase.IDLE:
		return
	var director := get_tree().get_first_node_in_group("match_director") as MatchDirector
	if director and director.is_over():
		_finish(false) # the battle ended: the guns fall silent, no whistles
		return
	_time += delta
	if phase == Phase.WARNING:
		if _time >= warning_time:
			_time = 0.0
			begin_firing.rpc()
		return
	while _next_shell < shell_times.size() and _time >= shell_times[_next_shell]:
		var s: float = shell_strengths[_next_shell] if _next_shell < shell_strengths.size() else 0.5
		_fire_shell(s)
		_next_shell += 1
	if _time >= _length:
		_finish(true)


## Host: the barrage is over. Officers whistle and the advance goes on.
func _finish(whistles: bool) -> void:
	Enemy.barrage_hold_z = INF
	end_barrage.rpc()
	if not whistles:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e and e.state != Enemy.State.DEAD and e.data.kind == EnemyData.Kind.OFFICER:
			e.signal_advance()


@rpc("authority", "call_local", "reliable")
func begin_warning() -> void:
	phase = Phase.WARNING
	shells_fired = 0
	barrage_started.emit()


@rpc("authority", "call_local", "reliable")
func begin_firing() -> void:
	phase = Phase.FIRING
	if sound:
		_audio.play()


@rpc("authority", "call_local", "reliable")
func end_barrage() -> void:
	phase = Phase.IDLE
	_audio.stop()
	_scorch_fade = scorch_fade_time
	barrage_ended.emit()


# ------------------------------------------------------------------ shells (host)
func _fire_shell(strength: float) -> void:
	var pos: Vector3 = _pick_landing(strength)
	var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
	if terrain:
		pos.y = terrain.get_height(pos.x, pos.z)
	# Who is hit: only people out in the open.
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p.is_dead or is_covered(p):
			continue
		var d: float = p.global_position.distance_to(pos)
		if d > harm_radius_m:
			continue
		var dmg: float = 500.0 if d <= kill_radius_m else lerpf(near_damage, 10.0, (d - kill_radius_m) / (harm_radius_m - kill_radius_m))
		p.take_damage(dmg, -1, pos, Vector3.UP)
		p.notify_hurt.rpc_id(p.get_peer_id(), pos)
	explode.rpc(pos, strength)


## Where the next shell lands: near someone standing in the open (sometimes), otherwise in
## front of or behind the trench, closer to the players for the louder bangs.
func _pick_landing(strength: float) -> Vector3:
	var exposed: Array[Player] = []
	var everyone: Array[Player] = []
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p.is_dead:
			continue
		everyone.append(p)
		if not is_covered(p):
			exposed.append(p)
	for attempt in 12:
		var pos: Vector3
		if not exposed.is_empty() and _rng.randf() < aimed_share:
			var p: Player = exposed[_rng.randi() % exposed.size()]
			pos = p.global_position + _flat_offset(_rng.randf_range(2.0, harm_radius_m))
		else:
			var centre: Vector3 = everyone[_rng.randi() % everyone.size()].global_position if not everyone.is_empty() else Vector3(0, 0, 60)
			var dist: float = lerpf(far_m, near_m, clampf(strength, 0.0, 1.0)) * _rng.randf_range(0.8, 1.25)
			pos = centre + _flat_offset(dist)
		pos.x = clampf(pos.x, zone_min.x, zone_max.x)
		pos.z = clampf(pos.z, zone_min.y, zone_max.y)
		if not trench_rect.has_point(Vector2(pos.x, pos.z)):
			return pos
	return Vector3(_rng.randf_range(zone_min.x, zone_max.x), 0.0, _rng.randf_range(20.0, 44.0))


func _flat_offset(dist: float) -> Vector3:
	var a: float = _rng.randf() * TAU
	return Vector3(cos(a), 0.0, sin(a)) * dist


# ------------------------------------------------------------------ explosions (every computer)
## A shell lands: flash, earth and snow thrown up, a column of smoke, a dark mark in the snow,
## and the ground shakes under you.
@rpc("authority", "call_local", "reliable")
func explode(pos: Vector3, strength: float) -> void:
	shells_fired += 1
	var b: Array = _blasts[_next_blast]
	_next_blast = (_next_blast + 1) % _blasts.size()
	var size: float = lerpf(0.8, 1.3, strength)
	var flash := b[0] as MeshInstance3D
	flash.global_position = pos + Vector3.UP * 1.5
	flash.scale = Vector3.ONE * size
	flash.visible = true
	var light := b[1] as OmniLight3D
	light.global_position = pos + Vector3.UP * 2.0
	light.visible = true
	_flash_time[_blasts.find(b)] = 0.18
	for i in [2, 3, 4, 5]:
		var p := b[i] as CPUParticles3D
		p.global_position = pos
		p.restart()
	var scorch := _scorches[_next_scorch]
	_next_scorch = (_next_scorch + 1) % _scorches.size()
	scorch.global_position = pos + Vector3.UP * 0.07
	scorch.rotation.y = randf() * TAU
	scorch.scale = Vector3.ONE * size * randf_range(0.8, 1.2)
	var sm := scorch.material_override as StandardMaterial3D
	sm.albedo_color.a = 0.75
	scorch.visible = true
	_scorch_fade = -1.0
	# Shake the camera of the player on this computer: stronger the closer it landed.
	for node in get_tree().get_nodes_in_group("players"):
		var pl := node as Player
		if pl.is_local_player():
			var d: float = pl.global_position.distance_to(pos)
			pl.add_shake(clampf(1.0 - d / 90.0, 0.0, 1.0) * (0.5 + strength))


func _update_visuals(delta: float) -> void:
	for i in _blasts.size():
		if _flash_time[i] > 0.0:
			_flash_time[i] -= delta
			if _flash_time[i] <= 0.0:
				(_blasts[i][0] as Node3D).visible = false
				(_blasts[i][1] as Node3D).visible = false
	if _scorch_fade > 0.0:
		_scorch_fade -= delta
		var a: float = clampf(_scorch_fade / scorch_fade_time, 0.0, 1.0) * 0.75
		for s in _scorches:
			if s.visible:
				var m := s.material_override as StandardMaterial3D
				m.albedo_color.a = minf(m.albedo_color.a, a)
				if a <= 0.0:
					s.visible = false


func _make_pool() -> void:
	var soft: Texture2D = ImpactEffects.make_soft_texture()
	for i in 6:
		var flash := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(10.0, 10.0)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.albedo_color = Color(1.0, 0.72, 0.35, 0.95)
		fm.albedo_texture = soft
		q.material = fm
		flash.mesh = q
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flash.visible = false
		add_child(flash)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.7, 0.4)
		light.light_energy = 4.0
		light.omni_range = 30.0
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		# Frozen earth: dark clods thrown high, falling back fast.
		var earth := _burst(40, 1.8, Vector2(9.0, 19.0), 24.0, Vector3(0, -9.8, 0), 0.7, Color(0.16, 0.12, 0.09, 1.0), soft)
		# The dark fountain of earth and snow right above the hit.
		var plume := _burst(18, 2.4, Vector2(6.0, 13.0), 14.0, Vector3(0, -5.0, 0), 3.2, Color(0.24, 0.2, 0.17, 0.9), soft)
		plume.damping_min = 1.5
		plume.damping_max = 3.0
		# Snow: a big pale cloud thrown up and hanging in the air.
		var snow := _burst(30, 3.0, Vector2(3.0, 9.0), 55.0, Vector3(0.4, -1.5, 0.2), 4.0, Color(0.76, 0.8, 0.88, 0.85), soft)
		snow.damping_min = 2.0
		snow.damping_max = 3.5
		# Smoke: a dark grey column that rises and drifts away with the wind.
		var smoke := _burst(12, 8.0, Vector2(1.5, 4.0), 18.0, Vector3(0.7, 0.7, 0.3), 7.0, Color(0.3, 0.29, 0.28, 0.6), soft)
		smoke.explosiveness = 0.75
		var grow := Curve.new()
		grow.add_point(Vector2(0.0, 0.4))
		grow.add_point(Vector2(1.0, 1.0))
		smoke.scale_amount_curve = grow
		for p in [earth, plume, snow, smoke]:
			ImpactEffects.web_fallback(p)
			add_child(p)
		_blasts.append([flash, light, earth, snow, smoke, plume])
		_flash_time.append(0.0)
	# Dark marks in the snow where the shells landed.
	var mark := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.12, 0.1, 0.08, 1.0))
	g.set_color(1, Color(0.2, 0.18, 0.15, 0.0))
	g.add_point(0.45, Color(0.16, 0.13, 0.1, 0.85))
	mark.gradient = g
	mark.fill = GradientTexture2D.FILL_RADIAL
	mark.fill_from = Vector2(0.5, 0.5)
	mark.fill_to = Vector2(0.5, 0.0)
	mark.width = 64
	mark.height = 64
	for i in 30:
		var s := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(5.0, 5.0)
		s.mesh = pm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = mark
		m.albedo_color = Color(1, 1, 1, 0.75)
		s.material_override = m
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.visible = false
		add_child(s)
		_scorches.append(s)


func _burst(amount: int, lifetime: float, speed: Vector2, spread: float, gravity: Vector3, size: float,
		color: Color, tex: Texture2D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = gravity
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color, 0.0))
	p.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
