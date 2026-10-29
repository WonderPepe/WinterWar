class_name ImpactEffects
extends Node3D
## Bullet holes, impact puffs and muzzle flashes of other players.
##
## Everything is "pooled": a fixed number of holes/puffs is created once and then
## reused in turn. Creating and deleting nodes for every shot would be slow,
## especially in a web browser. (Godot's Decal node is not available in the
## Compatibility renderer, so holes are small flat round quads instead.)

@export var max_holes: int = 64
@export var max_puffs: int = 10
@export var max_flashes: int = 4
@export var hole_size: float = 0.07
@export var flash_duration: float = 0.05

const SURFACE_COLORS: Dictionary = {
	"snow": [Color(0.32, 0.36, 0.44), Color(0.95, 0.97, 1.0)], # [hole colour, puff colour]
	"wood": [Color(0.09, 0.06, 0.04), Color(0.42, 0.3, 0.18)],
}

var _holes: Array[MeshInstance3D] = []
var _hole_materials: Dictionary = {}
var _next_hole: int = 0
var _puffs: Array[CPUParticles3D] = []
var _next_puff: int = 0
var _flashes: Array[MeshInstance3D] = []
var _next_flash: int = 0


func _ready() -> void:
	add_to_group("impact_effects")
	var round_tex := _make_round_texture()
	for surface: String in SURFACE_COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = SURFACE_COLORS[surface][0]
		m.albedo_texture = round_tex
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
	for i in max_puffs:
		var puff := _make_puff()
		add_child(puff)
		_puffs.append(puff)
	var flash_mat := _make_flash_material(round_tex)
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


## Show a bullet hole and a puff where a bullet hit.
func spawn_impact(pos: Vector3, normal: Vector3, surface: String, attach_to: Node3D = null) -> void:
	if not SURFACE_COLORS.has(surface):
		surface = "snow"
	var up: Vector3 = Vector3.RIGHT if absf(normal.y) > 0.99 else Vector3.UP
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

	var puff := _puffs[_next_puff]
	_next_puff = (_next_puff + 1) % _puffs.size()
	puff.global_transform = Transform3D(Basis.looking_at(-normal, up) * Basis(Vector3.RIGHT, PI / 2.0), pos)
	puff.color = SURFACE_COLORS[surface][1]
	puff.restart()


## A short flash at another player's muzzle.
func spawn_flash(pos: Vector3) -> void:
	var f := _flashes[_next_flash]
	_next_flash = (_next_flash + 1) % _flashes.size()
	f.global_position = pos
	f.visible = true
	get_tree().create_timer(flash_duration).timeout.connect(func() -> void: f.visible = false)


func _make_puff() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = Vector3.UP # turned to point along the surface normal
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -5, 0)
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.0
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


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
