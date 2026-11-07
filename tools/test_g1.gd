extends Node
## Automated test for G1 "a real battle" (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_g1.gd

var game: Node
var p: Player
var director: MatchDirector
var spawner: WaveSpawner
var hud: HUD
var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ready() -> void:
	await get_tree().process_frame
	run()


func start_game() -> void:
	if game:
		game.queue_free()
		await frames(2)
	get_tree().paused = false
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await frames(5)
	await physics(5)
	p = get_tree().get_first_node_in_group("players")
	director = get_tree().get_first_node_in_group("match_director")
	spawner = get_tree().get_first_node_in_group("wave_spawner")
	hud = game.get_node("HUD")
	p.input.set_process(false)
	spawner.set_process(false) # the test sends the soldiers itself


func spawn_enemy(pos: Vector3) -> Enemy:
	var e: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
	e.name = "TestEnemy_%d" % Time.get_ticks_usec()
	e.position = pos
	e.attack_point = pos
	game.get_node("Enemies").add_child(e, true)
	return e


func run() -> void:
	# --- Main menu: difficulty choice ---
	var menu: Control = load("res://ui/main_menu.tscn").instantiate()
	var opt := menu.get_node_or_null("Center/VBox/DifficultyRow/DifficultyOption") as OptionButton
	check(opt != null and opt.item_count == 3, "main menu: Easy / Normal / Hard")
	menu.free()

	Settings.difficulty = 1
	await start_game()
	check(director != null and director.get_difficulty_name() == "Normal", "match uses the chosen difficulty (Normal)")
	check(director.waves_to_win == 10 and director.trench_limit == 4 and spawner.max_waves == 10, "Normal: 10 waves to hold, line breaks at 4")

	# --- Ammo crate ---
	var crate := get_tree().get_first_node_in_group("ammo_crates") as AmmoCrate
	check(get_tree().get_nodes_in_group("ammo_crates").size() == 2, "two ammo crates (trench + bunker)")
	p.weapons.reserve_ammo = PackedInt32Array([0, 0])
	p.bandages = 0
	p.global_position = crate.global_position + crate.global_basis * Vector3(0, 0, -1.2) + Vector3(0, 0.1, 0)
	await physics(3)
	check(p.find_ammo_crate() == crate, "crate in reach from the trench floor")
	p.input.request_interact()
	await physics(3)
	check(p.weapons.reserve_ammo[0] == 30 and p.weapons.reserve_ammo[1] == 140 and p.bandages == p.max_bandages,
		"F at the crate refills spare ammo and bandages")

	# --- Bandage ---
	p.health = 40
	p.input.request_bandage()
	await physics(3)
	check(p.is_bandaging and not p.weapons._can_fire_now(), "B starts a bandage (no shooting meanwhile)")
	await seconds(p.bandage_time + 0.3)
	check(not p.is_bandaging and p.health == 90 and p.bandages == 1, "bandage heals 50 (health %d, bandages %d)" % [p.health, p.bandages])
	p.health = 100
	p.input.request_bandage()
	await physics(3)
	check(not p.is_bandaging, "no bandage at full health")

	# --- Healing between waves, wave counter, dusk ---
	p.health = 35
	var dusk: DuskLight = game.get_node("Dusk")
	dusk.transition_time = 0.2
	var sun := get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	var energy_before: float = sun.light_energy
	spawner.wave_number = 3
	await frames(2) # the HUD sees battle 3 start first (as in a real game), else it closes the day screen
	director._on_wave_cleared(3)
	await seconds(1.0)
	check(p.health == 100, "everyone patched up when a wave is cleared")
	check(hud.wave_label.text == "BATTLE 3 / 10", "HUD shows the battle out of 10 ('%s')" % hud.wave_label.text)
	check(dusk.progress > 0.25 and sun.light_energy < energy_before - 0.1, "evening comes: the sun sinks (energy %.2f → %.2f)" % [energy_before, sun.light_energy])

	# --- New battle: everyone back at the start spot, fresh, behind the black day screen ---
	var start: Node3D = get_tree().get_nodes_in_group("player_spawn")[0]
	p.global_position = Vector3(-30, 0.5, 20) # out in front of the trench
	p.is_crouching = true
	p.weapons.reserve_ammo = PackedInt32Array([0, 0])
	p.bandages = 0
	await seconds(director.reset_players_delay - 1.0 - 0.3) # still before the reset
	check(p.global_position.distance_to(start.global_position) > 5.0, "players stay put while 'BATTLE 3 COMPLETED' shows")
	await seconds(0.6)
	check(hud.day_screen.is_black() and p.global_position.distance_to(start.global_position) < 0.5,
			"new battle: player back at the start spot while the screen is black (%.1f m away)" % p.global_position.distance_to(start.global_position))
	check(not p.is_crouching and p.bandages == p.max_bandages and p.weapons.reserve_ammo[0] > 0, "new battle: standing, ammo and bandages refilled")
	check(is_equal_approx(dusk.progress, 0.3), "new battle opens with its own light (%.2f)" % dusk.progress)
	# A dead player comes back at once, and the old respawn timer does nothing later.
	p.take_damage(1000.0, -1, p.global_position, Vector3.UP)
	check(p.is_dead, "player killed before battle 4 is cleared")
	p.global_position += Vector3(2, 0, 0)
	hud.day_screen.close_now()
	spawner.wave_number = 4
	await frames(2)
	director._on_wave_cleared(4)
	await seconds(director.reset_players_delay + 0.3)
	check(not p.is_dead and p.health == 100 and p.global_position.distance_to(start.global_position) < 0.5, "a dead player is back at the start for the new battle")
	var deaths_before: int = p.deaths
	p.global_position = start.global_position + Vector3(0, 0, -1.0)
	await seconds((game as Game).respawn_time) # the old death's timer runs out meanwhile
	check(p.deaths == deaths_before and p.global_position.distance_to(start.global_position + Vector3(0, 0, -1.0)) < 0.5, "the old respawn timer doesn't move him again")
	hud.day_screen.close_now()

	# --- Assault: a soldier at his jump-off point rushes the trench and jumps in ---
	p.god_mode = true
	p.global_position = Vector3(-10, -1.3, 61) # on the straight at x = -10
	await physics(3)
	var link := get_tree().get_first_node_in_group("trench_entry") as NavigationLink3D
	check(get_tree().get_nodes_in_group("trench_entry").size() == 10, "10 trench entries (one per ~20 m of trench)")
	var entry: NavigationLink3D = get_tree().get_nodes_in_group("trench_entry")[3]
	var jump_off: Vector3 = entry.global_transform * entry.start_position + Vector3(0, 0.1, -12)
	var e := spawn_enemy(jump_off)
	await physics(10) # the navigation map needs a few frames
	e._assault_after = 0.5
	e.state = Enemy.State.PATROL
	var entered := false
	for i in 40:
		await seconds(0.5)
		if e.is_in_trench():
			entered = true
			break
	check(link != null and entered, "assault: the soldier jumps into the trench (state %s)" % Enemy.State.keys()[e.state])
	await seconds(1.0)
	check(director.in_trench >= 1, "HUD counter: Soviets in the trench (%d)" % director.in_trench)
	await frames(2)
	check(hud.trench_label.visible and hud.trench_label.text.contains("/ 4"), "HUD warns: '%s'" % hud.trench_label.text)
	# He fights in the trench: closes in on / shoots at the player.
	var shots_before: int = e._shots_at_target
	await seconds(8.0)
	check(e._shots_at_target > shots_before or e.global_position.distance_to(p.global_position) < 8.0,
		"in the trench he goes for the player (%.1f m away, %d shots)" % [e.global_position.distance_to(p.global_position), e._shots_at_target])

	# --- Defeat: 4 in the trench at once ---
	for x in [50.0, 70.0, 90.0]: # on the trench centre line (the line passes z = 61 at x = 50, 70, 90)
		spawn_enemy(Vector3(x, -1.3, 61)).state = Enemy.State.ASSAULT
	await seconds(1.0)
	check(director.result == MatchDirector.Result.DEFEAT, "4 Soviets in the trench: the line is broken")
	await frames(3)
	check(hud.end_screen.visible and hud.end_screen.title.text == "THE LINE IS BROKEN", "end screen: defeat")
	check(get_tree().paused, "single player: the game stops behind the end screen")
	check(not spawner.active, "no more waves after the end")

	# --- Victory: clear the last wave ---
	await start_game()
	spawner.wave_number = 10
	director._on_wave_cleared(10)
	await frames(3)
	check(director.result == MatchDirector.Result.VICTORY, "last wave cleared: victory")
	check(hud.end_screen.visible and hud.end_screen.title.text == "THE LINE HELD", "end screen: victory with statistics")
	check(hud.end_screen.stats.text.contains("Battles held: 10 / 10"), "statistics show battles held")

	# --- Hard ---
	get_tree().paused = false
	Settings.difficulty = 2
	await start_game()
	check(director.waves_to_win == 10 and director.trench_limit == 3 and (game as Game).respawn_time == 10.0 \
		and Enemy.spread_multiplier < 1.0, "Hard: 10 waves, breaks at 3, slower respawn, better enemy aim")
	check(is_equal_approx(Enemy.damage_multiplier, 1.0), "Hard: full enemy damage")

	# --- Easy: also 10 waves, softer bullets ---
	get_tree().paused = false
	Settings.difficulty = 0
	await start_game()
	check(director.waves_to_win == 10 and spawner.max_waves == 10, "Easy: 10 waves too")
	check(is_equal_approx(Enemy.damage_multiplier, 0.6), "Easy: enemy bullets do 0.6× damage")
	Settings.difficulty = 1
	Enemy.spread_multiplier = 1.0
	Enemy.damage_multiplier = 1.0

	# --- Test mode: start at wave 7 ---
	get_tree().paused = false
	MatchDirector.test_start_wave = 7
	await start_game()
	var dusk7: DuskLight = game.get_node("Dusk")
	check(director.test_wave == 7 and director.waves_cleared == 6 and spawner.wave_number == 6,
			"test mode: waves 1–6 count as held (cleared %d, spawner at %d)" % [director.waves_cleared, spawner.wave_number])
	check(is_equal_approx(dusk7.progress, 0.6), "test mode: the evening light starts at wave 7's (%.2f)" % dusk7.progress)
	check(not hud.day_screen.is_open and hud.wave_banner.modulate.a < 0.01, "test mode: no day screen or banner for the skipped waves")
	check(hud.test_tag.visible, "test mode: HUD shows TEST MODE")
	spawner.set_process(true)
	await seconds(director.test_first_wave_delay + 0.5)
	check(spawner.wave_number == 7 and hud.wave_label.text == "BATTLE 7 / 10", "test mode: battle 7 comes first ('%s')" % hud.wave_label.text)
	spawner.set_process(false)
	director._on_wave_cleared(7)
	await seconds(0.3)
	check(hud.day_screen.is_open, "test mode: the day screen comes after the chosen wave")
	MatchDirector.test_start_wave = 0
	await start_game()
	check(director.test_wave == 0 and spawner.wave_number == 0 and not hud.test_tag.visible, "normal battle again after test mode")

	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
