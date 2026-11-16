class_name TankTracks
extends Node3D
## V10b: the tracks a tank leaves in the snow (the "TankTracks" node of the Game).
##
## Picture only. Every computer makes the tracks by itself from where it sees the tanks
## (the "tanks" group), so nothing is synced and the tank script knows nothing about them.
##
## All track pieces are ONE MultiMesh: many copies of one small flat mesh, drawn in a single
## draw call. It is a pool of `pool_size` strips, each `strip_length` m long with the two ruts
## painted on it. A tank lays a new strip every `strip_length` m it drives; when the pool is
## full the oldest strip is used again. The strips lie on the ground (four height samples each),
## a few centimetres up so they don't flicker against the snow.
## A new day: all tracks are cleared behind the black day screen.

@export var pool_size: int = 640 ## Strips in the pool (640 × 1.5 m ≈ four tanks driving the whole field).
@export var strip_length: float = 1.5 ## A new strip every this many metres.
@export var strip_width: float = 2.6 ## Whole width of a strip (both ruts and the snow between).
@export var rut_centre_m: float = 1.02 ## Each rut's middle is this far from the tank's centre line.
@export var rut_width_m: float = 0.34
@export var lift: float = 0.05 ## Metres above the ground.
@export var color: Color = Color(0.52, 0.57, 0.68) ## Pressed snow in the ruts (it is lit like the snow around it).
@export var strength: float = 0.8 ## 0 = invisible … 1 = the ruts hide the snow under them completely.

var strips_laid: int = 0 ## Since the last clear (tests).

var _mm: MultiMesh
var _placed: Array[Transform3D] = [] # where each strip of the pool lies (a headless build can't ask the MultiMesh)
var _next: int = 0
var _last: Dictionary = {} # tank instance id -> where its last strip ended (Vector3)
var _check: float = 0.0
var _was_black: bool = false


func _ready() -> void:
	add_to_group("tank_tracks")
	var plane := PlaneMesh.new() # flat, facing up; UV.y runs along the strip
	plane.size = Vector2(strip_width, strip_length)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = make_texture(strip_width, rut_centre_m, rut_width_m)
	m.albedo_color = Color(color, strength)
	m.roughness = 0.9
	m.metallic_specular = 0.2
	m.render_priority = -1 # drawn before smoke, scorch marks and other see-through things
	plane.material = m
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = plane
	_mm.instance_count = pool_size
	_placed.resize(pool_size)
	_mm.visible_instance_count = 0
	# The strips move around: a fixed box (the whole map) saves working it out again each time.
	_mm.custom_aabb = AABB(Vector3(-200, -30, -200), Vector3(400, 80, 400))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Strips"
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	mmi.top_level = true # strips are placed in world coordinates
	mmi.global_transform = Transform3D.IDENTITY


func _process(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Node3D
		if tank == null:
			continue
		var id: int = tank.get_instance_id()
		var pos: Vector3 = tank.global_position
		if not _last.has(id):
			_last[id] = pos
			continue
		var from: Vector3 = _last[id]
		var driven: float = Vector2(pos.x - from.x, pos.z - from.z).length()
		if driven < strip_length:
			continue
		if driven <= strip_length * 3.0: # (more = it was put somewhere else at once: no track)
			_lay(from, pos)
		_last[id] = pos
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	for id in _last.keys():
		if not is_instance_id_valid(id):
			_last.erase(id)
	var screen: Node = get_tree().get_first_node_in_group("day_screen")
	var black: bool = screen != null and screen.has_method("is_black") and screen.is_black()
	if black and not _was_black:
		clear()
	_was_black = black


## Removes all tracks.
func clear() -> void:
	_next = 0
	strips_laid = 0
	_mm.visible_instance_count = 0
	_last.clear()


## How many strips are shown now.
func visible_strips() -> int:
	return _mm.visible_instance_count


## Where strip `i` of the pool lies (tests).
func strip_transform(i: int) -> Transform3D:
	return _placed[i]


## One strip on the ground from `from` to `to`.
func _lay(from: Vector3, to: Vector3) -> void:
	var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
	var mid: Vector3 = (from + to) * 0.5
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length: float = flat.length()
	var dir: Vector3 = flat / length
	var right: Vector3 = dir.cross(Vector3.UP)
	var half_l: float = length * 0.5
	# The ground at the strip's front, back and under the two ruts.
	var h_front: float = _ground(terrain, mid + dir * half_l, to.y)
	var h_back: float = _ground(terrain, mid - dir * half_l, from.y)
	var h_left: float = _ground(terrain, mid - right * rut_centre_m, mid.y)
	var h_right: float = _ground(terrain, mid + right * rut_centre_m, mid.y)
	var forward3: Vector3 = Vector3(dir.x * length, h_front - h_back, dir.z * length).normalized()
	var right3: Vector3 = Vector3(right.x * rut_centre_m * 2.0, h_right - h_left, right.z * rut_centre_m * 2.0).normalized()
	var up: Vector3 = right3.cross(forward3).normalized()
	right3 = forward3.cross(up).normalized()
	# Stretched a little along its length so it reaches exactly from `from` to `to` (no gaps).
	var strip_basis := Basis(right3, up, -forward3 * (length / strip_length))
	var y: float = (h_front + h_back + h_left + h_right) / 4.0 + lift
	_placed[_next] = Transform3D(strip_basis, Vector3(mid.x, y, mid.z))
	_mm.set_instance_transform(_next, _placed[_next])
	_next = (_next + 1) % pool_size
	strips_laid += 1
	_mm.visible_instance_count = mini(strips_laid, pool_size)


func _ground(terrain: TerrainGenerator, p: Vector3, fallback: float) -> float:
	return terrain.get_height(p.x, p.z) if terrain else fallback


## The picture on a strip: two ruts with the cross-bars of the track links, see-through
## everywhere else. White/grey only – the material's colour tints it.
static func make_texture(width_m: float, rut_centre: float, rut_width: float) -> ImageTexture:
	const W: int = 128
	const H: int = 64
	const BARS: float = 12.0 # track links per strip
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1939
	for y in H:
		var bar: float = 0.5 + 0.5 * sin((y + 0.5) / H * TAU * BARS)
		for x in W:
			var m: float = ((x + 0.5) / W - 0.5) * width_m # metres from the centre line
			var d: float = absf(absf(m) - rut_centre) # metres from the middle of the nearest rut
			var a: float = 1.0 - smoothstep(rut_width * 0.5 - 0.05, rut_width * 0.5 + 0.05, d)
			var shade: float = lerpf(0.72, 1.0, bar) * rng.randf_range(0.93, 1.0)
			img.set_pixel(x, y, Color(shade, shade, shade, a * lerpf(1.0, 0.7, bar)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
