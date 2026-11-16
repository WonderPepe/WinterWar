class_name HitMarker
extends Control
## A small X at the screen centre that flashes when your shot hits:
## white for a hit, red for a kill. A head shot (D9) also gets a small ring around the X.

@export var duration: float = 0.25
@export var inner: float = 6.0
@export var outer: float = 14.0
@export var hit_color: Color = Color(1, 1, 1)
@export var kill_color: Color = Color(1, 0.25, 0.2)
@export var head_ring_radius: float = 18.0 ## The head-shot ring, just outside the X.

var _time_left: float = 0.0
var _color: Color = Color.WHITE
var _head: bool = false


func show_hit(killed: bool, head: bool = false) -> void:
	_time_left = duration
	_color = kill_color if killed else hit_color
	_head = head


func _process(delta: float) -> void:
	if _time_left > 0.0:
		_time_left -= delta
		queue_redraw()


func _draw() -> void:
	if _time_left <= 0.0:
		return
	var c: Color = _color
	c.a = clampf(_time_left / duration, 0.0, 1.0)
	var center: Vector2 = size / 2.0
	for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var d: Vector2 = dir.normalized()
		draw_line(center + d * inner, center + d * outer, Color(0, 0, 0, c.a * 0.6), 4.0)
		draw_line(center + d * inner, center + d * outer, c, 2.0)
	if _head:
		draw_arc(center, head_ring_radius, 0.0, TAU, 32, Color(0, 0, 0, c.a * 0.6), 4.0, true)
		draw_arc(center, head_ring_radius, 0.0, TAU, 32, c, 2.0, true)
