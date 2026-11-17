class_name GrenadeWarning
extends Control
## GR1: a grenade icon over every live grenade close to you (owner: icon only, no text).
## A grenade you can see: the icon floats just above it. One behind you or off the screen: the
## icon sits at the edge of the screen in its direction, with a small arrow pointing to it.
## The closer the grenade, the bigger, redder and faster-pulsing the icon.
## GR2: one close enough to pick up (and you are free to) gets a small [F] key next to its icon.
## Only reads what the GrenadeManager shows on this computer (UI only reads state).

@export var warn_radius_m: float = 10.0 ## Grenades closer than this get an icon.
@export var icon_size: float = 30.0 ## Pixels (at 1080 lines; scales with the screen).
@export var edge_margin: float = 70.0 ## Off-screen icons stay this far inside the screen edge.

var _player: Player
var _shown: bool = false
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_player(p: Player) -> void:
	_player = p


func _process(delta: float) -> void:
	_time += delta
	var any: bool = not _near_grenades().is_empty()
	if any or _shown:
		queue_redraw()
	_shown = any


## [{pos, d}] of the live grenades within `warn_radius_m` of the local player.
func _near_grenades() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _player == null or not is_instance_valid(_player) or _player.is_dead:
		return out
	var manager := get_tree().get_first_node_in_group("grenades") as GrenadeManager
	if manager == null:
		return out
	for g in manager.get_visible_grenades():
		var d: float = _player.global_position.distance_to(g.pos)
		if d <= warn_radius_m:
			out.append({"pos": g.pos, "d": d})
	return out


## GR2: the index (in `_near_grenades()`) of the grenade F would pick up now, or -1.
## The same rule as the host's (GrenadeGrabHandler.try_grab), on this computer's picture.
func grabbable_index() -> int:
	if _player == null or not is_instance_valid(_player):
		return -1
	var grab: GrenadeGrabHandler = _player.grab
	if grab == null or grab.is_busy() or _player.is_dead or _player.is_climbing or _player.is_bandaging \
			or _player.get_mounted_gun() != null or not _player.molotov.can_put_away():
		return -1
	var near: Array[Dictionary] = _near_grenades()
	var best: int = -1
	var best_d: float = grab.grab_radius_m
	for i in near.size():
		for pt in grab.grab_points():
			var d: float = pt.distance_to(near[i].pos)
			if d <= best_d:
				best_d = d
				best = i
	return best


func _draw() -> void:
	var near: Array[Dictionary] = _near_grenades()
	if near.is_empty():
		return
	var cam: Camera3D = _player.camera
	var screen: Vector2 = size
	if screen.x < 16.0 or screen.y < 16.0 or not cam.is_inside_tree():
		return
	var px: float = icon_size * screen.y / 1080.0
	var grab_i: int = grabbable_index()
	for gi in near.size():
		var g: Dictionary = near[gi]
		var key: bool = gi == grab_i
		var pos: Vector3 = g.pos
		var urgency: float = clampf(1.0 - float(g.d) / warn_radius_m, 0.0, 1.0)
		var pulse: float = 0.5 + 0.5 * sin(_time * lerpf(6.0, 16.0, urgency))
		var s: float = px * lerpf(0.9, 1.35, urgency) * (1.0 + 0.08 * pulse)
		var col: Color = Color(1.0, 0.85, 0.35).lerp(Color(1.0, 0.25, 0.15), urgency)
		var inside := Rect2(Vector2.ONE * edge_margin, screen - Vector2.ONE * edge_margin * 2.0)
		var at := Vector2(-1.0, -1.0)
		if not cam.is_position_behind(pos + Vector3.UP * 0.25):
			at = cam.unproject_position(pos + Vector3.UP * 0.25)
		if inside.has_point(at):
			_draw_icon(at - Vector2(0.0, s * 1.7), s, col)
			if key:
				_draw_key(at - Vector2(-s * 1.15, s * 1.7), s)
			continue
		# Off the screen: at the edge, in its direction (0 = ahead, +90° = right, 180° = behind).
		var to: Vector3 = (pos - _player.global_position).rotated(Vector3.UP, -_player.input.look_yaw)
		var angle: float = atan2(to.x, -to.z)
		var dir := Vector2(sin(angle), -cos(angle))
		var half: Vector2 = screen / 2.0 - Vector2.ONE * edge_margin
		var k: float = minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		var c: Vector2 = screen / 2.0 + dir * k
		_draw_icon(c, s, col)
		if key:
			_draw_key(c - dir * s * 1.1, s)
		var tip: Vector2 = c + dir * s * 1.15
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip, c + dir * s * 0.75 + side * s * 0.28,
				c + dir * s * 0.75 - side * s * 0.28]), col)


## The F-1 drawn with shapes: a dark disc behind it (shows on bright snow), the ribbed body,
## the fuze on top and the lever down its side.
func _draw_icon(c: Vector2, s: float, col: Color) -> void:
	var dark := Color(0.05, 0.05, 0.05, 0.55)
	draw_circle(c, s * 0.72, dark)
	var body_c: Vector2 = c + Vector2(0.0, s * 0.12)
	var pts := PackedVector2Array()
	for i in 20:
		var a: float = TAU * i / 20.0
		pts.append(body_c + Vector2(cos(a) * s * 0.27, sin(a) * s * 0.36))
	draw_colored_polygon(pts, col)
	var line := Color(0.1, 0.08, 0.05, 0.9)
	var w: float = maxf(1.0, s * 0.05)
	for y in [-0.12, 0.12]:
		var half_w: float = s * 0.27 * sqrt(1.0 - pow(y / 0.36, 2.0))
		draw_line(body_c + Vector2(-half_w, y * s), body_c + Vector2(half_w, y * s), line, w)
	draw_line(body_c + Vector2(0.0, -s * 0.34), body_c + Vector2(0.0, s * 0.34), line, w)
	draw_rect(Rect2(c + Vector2(-s * 0.09, -s * 0.44), Vector2(s * 0.18, s * 0.2)), col)
	draw_line(c + Vector2(s * 0.09, -s * 0.4), c + Vector2(s * 0.3, -s * 0.05), col, maxf(1.5, s * 0.08))


## GR2: a small keyboard key with "F" on it (you can pick this grenade up and throw it back).
func _draw_key(c: Vector2, s: float) -> void:
	var r := Rect2(c - Vector2(s * 0.38, s * 0.38), Vector2(s * 0.76, s * 0.76))
	draw_rect(r, Color(0.05, 0.05, 0.05, 0.7))
	draw_rect(r, Color(0.95, 0.95, 0.9, 0.95), false, maxf(1.0, s * 0.05))
	var font: Font = get_theme_default_font()
	var fs: int = maxi(10, int(s * 0.62))
	var w: float = font.get_string_size("F", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w / 2.0, fs * 0.36), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.95, 0.9))
