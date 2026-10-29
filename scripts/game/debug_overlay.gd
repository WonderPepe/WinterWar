extends Label
## Temporary debug text for testing Milestone 1 (the real HUD comes in M4).
## Shows information about the player controlled on this computer.

func _process(_delta: float) -> void:
	var player: Player = _find_local_player()
	if player == null:
		text = "Waiting for player..."
		return
	var state: String = "standing"
	if player.is_crouching:
		state = "crouching"
	elif player.is_sprinting:
		state = "SPRINTING"
	if not player.is_on_floor():
		state += " (in air)"
	text = "Speed: %.1f m/s   Stamina: %d   Health: %d\nState: %s   Deep snow: %s\nFPS: %d   Mouse: %s" % [
		player.get_speed(), int(player.stamina), player.health,
		state, "YES" if player.is_in_deep_snow() else "no",
		Engine.get_frames_per_second(),
		"captured (Esc to release)" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "free (click to capture)",
	]


func _find_local_player() -> Player:
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p and p.is_local_player():
			return p
	return null
