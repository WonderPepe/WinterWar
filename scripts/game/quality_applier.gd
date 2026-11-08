extends Node
## Applies the graphics quality setting (Settings autoload) to this level:
## sun shadows, tree draw distance, fog, falling and drifting snow.
## Runs when the game starts and whenever the player changes a setting.

func _ready() -> void:
	Settings.changed.connect(apply)
	apply.call_deferred() # after the level and players are ready


func apply() -> void:
	var p: Dictionary = Settings.preset()
	var sun := get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = p.shadows
		sun.directional_shadow_max_distance = maxf(p.shadow_distance, 1.0)
		# One shadow "split" is cheaper; two give sharper shadows close to you.
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if p.shadow_distance > 50.0 else DirectionalLight3D.SHADOW_ORTHOGONAL
	var forest := get_tree().get_first_node_in_group("forest") as ForestScatter
	if forest:
		forest.set_visibility_end(p.tree_distance)
		forest.set_detail_distance(p.tree_detail_distance)
	# Fog density and falling / drifting snow depend on the battle's weather too (B3): DuskLight.
	var weather := get_tree().get_first_node_in_group("weather") as DuskLight
	if weather:
		weather.apply_quality()
