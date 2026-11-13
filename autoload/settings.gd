extends Node
## Settings (autoload): graphics quality, mouse sensitivity, volume and fullscreen.
## Saved to user://settings.cfg (in a browser this is stored by the browser itself).
## Holds no player or game state - only the person's preferences.
## Other scripts read the values below and listen to `changed`.

signal changed
## The size of the 3D picture changed (new window size, fullscreen, quality or the 3D resolution setting).
signal render_size_changed

enum Quality { LOW, MEDIUM, HIGH }
## AUTO = the 3D picture is never taller than the preset's "max_lines" (big / high-density screens
## would otherwise draw four times the pixels of 1080p). FULL = no limit, the old behaviour.
enum Resolution { AUTO, FULL }

const SAVE_PATH: String = "user://settings.cfg"

## What each quality level changes. Tweak these numbers to rebalance the presets.
## "render_scale": the 3D picture's size as a share of the window. "max_lines": with
## 3D resolution = Auto the 3D picture is at most this many pixel lines tall.
const PRESETS: Dictionary = {
	Quality.LOW: {
		"shadows": false, "shadow_distance": 0.0, "tree_distance": 140.0, "tree_detail_distance": 35.0,
		"snow_amount": 250, "drift_amount": 0, "render_scale": 0.75, "max_lines": 720, "fog_density": 0.006,
	},
	Quality.MEDIUM: {
		"shadows": true, "shadow_distance": 40.0, "tree_distance": 180.0, "tree_detail_distance": 50.0,
		"snow_amount": 550, "drift_amount": 120, "render_scale": 0.9, "max_lines": 900, "fog_density": 0.0045,
	},
	Quality.HIGH: {
		"shadows": true, "shadow_distance": 70.0, "tree_distance": 220.0, "tree_detail_distance": 70.0,
		"snow_amount": 900, "drift_amount": 220, "render_scale": 1.0, "max_lines": 1080, "fog_density": 0.0035,
	},
}

var quality: Quality = Quality.HIGH
var resolution: Resolution = Resolution.AUTO ## 3D resolution: Auto (capped) or Full.
var mouse_sensitivity: float = 1.0 ## Multiplier on the normal mouse speed.
var volume: float = 0.8 ## 0..1
var ambience_volume: float = 0.7 ## 0..1: wind and the distant battle.
var show_breath: bool = true ## Breath vapour (yours and the soldiers').
var fullscreen: bool = false
var difficulty: int = 1 ## 0 = Easy, 1 = Normal, 2 = Hard (resources/difficulty/).


func _ready() -> void:
	# First start: Medium in a browser, High on desktop.
	quality = Quality.MEDIUM if OS.has_feature("web") else Quality.HIGH
	_load()
	if OS.has_feature("web"):
		# A browser only allows fullscreen after a click, so a saved "on" can't be applied at
		# start-up (it would silently fail): start windowed, the player ticks it again.
		fullscreen = false
	apply()
	# A new window size (resize, fullscreen) needs a new 3D scale to stay under the cap.
	get_tree().root.size_changed.connect(_apply_render_scale)
	# Browser: the "hold Esc to leave fullscreen" notice (menus and battle alike).
	var notice: CanvasLayer = load("res://scripts/ui/fullscreen_notice.gd").new()
	notice.name = "FullscreenNotice"
	add_child(notice)


## The numbers for the current quality level.
func preset() -> Dictionary:
	return PRESETS[quality]


## How much the 3D picture is scaled down for a window `window_height` pixels tall: the preset's
## own scale, and never more than `max_lines` lines when `capped`. (Godot allows 0.25 at the least.)
static func scale_for(window_height: int, preset_scale: float, max_lines: int, capped: bool) -> float:
	if not capped or window_height <= 0:
		return preset_scale
	var lines: float = minf(window_height * preset_scale, float(max_lines))
	return clampf(lines / window_height, 0.25, preset_scale)


## The 3D scale in use right now (1.0 = every pixel of the window).
func render_scale() -> float:
	var p: Dictionary = preset()
	return scale_for(get_tree().root.size.y, p.render_scale, p.max_lines, resolution == Resolution.AUTO)


## The real size of the 3D picture in pixels.
func render_size() -> Vector2i:
	return Vector2i((Vector2(get_tree().root.size) * render_scale()).round())


func _apply_render_scale() -> void:
	var s: float = render_scale()
	if not is_equal_approx(get_tree().root.scaling_3d_scale, s):
		get_tree().root.scaling_3d_scale = s
	render_size_changed.emit()


## Apply everything that is global, then tell the rest of the game to update.
func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	var amb: int = AudioServer.get_bus_index(&"Ambience")
	if amb >= 0:
		AudioServer.set_bus_volume_db(amb, linear_to_db(maxf(ambience_volume, 0.0001)) - 3.0)
	_apply_render_scale()
	var want_full: bool = fullscreen
	var is_full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if want_full != is_full and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_full else DisplayServer.WINDOW_MODE_WINDOWED)
	changed.emit()


func set_quality(value: Quality) -> void:
	quality = value
	_save_and_apply()


func set_resolution(value: Resolution) -> void:
	resolution = value
	_save_and_apply()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = value
	_save_and_apply()


func set_volume(value: float) -> void:
	volume = value
	_save_and_apply()


func set_ambience_volume(value: float) -> void:
	ambience_volume = value
	_save_and_apply()


func set_show_breath(value: bool) -> void:
	show_breath = value
	_save_and_apply()


func set_difficulty(value: int) -> void:
	difficulty = value
	_save_and_apply()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_save_and_apply()


func _save_and_apply() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "resolution", resolution)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "ambience_volume", ambience_volume)
	cfg.set_value("graphics", "show_breath", show_breath)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.save(SAVE_PATH)
	apply()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	quality = cfg.get_value("graphics", "quality", quality)
	resolution = clampi(cfg.get_value("graphics", "resolution", resolution), 0, Resolution.size() - 1) as Resolution
	fullscreen = cfg.get_value("graphics", "fullscreen", fullscreen)
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	volume = cfg.get_value("audio", "volume", volume)
	ambience_volume = cfg.get_value("audio", "ambience_volume", ambience_volume)
	show_breath = cfg.get_value("graphics", "show_breath", show_breath)
	difficulty = cfg.get_value("game", "difficulty", difficulty)
