extends Label
## Temporary debug text for testing (the real HUD comes in M4).
## Shows information about the player controlled on this computer.

var _hit_text_until: float = 0.0
var _hit_text: String = ""
var _connected_player: Player


func _process(_delta: float) -> void:
	var player: Player = _find_local_player()
	if player == null:
		text = "Waiting for player..."
		return
	if player != _connected_player:
		_connected_player = player
		player.weapons.hit_confirmed.connect(_on_hit_confirmed)

	var state: String = "standing"
	if player.is_crouching:
		state = "crouching"
	elif player.is_sprinting:
		state = "SPRINTING"
	if not player.is_on_floor():
		state += " (in air)"
	var w: WeaponData = player.weapons.get_current_weapon()
	var weapon_line: String = "%s   %d / %d%s%s" % [
		w.display_name, player.weapons.get_mag_ammo(), player.weapons.get_reserve_ammo(),
		"   RELOADING" if player.weapons.is_reloading else "",
		"   [aiming]" if player.weapons.is_aiming else "",
	]
	var now: float = Time.get_ticks_msec() / 1000.0
	text = "Speed: %.1f m/s   Stamina: %d   Health: %d\nState: %s   Deep snow: %s\n%s\n%s\nFPS: %d   Mouse: %s" % [
		player.get_speed(), int(player.stamina), player.health,
		state, "YES" if player.is_in_deep_snow() else "no",
		weapon_line,
		_hit_text if now < _hit_text_until else "",
		Engine.get_frames_per_second(),
		"captured (Esc to release)" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "free (click to capture)",
	]


func _on_hit_confirmed(killed: bool) -> void:
	_hit_text = ">>> HIT - TARGET DOWN <<<" if killed else ">>> HIT <<<"
	_hit_text_until = Time.get_ticks_msec() / 1000.0 + 0.4


func _find_local_player() -> Player:
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p and p.is_local_player():
			return p
	return null
