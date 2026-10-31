class_name EndScreen
extends Control
## Shown when the battle is over: victory ("the line held") or defeat ("the line is broken"),
## with your statistics. Play again (single player) or back to the main menu.

const GAME_SCENE: String = "res://scenes/game.tscn"

@onready var title: Label = $Center/Panel/VBox/Title
@onready var subtitle: Label = $Center/Panel/VBox/Subtitle
@onready var stats: Label = $Center/Panel/VBox/Stats
@onready var again_button: Button = $Center/Panel/VBox/Buttons/PlayAgainButton
@onready var menu_button: Button = $Center/Panel/VBox/Buttons/MainMenuButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # works while the game is paused
	visible = false
	again_button.pressed.connect(_on_play_again)
	menu_button.pressed.connect(NetworkManager.leave_game)


func open(director: MatchDirector, player: Player) -> void:
	var won: bool = director.result == MatchDirector.Result.VICTORY
	title.text = "THE LINE HELD" if won else "THE LINE IS BROKEN"
	title.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0) if won else Color(1.0, 0.55, 0.45))
	subtitle.text = ("Dusk falls over Summa. The attack has failed." if won
			else "The Soviets are in the trench. The position is lost.")
	var shots: int = player.weapons.shots_fired
	var accuracy: int = roundi(100.0 * player.weapons.shots_hit / shots) if shots > 0 else 0
	var minutes: int = int(director.match_time) / 60
	stats.text = "Difficulty: %s\nWaves held: %d / %d\nKills: %d\nDeaths: %d\nHits: %d %%  (%d / %d shots)\nTime: %d min %02d s" % [
		director.get_difficulty_name(), director.waves_cleared, director.waves_to_win,
		player.kills, player.deaths, accuracy, player.weapons.shots_hit, shots,
		minutes, int(director.match_time) % 60]
	again_button.visible = NetworkManager.is_single_player()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NetworkManager.is_single_player():
		get_tree().paused = true
	(again_button if again_button.visible else menu_button).grab_focus()


func _on_play_again() -> void:
	NetworkManager.start_single_player()
	LoadingScreen.go(get_tree(), GAME_SCENE)
