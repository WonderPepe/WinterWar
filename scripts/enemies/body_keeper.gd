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
## - at most `Settings.preset().max_bodies` bodies (36 / 24 / 24 on High / Medium / Low); when
##   one more comes, the oldest sinks into the snow,
## - a body casts no shadow and is not drawn beyond `hide_distance_m`,
## - V10c: as soon as a body is handed over his pose is "baked" (frozen into a plain shape, no
##   skeleton) and glued together with up to `batch_size` other bodies lying near him into one
##   shape, a "batch" (a MeshInstance3D child called BodyBatch…). The graphics card gets one
##   "draw call" (one order: draw this) per batch instead of one per body – 24 bodies cost about
##   4–6 draw calls, not 24. Only the batches that change are rebuilt (a new body, the oldest
##   taken away), and only at those moments, never every frame.
## A new day: behind the black day screen all but the newest `keep_overnight` bodies are
## removed, and those that stay get snow on them (owner 2026-11-16: 12 stay "to give a feeling
## of continuity"; 2026-11-24: 24, "a more realistic feeling of war").

@export var keep_overnight: int = 24 ## This many of the newest bodies are still there the next day.
@export var overnight_snow: float = 0.3 ## Snow on a body after a night (0 = none … 1 = nearly covered); a second night adds more.
@export var hide_distance_m: float = 170.0 ## Bodies further away than this are not drawn.
@export var cast_shadows: bool = false ## Shadows for bodies cost one more draw call each.
@export var sink_time: float = 3.0 ## Seconds for the oldest body to sink into the snow when there are too many.
@export var sink_depth: float = 0.7
@export var drop_speed: float = 4.0 ## m/s: a soldier killed in the air (jumping into the trench) comes down this fast.
@export var batch_size: int = 6 ## V10c: at most this many bodies in one batch (one draw call).
@export var batch_radius_m: float = 35.0 ## V10c: a body joins a batch whose first body lies this close; else a new batch.

## V10c: one batch – bodies lying near each other, drawn as one shape.
class Batch:
	var node: MeshInstance3D
	var centre: Vector3
	var bodies: Array[SoldierVisual] = []

var _bodies: Array[SoldierVisual] = [] # oldest first
var _batches: Array[Batch] = []
var _batch_of: Dictionary = {} # SoldierVisual -> Batch
var _material: ShaderMaterial # the soldier material with baked snow on (shared by all batches)
var _batch_count: int = 0 # for the node names
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
	if not _drop_to_ground(body):
		_bake(body)
	_trim()


## V10c: how many batches (draw calls) the bodies use now.
func batch_count() -> int:
	return _batches.size()


## V10c: the batch nodes (for tests).
func get_batch_nodes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for b in _batches:
		out.append(b.node)
	return out


## V10c: freeze the body and put him into a batch near him (or a new one).
func _bake(body: SoldierVisual) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion() or not _bodies.has(body):
		return
	if _material == null and body.get_material():
		_material = body.get_material().duplicate()
		_material.set_shader_parameter("coat_tint", Color(1, 1, 1)) # (the tint is in the colours)
		_material.set_shader_parameter("snow_cover", 0.0)
		_material.set_shader_parameter("baked_snow", true)
	body.bake_body()
	if body.baked.is_empty():
		return
	var best: Batch = null
	var best_d: float = batch_radius_m
	for b in _batches:
		var d: float = b.centre.distance_to(body.position)
		if b.bodies.size() < batch_size and d <= best_d:
			best = b
			best_d = d
	if best == null:
		best = Batch.new()
		best.centre = body.position
		best.node = MeshInstance3D.new()
		best.node.name = "BodyBatch%d" % _batch_count
		_batch_count += 1
		best.node.mesh = ArrayMesh.new()
		best.node.material_override = _material
		best.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# (measured from the batch's middle: a little further, so its outer bodies still go at about hide_distance_m)
		best.node.visibility_range_end = hide_distance_m + batch_radius_m * 0.5
		add_child(best.node)
		_batches.append(best)
	best.bodies.append(body)
	_batch_of[body] = best
	_rebuild(best)


## V10c: a body leaves his batch (to sink, or to go for good). Empty batches go.
func _take_out(body: SoldierVisual) -> void:
	var b: Batch = _batch_of.get(body)
	if b == null:
		return
	_batch_of.erase(body)
	b.bodies.erase(body)
	if b.bodies.is_empty():
		_batches.erase(b)
		b.node.queue_free()
	else:
		_rebuild(b)


## V10c: glue the batch's bodies into one shape again. The arrays are only joined end to end
## (no loops in the script), each body's snow goes into UV2.x.
func _rebuild(b: Batch) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	for body in b.bodies:
		var a: Array = body.baked
		verts.append_array(body.transform * (a[Mesh.ARRAY_VERTEX] as PackedVector3Array))
		normals.append_array(Transform3D(body.transform.basis.inverse().transposed(), Vector3.ZERO) * (a[Mesh.ARRAY_NORMAL] as PackedVector3Array))
		colors.append_array(a[Mesh.ARRAY_COLOR])
		uvs.append_array(a[Mesh.ARRAY_TEX_UV])
		var snow := PackedVector2Array()
		snow.resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		snow.fill(Vector2(body.get_snow_cover(), 0.0))
		uv2.append_array(snow)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := b.node.mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## V10c: a baked body that has to sink gets his own picture back for the few seconds it takes
## (a plain shape under his node, which then sinks).
func _show_alone(body: SoldierVisual) -> void:
	var a: Array = body.baked.duplicate()
	var snow := PackedVector2Array()
	snow.resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	snow.fill(Vector2(body.get_snow_cover(), 0.0))
	a[Mesh.ARRAY_TEX_UV2] = snow
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mi := MeshInstance3D.new()
	mi.name = "Sinking"
	mi.mesh = mesh
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = hide_distance_m
	body.add_child(mi)


## Behind the black day screen: only the newest `keep_overnight` bodies stay, with snow on them.
func new_day() -> void:
	_forget_freed()
	while _bodies.size() > keep_overnight:
		var gone: SoldierVisual = _bodies.pop_front()
		_take_out(gone)
		gone.queue_free()
	for b in _bodies:
		b.set_snow_cover(minf(b.get_snow_cover() + overnight_snow, 0.9))
	for batch in _batches:
		_rebuild(batch) # the new snow (behind the black screen, nobody sees the work)


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
		if _batch_of.has(old):
			_take_out(old)
			_show_alone(old)
		var tween := old.create_tween()
		tween.tween_property(old, "position:y", old.position.y - sink_depth, sink_time)
		tween.tween_callback(old.queue_free)


func _forget_freed() -> void:
	for i in range(_bodies.size() - 1, -1, -1):
		if not is_instance_valid(_bodies[i]) or _bodies[i].is_queued_for_deletion():
			_bodies.remove_at(i)
	# (a body freed by someone else must not stay in a batch)
	for batch in _batches.duplicate():
		var before: int = batch.bodies.size()
		for i in range(batch.bodies.size() - 1, -1, -1):
			if not is_instance_valid(batch.bodies[i]) or not _bodies.has(batch.bodies[i]):
				batch.bodies.remove_at(i)
		if batch.bodies.size() != before:
			for k in _batch_of.keys():
				if _batch_of[k] == batch and not batch.bodies.has(k):
					_batch_of.erase(k)
			if batch.bodies.is_empty():
				_batches.erase(batch)
				batch.node.queue_free()
			else:
				_rebuild(batch)


## A soldier killed in the air (jumping into the trench) stopped where he was hit: bring the
## body down to the ground under it.
## Returns true if he is coming down (V10c: he is baked when he is down).
func _drop_to_ground(body: SoldierVisual) -> bool:
	var from: Vector3 = body.global_position + Vector3.UP * 0.3
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 8.0, 1) # 1 = the world layer
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var fall: float = body.global_position.y - (hit.position as Vector3).y
	if fall > 0.15:
		var tween := body.create_tween()
		tween.tween_property(body, "position:y", body.position.y - fall, fall / drop_speed) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(_bake.bind(body))
		return true
	return false
