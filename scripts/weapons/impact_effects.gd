class_name ImpactEffects
extends Node3D
## Bullet holes, impact sprays, gun smoke, muzzle flashes of other players and the
## crack of bullets flying past you.
##
## Everything is "pooled": a fixed number of each effect is created once and then
## reused in turn. Creating and deleting nodes for every shot would be slow,
## especially in a web browser. (Godot's Decal node is not available in the
## Compatibility renderer, so holes are small flat round quads instead.)

@export var max_holes: int = 64
@export var sprays_per_surface: int = 8
@export var max_smoke: int = 16
@export var max_flashes: int = 12
@export var max_cracks: int = 4
@export var hole_size: float = 0.07
@export var flash_duration: float = 0.05

const HOLE_COLORS: Dictionary = {
	"snow": Color(0.32, 0.36, 0.44),
	"wood": Color(0.09, 0.06, 0.04),
}
const CRACK_SOUNDS: Array[String] = ["res://assets/audio/bullet_crack_1.wav", "res://assets/audio/bullet_crack_2.wav"]

var _holes: Array[MeshInstance3D] = []
var _hole_materials: Dictionary = {}
var _next_hole: int = 0
var _sprays: Dictionary = {} # surface -> Array[CPUParticles3D]
var _next_spray: Dictionary = {}
var _smoke: Array[CPUParticles3D] = []
var _next_smoke: int = 0
var _flashes: Array[MeshInstance3D] = []
var _next_flash: int = 0
var _cracks: Array[AudioStreamPlayer3D] = []
var _next_crack: int = 0
var _crack_streams: Array[AudioStream] = []
var _round_tex: GradientTexture2D
var cracks_played: int = 0 ## How many near-miss cracks were heard (used by the tests).
var _soft_tex: GradientTexture2D
var _ricochets: Array[AudioStreamPlayer3D] = []
var _next_ricochet: int = 0


func _ready() -> void:
	add_to_group("impact_effects")
	_round_tex = _make_round_texture()
	_soft_tex = make_soft_texture()
	for surface: String in HOLE_COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = HOLE_COLORS[surface]
		m.albedo_texture = _round_tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.roughness = 1.0
		_hole_materials[surface] = m
	var quad := QuadMesh.new()
	quad.size = Vector2(hole_size, hole_size)
	for i in max_holes:
		var hole := MeshInstance3D.new()
		hole.mesh = quad
		hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hole.visible = false
		add_child(hole)
		_holes.append(hole)
	for surface in ["snow", "wood", "cloth", "metal"]:
		var pool: Array[CPUParticles3D] = []
		for i in sprays_per_surface:
			var p := _make_spray(surface)
			add_child(p)
			pool.append(p)
		_sprays[surface] = pool
		_next_spray[surface] = 0
	for i in max_smoke:
		var s := make_smoke_emitter(_soft_tex)
		add_child(s)
		_smoke.append(s)
	var flash_mat := _make_flash_material(_round_tex)
	for i in max_flashes:
		var f := MeshInstance3D.new()
		var fq := QuadMesh.new()
		fq.size = Vector2(0.35, 0.35)
		fq.material = flash_mat
		f.mesh = fq
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.visible = false
		add_child(f)
		_flashes.append(f)
	for path in CRACK_SOUNDS:
		_crack_streams.append(load(path))
	for i in 3: # bullets glancing off a tank (only if a "ricochet…" recording exists)
		var r := AudioStreamPlayer3D.new()
		r.bus = &"SFX"
		r.unit_size = 10.0
		add_child(r)
		_ricochets.append(r)
	for i in max_cracks:
		var a := AudioStreamPlayer3D.new()
		a.bus = &"SFX"
		a.unit_size = 4.0
		a.volume_db = -3.0
		add_child(a)
		_cracks.append(a)


## Show a bullet hole and a spray (snow powder, wood splinters, cloth dust) where a bullet hit.
func spawn_impact(pos: Vector3, normal: Vector3, surface: String, attach_to: Node3D = null) -> void:
	if not _sprays.has(surface):
		surface = "snow"
	var up: Vector3 = Vector3.RIGHT if absf(normal.y) > 0.99 else Vector3.UP
	_spawn_spray(surface, pos, normal, up)
	if surface == "metal":
		_play_ricochet(pos)
	if not HOLE_COLORS.has(surface):
		return # no bullet holes on moving soldiers
	var facing := Basis.looking_at(-normal, up) # quad's front (+Z) points along the normal

	var hole := _holes[_next_hole]
	_next_hole = (_next_hole + 1) % _holes.size()
	var parent: Node = attach_to if attach_to else self # stick to moving targets
	if hole.get_parent() != parent:
		hole.get_parent().remove_child(hole)
		parent.add_child(hole)
	hole.global_transform = Transform3D(facing.rotated(normal, randf() * TAU), pos + normal * 0.01)
	hole.material_override = _hole_materials[surface]
	hole.visible = true


func _spawn_spray(surface: String, pos: Vector3, normal: Vector3, up: Vector3) -> void:
	var pool: Array[CPUParticles3D] = _sprays[surface]
	var i: int = _next_spray[surface]
	_next_spray[surface] = (i + 1) % pool.size()
	var p := pool[i]
	p.global_transform = Transform3D(Basis.looking_at(-normal, up) * Basis(Vector3.RIGHT, PI / 2.0), pos)
	p.visible = true
	p.restart()


## A puff of gun smoke drifting away from a muzzle. `direction` = where the barrel points.
## `faint` = your own gun: a thinner puff that is blown away quicker, so you can still aim.
func spawn_smoke(pos: Vector3, direction: Vector3, big: bool = false, faint: bool = false) -> void:
	var s := _smoke[_next_smoke]
	_next_smoke = (_next_smoke + 1) % _smoke.size()
	s.global_position = pos
	s.direction = direction.normalized()
	s.amount = 10 if big else (4 if faint else 6)
	s.color = Color(1, 1, 1, 0.35 if faint else 1.0)
	var m := (s.mesh as PrimitiveMesh).material as StandardMaterial3D
	m.albedo_color.a = 0.1 if faint else 0.3 # thin: it must never hide what you aim at
	s.visible = true
	s.initial_velocity_min = 2.5 if faint else 1.0
	s.initial_velocity_max = 4.0 if faint else 2.5
	s.restart()


## The sharp crack of a bullet passing close to this computer's player.
func play_crack(pos: Vector3) -> void:
	var a := _cracks[_next_crack]
	_next_crack = (_next_crack + 1) % _cracks.size()
	a.stream = _crack_streams[randi() % _crack_streams.size()]
	a.global_position = pos
	a.pitch_scale = randf_range(0.9, 1.15)
	a.play()
	cracks_played += 1


## Hide every spray and smoke puff at once (after the shader warm-up showed them).
func hide_all() -> void:
	for pool in _sprays.values():
		for p: CPUParticles3D in pool:
			p.visible = false
	for s in _smoke:
		s.visible = false


## Surface type from the "surface" metadata of the hit object (or its parents).
static func surface_of(node: Node, normal: Vector3) -> String:
	var surface: String = "snow"
	var n: Node = node
	for i in 3:
		if n and n.has_meta("surface"):
			surface = n.get_meta("surface")
			break
		n = n.get_parent() if n else null
	if surface == "earthwork": # trench: snow on top, log walls on the sides
		surface = "snow" if normal.y > 0.7 else "wood"
	return surface


## A bullet glancing off armour: a recording named "ricochet…" in assets/audio/recorded/, if any.
func _play_ricochet(pos: Vector3) -> void:
	var stream: AudioStream = RecordedSounds.pick("ricochet")
	if stream == null:
		return
	var r := _ricochets[_next_ricochet]
	_next_ricochet = (_next_ricochet + 1) % _ricochets.size()
	r.stream = stream
	r.pitch_scale = randf_range(0.9, 1.15)
	r.global_position = pos
	r.play()


## A short flash at another player's muzzle.
func spawn_flash(pos: Vector3) -> void:
	var f := _flashes[_next_flash]
	_next_flash = (_next_flash + 1) % _flashes.size()
	f.global_position = pos
	f.visible = true
	get_tree().create_timer(flash_duration).timeout.connect(func() -> void: f.visible = false)


## Particles for one kind of hit. Snow: a burst of powder that hangs in the air a moment.
## Wood: small dark splinters that fall quickly. Cloth: a little dust.
## Metal (tank armour): a few bright sparks that fly off and drop.
func _make_spray(surface: String) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = Vector3.UP # turned to point along the surface normal
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _soft_tex if surface != "wood" else _round_tex
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fade := Gradient.new()
	match surface:
		"snow":
			p.amount = 24
			p.lifetime = 1.1
			p.spread = 40.0
			p.initial_velocity_min = 1.5
			p.initial_velocity_max = 4.5
			p.gravity = Vector3(0.3, -2.5, 0.1) # light powder, carried a little by the wind
			p.damping_min = 3.0
			p.damping_max = 5.0
			q.size = Vector2(0.1, 0.1)
			p.scale_amount_min = 1.0
			p.scale_amount_max = 3.0
			# A little darker and bluer than sunlit snow, or you couldn't see it against the ground.
			fade.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
			fade.colors = PackedColorArray([Color(0.72, 0.77, 0.86, 1.0), Color(0.78, 0.82, 0.9, 0.75), Color(0.84, 0.88, 0.94, 0.0)])
		"wood":
			p.amount = 12
			p.lifetime = 0.8
			p.spread = 30.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 5.0
			p.gravity = Vector3(0, -9.8, 0)
			q.size = Vector2(0.025, 0.06)
			m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED # splinters tumble, not face you
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			p.angle_min = 0.0
			p.angle_max = 360.0
			p.angular_velocity_min = -720.0
			p.angular_velocity_max = 720.0
			fade.set_color(0, Color(0.45, 0.32, 0.2, 1.0))
			fade.set_color(1, Color(0.35, 0.25, 0.15, 0.6))
		"metal":
			p.amount = 10
			p.lifetime = 0.35
			p.spread = 55.0
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 9.0
			p.gravity = Vector3(0, -9.8, 0)
			q.size = Vector2(0.03, 0.03)
			p.scale_amount_min = 0.7
			p.scale_amount_max = 1.4
			m.albedo_texture = _round_tex
			fade.set_color(0, Color(1.0, 0.78, 0.35, 1.0))
			fade.set_color(1, Color(1.0, 0.5, 0.15, 0.0))
		_: # cloth
			p.amount = 10
			p.lifetime = 0.6
			p.spread = 50.0
			p.initial_velocity_min = 0.5
			p.initial_velocity_max = 1.5
			p.gravity = Vector3(0, -1.0, 0)
			p.damping_min = 2.0
			p.damping_max = 3.0
			q.size = Vector2(0.06, 0.06)
			p.scale_amount_min = 0.8
			p.scale_amount_max = 1.8
			fade.set_color(0, Color(0.42, 0.4, 0.34, 0.8))
			fade.set_color(1, Color(0.42, 0.4, 0.34, 0.0))
	p.color_ramp = fade
	web_fallback(p)
	return p


## WORKAROUND: particles that take their colour from the particle system ("vertex colour",
## colour ramp) are drawn BLACK in browsers and on some graphics cards (Windows computers that
## run the Compatibility renderer through ANGLE/Direct3D). So every particle effect gets ONE
## fixed colour in its material instead, and the particles shrink away at the end instead of
## fading out. Call this after the particle system and its mesh material are set up.
static func web_fallback(p: CPUParticles3D, _force: bool = true) -> void:
	if p.color_ramp == null:
		return
	var m := (p.mesh as PrimitiveMesh).material as StandardMaterial3D
	m.vertex_color_use_as_albedo = false
	m.albedo_color = p.color_ramp.sample(0.1)
	p.color_ramp = null
	var old: Curve = p.scale_amount_curve
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, old.sample(0.0) if old else 1.0))
	shrink.add_point(Vector2(0.6, old.sample(0.6) if old else 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink


## Gun smoke: soft grey puffs that grow, rise slowly and drift with the wind.
## Static so the Maxim can make its own long-lasting emitter with the same look.
static func make_smoke_emitter(tex: Texture2D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 6
	p.lifetime = 1.8
	p.explosiveness = 0.9
	p.local_coords = false
	p.direction = Vector3.FORWARD
	p.spread = 12.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.damping_min = 2.5
	p.damping_max = 3.5
	p.gravity = Vector3(0.45, 0.25, 0.2) # rises a little and drifts with the wind
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(0.86, 0.87, 0.89, 0.3)) # light grey-white against the snow
	fade.set_color(1, Color(0.9, 0.91, 0.93, 0.0))
	p.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	web_fallback(p)
	return p


## A very soft round blob (smoke, powder, breath).
static func make_soft_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	return t


## A soft round white dot generated in code (no image file needed).
static func _make_round_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 1))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	return t


static func _make_flash_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.78, 0.35)
	m.albedo_texture = tex
	return m
