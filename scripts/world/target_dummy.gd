class_name TargetDummy
extends Node3D
## A wooden practice target. Falls over when "killed" and stands up again.
## Uses the same take_damage() function that enemies and players use.

@export var max_health: float = 100.0
@export var reset_time: float = 3.0 ## Seconds before it stands up again.
@export var label_text: String = "" ## Text floating above the target (e.g. its distance).

var health: float = 100.0
## Synced from the host by DummySync.
var is_down: bool = false:
	set = _set_is_down

var _tween: Tween

@onready var body: Node3D = $Body


func _ready() -> void:
	health = max_health
	if label_text != "":
		($DistanceLabel as Label3D).text = label_text
	var terrain := get_tree().get_first_node_in_group("terrain") as TerrainGenerator
	if terrain:
		global_position.y = terrain.get_height(global_position.x, global_position.z)


## Called by the host when a bullet hits. Returns true if this hit knocked it down.
func take_damage(amount: float, _attacker_id: int, _hit_position: Vector3, _hit_normal: Vector3) -> bool:
	if not multiplayer.is_server() or is_down:
		return false
	health -= amount
	if health > 0.0:
		return false
	is_down = true
	get_tree().create_timer(reset_time).timeout.connect(_stand_up)
	return true


func _stand_up() -> void:
	health = max_health
	is_down = false


func _set_is_down(value: bool) -> void:
	is_down = value
	if not is_node_ready():
		return
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD)
	var angle: float = deg_to_rad(-85.0) if is_down else 0.0 # falls away from the trench
	_tween.tween_property(body, "rotation:x", angle, 0.35 if is_down else 0.6)
