class_name SettingsMenu
extends Control
## Settings panel used by the main menu and the pause menu.
## Changes are applied and saved immediately (see the Settings autoload).

signal closed

@onready var quality: OptionButton = $Panel/VBox/Grid/Quality
@onready var resolution: OptionButton = $Panel/VBox/Grid/Resolution
@onready var resolution_hint: Label = $Panel/VBox/Grid/ResolutionHint
@onready var sensitivity: HSlider = $Panel/VBox/Grid/Sensitivity
@onready var sensitivity_value: Label = $Panel/VBox/Grid/SensitivityValue
@onready var volume: HSlider = $Panel/VBox/Grid/Volume
@onready var volume_value: Label = $Panel/VBox/Grid/VolumeValue
@onready var ambience: HSlider = $Panel/VBox/Grid/Ambience
@onready var ambience_value: Label = $Panel/VBox/Grid/AmbienceValue
@onready var breath: CheckButton = $Panel/VBox/Grid/Breath
@onready var fullscreen: CheckButton = $Panel/VBox/Grid/Fullscreen
@onready var back: Button = $Panel/VBox/BackButton


func _ready() -> void:
	quality.clear()
	for label in ["Low", "Medium", "High"]:
		quality.add_item(label)
	quality.item_selected.connect(func(i: int) -> void: Settings.set_quality(i as Settings.Quality))
	resolution.clear()
	for label in ["Auto", "Full"]:
		resolution.add_item(label)
	resolution.item_selected.connect(func(i: int) -> void: Settings.set_resolution(i as Settings.Resolution))
	Settings.render_size_changed.connect(_refresh_labels)
	sensitivity.value_changed.connect(func(v: float) -> void:
		Settings.set_mouse_sensitivity(v)
		_refresh_labels())
	volume.value_changed.connect(func(v: float) -> void:
		Settings.set_volume(v / 100.0)
		_refresh_labels())
	ambience.value_changed.connect(func(v: float) -> void:
		Settings.set_ambience_volume(v / 100.0)
		_refresh_labels())
	breath.toggled.connect(Settings.set_show_breath)
	fullscreen.toggled.connect(Settings.set_fullscreen)
	back.pressed.connect(close)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func open() -> void:
	visible = true
	back.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _on_visibility_changed() -> void:
	if not visible:
		return
	# Show the current values (without triggering a save).
	quality.select(Settings.quality)
	resolution.select(Settings.resolution)
	sensitivity.set_value_no_signal(Settings.mouse_sensitivity)
	volume.set_value_no_signal(Settings.volume * 100.0)
	ambience.set_value_no_signal(Settings.ambience_volume * 100.0)
	breath.set_pressed_no_signal(Settings.show_breath)
	fullscreen.set_pressed_no_signal(Settings.fullscreen)
	_refresh_labels()


func _refresh_labels() -> void:
	# The real size of the 3D picture (Auto keeps it small enough on big screens).
	var size_3d: Vector2i = Settings.render_size()
	resolution_hint.text = "3D picture: %d × %d" % [size_3d.x, size_3d.y]
	sensitivity_value.text = "%.2f×" % sensitivity.value
	volume_value.text = "%d %%" % int(volume.value)
	ambience_value.text = "%d %%" % int(ambience.value)
