class_name ControlsPanel
extends Control
## "Controls": a list of every key and what it does (main menu and pause menu).
## The key names are read from the Input Map (Project Settings → Input Map), so the list
## stays right if a key is changed there. Back or Esc closes it.

signal closed

## The list: a section title (a String) or a row [actions, what it does]. `actions` is one
## action name or several (their keys are shown side by side, e.g. W A S D).
const ROWS: Array = [
	"MOVEMENT",
	[["move_forward", "move_left", "move_back", "move_right"], "Move"],
	["jump", "Jump"],
	["sprint", "Sprint (hold)"],
	["crouch", "Crouch (hold)"],
	"WEAPONS",
	["fire", "Fire"],
	["aim", "Aim down the sights (hold)"],
	["reload", "Reload"],
	["weapon_1", "Mosin-Nagant rifle"],
	["weapon_2", "Suomi submachine gun"],
	"MOLOTOV COCKTAIL",
	["molotov", "Take a bottle in your hand (1 / 2 put an unlit bottle away)"],
	["aim", "Hold about 1 s to light the rag – then hold to aim"],
	["fire", "Throw – aim for the engine deck at the back of the tank"],
	"OTHER",
	["interact", "Pick up ammo or Molotov cocktails, use / leave the Maxim gun"],
	["bandage", "Bandage your wounds"],
	["pause", "Pause menu"],
]
## Test keys: only listed when the game runs from the Godot editor.
const DEBUG_ROWS: Array = [
	"TEST KEYS (EDITOR ONLY)",
	["debug_god_mode", "God mode"],
	["debug_enemy_labels", "Enemy labels"],
	["debug_overlay", "Debug overlay"],
	["debug_spawn_tank", "Bring a tank"],
	["debug_destroy_tank", "Knock out the nearest tank"],
]

@onready var grid: GridContainer = $Center/Panel/VBox/Scroll/Grid
@onready var scroll: ScrollContainer = $Center/Panel/VBox/Scroll
@onready var back: Button = $Center/Panel/VBox/BackButton


func _ready() -> void:
	back.pressed.connect(close)
	_fill()


func open() -> void:
	visible = true
	scroll.scroll_vertical = 0 # start at the top
	back.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func _fill() -> void:
	for child in grid.get_children():
		child.queue_free()
	var rows: Array = ROWS.duplicate()
	if OS.has_feature("editor"):
		rows.append_array(DEBUG_ROWS)
	for row in rows:
		if row is String:
			_add_label(row, 16, Color(1.0, 0.86, 0.6), true) # section title on the left...
			_add_label("", 16, Color.WHITE) # ...and an empty cell on the right
		else:
			var actions: Array = row[0] if row[0] is Array else [row[0]]
			var keys: PackedStringArray = PackedStringArray()
			for action in actions:
				keys.append(key_text(action))
			_add_label(" ".join(keys), 17, Color(1.0, 0.95, 0.8))
			_add_label(row[1], 17, Color(0.92, 0.94, 0.97))


func _add_label(text: String, size: int, color: Color, top_gap: bool = false) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if top_gap and grid.get_child_count() > 0:
		l.text = "\n" + text # a little air above every section but the first
	grid.add_child(l)


## "W", "Space", "Left mouse", "C / Ctrl"... – the keys of an action in the Input Map.
static func key_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var names: PackedStringArray = PackedStringArray()
	for ev in InputMap.action_get_events(action):
		var n: String = ""
		if ev is InputEventKey:
			var code: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
			n = OS.get_keycode_string(code)
			if n == "Escape":
				n = "Esc"
		elif ev is InputEventMouseButton:
			match ev.button_index:
				MOUSE_BUTTON_LEFT: n = "Left mouse"
				MOUSE_BUTTON_RIGHT: n = "Right mouse"
				MOUSE_BUTTON_MIDDLE: n = "Middle mouse"
				_: n = "Mouse %d" % ev.button_index
		if n != "" and not names.has(n):
			names.append(n)
	return " / ".join(names) if not names.is_empty() else "?"
