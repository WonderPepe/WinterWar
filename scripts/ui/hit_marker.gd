class_name HitMarker
extends Control
## A small X at the screen centre that flashes when your shot hits:
## white for a hit, red for a kill.

@export var duration: float = 0.25
@export var inner: float = 6.0
@export var outer: float = 14.0
@export var hit_color: Color = Color(1, 1, 1)
@export var kill_color: Color = Color(1, 0.25, 0.2)

var _time_left: float = 0.0
var _color: Color = Color.WHITE


func show_hit(killed: bool) -> void:
	_time_left = duration
	_color = kill_color if killed else hit_color


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
