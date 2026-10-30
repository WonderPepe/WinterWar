class_name DamageIndicator
extends Control
## Red arcs around the crosshair pointing to where hits came from, fading out.
## Top = in front of you, right = to your right, bottom = behind you.

@export var radius: float = 110.0
@export var arc_degrees: float = 36.0
@export var show_time: float = 1.6

var _hits: Array = [] # [world source position, time left]
var _player: Player


func set_player(p: Player) -> void:
	_player = p


func add_hit(source: Vector3) -> void:
	_hits.append([source, show_time])
	queue_redraw()


func _process(delta: float) -> void:
	if _hits.is_empty():
		return
	for h in _hits:
		h[1] -= delta
	_hits = _hits.filter(func(h: Array) -> bool: return h[1] > 0.0)
	queue_redraw()


func _draw() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var center: Vector2 = size / 2.0
	for h in _hits:
		var to_source: Vector3 = (h[0] as Vector3) - _player.global_position
		# Turn into the player's view: 0 = straight ahead, positive = to the right.
		var local: Vector3 = to_source.rotated(Vector3.UP, -_player.input.look_yaw)
		var angle: float = atan2(local.x, -local.z)
		var alpha: float = clampf(h[1] / show_time, 0.0, 1.0)
		var start: float = angle - PI / 2.0 - deg_to_rad(arc_degrees / 2.0)
		draw_arc(center, radius, start, start + deg_to_rad(arc_degrees), 16, Color(0.85, 0.08, 0.05, 0.85 * alpha), 9.0, true)
