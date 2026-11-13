class_name MatchDirector
extends Node
## The rules of one battle: "hold the line until dusk".
##
## Runs on the HOST (in co-op the others only read the synced values below, via MatchSync):
## - applies the difficulty chosen in the main menu (DifficultyData),
## - wins the match when the last wave is cleared,
## - loses it when too many Soviets are inside the trench at the same time (not while the players
##   are retaking a captured trench, L3 battle 6 – the Soviets are in it then by definition),
## - patches everyone up (full health) after every cleared wave,
## - puts everyone back at their start spot for the next battle (behind the black day screen).

signal match_ended(result: int)

enum Result { PLAYING, VICTORY, DEFEAT }

@export var difficulties: Array[DifficultyData] = [] ## Easy, Normal, Hard.
@export var check_interval: float = 0.25 ## Seconds between "how many are in the trench?" counts.
@export var test_first_wave_delay: float = 3.0 ## Test mode: seconds before the chosen wave starts.
## Seconds after a cleared battle before the players are moved back to their start spots.
## The day screen shows "BATTLE n COMPLETED" for 2.5 s, then fades to black in 1 s.
@export var reset_players_delay: float = 3.8

## Test mode (main menu, only in the Godot editor): the battle starts at this wave (0 = normal).
## Kept for "Play again"; the normal Single Player button sets it back to 0.
static var test_start_wave: int = 0

# --- Synced from the host by MatchSync ---
var difficulty: int = 1
var waves_to_win: int = 8
var trench_limit: int = 4
var in_trench: int = 0 ## Living Soviets inside the trench right now.
var waves_cleared: int = 0
var result: int = Result.PLAYING:
	set = _set_result
var match_time: float = 0.0 ## Seconds since the match started (stops at the end).
var test_wave: int = 0 ## Test mode: the wave this battle started at (0 = a normal battle).
## The wave this match started at when the earlier ones were skipped: Test mode, or D1 a retried /
## continued run (0 = from battle 1). The HUD shows no banners or day screens for the skipped ones.
var start_wave: int = 0

var _check_timer: float = 0.0
var _run_restored: bool = false ## D1: the players have got their saved totals back.

@onready var spawner: WaveSpawner = get_parent().get_node("WaveSpawner")


func _ready() -> void:
	add_to_group("match_director")
	if not multiplayer.is_server():
		return
	# D1: a run keeps the difficulty it was started on; Test mode uses the menu's.
	var in_run: bool = RunSave.active and test_start_wave <= 0
	difficulty = clampi(RunSave.difficulty if in_run else Settings.difficulty, 0, maxi(difficulties.size() - 1, 0))
	if difficulties.is_empty():
		return
	var d: DifficultyData = difficulties[difficulty]
	waves_to_win = d.waves_to_win
	trench_limit = d.trench_limit
	spawner.base_enemies = d.base_enemies
	spawner.enemies_added_per_wave = d.enemies_added_per_wave
	spawner.wave_list = d.waves
	spawner.max_waves = d.waves_to_win
	Enemy.spread_multiplier = d.enemy_spread_multiplier
	Enemy.damage_multiplier = d.enemy_damage_multiplier
	var game := get_parent() as Game
	if game:
		game.respawn_time = d.respawn_time
	spawner.wave_cleared.connect(_on_wave_cleared)
	if test_start_wave > 0:
		_start_test_mode(clampi(test_start_wave, 1, maxi(waves_to_win, 1)))
	elif in_run and RunSave.battle > 1:
		# D1: retry / continue – the battles before the saved one are already held.
		match_time = RunSave.time
		_start_at_wave(clampi(RunSave.battle, 1, maxi(waves_to_win, 1)))


## True when this match is part of a saved run (D1) – not Test mode, not the benchmark or tests.
func is_run() -> bool:
	return RunSave.active and test_wave == 0


## Test mode: pretend the earlier waves were already held (evening light, front reports),
## then send the chosen wave soon.
func _start_test_mode(wave: int) -> void:
	test_wave = wave
	_start_at_wave(wave)


## Host: start the match at `wave` as if the earlier ones had been held.
func _start_at_wave(wave: int) -> void:
	start_wave = wave
	waves_cleared = wave - 1
	spawner.start_at_wave(wave, test_first_wave_delay)


func get_difficulty_name() -> String:
	if difficulty < difficulties.size():
		return difficulties[difficulty].display_name
	return ""


## 0 at the start of the battle ... 1 when the last wave has been cleared (dusk).
func get_day_progress() -> float:
	return clampf(float(waves_cleared) / maxf(waves_to_win, 1), 0.0, 1.0)


func is_over() -> bool:
	return result != Result.PLAYING


func _process(delta: float) -> void:
	if not multiplayer.is_server() or is_over():
		return
	if not _run_restored:
		# D1: once, when the players exist – their kills, deaths and shots so far in this run.
		_run_restored = true
		if is_run():
			for node in get_tree().get_nodes_in_group("players"):
				RunSave.restore_player(node as Player)
	match_time += delta
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = check_interval
	if spawner.retaking:
		in_trench = 0 # L3: they hold it – the players are taking it back, no "line broken" defeat
		return
	var count: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e and e.state != Enemy.State.DEAD and e.is_in_trench():
			count += 1
	in_trench = count
	if in_trench >= trench_limit:
		end_match(Result.DEFEAT)


func _on_wave_cleared(number: int) -> void:
	waves_cleared = number
	# Between waves the medics patch everyone up.
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if not p.is_dead:
			p.heal(p.max_health)
	if number >= waves_to_win:
		if is_run():
			RunSave.clear() # the run is finished: nothing left to continue
		end_match(Result.VICTORY)
		return
	if is_run():
		# D1: checkpoint – Retry and Continue start at the next battle with these totals.
		RunSave.checkpoint(number + 1, match_time, get_tree().get_nodes_in_group("players"))
	_reset_players_later()


## Host: a new day – move the players back once the screen has gone black.
func _reset_players_later() -> void:
	await get_tree().create_timer(reset_players_delay, false).timeout
	if is_over():
		return
	var game := get_parent() as Game
	if game:
		game.reset_players_to_start()


## Host: the battle is over. The soldiers stop where they are.
func end_match(r: int) -> void:
	if not multiplayer.is_server() or is_over():
		return
	result = r
	spawner.active = false
	for node in get_tree().get_nodes_in_group("enemies"):
		(node as Enemy).freeze()
	for node in get_tree().get_nodes_in_group("tanks"):
		(node as Tank).freeze()


func _set_result(value: int) -> void:
	var changed: bool = value != result
	result = value
	if changed and value != Result.PLAYING:
		Game.set_leave_warning(false) # the battle is over: closing the tab needs no warning
		match_ended.emit(value)
