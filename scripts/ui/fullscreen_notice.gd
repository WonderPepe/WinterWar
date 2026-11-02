extends CanvasLayer
## Browser only: a short notice when the game goes fullscreen.
##
## In fullscreen the page locks the keyboard (Keyboard Lock, Chrome / Edge – see the
## `html/head_include` script in export_presets.cfg), so Ctrl+W can't close the tab by accident
## (W + Ctrl = forward + crouch). The price: a short Esc press goes to the game (pause menu) and
## the browser only leaves fullscreen when Esc is HELD down – this notice tells the player.
## It also unticks the Settings "Fullscreen" box when the player leaves fullscreen that way.
## Created by the Settings autoload, so it works in the menus and in the battle.

const MESSAGE: String = "FULLSCREEN\nHold [Esc] down to leave fullscreen.\n(A short press opens the pause menu.)"
const SHOW_TIME: float = 6.0 ## Seconds the notice stays (then it fades out).
const POLL_TIME: float = 0.25 ## Seconds between "are we fullscreen?" checks.

var _was_full: bool = false
var _poll: float = 0.0
var _show_left: float = 0.0
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 100 # above the loading screen, menus and HUD
	process_mode = Node.PROCESS_MODE_ALWAYS # also while the game is paused
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 40.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.08, 0.85)
	box.border_color = Color(0.85, 0.9, 1.0, 0.6)
	box.set_border_width_all(1)
	box.set_content_margin_all(14.0)
	_panel.add_theme_stylebox_override("panel", box)
	center.add_child(_panel)
	_label = Label.new()
	_label.text = MESSAGE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	_panel.visible = false


func _process(delta: float) -> void:
	if _show_left > 0.0:
		_show_left -= delta
		_panel.modulate.a = clampf(_show_left, 0.0, 1.0) # fades out in the last second
		_panel.visible = _show_left > 0.0
	if not OS.has_feature("web"):
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_TIME
	var full: bool = _js_yes("document.fullscreenElement")
	if full and not _was_full:
		if keyboard_lock_supported():
			show_notice()
	elif _was_full and not full and Settings.fullscreen:
		Settings.set_fullscreen(false) # left with Esc held down: untick the setting too
	_was_full = full


## Shows the notice (also used by the tests).
func show_notice() -> void:
	_show_left = SHOW_TIME
	_panel.modulate.a = 1.0
	_panel.visible = true
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.summaFullscreenNotices = (window.summaFullscreenNotices || 0) + 1;", true) # (web test)


func is_showing() -> bool:
	return _panel.visible


## True in browsers that can lock the keyboard in fullscreen (Chrome, Edge). Elsewhere a short
## Esc still leaves fullscreen as usual, so no notice is needed.
static func keyboard_lock_supported() -> bool:
	if not OS.has_feature("web"):
		return false
	return _js_yes("navigator.keyboard && navigator.keyboard.lock")


## True if the JavaScript expression is truthy. (Asked as a 'yes'/'no' string: a JavaScript
## true/false did not come back as a GDScript bool in the web export, and comparing the null
## that came instead stopped the function without an error message.)
static func _js_yes(expression: String) -> bool:
	return str(JavaScriptBridge.eval("(%s) ? 'yes' : 'no'" % expression, true)) == "yes"
