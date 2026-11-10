extends Node
## Test for the Controls screen, the tank stopping 3 m closer and the first-tank-battle
## Molotov hint (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_controls.gd

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ready() -> void:
	await get_tree().process_frame
	run()


func wait_for(cond: Callable, limit: float) -> bool:
	var t: float = 0.0
	while t < limit:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return cond.call()


func run() -> void:
	# --- Every action in the list exists in the Input Map and has a readable key.
	for row in ControlsPanel.ROWS + ControlsPanel.DEBUG_ROWS:
		if row is String:
			continue
		var actions: Array = row[0] if row[0] is Array else [row[0]]
		for a in actions:
			var k: String = ControlsPanel.key_text(a)
			check(k != "?" and k != "", "%s → '%s'" % [a, k])
	check(ControlsPanel.key_text("move_forward") == "W", "W moves forward")
	check(ControlsPanel.key_text("fire") == "Left mouse", "left mouse fires")
	check(ControlsPanel.key_text("pause") == "Esc", "Esc pauses")

	# --- Main menu: Controls button opens the panel, Back / Esc closes it.
	var menu: MainMenu = load("res://ui/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await seconds(0.2)
	check(not menu.controls_panel.visible, "main menu: controls hidden at start")
	menu.controls_button.pressed.emit()
	check(menu.controls_panel.visible and not menu.menu_box.visible, "main menu: Controls opens the list")
	check(menu.controls_panel.grid.get_child_count() >= 40, "the list has rows (%d cells)" % menu.controls_panel.grid.get_child_count())
	menu.controls_panel.back.pressed.emit()
	check(not menu.controls_panel.visible and menu.menu_box.visible, "main menu: Back closes the list")
	menu.controls_button.pressed.emit()
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	Input.parse_input_event(esc)
	await seconds(0.1)
	check(not menu.controls_panel.visible and menu.menu_box.visible, "main menu: Esc closes the list")
	menu.queue_free()
	await seconds(0.1)

	# --- In the game: pause menu Controls; tanks park 3 m closer; the hint.
	Settings.difficulty = 1
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	await seconds(0.5)
	var pm := game.get_node("PauseMenu")
	pm.open()
	pm.controls_button.pressed.emit()
	check(pm.controls_panel.visible and not pm.panel.visible, "pause menu: Controls opens the list")
	Input.parse_input_event(esc)
	await seconds(0.1)
	check(not pm.controls_panel.visible and pm.panel.visible and pm.is_open, "pause menu: Esc closes only the list, the menu stays")
	pm.resume()
	pm.free()

	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	for r in spawner.get_routes():
		var end: Vector3 = r.to_global(r.curve.sample_baked(r.curve.get_baked_length()))
		check(is_equal_approx(end.z, 49.0), "%s ends at z = %.1f (3 m closer than 46)" % [r.name, end.z])

	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.god_mode = true
	var hud: HUD = game.get_node("HUD")
	var waves: WaveSpawner = get_tree().get_first_node_in_group("wave_spawner")
	Engine.time_scale = 4.0
	waves.time_between_groups = 0.3
	waves.start_at_wave(2, 0.1)
	await wait_for(func() -> bool: return waves.wave_number == 2, 3.0)
	await seconds(0.3)
	check(not hud._tank_hint_shown, "battle 2 (no tanks): no Molotov hint")
	# Battle 3 (first tanks) directly, as if battle 2 was cleared.
	waves.start_at_wave(3, 0.1)
	await wait_for(func() -> bool: return waves.wave_number == 3, 3.0)
	await seconds(0.2)
	check(hud._tank_hint_shown and not hud.tank_hint.visible, "battle 3: hint waits while the BATTLE banner is up")
	await wait_for(func() -> bool: return hud.tank_hint.visible, 8.0)
	check(hud.tank_hint.visible and hud.tank_hint.text.contains("TANKS ARE COMING") and hud.tank_hint.text.contains("[F]")
			and hud.tank_hint.text.contains("[G]"), "hint shown after the banner: '%s'" % hud.tank_hint.text.replace("\n", " / "))
	await wait_for(func() -> bool: return not hud.tank_hint.visible, hud.tank_hint_time + 2.0)
	check(not hud.tank_hint.visible, "hint goes away after %d s" % hud.tank_hint_time)
	hud._last_wave = 3
	waves.start_at_wave(4, 0.1)
	await wait_for(func() -> bool: return waves.wave_number == 4, 3.0)
	await seconds(6.0)
	check(not hud.tank_hint.visible, "battle 4: no second hint")
	Engine.time_scale = 1.0

	print("RESULT: %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
