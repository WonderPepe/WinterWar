class_name EndScreen
extends Control
## Shown when the battle is over: victory ("the line held") or defeat ("the line is broken"),
## with your statistics. D1: after a defeat "Retry battle n" plays the lost battle again, after a
## victory "New run" starts from battle 1 (single player); or back to the main menu.

const GAME_SCENE: String = "res://scenes/game.tscn"

@onready var title: Label = $Center/Panel/VBox/Title
@onready var subtitle: Label = $Center/Panel/VBox/Subtitle
@onready var stats: Label = $Center/Panel/VBox/Stats
@onready var report: Label = $Center/Panel/VBox/Report
@onready var again_button: Button = $Center/Panel/VBox/Buttons/PlayAgainButton
var _won: bool = false
var _lost_battle: int = 1 ## The battle the line broke in.

@onready var menu_button: Button = $Center/Panel/VBox/Buttons/MainMenuButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # works while the game is paused
	visible = false
	again_button.pressed.connect(_on_play_again)
	menu_button.pressed.connect(NetworkManager.leave_game)


func open(director: MatchDirector, player: Player, reports: FrontReports = null) -> void:
	var won: bool = director.result == MatchDirector.Result.VICTORY
	_won = won
	_lost_battle = clampi(director.waves_cleared + 1, 1, maxi(director.waves_to_win, 1))
	again_button.text = "New run" if won else "Retry battle %d" % _lost_battle
	title.text = "THE LINE HELD" if won else "THE LINE IS BROKEN"
	title.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0) if won else Color(1.0, 0.55, 0.45))
	subtitle.text = ("Dusk falls over Summa. The attack has failed." if won
			else "The Soviets are in the trench. The position is lost.")
	# Victory: the date of the last battle held (the briefings are shown before the battles).
	var r: PackedStringArray = reports.get_report(director.waves_cleared) if reports and won else PackedStringArray()
	report.visible = r.size() == 2
	if report.visible:
		report.text = r[0]
	var shots: int = player.weapons.shots_fired
	var accuracy: int = roundi(100.0 * player.weapons.shots_hit / shots) if shots > 0 else 0
	var minutes: int = int(director.match_time) / 60
	# D1: in a run the numbers cover the whole run (they are carried over a retry / Continue).
	stats.text = "Difficulty: %s\nBattles held: %d / %d\nKills: %d\nDeaths: %d\nHits: %d %%  (%d / %d shots)\nTime: %d min %02d s" % [
		director.get_difficulty_name(), director.waves_cleared, director.waves_to_win,
		player.kills, player.deaths, accuracy, player.weapons.shots_hit, shots,
		minutes, int(director.match_time) % 60]
	if director.is_run():
		stats.text += "\nRetries: %d" % RunSave.retries
	again_button.visible = NetworkManager.is_single_player()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NetworkManager.is_single_player():
		get_tree().paused = true
	(again_button if again_button.visible else menu_button).grab_focus()


## Single player. Defeat: the lost battle again, from the last checkpoint (the numbers of the
## failed try are dropped). Victory: a new run from battle 1.
func _on_play_again() -> void:
	prepare_again()
	NetworkManager.start_single_player()
	LoadingScreen.go(get_tree(), GAME_SCENE)


## Sets up what the next match starts as (separate from the scene change, so it can be tested).
func prepare_again() -> void:
	if MatchDirector.test_start_wave > 0:
		if not _won:
			MatchDirector.test_start_wave = _lost_battle # Test mode: no saved run involved
	elif _won:
		RunSave.start_new(Settings.difficulty)
	else:
		if not RunSave.active:
			# The game scene was started on its own (editor): make it a run at the lost battle.
			RunSave.start_new(Settings.difficulty)
			RunSave.battle = _lost_battle
		RunSave.retry()
