extends CanvasLayer
## Esc menu: Resume / Main Menu. It also opens by itself whenever the mouse is not
## captured - in a browser the mouse can only be locked after a click, so this menu
## doubles as the "click to play" screen.
## In single player the game pauses; in co-op (later) it will only show the menu.

const RECAPTURE_GRACE: float = 0.5 ## Seconds to let the browser lock the mouse after Resume.

var is_open: bool = false
var _ignore_until: float = 0.0

@onready var root: Control = $Root
@onready var resume_button: Button = $Root/Panel/VBox/ResumeButton
@onready var menu_button: Button = $Root/Panel/VBox/MainMenuButton
@onready var settings_button: Button = $Root/Panel/VBox/SettingsButton
@onready var panel: Control = $Root/Panel
@onready var settings_menu: SettingsMenu = $Root/SettingsMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps working while the game is paused
	resume_button.pressed.connect(resume)
	menu_button.pressed.connect(NetworkManager.leave_game)
	settings_button.pressed.connect(func() -> void:
		panel.visible = false
		settings_menu.open())
	settings_menu.closed.connect(func() -> void:
		panel.visible = true
		settings_button.grab_focus())
	settings_menu.visible = false
	_ignore_until = _now() + RECAPTURE_GRACE
	_close()


func _process(_delta: float) -> void:
	# Mouse got released (browser Esc, alt-tab, or never captured yet)? Show the menu.
	if _match_over():
		return # the end screen has the mouse now
	if get_tree().root.has_node("LoadingScreen"):
		# The loading screen asks for the first click itself ("Click to start the battle").
		_ignore_until = _now() + RECAPTURE_GRACE
		return
	if not is_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _now() > _ignore_until:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not settings_menu.visible and not _match_over() \
			and not get_tree().root.has_node("LoadingScreen"):
		if is_open:
			resume()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NetworkManager.is_single_player():
		get_tree().paused = true
	resume_button.grab_focus()


func resume() -> void:
	_close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_ignore_until = _now() + RECAPTURE_GRACE


func _close() -> void:
	is_open = false
	root.visible = false
	settings_menu.visible = false
	panel.visible = true
	get_tree().paused = false


func _match_over() -> bool:
	var director := get_tree().get_first_node_in_group("match_director") as MatchDirector
	return director != null and director.is_over()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
