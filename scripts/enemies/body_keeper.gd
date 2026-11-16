class_name BodyKeeper
extends Node3D
## V10b: keeps the bodies of fallen soldiers on the field (the "Bodies" node of the Game).
##
## A few seconds after a soldier falls, his picture (the SoldierVisual node) is handed to this
## node with `take()`. From then on the body is only a picture: no script running, no collision,
## nothing sent over the network. The soldier node itself is removed as before, so the AI, the
## count of living soldiers and the trench count never see the bodies.
##
## Runs on EVERY computer by itself (each one keeps the bodies it saw fall) – nothing is synced.
## A player who joins late does not see the bodies from before he came.
##
## Limits, so the picture stays fast:
## - at most `Settings.preset().max_bodies` bodies (36 / 24 / 12 on High / Medium / Low); when
##   one more comes, the oldest sinks into the snow,
## - a body casts no shadow and is not drawn beyond `hide_distance_m`.
## A new day: behind the black day screen all but the newest `keep_overnight` bodies are
## removed, and those that stay get snow on them (owner 2026-11-16: 12 stay "to give a feeling
## of continuity").

@export var keep_overnight: int = 12 ## This many of the newest bodies are still there the next day.
@export var overnight_snow: float = 0.3 ## Snow on a body after a night (0 = none … 1 = nearly covered); a second night adds more.
@export var hide_distance_m: float = 170.0 ## Bodies further away than this are not drawn.
@export var cast_shadows: bool = false ## Shadows for bodies cost one more draw call each.
@export var sink_time: float = 3.0 ## Seconds for the oldest body to sink into the snow when there are too many.
@export var sink_depth: float = 0.7
@export var drop_speed: float = 4.0 ## m/s: a soldier killed in the air (jumping into the trench) comes down this fast.

var _bodies: Array[SoldierVisual] = [] # oldest first
var _check: float = 0.0
var _was_black: bool = false


func _ready() -> void:
	add_to_group("body_keeper")
	Settings.changed.connect(_trim)


## How many bodies may lie on the field with the current graphics quality.
func max_bodies() -> int:
	return int(Settings.preset().get("max_bodies", 24))


## The bodies kept now (oldest first).
func get_bodies() -> Array[SoldierVisual]:
	_forget_freed()
	return _bodies.duplicate()


## Takes over the picture of a soldier who has fallen and lies still.
func take(body: SoldierVisual) -> void:
	if body == null or body.is_body:
		return
	body.become_body(hide_distance_m, cast_shadows)
	body.reparent(self, true) # true = he stays exactly where he lies
	_bodies.append(body)
	_drop_to_ground(body)
	_trim()


## Behind the black day screen: only the newest `keep_overnight` bodies stay, with snow on them.
func new_day() -> void:
	_forget_freed()
	while _bodies.size() > keep_overnight:
		_bodies.pop_front().queue_free()
	for b in _bodies:
		b.set_snow_cover(minf(b.get_snow_cover() + overnight_snow, 0.9))


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	var screen: Node = get_tree().get_first_node_in_group("day_screen")
	var black: bool = screen != null and screen.has_method("is_black") and screen.is_black()
	if black and not _was_black:
		new_day()
	_was_black = black


## Too many (a new body, or the quality was turned down): the oldest sink into the snow.
func _trim() -> void:
	_forget_freed()
	while _bodies.size() > max_bodies():
		var old: SoldierVisual = _bodies.pop_front()
		var tween := old.create_tween()
		tween.tween_property(old, "position:y", old.position.y - sink_depth, sink_time)
		tween.tween_callback(old.queue_free)


func _forget_freed() -> void:
	for i in range(_bodies.size() - 1, -1, -1):
		if not is_instance_valid(_bodies[i]) or _bodies[i].is_queued_for_deletion():
			_bodies.remove_at(i)


## A soldier killed in the air (jumping into the trench) stopped where he was hit: bring the
## body down to the ground under it.
func _drop_to_ground(body: SoldierVisual) -> void:
	var from: Vector3 = body.global_position + Vector3.UP * 0.3
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 8.0, 1) # 1 = the world layer
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var fall: float = body.global_position.y - (hit.position as Vector3).y
	if fall > 0.15:
		var tween := body.create_tween()
		tween.tween_property(body, "position:y", body.position.y - fall, fall / drop_speed) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
