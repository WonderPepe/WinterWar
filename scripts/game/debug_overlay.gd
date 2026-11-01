extends Label
## Debug text for testing (F3 shows/hides it). The real HUD is ui/hud.tscn.
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
	var waves := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	var wave_line: String = ""
	if waves:
		wave_line = "Battle %d   Enemies alive: %d" % [waves.wave_number, waves.alive_count]
		if waves.get_time_to_next_wave() > 0.0:
			wave_line += "   Next battle in %d s" % ceili(waves.get_time_to_next_wave())
	text = "Speed: %.1f m/s   Stamina: %d   Health: %d%s\nState: %s   Deep snow: %s\n%s\n%s\n%s\nFPS: %d   Mouse: %s   [F1 god mode, F2 enemy labels, F3 hide]" % [
		player.get_speed(), int(player.stamina), player.health, "  (GOD MODE)" if player.god_mode else "",
		state, "YES" if player.is_in_deep_snow() else "no",
		weapon_line,
		wave_line,
		_hit_text if now < _hit_text_until else "",
		Engine.get_frames_per_second(),
		"captured" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "free",
	]


func _ready() -> void:
	visible = false # F3 shows it


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		visible = not visible
	if event.is_action_pressed("debug_enemy_labels"):
		Enemy.show_debug_labels = not Enemy.show_debug_labels


func _on_hit_confirmed(killed: bool) -> void:
	_hit_text = ">>> HIT - KILLED <<<" if killed else ">>> HIT <<<"
	_hit_text_until = Time.get_ticks_msec() / 1000.0 + 0.4


func _find_local_player() -> Player:
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p and p.is_local_player():
			return p
	return null
