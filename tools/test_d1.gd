extends Node
## Automated test for D1 "retry the lost battle / continue a run" (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_d1.gd
## Uses user://run.cfg; a file that was there before the test is put back at the end.

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


func start_game() -> void:
	if game:
		game.queue_free()
		await frames(2)
	get_tree().paused = false
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await frames(5)
	for i in 5:
		await get_tree().physics_frame
	p = get_tree().get_first_node_in_group("players")
	director = get_tree().get_first_node_in_group("match_director")
	spawner = get_tree().get_first_node_in_group("wave_spawner")
	hud = game.get_node("HUD")
	p.input.set_process(false)
	spawner.set_process(false) # no soldiers: the test "holds" the battles itself


func menu_continue() -> Button:
	var menu: Control = load("res://ui/main_menu.tscn").instantiate()
	add_child(menu)
	var b: Button = menu.get_node("Center/VBox/ContinueButton")
	remove_child(menu)
	menu.queue_free()
	return b


func _ready() -> void:
	await get_tree().process_frame
	var backup: String = FileAccess.get_file_as_string(RunSave.SAVE_PATH) if FileAccess.file_exists(RunSave.SAVE_PATH) else ""
	if backup != "":
		DirAccess.remove_absolute(RunSave.SAVE_PATH)
	MatchDirector.test_start_wave = 0
	Settings.difficulty = 1

	# --- No saved run ---
	var b: Button = menu_continue()
	check(not b.visible and RunSave.peek().is_empty(), "no saved run: no Continue button")

	# --- A new run on Easy; the menu is then switched to Normal ---
	RunSave.start_new(0)
	await start_game()
	check(director.is_run() and director.get_difficulty_name() == "Easy" and director.start_wave == 0, "new run: battle 1 on the run's difficulty (Easy)")
	check(not FileAccess.file_exists(RunSave.SAVE_PATH), "nothing is saved before a battle is held")
	p.kills = 5
	p.weapons.shots_fired = 20
	p.weapons.shots_hit = 8
	director.match_time = 100.0
	director._on_wave_cleared(1)
	var s: Dictionary = RunSave.peek()
	check(s.get("battle", 0) == 2 and s.get("difficulty", -1) == 0 and s.totals.get("1", {}).get("kills", 0) == 5,
			"battle 1 held: saved – next battle 2, Easy, 5 kills")
	p.kills = 12
	p.deaths = 2
	director.match_time = 300.0
	director._on_wave_cleared(2)
	director._on_wave_cleared(3)
	check(RunSave.peek().get("battle", 0) == 4, "battles 2–3 held: the save moves on to battle 4")

	# --- Battle 4 is lost ---
	p.kills = 15 # three more in the lost battle
	p.deaths = 4
	director.match_time = 380.0
	director.end_match(MatchDirector.Result.DEFEAT)
	await frames(3)
	var es: EndScreen = hud.end_screen
	check(es.visible and es.again_button.visible and es.again_button.text == "Retry battle 4", "defeat: the button says '%s'" % es.again_button.text)
	check(es.stats.text.contains("Retries: 0") and es.stats.text.contains("Kills: 15"), "defeat screen: the try's numbers and Retries: 0")
	es.prepare_again()
	check(RunSave.retries == 1 and RunSave.peek().get("retries", 0) == 1, "Retry: counted and saved")
	await start_game()
	await frames(3)
	check(director.start_wave == 4 and director.waves_cleared == 3 and spawner.wave_number == 3 and director.test_wave == 0,
			"retry: the match starts at battle 4 (start %d, cleared %d)" % [director.start_wave, director.waves_cleared])
	check(p.kills == 12 and p.deaths == 2 and p.weapons.shots_fired == 20 and p.weapons.shots_hit == 8,
			"retry: totals back to the checkpoint – the lost try is dropped (kills %d, deaths %d)" % [p.kills, p.deaths])
	check(director.match_time >= 300.0 and director.match_time < 310.0, "retry: the time goes on from the checkpoint (%.0f s)" % director.match_time)
	check(not hud.test_tag.visible and director.get_difficulty_name() == "Easy", "retry: no TEST tag, still Easy")
	check(not hud.day_screen.is_open and hud.wave_banner.modulate.a < 0.01, "retry: no day screen or banner for the battles already held")
	var dusk: DuskLight = game.get_node("Dusk")
	check(dusk.battle == 4, "retry: the weather of battle 4")

	# --- Continue from the main menu (as after closing the game) ---
	RunSave.active = false
	RunSave.battle = 1
	RunSave.totals = {}
	RunSave.retries = 0
	b = menu_continue()
	check(b.visible and b.text == "Continue – Battle 4 (Easy)", "main menu: '%s'" % b.text)
	check(RunSave.load_saved() and RunSave.battle == 4 and RunSave.retries == 1 and RunSave.difficulty == 0, "Continue reads the saved run")
	await start_game()
	await frames(3)
	check(director.start_wave == 4 and p.kills == 12 and director.get_difficulty_name() == "Easy",
			"continue: battle 4, 12 kills, Easy although the menu says Normal")
	director._on_wave_cleared(4)
	await frames(3)
	check(hud.day_screen.is_open, "continue: the day screen comes after the battle that was played")

	# --- Loading screen: the briefing of the battle the run goes on from ---
	RunSave.battle = 9
	LoadingScreen.target_scene = "res://ui/controls_panel.tscn"
	LoadingScreen.click_to_start = true
	var ls: Node = load("res://ui/loading_screen.tscn").instantiate()
	add_child(ls)
	await get_tree().process_frame
	var found: bool = false
	for l in ls.find_children("*", "Label", true, false):
		found = found or (l as Label).text == "13 February 1940"
	check(found, "loading screen: briefing of the continued battle (9 = 13 February 1940)")
	ls.free()

	# --- A new run only replaces the saved one when its battle 1 is held ---
	RunSave.start_new(1)
	await start_game()
	check(director.get_difficulty_name() == "Normal" and director.start_wave == 0 and p.kills == 0, "new run: Normal, battle 1, zero kills")
	check(RunSave.peek().get("battle", 0) == 5 and RunSave.peek().get("difficulty", -1) == 0, "the old saved run is still there")
	director.end_match(MatchDirector.Result.DEFEAT)
	await frames(3)
	check(hud.end_screen.again_button.text == "Retry battle 1", "lost in battle 1: 'Retry battle 1'")
	hud.end_screen.prepare_again()
	check(RunSave.peek().get("battle", 0) == 5 and RunSave.peek().get("retries", -1) == 1, "…and that retry does not touch the old save")
	await start_game()
	await frames(3)
	check(director.start_wave == 0 and spawner.wave_number == 0 and RunSave.retries == 1, "retry of battle 1 starts at battle 1")
	director._on_wave_cleared(1)
	s = RunSave.peek()
	check(s.get("battle", 0) == 2 and s.get("difficulty", -1) == 1 and s.get("retries", -1) == 1, "battle 1 held: now the new run is the saved one")

	# --- Victory ends the run ---
	director._on_wave_cleared(10)
	await frames(3)
	check(not FileAccess.file_exists(RunSave.SAVE_PATH) and RunSave.peek().is_empty(), "victory: the saved run is removed")
	check(hud.end_screen.visible and hud.end_screen.again_button.text == "New run" and hud.end_screen.stats.text.contains("Retries: 1"),
			"victory: 'New run' and Retries: 1")
	hud.end_screen.prepare_again()
	check(RunSave.active and RunSave.battle == 1 and RunSave.retries == 0, "New run: a fresh run from battle 1")
	b = menu_continue()
	check(not b.visible, "main menu after the victory: no Continue button")

	# --- Test mode never touches the saved run ---
	MatchDirector.test_start_wave = 5
	await start_game()
	await frames(3)
	check(not director.is_run() and director.start_wave == 5 and hud.test_tag.visible, "test mode: not a run, TEST tag shown")
	director._on_wave_cleared(5)
	check(not FileAccess.file_exists(RunSave.SAVE_PATH), "test mode: nothing saved")
	director.end_match(MatchDirector.Result.DEFEAT)
	await frames(3)
	hud.end_screen.prepare_again()
	check(MatchDirector.test_start_wave == 6 and hud.end_screen.again_button.text == "Retry battle 6", "test mode: Retry stays in test mode at the lost battle")
	MatchDirector.test_start_wave = 0

	# --- A broken or strange file is ignored ---
	var f := FileAccess.open(RunSave.SAVE_PATH, FileAccess.WRITE)
	f.store_string("this is not a save file")
	f.close()
	check(RunSave.peek().is_empty() and not RunSave.load_saved(), "a broken save file is ignored")
	RunSave.start_new(1)
	RunSave.battle = 99
	RunSave.active = true
	await start_game()
	check(director.start_wave == 10, "a battle number past the end is clamped to the last battle")

	# Clean up: back to "not in a run", the earlier file (if any) back in place.
	RunSave.active = false
	RunSave.battle = 1
	DirAccess.remove_absolute(RunSave.SAVE_PATH)
	if backup != "":
		f = FileAccess.open(RunSave.SAVE_PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	print("RESULT: %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
