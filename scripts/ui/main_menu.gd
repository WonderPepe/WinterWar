class_name MainMenu
extends Control
## The first screen: start single player, or (later) host / join co-op.

const GAME_SCENE: String = "res://scenes/game.tscn"
const BENCHMARK_SCENE: String = "res://scenes/benchmark.tscn"

## Time the last "start" button was pressed (used by the benchmark to measure load time).
static var start_pressed_msec: int = 0

@onready var single_button: Button = $Center/VBox/SinglePlayerButton
@onready var host_button: Button = $Center/VBox/HostCoopButton
@onready var join_button: Button = $Center/VBox/JoinCoopButton
@onready var quit_button: Button = $Center/VBox/QuitButton
@onready var settings_button: Button = $Center/VBox/SettingsButton
@onready var benchmark_button: Button = $Center/VBox/BenchmarkButton
@onready var credits_button: Button = $Center/VBox/CreditsButton
@onready var credits: Control = $Credits
@onready var credits_back: Button = $Credits/Panel/VBox/BackButton
@onready var menu_box: Control = $Center
@onready var settings_menu: SettingsMenu = $SettingsMenu
@onready var difficulty_option: OptionButton = $Center/VBox/DifficultyRow/DifficultyOption
@onready var version_label: Label = $Version


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit_button.visible = not OS.has_feature("web") # a browser tab can't be "quit"
	# The version number comes from Project Settings → Application → Config → Version.
	version_label.text = "Prototype · v%s" % ProjectSettings.get_setting("application/config/version", "?")
	single_button.pressed.connect(_on_single_player)
	difficulty_option.select(clampi(Settings.difficulty, 0, difficulty_option.item_count - 1))
	difficulty_option.item_selected.connect(Settings.set_difficulty)
	benchmark_button.pressed.connect(_on_benchmark)
	settings_button.pressed.connect(func() -> void:
		menu_box.visible = false
		settings_menu.open())
	settings_menu.closed.connect(func() -> void:
		menu_box.visible = true
		settings_button.grab_focus())
	settings_menu.visible = false
	credits_button.pressed.connect(func() -> void:
		menu_box.visible = false
		credits.visible = true
		credits_back.grab_focus())
	credits_back.pressed.connect(func() -> void:
		credits.visible = false
		menu_box.visible = true
		credits_button.grab_focus())
	quit_button.pressed.connect(get_tree().quit)
	host_button.disabled = true # co-op comes later
	join_button.disabled = true
	single_button.grab_focus()


func _on_single_player() -> void:
	start_pressed_msec = Time.get_ticks_msec()
	NetworkManager.start_single_player()
	LoadingScreen.go(get_tree(), GAME_SCENE) # with a progress bar


func _on_benchmark() -> void:
	start_pressed_msec = Time.get_ticks_msec()
	NetworkManager.start_single_player()
	LoadingScreen.go(get_tree(), BENCHMARK_SCENE)
