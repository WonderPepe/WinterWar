class_name ShaderWarmup
extends CanvasLayer
## Removes the "first shot stutter".
##
## The first time an effect is drawn (muzzle flash and its light, bullet impacts, a soldier),
## the browser has to prepare ("compile") its shader, which freezes the game for ~0.1 s.
## So while a short "Preparing the battlefield..." screen is shown, we draw every effect
## once in front of the camera. When the real fight starts, everything is ready.

@export var frames: int = 10 ## How many frames to keep the effects on screen.

## 0..1 while warming up (shown by the LoadingScreen's progress bar).
var progress: float = 0.0

var _cover: ColorRect
var _temp: Array[Node] = []


func _ready() -> void:
	add_to_group("shader_warmup")
	layer = 50
	_cover = ColorRect.new()
	_cover.color = Color(0.13, 0.16, 0.21) # same as the loading screen
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)
	var label := Label.new()
	label.text = "Preparing the battlefield..."
	label.add_theme_font_size_override("font_size", 22)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_cover.add_child(label)
	_warm_up.call_deferred()


func _warm_up() -> void:
	var player: Player = null
	for i in 5: # the player is spawned by the Game in the same frame - wait for it
		player = _local_player()
		if player:
			break
		await get_tree().process_frame
	if player == null:
		queue_free()
		return
	var cam: Camera3D = player.camera
	var front: Vector3 = cam.global_position - cam.global_basis.z * 3.0
	var effects := get_tree().get_first_node_in_group("impact_effects") as ImpactEffects

	# Both weapons with muzzle flash and its light.
	var weapons: WeaponController = player.weapons
	for vm in weapons._view_models:
		vm.visible = true
		vm._flash_until = Time.get_ticks_msec() / 1000.0 + 10.0
	# Impacts on every surface type and another player's muzzle flash.
	if effects:
		for surface in ["snow", "wood", "cloth", "metal"]:
			effects.spawn_impact(front, cam.global_basis.z, surface) # facing the camera
		effects.spawn_flash(front)
		effects.spawn_smoke(front, -cam.global_basis.z)
	# A soldier model (just its meshes, without the AI).
	var enemy_scene: PackedScene = load("res://scenes/enemies/soviet_rifleman.tscn")
	var enemy: Node = enemy_scene.instantiate()
	var visual: Node3D = enemy.get_node("Visual")
	enemy.remove_child(visual)
	enemy.free()
	player.get_parent().add_child(visual)
	visual.global_position = cam.global_position - cam.global_basis.z * 4.0 - Vector3.UP * 1.2
	_temp.append(visual)
	# The Maxim's own model (its materials are only seen once you enter the bunker).
	var maxim_model: Node3D = load("res://assets/models/weapons/maxim/model.gltf").instantiate()
	player.get_parent().add_child(maxim_model)
	maxim_model.scale = Vector3.ONE * 0.01
	maxim_model.global_position = cam.global_position - cam.global_basis.z * 2.5
	_temp.append(maxim_model)
	# The T-26 tank's model (T1), shrunk to a toy in front of you.
	var tank_model: Node3D = load("res://assets/models/vehicles/t26/model.gltf").instantiate()
	player.get_parent().add_child(tank_model)
	tank_model.scale = Vector3.ONE * 0.02
	tank_model.global_position = cam.global_position - cam.global_basis.z * 2.5 + cam.global_basis.x * 0.3
	_temp.append(tank_model)

	for i in frames:
		progress = float(i + 1) / frames
		await get_tree().process_frame

	# Clean up: hide everything again and show the real game.
	for vm in weapons._view_models:
		vm._flash_until = 0.0
	weapons._apply_slot()
	if effects:
		for hole in effects._holes:
			hole.visible = false
		effects.hide_all() # no smoke or snow spray hanging in front of you when the game starts
	for n in _temp:
		n.queue_free()
	queue_free()


func _local_player() -> Player:
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p and p.is_local_player():
			return p
	return null
