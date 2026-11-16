class_name TrackAnimator
extends Node
## T6: makes a tank's tracks run and its wheels turn (the "TrackAnimator" node of the tank).
##
## Picture only, and it knows nothing about how the tank is driven: it does not look at the
## tank's AI, its route or its speed setting. Every physics step it only looks at where the
## hull is NOW compared with one step ago, and works out from that how far each track must
## have run over the ground:
##     forward  = how far the hull moved towards its nose (backwards = negative)
##     turn     = how far the hull turned (to the left = positive) × half the track gauge
##     left track  = forward - turn
##     right track = forward + turn
## Driving straight both tracks run alike; in a bend the inner one runs slower; turning on
## the spot they run opposite ways; reversing they run backwards; standing still they stop.
## Because it is worked out from the real movement, the links on the ground stay exactly where
## they are on the snow – the track never "skates".
##
## Nothing is synced: every computer does this by itself from where it sees the tank (like the
## TankTracks in the snow), so it also works for co-op guests.
##
## What it moves – no new meshes, no extra draw calls:
##   - the two track belts: their link picture is slid along the belt (tank_track.gdshader),
##   - the wheels: each side's wheels are turned around their axles on the graphics card
##     (tank_wheels.gdshader; the axles were written into the model by tools/import_weapons.py).
## Per tank and physics step that is four numbers sent to four materials, and only while the
## tank moves.

const TRACK_SHADER: Shader = preload("res://resources/shaders/tank_track.gdshader")
const WHEEL_SHADER: Shader = preload("res://resources/shaders/tank_wheels.gdshader")
const LEFT: int = 0
const RIGHT: int = 1

@export var model_path: NodePath = ^"../Model" ## The tank's model (the glTF scene with the track and chassis meshes).

@export_group("Tank measures (T-26)")
@export var half_track_gauge: float = 1.03 ## Metres from the tank's centre line to the middle of a track.
@export var metres_per_repeat: float = 0.81 ## Belt length covered by one repeat of the link picture.
@export var belt_repeats: float = 12.0 ## Repeats of the link picture around the whole belt.
@export var sprocket_radius: float = 0.322 ## Drive sprocket and idler (m).
@export var road_wheel_radius: float = 0.161
@export var roller_radius: float = 0.142 ## Return rollers under the top run.

@export_group("Keeping it believable")
@export var max_track_speed: float = 4.0 ## m/s: a track never runs faster than this (the T-26 drives 2 m/s; this only tames glitches).
@export var dead_zone_speed: float = 0.02 ## m/s: slower than this counts as standing – the tracks stop dead.
@export var teleport_distance: float = 2.0 ## Moved further than this in ONE step = it was put there (spawn, tests): no track movement.

@export_group("Look")
@export_range(0.0, 1.0) var snow_amount: float = 0.6 ## Packed snow on the links (0 = bare steel).
@export_range(0.0, 1.0) var dirt_amount: float = 0.45 ## Frozen dirt on the links.

## Whose movement is read: the tank. Normally the parent node; set it before the node enters
## the tree to use something else (ShaderWarmup does).
var body: Node3D = null
## The model whose tracks and wheels are animated (normally `model_path`).
var model: Node3D = null

var left_speed: float = 0.0 ## m/s the left track runs now (forwards = +). Read-only.
var right_speed: float = 0.0
var left_travel: float = 0.0 ## Metres the left track has run since the tank appeared. Read-only.
var right_travel: float = 0.0

var _track_materials: Array[ShaderMaterial] = [null, null] # LEFT, RIGHT
var _wheel_materials: Array[ShaderMaterial] = [null, null]
var _previous: Transform3D
var _has_previous: bool = false

static var _grime: ImageTexture = null # shared by every tank


func _ready() -> void:
	if body == null:
		body = get_parent() as Node3D
	if model == null:
		model = get_node_or_null(model_path) as Node3D
	if body == null or model == null:
		push_warning("TrackAnimator: no tank / no model – nothing to animate")
		set_physics_process(false)
		return
	_setup_materials()


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	if body.is_in_group(&"tank_wrecks"):
		left_speed = 0.0
		right_speed = 0.0
		set_physics_process(false) # a wreck never drives again
		return
	var now: Transform3D = body.global_transform
	if not _has_previous:
		_previous = now # (the tank is put on its route only after this node is ready)
		_has_previous = true
		return
	var track_basis: Basis = now.basis.orthonormalized()
	var moved: Vector3 = now.origin - _previous.origin
	# Where the nose pointed one step ago, seen from the hull as it stands now:
	# to the right of straight ahead (+x) = the hull has turned left since.
	var old_nose: Vector3 = track_basis.transposed() * (-_previous.basis.z)
	_previous = now
	if moved.length_squared() > teleport_distance * teleport_distance:
		left_speed = 0.0
		right_speed = 0.0
		return
	var forward: float = moved.dot(-track_basis.z)
	var turn: float = atan2(old_nose.x, -old_nose.z) * half_track_gauge
	_run(forward - turn, forward + turn, delta)


## True while at least one track is running.
func is_moving() -> bool:
	return left_speed != 0.0 or right_speed != 0.0


## The material of one track belt (tests, tuning). `side`: TrackAnimator.LEFT or RIGHT.
func track_material(side: int) -> ShaderMaterial:
	return _track_materials[side]


## The material of one side's wheels.
func wheel_material(side: int) -> ShaderMaterial:
	return _wheel_materials[side]


## How many repeats of the link picture a track has been slid (0 … belt_repeats).
func scroll_of(side: int) -> float:
	return fposmod((left_travel if side == LEFT else right_travel) / metres_per_repeat, belt_repeats)


## The two tracks ran `left` / `right` metres over the ground in the last `delta` seconds.
func _run(left: float, right: float, delta: float) -> void:
	left = _believable(left, delta)
	right = _believable(right, delta)
	left_speed = left / delta
	right_speed = right / delta
	if left != 0.0:
		left_travel += left
		_show(LEFT, left_travel)
	if right != 0.0:
		right_travel += right
		_show(RIGHT, right_travel)


## Too slow to see = standing (0); never faster than `max_track_speed`.
func _believable(metres: float, delta: float) -> float:
	if absf(metres) < dead_zone_speed * delta:
		return 0.0
	var limit: float = max_track_speed * delta
	return clampf(metres, -limit, limit)


## Sends one side's numbers to its two materials. The numbers are wrapped (a full turn of the
## belt / of a wheel looks the same as none), so they stay small and exact however far it drives.
func _show(side: int, travel: float) -> void:
	var track: ShaderMaterial = _track_materials[side]
	if track:
		track.set_shader_parameter(&"scroll", fposmod(travel / metres_per_repeat, belt_repeats))
	var wheels: ShaderMaterial = _wheel_materials[side]
	if wheels:
		wheels.set_shader_parameter(&"wheel_angles", Vector3(
				fposmod(travel / sprocket_radius, TAU),
				fposmod(travel / road_wheel_radius, TAU),
				fposmod(travel / roller_radius, TAU)))


## Gives the model's two track belts and two chassis meshes their own materials (once).
## Which mesh is the left one is read from where it sits, not from its name.
func _setup_materials() -> void:
	var to_body: Transform3D = body.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var part_name: String = String(part.name).to_lower()
		var is_track: bool = part_name.begins_with("track")
		if not is_track and not part_name.begins_with("chassis"):
			continue
		var centre: Vector3 = (to_body * part.global_transform) * part.get_aabb().get_center()
		var side: int = LEFT if centre.x < 0.0 else RIGHT # (the nose points to -z, so -x is the left)
		var material := ShaderMaterial.new()
		material.shader = TRACK_SHADER if is_track else WHEEL_SHADER
		var original := part.get_active_material(0) as BaseMaterial3D
		if original:
			material.set_shader_parameter(&"albedo_tex", original.albedo_texture)
			material.set_shader_parameter(&"roughness", original.roughness)
		if is_track:
			material.set_shader_parameter(&"grime_tex", grime_texture())
			material.set_shader_parameter(&"belt_repeats", belt_repeats)
			material.set_shader_parameter(&"snow_amount", snow_amount)
			material.set_shader_parameter(&"dirt_amount", dirt_amount)
			# Every tank (and each of its sides) wears its snow in a different place. From the
			# tank's name, so all computers see the same.
			var shift: float = float(absi(hash(body.name)) % 997) / 997.0 + 0.41 * side
			material.set_shader_parameter(&"grime_shift", fposmod(shift, 1.0))
			_track_materials[side] = material
		else:
			_wheel_materials[side] = material
		part.set_surface_override_material(0, material)
	for i in 2:
		if _track_materials[i] == null or _wheel_materials[i] == null:
			push_warning("TrackAnimator: a track or chassis mesh is missing from the model")


# ------------------------------------------------------------------ snow and dirt picture
const GRIME_W: int = 16 # pixels across the belt
const GRIME_H: int = 256 # pixels around the belt (it wraps: the last row meets the first)
const LATTICE_W: int = 8
const LATTICE_H: int = 64

## The snow-and-dirt picture for the track belts: R = snow patches, G = frozen dirt,
## B = snow patches grown a little (used in the gaps between the links, where snow packs first).
## It goes once around the whole belt. Made once in code (a few ms) and shared by all tanks:
## random numbers on a coarse grid, blended smoothly, at two sizes on top of each other.
static func grime_texture() -> ImageTexture:
	if _grime != null:
		return _grime
	var rng := RandomNumberGenerator.new()
	rng.seed = 1940 # always the same picture
	var lattice := PackedFloat32Array()
	lattice.resize(LATTICE_W * LATTICE_H * 4) # 4 numbers per grid point: big snow, fine snow, big dirt, fine dirt
	for i in lattice.size():
		lattice[i] = rng.randf()
	var img := Image.create(GRIME_W, GRIME_H, false, Image.FORMAT_RGBA8)
	for y in GRIME_H:
		var v: float = (y + 0.5) / GRIME_H
		for x in GRIME_W:
			var u: float = (x + 0.5) / GRIME_W
			var snow: float = _soft_noise(lattice, 0, u, v) * 0.6 + _soft_noise(lattice, 1, u * 2.0 + 0.37, v * 3.0) * 0.4
			var dirt: float = _soft_noise(lattice, 2, u, v) * 0.5 + _soft_noise(lattice, 3, u * 2.0 + 0.37, v * 3.0) * 0.5
			img.set_pixel(x, y, Color(
					smoothstep(0.56, 0.74, snow),
					smoothstep(0.45, 0.80, dirt),
					smoothstep(0.56, 0.74, snow + 0.16)))
	img.generate_mipmaps()
	_grime = ImageTexture.create_from_image(img)
	return _grime


## One of the four number sets of the grid at (u, v), blended between the four nearest grid
## points. The grid repeats in both directions (u and v may be any number).
static func _soft_noise(lattice: PackedFloat32Array, channel: int, u: float, v: float) -> float:
	var x: float = u * LATTICE_W - 0.5
	var y: float = v * LATTICE_H - 0.5
	var x0: int = floori(x)
	var y0: int = floori(y)
	var fx: float = x - x0
	var fy: float = y - y0
	var xa: int = posmod(x0, LATTICE_W)
	var xb: int = posmod(x0 + 1, LATTICE_W)
	var row_a: int = posmod(y0, LATTICE_H) * LATTICE_W
	var row_b: int = posmod(y0 + 1, LATTICE_H) * LATTICE_W
	var top: float = lerpf(lattice[(row_a + xa) * 4 + channel], lattice[(row_a + xb) * 4 + channel], fx)
	var bottom: float = lerpf(lattice[(row_b + xa) * 4 + channel], lattice[(row_b + xb) * 4 + channel], fx)
	return lerpf(top, bottom, fy)
