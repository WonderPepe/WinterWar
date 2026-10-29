extends Node
## Settings (autoload): graphics quality, mouse sensitivity, volume and fullscreen.
## Saved to user://settings.cfg (in a browser this is stored by the browser itself).
## Holds no player or game state - only the person's preferences.
## Other scripts read the values below and listen to `changed`.

signal changed

enum Quality { LOW, MEDIUM, HIGH }

const SAVE_PATH: String = "user://settings.cfg"

## What each quality level changes. Tweak these numbers to rebalance the presets.
const PRESETS: Dictionary = {
	Quality.LOW: {
		"shadows": false, "shadow_distance": 0.0, "tree_distance": 110.0,
		"snow_amount": 250, "render_scale": 0.75, "fog_density": 0.009,
	},
	Quality.MEDIUM: {
		"shadows": true, "shadow_distance": 40.0, "tree_distance": 150.0,
		"snow_amount": 550, "render_scale": 0.9, "fog_density": 0.008,
	},
	Quality.HIGH: {
		"shadows": true, "shadow_distance": 70.0, "tree_distance": 190.0,
		"snow_amount": 900, "render_scale": 1.0, "fog_density": 0.007,
	},
}

var quality: Quality = Quality.HIGH
var mouse_sensitivity: float = 1.0 ## Multiplier on the normal mouse speed.
var volume: float = 0.8 ## 0..1
var fullscreen: bool = false


func _ready() -> void:
	# First start: Medium in a browser, High on desktop.
	quality = Quality.MEDIUM if OS.has_feature("web") else Quality.HIGH
	_load()
	apply()


## The numbers for the current quality level.
func preset() -> Dictionary:
	return PRESETS[quality]


## Apply everything that is global, then tell the rest of the game to update.
func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	get_tree().root.scaling_3d_scale = preset().render_scale
	var want_full: bool = fullscreen
	var is_full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if want_full != is_full and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_full else DisplayServer.WINDOW_MODE_WINDOWED)
	changed.emit()


func set_quality(value: Quality) -> void:
	quality = value
	_save_and_apply()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = value
	_save_and_apply()


func set_volume(value: float) -> void:
	volume = value
	_save_and_apply()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_save_and_apply()


func _save_and_apply() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("audio", "volume", volume)
	cfg.save(SAVE_PATH)
	apply()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	quality = cfg.get_value("graphics", "quality", quality)
	fullscreen = cfg.get_value("graphics", "fullscreen", fullscreen)
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	volume = cfg.get_value("audio", "volume", volume)
