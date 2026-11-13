class_name MainMenu
extends Control
## The first screen: start single player, or (later) host / join co-op.

const GAME_SCENE: String = "res://scenes/game.tscn"
const BENCHMARK_SCENE: String = "res://scenes/benchmark.tscn"

## Time the last "start" button was pressed (used by the benchmark to measure load time).
static var start_pressed_msec: int = 0

@onready var continue_button: Button = $Center/VBox/ContinueButton
@onready var single_button: Button = $Center/VBox/SinglePlayerButton
@onready var host_button: Button = $Center/VBox/HostCoopButton
@onready var join_button: Button = $Center/VBox/JoinCoopButton
@onready var quit_button: Button = $Center/VBox/QuitButton
@onready var settings_button: Button = $Center/VBox/SettingsButton
@onready var benchmark_button: Button = $Center/VBox/BenchmarkButton
@onready var credits_button: Button = $Center/VBox/CreditsButton
@onready var credits: Control = $Credits
@onready var credits_back: Button = $Credits/Panel/VBox/BackButton
@onready var credits_scroll: ScrollContainer = $Credits/Panel/VBox/Scroll
@onready var menu_box: Control = $Center
@onready var settings_menu: SettingsMenu = $SettingsMenu
@onready var controls_button: Button = $Center/VBox/ControlsButton
@onready var controls_panel: ControlsPanel = $ControlsPanel
@onready var difficulty_option: OptionButton = $Center/VBox/DifficultyRow/DifficultyOption
@onready var version_label: Label = $Version
@onready var test_button: Button = $Center/VBox/TestModeButton
@onready var test_panel: Control = $TestMode
@onready var test_wave: SpinBox = $TestMode/Panel/VBox/WaveRow/WaveSpin
@onready var test_info: Label = $TestMode/Panel/VBox/Info
@onready var test_start: Button = $TestMode/Panel/VBox/StartButton
@onready var test_back: Button = $TestMode/Panel/VBox/BackButton


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit_button.visible = not OS.has_feature("web") # a browser tab can't be "quit"
	# The version number comes from Project Settings → Application → Config → Version.
	version_label.text = "Prototype · v%s" % ProjectSettings.get_setting("application/config/version", "?")
	single_button.pressed.connect(_on_single_player)
	difficulty_option.select(clampi(Settings.difficulty, 0, difficulty_option.item_count - 1))
	# D1: Continue is only there when a saved run exists; it names the battle and the run's difficulty.
	var saved: Dictionary = RunSave.peek()
	continue_button.visible = not saved.is_empty()
	if continue_button.visible:
		continue_button.text = "Continue – Battle %d (%s)" % [saved.battle,
				difficulty_option.get_item_text(clampi(saved.difficulty, 0, difficulty_option.item_count - 1))]
	continue_button.pressed.connect(_on_continue)
	difficulty_option.item_selected.connect(Settings.set_difficulty)
	benchmark_button.pressed.connect(_on_benchmark)
	settings_button.pressed.connect(func() -> void:
		menu_box.visible = false
		settings_menu.open())
	settings_menu.closed.connect(func() -> void:
		menu_box.visible = true
		settings_button.grab_focus())
	settings_menu.visible = false
	controls_button.pressed.connect(func() -> void:
		menu_box.visible = false
		controls_panel.open())
	controls_panel.closed.connect(func() -> void:
		menu_box.visible = true
		controls_button.grab_focus())
	controls_panel.visible = false
	credits_button.pressed.connect(func() -> void:
		menu_box.visible = false
		credits.visible = true
		credits_scroll.scroll_vertical = 0 # start at the top
		credits_back.grab_focus())
	credits_back.pressed.connect(_close_credits)
	quit_button.pressed.connect(get_tree().quit)
	# Test mode: start the battle at any wave. Only when run from the Godot editor.
	test_button.visible = OS.has_feature("editor")
	test_panel.visible = false
	test_wave.value = clampi(MatchDirector.test_start_wave, 1, int(test_wave.max_value))
	test_button.pressed.connect(func() -> void:
		menu_box.visible = false
		test_info.text = "Difficulty: %s (change it in the main menu)" % difficulty_option.get_item_text(difficulty_option.selected)
		test_panel.visible = true
		test_start.grab_focus())
	test_back.pressed.connect(func() -> void:
		test_panel.visible = false
		menu_box.visible = true
		test_button.grab_focus())
	test_start.pressed.connect(_on_test_start)
	if test_button.visible and continue_button.visible and quit_button.visible:
		# Only in the editor: with both extra buttons the list is one row too tall for 720 p.
		(single_button.get_parent() as VBoxContainer).add_theme_constant_override("separation", 3)
	host_button.disabled = true # co-op comes later
	join_button.disabled = true
	(continue_button if continue_button.visible else single_button).grab_focus()


## D1: go on with the saved run, from the battle after the last one held.
func _on_continue() -> void:
	if not RunSave.load_saved():
		continue_button.visible = false # the file has gone meanwhile
		return
	MatchDirector.test_start_wave = 0
	start_pressed_msec = Time.get_ticks_msec()
	NetworkManager.start_single_player()
	LoadingScreen.go(get_tree(), GAME_SCENE)


## A new run from battle 1 (an older saved run is only replaced once battle 1 is held).
func _on_single_player() -> void:
	MatchDirector.test_start_wave = 0
	RunSave.start_new(Settings.difficulty)
	start_pressed_msec = Time.get_ticks_msec()
	NetworkManager.start_single_player()
	LoadingScreen.go(get_tree(), GAME_SCENE) # with a progress bar


func _on_test_start() -> void:
	MatchDirector.test_start_wave = int(test_wave.value)
	RunSave.active = false # Test mode never touches the saved run
	start_pressed_msec = Time.get_ticks_msec()
	NetworkManager.start_single_player()
	LoadingScreen.go(get_tree(), GAME_SCENE)


func _on_benchmark() -> void:
	MatchDirector.test_start_wave = 0
	RunSave.active = false
	start_pressed_msec = Time.get_ticks_msec()
	NetworkManager.start_single_player()
	LoadingScreen.go(get_tree(), BENCHMARK_SCENE, false) # the benchmark runs on its own


func _close_credits() -> void:
	credits.visible = false
	menu_box.visible = true
	credits_button.grab_focus()


## Esc (ui_cancel) closes the credits too.
func _unhandled_input(event: InputEvent) -> void:
	if credits.visible and event.is_action_pressed("ui_cancel"):
		_close_credits()
		get_viewport().set_input_as_handled()
