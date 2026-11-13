class_name RunSave
extends RefCounted
## D1: the saved run – "retry the lost battle" and "Continue" in the main menu.
##
## A RUN is one try at holding all the battles on one difficulty. Every time a battle is held the
## host writes a CHECKPOINT: the next battle, the difficulty and every player's totals so far.
## - Retry (end screen after a defeat) starts again from the checkpoint in memory.
## - Continue (main menu) first reads the checkpoint back from user://run.cfg.
## Saved next to settings.cfg (in a browser the browser stores it itself; a private window or
## "clear site data" loses it).
##
## Everything is static (shared by the whole game, like `MatchDirector.test_start_wave`), so it
## survives the scene change between the menu and the battle. Only the HOST reads and writes it.
## Test Mode and the benchmark never touch it (`active` is false there).

const SAVE_PATH: String = "user://run.cfg"
const TOTAL_KEYS: PackedStringArray = ["kills", "deaths", "shots", "hits"]

## True while the match being played belongs to a run (Single Player, Continue, Retry).
static var active: bool = false
static var difficulty: int = 1 ## The run's own difficulty (not changed by the menu mid-run).
static var battle: int = 1 ## The battle the next match starts at (1 = a fresh run).
static var retries: int = 0 ## Times a lost battle was tried again in this run.
static var time: float = 0.0 ## Match time at the checkpoint, seconds.
## Peer id (as text; "1" = the host) -> {kills, deaths, shots, hits} at the checkpoint.
static var totals: Dictionary = {}
## True when the file on disk belongs to THIS run. A new run only replaces an older saved run
## once its first battle is held, so a wrong click on Single Player loses nothing.
static var _file_is_ours: bool = false


## Single Player / "New run": a fresh run from battle 1. The old file stays for now.
static func start_new(new_difficulty: int) -> void:
	active = true
	difficulty = new_difficulty
	battle = 1
	retries = 0
	time = 0.0
	totals = {}
	_file_is_ours = false


## What the saved file holds, without changing anything: {} when there is no (usable) saved run,
## else {difficulty, battle, retries, time, totals}. The main menu uses it for the Continue button.
static func peek() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return {}
	var saved_battle: int = int(cfg.get_value("run", "battle", 0))
	if saved_battle < 2:
		return {}
	var saved_totals: Variant = cfg.get_value("run", "totals", {})
	return {
		"difficulty": clampi(int(cfg.get_value("run", "difficulty", 1)), 0, 2),
		"battle": saved_battle,
		"retries": maxi(int(cfg.get_value("run", "retries", 0)), 0),
		"time": maxf(float(cfg.get_value("run", "time", 0.0)), 0.0),
		"totals": saved_totals if saved_totals is Dictionary else {},
	}


## Continue: take the saved run into use. False when there is none.
static func load_saved() -> bool:
	var saved: Dictionary = peek()
	if saved.is_empty():
		return false
	active = true
	difficulty = saved.difficulty
	battle = saved.battle
	retries = saved.retries
	time = saved.time
	totals = saved.totals
	_file_is_ours = true
	return true


## Host: a battle was held – remember where the run stands and write it to the disk.
static func checkpoint(next_battle: int, match_time: float, players: Array[Node]) -> void:
	if not active:
		return
	battle = next_battle
	time = match_time
	totals = {}
	for node in players:
		var p := node as Player
		if p:
			totals[str(p.get_peer_id())] = {
				"kills": p.kills, "deaths": p.deaths,
				"shots": p.weapons.shots_fired, "hits": p.weapons.shots_hit,
			}
	_file_is_ours = true
	_write()


## Host: a match of the run starts – give the players their totals from the checkpoint back.
static func restore_player(p: Player) -> void:
	var t: Dictionary = totals.get(str(p.get_peer_id()), {})
	p.kills = int(t.get("kills", 0))
	p.deaths = int(t.get("deaths", 0))
	p.weapons.shots_fired = int(t.get("shots", 0))
	p.weapons.shots_hit = int(t.get("hits", 0))


## Retry after a defeat: the same checkpoint again, one more retry on the counter.
static func retry() -> void:
	active = true
	retries += 1
	if _file_is_ours:
		_write()


## Victory: the run is finished, nothing left to continue.
static func clear() -> void:
	if not active or not _file_is_ours:
		return
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	_file_is_ours = false


static func _write() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "difficulty", difficulty)
	cfg.set_value("run", "battle", battle)
	cfg.set_value("run", "retries", retries)
	cfg.set_value("run", "time", time)
	cfg.set_value("run", "totals", totals)
	cfg.save(SAVE_PATH)
