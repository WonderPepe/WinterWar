class_name Crosshair
extends Control
## Four short lines around the screen centre. The gap shows the weapon's real
## current spread: it opens up when you move or keep firing.

@export var line_length: float = 9.0
@export var thickness: float = 2.0
@export var min_gap: float = 4.0
@export var color: Color = Color(1, 1, 1, 0.9)
@export var outline_color: Color = Color(0, 0, 0, 0.55)

var spread_deg: float = 0.0 ## Set by the HUD every frame.
var fov_deg: float = 75.0   ## Camera field of view, needed to turn degrees into pixels.


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size / 2.0
	var half_height: float = get_viewport_rect().size.y / 2.0
	var gap: float = half_height * tan(deg_to_rad(spread_deg)) / tan(deg_to_rad(fov_deg) / 2.0)
	gap = maxf(gap, min_gap)
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var a: Vector2 = center + dir * gap
		var b: Vector2 = center + dir * (gap + line_length)
		draw_line(a - dir, b + dir, outline_color, thickness + 2.0)
		draw_line(a, b, color, thickness)
