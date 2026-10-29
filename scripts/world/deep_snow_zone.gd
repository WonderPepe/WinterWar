class_name DeepSnowZone
extends Area3D
## An area of deep snow. Anything that walks into it and has the methods
## enter_deep_snow() / exit_deep_snow() (players now, enemies later) is slowed down.
## The zone places itself on the ground and draws a soft snow drift.

@export var size: Vector3 = Vector3(20, 4, 12) ## Width, height, depth of the zone in metres.
@export var drift_height: float = 0.35 ## How far the drift visual sticks up from the ground.
@export var drift_material: Material


func _ready() -> void:
	add_to_group("deep_snow")
	collision_layer = 0          # nothing needs to detect the zone itself
	collision_mask = 0b110       # detect players (layer 2) and enemies (layer 3)
	monitorable = false

	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)

	var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
	if terrain:
		global_position.y = terrain.get_height(global_position.x, global_position.z)
	_make_drift()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _make_drift() -> void:
	# A squashed sphere half-buried in the ground looks like a snow drift.
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 24
	sphere.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = drift_material
	mi.scale = Vector3(size.x, drift_height * 4.0, size.z)
	mi.position.y = -drift_height
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_deep_snow"):
		body.enter_deep_snow()


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_deep_snow"):
		body.exit_deep_snow()
