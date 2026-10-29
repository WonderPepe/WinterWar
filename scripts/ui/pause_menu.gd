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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps working while the game is paused
	resume_button.pressed.connect(resume)
	menu_button.pressed.connect(NetworkManager.leave_game)
	_ignore_until = _now() + RECAPTURE_GRACE
	_close()


func _process(_delta: float) -> void:
	# Mouse got released (browser Esc, alt-tab, or never captured yet)? Show the menu.
	if not is_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _now() > _ignore_until:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
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
	get_tree().paused = false


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
