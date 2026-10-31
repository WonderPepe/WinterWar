class_name MatchDirector
extends Node
## The rules of one battle: "hold the line until dusk".
##
## Runs on the HOST (in co-op the others only read the synced values below, via MatchSync):
## - applies the difficulty chosen in the main menu (DifficultyData),
## - wins the match when the last wave is cleared,
## - loses it when too many Soviets are inside the trench at the same time,
## - patches everyone up (full health) after every cleared wave.

signal match_ended(result: int)

enum Result { PLAYING, VICTORY, DEFEAT }

@export var difficulties: Array[DifficultyData] = [] ## Easy, Normal, Hard.
@export var check_interval: float = 0.25 ## Seconds between "how many are in the trench?" counts.

# --- Synced from the host by MatchSync ---
var difficulty: int = 1
var waves_to_win: int = 8
var trench_limit: int = 4
var in_trench: int = 0 ## Living Soviets inside the trench right now.
var waves_cleared: int = 0
var result: int = Result.PLAYING:
	set = _set_result
var match_time: float = 0.0 ## Seconds since the match started (stops at the end).

var _check_timer: float = 0.0

@onready var spawner: WaveSpawner = get_parent().get_node("WaveSpawner")


func _ready() -> void:
	add_to_group("match_director")
	if not multiplayer.is_server():
		return
	difficulty = clampi(Settings.difficulty, 0, maxi(difficulties.size() - 1, 0))
	if difficulties.is_empty():
		return
	var d: DifficultyData = difficulties[difficulty]
	waves_to_win = d.waves_to_win
	trench_limit = d.trench_limit
	spawner.base_enemies = d.base_enemies
	spawner.enemies_added_per_wave = d.enemies_added_per_wave
	spawner.max_waves = d.waves_to_win
	Enemy.spread_multiplier = d.enemy_spread_multiplier
	var game := get_parent() as Game
	if game:
		game.respawn_time = d.respawn_time
	spawner.wave_cleared.connect(_on_wave_cleared)


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
	match_time += delta
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = check_interval
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
		end_match(Result.VICTORY)


## Host: the battle is over. The soldiers stop where they are.
func end_match(r: int) -> void:
	if not multiplayer.is_server() or is_over():
		return
	result = r
	spawner.active = false
	for node in get_tree().get_nodes_in_group("enemies"):
		(node as Enemy).freeze()


func _set_result(value: int) -> void:
	var changed: bool = value != result
	result = value
	if changed and value != Result.PLAYING:
		match_ended.emit(value)
