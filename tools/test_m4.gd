extends Node
## Automated test for Milestone 4: death/respawn, kills, HUD, pause menu, main menu.

var p: Player
var fails := 0

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout

func aim_at(point: Vector3) -> void:
	var d: Vector3 = point - p.camera.global_position
	p.input.look_yaw = atan2(-d.x, -d.z)
	p.input.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())

func _ready() -> void:
	await get_tree().process_frame # the root can't take new children while it is adding us
	run()

func run() -> void:
	# --- Main menu -> game ---
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await seconds(0.3)
	check(get_tree().current_scene.name == "MainMenu", "main menu is shown")
	var vb := get_tree().current_scene.get_node("Center/VBox")
	check(vb.get_node("HostCoopButton").disabled and vb.get_node("JoinCoopButton").disabled, "co-op buttons are greyed out")
	vb.get_node("SinglePlayerButton").pressed.emit()
	await seconds(0.5)
	check(get_tree().current_scene.name == "Game", "Single Player starts the game")
	var game: Game = get_tree().current_scene
	var pause_menu: Node = game.get_node("PauseMenu")
	await seconds(0.7) # headless: the mouse can't be captured, so the pause menu opens itself
	check(pause_menu.is_open and get_tree().paused, "pause menu opens (and pauses) when the mouse is free")
	pause_menu.resume()
	check(not pause_menu.is_open and not get_tree().paused, "Resume closes the menu and unpauses")
	pause_menu.free() # from here on the test drives the game directly
	await seconds(0.2)

	p = get_tree().get_nodes_in_group("players")[0]
	p.input.set_process(false)
	var hud: HUD = game.get_node("HUD")
	game.respawn_time = 1.5
	await seconds(0.3)
	check(hud.ammo_label.text == "5 / 30", "HUD shows ammo 5 / 30")
	check(hud.health_bar.value == 100 and hud.health_value.text == "100", "HUD shows health 100")
	check(hud.crosshair.visible and not hud.death_screen.visible, "crosshair visible, death screen hidden")

	# --- Kill an enemy with the Mosin: kill counted, HUD updates ---
	var waves: WaveSpawner = get_tree().get_first_node_in_group("wave_spawner")
	waves._timer = 0.0
	await seconds(1.0)
	var e: Enemy = get_tree().get_nodes_in_group("enemies")[0]
	e.set_physics_process(false)
	var terrain: TerrainGenerator = get_tree().get_first_node_in_group("terrain")
	e.global_position = Vector3(p.global_position.x, terrain.get_height(p.global_position.x, 35.0), 35.0)
	await seconds(0.3)
	p.input.aim_held = true
	await seconds(0.5)
	aim_at(e.global_position + Vector3.UP * 1.2)
	await get_tree().physics_frame
	p.input.fire_held = true
	await seconds(0.1)
	p.input.fire_held = false
	p.input.aim_held = false
	await seconds(0.2)
	check(e.state == Enemy.State.DEAD and p.kills == 1, "enemy killed, kills = %d" % p.kills)
	check(hud.ammo_label.text == "4 / 30", "HUD ammo updated (%s)" % hud.ammo_label.text)
	check(hud.score_label.text.begins_with("Kills 1"), "HUD score shows the kill")
	check(hud.wave_label.text.begins_with("WAVE 1"), "HUD shows the wave (%s)" % hud.wave_label.text)

	# --- Damage flash, death, respawn ---
	var hp_before: int = p.health
	p.take_damage(30, -1, Vector3.ZERO, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame # the HUD updates during the frame after the signal
	print("  health %d -> %d, hud '%s', flash %.2f, hud player ok: %s" % [hp_before, p.health, hud.health_value.text, hud.damage_flash.modulate.a, hud._player == p])
	check(hud.damage_flash.modulate.a > 0.5, "red damage flash when hurt")
	check(hud.health_value.text == "70", "HUD health 70")
	var killed: bool = p.take_damage(200, -1, Vector3.ZERO, Vector3.UP)
	await seconds(0.3)
	check(killed and p.is_dead and p.deaths == 1, "player dies at 0 health (deaths %d)" % p.deaths)
	check(hud.death_screen.visible and hud.respawn_label.text.begins_with("Respawning in"), "death screen with countdown")
	check(not p.weapons.holder.visible and not hud.crosshair.visible, "gun and crosshair hidden while dead")
	check(p.collision_layer == 0, "dead body ignored by bullets/enemies")
	var ammo_before: int = p.weapons.get_mag_ammo()
	p.input.fire_held = true
	await seconds(0.2)
	p.input.fire_held = false
	check(p.weapons.get_mag_ammo() == ammo_before, "cannot shoot while dead")
	p.input.move_dir = Vector2(0, -1)
	var pos_dead := p.global_position
	await seconds(0.3)
	check(p.global_position.distance_to(pos_dead) < 0.05, "cannot move while dead")
	p.input.move_dir = Vector2.ZERO
	var watcher: Enemy = null
	for n in get_tree().get_nodes_in_group("enemies"):
		if (n as Enemy).state != Enemy.State.DEAD:
			watcher = n
	if watcher:
		watcher.global_position = Vector3(p.global_position.x, 0.5, 40)
		watcher.rotation.y = PI
		check(watcher._find_visible_player() == null, "enemies ignore a dead player")
	await seconds(1.4)
	check(not p.is_dead and p.health == 100 and p.weapons.get_mag_ammo() == 5 and p.weapons.get_reserve_ammo() == 30, "respawned with full health and ammo")
	check(p.global_position.z > 55 and p.global_position.y < -1.0, "respawned in the trench (%s)" % p.global_position)
	check(p.collision_layer == 0b10 and not hud.death_screen.visible, "collision restored, death screen hidden")

	# --- Back to the main menu ---
	NetworkManager.leave_game()
	await seconds(0.5)
	check(get_tree().current_scene.name == "MainMenu" and not get_tree().paused, "Main Menu button returns to the menu")

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
