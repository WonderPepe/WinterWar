extends Control
## The first screen: start single player, or (later) host / join co-op.

const GAME_SCENE: String = "res://scenes/game.tscn"

@onready var single_button: Button = $Center/VBox/SinglePlayerButton
@onready var host_button: Button = $Center/VBox/HostCoopButton
@onready var join_button: Button = $Center/VBox/JoinCoopButton
@onready var quit_button: Button = $Center/VBox/QuitButton


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit_button.visible = not OS.has_feature("web") # a browser tab can't be "quit"
	single_button.pressed.connect(_on_single_player)
	quit_button.pressed.connect(get_tree().quit)
	host_button.disabled = true # co-op comes later
	join_button.disabled = true
	single_button.grab_focus()


func _on_single_player() -> void:
	NetworkManager.start_single_player()
	get_tree().change_scene_to_file(GAME_SCENE)
