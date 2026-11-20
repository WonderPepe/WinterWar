extends Node
## Automated test for TC1 "clear the trench" (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_tc1.gd
## When `trench_limit` Soviets are in the trench, a `trench_clear_time` (30 s) countdown starts.
## Kill them below the limit and it goes back to the full time; run out and the line is broken.

var game: Node
var p: Player
var director: MatchDirector
var spawner: WaveSpawner
var hud: HUD
var fails := 0
var _slot: int = 0 ## Next free spot along the trench for a test soldier.


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
	p.god_mode = true
	spawner.set_process(false) # the test puts the soldiers in the trench itself
	hud.day_screen.close_now()
	_slot = 0


## A Soviet standing still in the trench (frozen: he neither moves nor shoots – only the count matters).
func trench_soviet() -> Enemy:
	var e: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
	e.name = "TC1Enemy_%d" % Time.get_ticks_usec()
	var pos := Vector3(-60.0 + _slot * 6.0, -1.3, 61.0)
	_slot += 1
	e.position = pos
	e.attack_point = pos
	game.get_node("Enemies").add_child(e, true)
	e.state = Enemy.State.ASSAULT
	e.freeze()
	e.global_position = pos
	return e


func kill(e: Enemy) -> void:
	e.take_damage(10000.0, 1, e.global_position + Vector3.UP, Vector3.UP)


func run() -> void:
	# --- The same limit on every difficulty ---
	Settings.difficulty = 1
	await start_game()
	var limits: Array = []
	for d in director.difficulties:
		limits.append([d.trench_limit, d.trench_clear_time])
	check(limits == [[6, 30.0], [6, 30.0], [6, 30.0]], "Easy / Normal / Hard: 6 in the trench, 30 s to clear it (%s)" % str(limits))
	check(director.trench_limit == 6 and is_equal_approx(director.trench_clear_time, 30.0), "Normal match: limit 6, 30 s")

	# --- Below the limit: no countdown ---
	var men: Array[Enemy] = []
	for i in 5:
		men.append(trench_soviet())
	await seconds(0.6)
	check(director.in_trench == 5 and director.breach_time_left < 0.0, "5 / 6 in the trench: no countdown (%d, %.1f)" % [director.in_trench, director.breach_time_left])
	await frames(2)
	check(hud.trench_label.visible and not hud.trench_label.text.contains("CLEAR IT"), "HUD: '%s'" % hud.trench_label.text)

	# --- The 6th jumps in: the countdown starts ---
	men.append(trench_soviet())
	await seconds(0.6)
	var t0: float = director.breach_time_left
	check(director.in_trench == 6 and t0 > 29.0 and t0 <= 30.0, "6 / 6: the 30 s countdown starts (%.2f s left)" % t0)
	check(director.result == MatchDirector.Result.PLAYING, "no defeat at once")
	await frames(2)
	check(hud.trench_label.text.contains("6 / 6") and hud.trench_label.text.contains("CLEAR IT: 30 s"), "HUD: '%s'" % hud.trench_label.text)
	await seconds(10.0)
	check(director.breach_time_left > 18.5 and director.breach_time_left < 20.5 and director.result == MatchDirector.Result.PLAYING,
		"10 s later: about 20 s left, still holding (%.2f)" % director.breach_time_left)

	# --- Kill one: below the limit, the clock is reset ---
	kill(men.pop_back())
	await seconds(0.6)
	check(director.in_trench == 5 and director.breach_time_left < 0.0, "one killed (5 / 6): countdown stopped (%.1f)" % director.breach_time_left)
	await frames(2)
	check(not hud.trench_label.text.contains("CLEAR IT"), "HUD: no countdown ('%s')" % hud.trench_label.text)

	# --- Full again: the full 30 s again, not what was left ---
	men.append(trench_soviet())
	await seconds(0.6)
	check(director.breach_time_left > 29.0, "6 / 6 again: back to the full 30 s (%.2f)" % director.breach_time_left)
	await seconds(21.0)
	await frames(2)
	check(director.breach_time_left > 0.0 and director.breach_time_left <= 10.0, "last 10 s (%.2f)" % director.breach_time_left)
	check(hud.trench_label.get_theme_color("font_color") == HUD.TRENCH_URGENT, "HUD: the countdown turns red in the last 10 s")

	# --- More than the limit doesn't end it early (no hard cap, owner) ---
	men.append(trench_soviet())
	men.append(trench_soviet())
	await seconds(0.6)
	check(director.in_trench == 8 and director.result == MatchDirector.Result.PLAYING, "8 / 6: still the countdown, no instant defeat")

	# --- Time runs out ---
	await seconds(director.breach_time_left + 0.6)
	check(director.result == MatchDirector.Result.DEFEAT, "the countdown ran out: the line is broken")
	await frames(3)
	check(hud.end_screen.visible and hud.end_screen.title.text == "THE LINE IS BROKEN", "end screen: defeat")

	# --- Battle 6 "retake the trench": no countdown while the Soviets hold it ---
	get_tree().paused = false
	await start_game()
	spawner.retaking = true
	for i in 7:
		trench_soviet()
	await seconds(1.0)
	check(director.breach_time_left < 0.0 and director.result == MatchDirector.Result.PLAYING, "retaking the trench: no countdown")
	spawner.retaking = false

	# --- 0 s to clear = the old rule (the line breaks at once) ---
	await start_game()
	director.trench_clear_time = 0.0
	for i in 6:
		trench_soviet()
	await seconds(0.6)
	check(director.result == MatchDirector.Result.DEFEAT, "trench_clear_time 0: broken at once (old rule)")

	get_tree().paused = false
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()
