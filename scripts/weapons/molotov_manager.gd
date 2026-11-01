class_name MolotovManager
extends Node3D
## Flying Molotov cocktails and the fires they start (T2).
##
## The HOST throws the bottle (`throw()`): it follows a ballistic arc, checked with short rays
## every physics frame. Every other computer only gets the start point and speed
## (`flight_started`) and draws the same arc itself, until the host says where it broke
## (`shatter`). On the host the fire then burns for a while and hurts anyone standing in it.
##   - engine deck of a tank → the tank catches fire (Tank.molotov_hit)
##   - anywhere else on a tank → a short fire on the armour (the crew can't see for a moment)
##   - the ground → a pool of burning fuel (`ground_burn_time` s, radius `fire_radius_m`)
## Bottles and fires are pooled (made once, reused).

enum Hit { GROUND, TANK_ARMOUR, TANK_ENGINE }

const GRAVITY := 9.8

@export var max_flight_time: float = 6.0
@export var fire_radius_m: float = 1.6 ## The burning fuel spreads this far.
@export var ground_burn_time: float = 6.0
@export var armour_burn_time: float = 4.0
@export var fire_tick: float = 0.5 ## Damage every this many seconds...
@export var player_burn_damage: float = 8.0 ## ...to a player standing in the fire,
@export var enemy_burn_damage: float = 25.0 ## ...and to a Soviet soldier.

var shatter_count: int = 0 ## Statistics / tests.

# Host: flying bottles [{id, pos, vel, t, exclude, thrower}] and burning fuel [{pos, until, thrower}].
var _flights: Array[Dictionary] = []
var _fires: Array[Dictionary] = []
var _next_id: int = 0
var _tick: float = 0.0
var _clock: float = 0.0
# Every computer: visual pools.
var _bottles: Array[Dictionary] = [] # {node, id, pos, vel, active}
var _fire_fx: Array[Dictionary] = [] # {node, until, flames, smoke}
var _next_fx: int = 0
var _break_fx: Array[CPUParticles3D] = []
var _next_break: int = 0
var _audio: Array[AudioStreamPlayer3D] = []
var _next_audio: int = 0


func _ready() -> void:
	add_to_group("molotovs")
	for i in 6:
		var b := make_bottle(true)
		b.visible = false
		add_child(b)
		_bottles.append({"node": b, "id": -1, "pos": Vector3.ZERO, "vel": Vector3.ZERO})
	for i in 8:
		var f := _make_fire()
		add_child(f.node)
		_fire_fx.append(f)
	for i in 4:
		var g := _make_glass_burst()
		add_child(g)
		_break_fx.append(g)
	for i in 4:
		var a := AudioStreamPlayer3D.new()
		a.bus = &"SFX"
		a.unit_size = 14.0
		add_child(a)
		_audio.append(a)


# ------------------------------------------------------------------ host
## Host: a bottle leaves `origin` with `velocity`. `thrower` (may be null) is not hit by it.
func throw(origin: Vector3, velocity: Vector3, thrower: Player) -> void:
	if not multiplayer.is_server():
		return
	_next_id += 1
	var exclude: Array[RID] = []
	if thrower:
		exclude.append(thrower.get_rid())
	_flights.append({"id": _next_id, "pos": origin, "vel": velocity, "t": 0.0, "exclude": exclude,
			"thrower": thrower.get_peer_id() if thrower else -1})
	flight_started.rpc(_next_id, origin, velocity)


## Host: a lit bottle falls at someone's feet (held too long, or its thrower died).
func drop_at(pos: Vector3, thrower_id: int) -> void:
	if not multiplayer.is_server():
		return
	_next_id += 1
	_start_fire(_next_id, pos, Vector3.UP, null, thrower_id)


func _physics_process(delta: float) -> void:
	_update_visuals(delta)
	if not multiplayer.is_server():
		return
	var space := get_world_3d().direct_space_state
	for f in _flights.duplicate():
		var from: Vector3 = f.pos
		var vel: Vector3 = f.vel
		vel.y -= GRAVITY * delta
		var to: Vector3 = from + vel * delta
		f.vel = vel
		f.t += delta
		var query := PhysicsRayQueryParameters3D.create(from, to, 0b111) # world, players, enemies
		query.exclude = f.exclude
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			_flights.erase(f)
			_start_fire(f.id, hit.position, hit.normal, hit.collider, f.thrower)
		elif f.t > max_flight_time:
			_flights.erase(f)
			shatter.rpc(f.id, to, Vector3.UP, -1, NodePath())
		else:
			f.pos = to
	_tick -= delta
	if _tick <= 0.0:
		_tick = fire_tick
		_burn_things()


## Host: the bottle broke at `pos`. Decides what burns and tells everyone.
func _start_fire(id: int, pos: Vector3, normal: Vector3, collider: Object, thrower_id: int) -> void:
	shatter_count += 1
	var tank: Tank = _find_tank(collider)
	if tank:
		var engine: bool = tank.molotov_hit(tank.to_local(pos))
		shatter.rpc(id, pos, normal, Hit.TANK_ENGINE if engine else Hit.TANK_ARMOUR, tank.get_path())
		return
	_fires.append({"pos": pos, "until": _now() + ground_burn_time, "thrower": thrower_id})
	shatter.rpc(id, pos, normal, Hit.GROUND, NodePath())


func _find_tank(collider: Object) -> Tank:
	var n := collider as Node
	for i in 3:
		if n == null:
			return null
		if n is Tank:
			return n
		n = n.get_parent()
	return null


## Host, every `fire_tick`: everyone standing in burning fuel gets hurt.
func _burn_things() -> void:
	var now: float = _now()
	for f in _fires.duplicate():
		if now > f.until:
			_fires.erase(f)
	for f in _fires:
		var pos: Vector3 = f.pos
		for node in get_tree().get_nodes_in_group("players"):
			var p := node as Player
			if not p.is_dead and _in_fire(p.global_position, pos):
				p.take_damage(player_burn_damage, -1, pos, Vector3.UP)
				p.notify_hurt.rpc_id(p.get_peer_id(), pos)
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Enemy
			if e and e.state != Enemy.State.DEAD and _in_fire(e.global_position, pos):
				if e.take_damage(enemy_burn_damage, f.thrower, pos, Vector3.UP):
					for pn in get_tree().get_nodes_in_group("players"):
						if (pn as Player).get_peer_id() == f.thrower:
							(pn as Player).kills += 1 # burnt by his Molotov


func _in_fire(body: Vector3, fire: Vector3) -> bool:
	return Vector2(body.x - fire.x, body.z - fire.z).length() <= fire_radius_m and absf(body.y - fire.y) < 1.5


## Host: is there burning fuel at `pos` right now? (tests)
func is_burning_at(pos: Vector3) -> bool:
	for f in _fires:
		if _now() <= f.until and _in_fire(pos, f.pos):
			return true
	return false


## Game time (also right in sped-up tests).
func _now() -> float:
	return _clock


func _process(delta: float) -> void:
	_clock += delta


# ------------------------------------------------------------------ every computer
@rpc("authority", "call_local", "reliable")
func flight_started(id: int, origin: Vector3, velocity: Vector3) -> void:
	for b in _bottles:
		if b.id == -1:
			b.id = id
			b.pos = origin
			b.vel = velocity
			(b.node as Node3D).global_position = origin
			(b.node as Node3D).visible = true
			_play(RecordedSounds.pick("molotov_throw"), origin)
			return


## The bottle broke: glass, a whoosh of burning fuel, then flames for a while.
## `on_path` = the tank it hit (the fire sticks to it), empty for the ground.
@rpc("authority", "call_local", "reliable")
func shatter(id: int, pos: Vector3, normal: Vector3, hit: int, on_path: NodePath) -> void:
	for b in _bottles:
		if b.id == id:
			b.id = -1
			(b.node as Node3D).visible = false
	if hit < 0:
		return # flew off the map
	var g := _break_fx[_next_break]
	_next_break = (_next_break + 1) % _break_fx.size()
	g.global_position = pos + normal * 0.05
	g.restart()
	_play(RecordedSounds.pick("molotov_break"), pos)
	if hit == Hit.TANK_ENGINE:
		return # the tank shows its own big engine fire
	var f: Dictionary = _fire_fx[_next_fx]
	if not is_instance_valid(f.node):
		# T3: this fire was stuck to a tank wreck that has been cleared away – make a new one.
		f = _make_fire()
		add_child(f.node)
		_fire_fx[_next_fx] = f
	_next_fx = (_next_fx + 1) % _fire_fx.size()
	var node := f.node as Node3D
	var parent: Node = get_node_or_null(on_path) if not on_path.is_empty() else self
	if parent == null:
		parent = self
	if node.get_parent() != parent:
		node.get_parent().remove_child(node)
		parent.add_child(node)
	node.global_position = pos + normal * 0.05
	node.visible = true
	f.until = _clock + (armour_burn_time if hit == Hit.TANK_ARMOUR else ground_burn_time)
	f.age = 0.0
	(f.flames as CPUParticles3D).emitting = true
	(f.smoke as CPUParticles3D).emitting = true
	var crackle: AudioStream = RecordedSounds.pick("fire_loop")
	var a := f.audio as AudioStreamPlayer3D
	if crackle:
		a.stream = crackle
		a.play()


func _update_visuals(delta: float) -> void:
	for b in _bottles:
		if b.id == -1:
			continue
		var vel: Vector3 = b.vel
		vel.y -= GRAVITY * delta
		b.vel = vel
		b.pos = (b.pos as Vector3) + vel * delta
		var node := b.node as Node3D
		node.global_position = b.pos
		node.rotate_object_local(Vector3.RIGHT, -delta * 9.0) # tumbling end over end
		if (b.pos as Vector3).y < -60.0:
			b.id = -1
			node.visible = false
	for f in _fire_fx:
		if not is_instance_valid(f.node):
			continue # went with a cleared-away wreck (replaced when next needed)
		var node := f.node as Node3D
		if not node.visible:
			continue
		f.age += delta
		# The fuel spreads out in the first moment, then burns down.
		var spread: float = clampf(f.age / 0.4, 0.3, 1.0)
		(f.flames as CPUParticles3D).emission_sphere_radius = fire_radius_m * 0.6 * spread
		if _clock > f.until:
			(f.flames as CPUParticles3D).emitting = false
			(f.smoke as CPUParticles3D).emitting = false
			(f.audio as AudioStreamPlayer3D).stop()
			if _clock > f.until + 3.0:
				node.visible = false


func _play(stream: AudioStream, pos: Vector3) -> void:
	if stream == null:
		return
	var a := _audio[_next_audio]
	_next_audio = (_next_audio + 1) % _audio.size()
	a.stream = stream
	a.global_position = pos
	a.play()


# ------------------------------------------------------------------ looks
## A Molotov cocktail made from shapes: a dark green bottle with a rag stuffed in its neck.
## Origin = middle of the bottle, neck pointing +Y. (Also used for the bottle in your hand.)
static func make_bottle(_flying: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Bottle"
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.16, 0.24, 0.13)
	glass.roughness = 0.15
	glass.metallic_specular = 0.8
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.038
	cyl.bottom_radius = 0.04
	cyl.height = 0.19
	cyl.radial_segments = 10
	cyl.rings = 1
	cyl.material = glass
	body.mesh = cyl
	root.add_child(body)
	var shoulder := MeshInstance3D.new()
	var sh := CylinderMesh.new()
	sh.top_radius = 0.016
	sh.bottom_radius = 0.038
	sh.height = 0.05
	sh.radial_segments = 10
	sh.rings = 1
	sh.material = glass
	shoulder.mesh = sh
	shoulder.position.y = 0.12
	root.add_child(shoulder)
	var neck := MeshInstance3D.new()
	var nk := CylinderMesh.new()
	nk.top_radius = 0.015
	nk.bottom_radius = 0.016
	nk.height = 0.06
	nk.radial_segments = 8
	nk.rings = 1
	nk.material = glass
	neck.mesh = nk
	neck.position.y = 0.175
	root.add_child(neck)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.78, 0.74, 0.62)
	cloth.roughness = 1.0
	var rag := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.035, 0.09, 0.02)
	rb.material = cloth
	rag.mesh = rb
	rag.name = "Rag"
	rag.position = Vector3(0.012, 0.215, 0.0)
	rag.rotation.z = -0.5
	root.add_child(rag)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## Flames: orange tongues licking upwards. `size` scales them (a rag = small, a fuel pool = big).
static func make_flames(amount: int, size: float, soft: Texture2D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Flames"
	p.amount = amount
	p.lifetime = 0.6
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.6 * size
	p.initial_velocity_max = 1.4 * size
	p.gravity = Vector3(0.2, 1.5 * size, 0.1)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.05 * size
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(0.3, 1.0))
	grow.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = grow
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var q := QuadMesh.new()
	q.size = Vector2(0.25, 0.35) * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.62, 0.18, 0.95))
	ramp.set_color(1, Color(0.9, 0.25, 0.05, 0.0))
	p.color_ramp = ramp
	ImpactEffects.web_fallback(p) # (particle colours draw black in browsers – see CLAUDE.md)
	return p


## Thick black smoke of burning petrol.
static func make_black_smoke(amount: int, size: float, soft: Texture2D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.amount = amount
	p.lifetime = 3.5
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0.45, 0.6, 0.2)
	p.damping_min = 0.2
	p.damping_max = 0.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3 * size
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	p.scale_amount_min = 1.2 * size
	p.scale_amount_max = 2.2 * size
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.08, 0.07, 0.06, 0.6))
	ramp.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	p.color_ramp = ramp
	ImpactEffects.web_fallback(p)
	return p


func _make_fire() -> Dictionary:
	var soft: Texture2D = ImpactEffects.make_soft_texture()
	var root := Node3D.new()
	root.name = "Fire"
	root.visible = false
	var flames := make_flames(28, 2.2, soft)
	flames.emitting = false
	root.add_child(flames)
	var smoke := make_black_smoke(12, 1.0, soft)
	smoke.emitting = false
	smoke.position.y = 0.6
	root.add_child(smoke)
	var audio := AudioStreamPlayer3D.new()
	audio.bus = &"SFX"
	audio.unit_size = 8.0
	root.add_child(audio)
	return {"node": root, "flames": flames, "smoke": smoke, "audio": audio, "until": 0.0, "age": 0.0}


func _make_glass_burst() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 14
	p.lifetime = 0.6
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -9.8, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	p.angle_max = 360.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.3, 0.45, 0.3, 0.9))
	ramp.set_color(1, Color(0.3, 0.45, 0.3, 0.0))
	p.color_ramp = ramp
	ImpactEffects.web_fallback(p)
	return p
