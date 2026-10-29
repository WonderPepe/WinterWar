extends Node
## Benchmark: the same 60-second run every time, so performance can be compared
## between computers, browsers and quality settings.
## The player (in god mode) follows a fixed camera route over the trench and the bog,
## fires the Suomi in bursts, and a 16-soldier attack plays out. Then a results
## screen shows FPS, slow frames, draw calls, triangles, script/physics time and memory.

@export var duration: float = 60.0
@export var warmup: float = 2.0 ## Seconds ignored at the start (everything is still loading).
@export var enemy_count: int = 16

## Camera route: [time (s), position (y = height above the ground), point to look at]
const ROUTE: Array = [
	[0.0, Vector3(-30, 0.0, 61), Vector3(-70, 0, -10)],
	[12.0, Vector3(-30, 0.0, 61), Vector3(30, 0, -10)],
	[16.0, Vector3(-20, 0.3, 48), Vector3(0, 0, -40)],
	[32.0, Vector3(10, 1.0, -40), Vector3(0, 0, -120)],
	[44.0, Vector3(-30, 1.0, -90), Vector3(40, 0, -60)],
	[54.0, Vector3(0, 1.0, 20), Vector3(0, 2, 90)],
	[60.0, Vector3(10, 1.0, 40), Vector3(-10, 2, 90)],
]

var _time: float = 0.0
var _running: bool = false
var _player: Player
var _terrain: TerrainGenerator
var _frame_times: PackedFloat32Array = PackedFloat32Array()
var _sum := {"draw_calls": 0.0, "primitives": 0.0, "objects": 0.0, "process_ms": 0.0, "physics_ms": 0.0}
var _max_draw_calls: float = 0.0
var _load_seconds: float = 0.0
var _progress_label: Label
var _results_layer: CanvasLayer
var _results_text: String = ""

@onready var game: Game = $Game


func _ready() -> void:
	if MainMenu.start_pressed_msec > 0:
		_load_seconds = (Time.get_ticks_msec() - MainMenu.start_pressed_msec) / 1000.0
	game.get_node("PauseMenu").queue_free() # the benchmark controls the game itself
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_terrain = get_tree().get_first_node_in_group("terrain")
	_player = get_tree().get_first_node_in_group("players")
	_player.god_mode = true
	_player.input.set_process(false)   # the route drives the "input", not the keyboard
	_player.set_physics_process(false) # we place the player directly
	_player.input.request_switch(1)    # Suomi: more shots, more effects
	var waves := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	waves.first_wave_delay = 0.0
	waves._timer = 0.0
	waves.base_enemies = enemy_count
	waves.max_alive = enemy_count
	waves.group_size_min = 4
	waves.group_size_max = 4
	waves.time_between_groups = 0.0
	_build_progress_label()
	_running = true


func _process(delta: float) -> void:
	if not _running:
		return
	_time += delta
	_follow_route()
	# Fire a 0.6 s burst every 2 s while the trench and the bog are in view.
	_player.input.fire_held = (_time > 3.0 and _time < 30.0) and fmod(_time, 2.0) < 0.6
	_player.input.aim_held = false
	if _time > warmup:
		_frame_times.append(delta)
		var draw_calls: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_sum.draw_calls += draw_calls
		_sum.primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_sum.objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		_sum.process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_sum.physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_max_draw_calls = maxf(_max_draw_calls, draw_calls)
	_progress_label.text = "BENCHMARK  %d / %d s   (Esc to stop)" % [int(_time), int(duration)]
	if _time >= duration:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		NetworkManager.leave_game()


func _follow_route() -> void:
	var i: int = 0
	while i < ROUTE.size() - 2 and _time > ROUTE[i + 1][0]:
		i += 1
	var a: Array = ROUTE[i]
	var b: Array = ROUTE[i + 1]
	var t: float = smoothstep(a[0], b[0], _time)
	var pos: Vector3 = (a[1] as Vector3).lerp(b[1], t)
	var look: Vector3 = (a[2] as Vector3).lerp(b[2], t)
	pos.y += _terrain.get_height(pos.x, pos.z)
	_player.global_position = pos
	var to_look: Vector3 = look - (pos + Vector3.UP * 1.6)
	_player.input.look_yaw = atan2(-to_look.x, -to_look.z)
	_player.input.look_pitch = atan2(to_look.y, Vector2(to_look.x, to_look.z).length())


# ------------------------------------------------------------------ results
func _finish() -> void:
	_running = false
	_player.input.fire_held = false
	var frames: int = _frame_times.size()
	var total: float = 0.0
	for ft in _frame_times:
		total += ft
	var sorted := _frame_times.duplicate()
	sorted.sort()
	var p99: float = sorted[int(frames * 0.99)] if frames > 0 else 0.0
	var worst: float = sorted[frames - 1] if frames > 0 else 0.0
	var avg_fps: float = frames / maxf(total, 0.001)
	var low_fps: float = 1.0 / maxf(p99, 0.0001)
	var n: float = maxf(frames, 1)
	var verdict: String
	if avg_fps >= 55.0 and low_fps >= 40.0:
		verdict = "GOOD - smooth on this computer"
	elif avg_fps >= 40.0:
		verdict = "OK - playable, try a lower quality for smoother play"
	else:
		verdict = "TOO SLOW - choose Low quality (Settings) and run again"
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var lines: PackedStringArray = [
		"Result: %s" % verdict,
		"",
		"Average FPS: %.1f        1%% low FPS: %.1f        Worst frame: %.1f ms" % [avg_fps, low_fps, worst * 1000.0],
		"Draw calls: %.0f average, %.0f max        Triangles: %.0fk        Objects: %.0f" % [_sum.draw_calls / n, _max_draw_calls, _sum.primitives / n / 1000.0, _sum.objects / n],
		"Scripts: %.2f ms/frame        Physics: %.2f ms/frame" % [_sum.process_ms / n, _sum.physics_ms / n],
		"Memory: %.0f MB        Video memory: %.0f MB" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0],
		"Load time (menu click -> game): %.1f s" % _load_seconds,
		"",
		"Quality: %s   Resolution: %dx%d at %d%%   Platform: %s%s" % [Settings.Quality.keys()[Settings.quality], view_size.x, view_size.y, int(Settings.preset().render_scale * 100), OS.get_name(), " (browser)" if OS.has_feature("web") else ""],
		"Graphics: %s / %s" % [RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name()],
		"Godot %s   Frames measured: %d" % [Engine.get_version_info().string, frames],
	]
	_results_text = "\n".join(lines)
	print("BENCHMARK RESULTS\n", _results_text)
	_show_results()


func _build_progress_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 18)
	_progress_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_progress_label.add_theme_constant_override("outline_size", 5)
	_progress_label.position = Vector2(16, 12)
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_progress_label)


func _show_results() -> void:
	_progress_label.text = "BENCHMARK DONE"
	_results_layer = CanvasLayer.new()
	_results_layer.layer = 40
	add_child(_results_layer)
	var root := Control.new()
	root.theme = load("res://ui/winter_theme.tres")
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "BENCHMARK RESULTS"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var body := Label.new()
	body.text = _results_text
	body.add_theme_font_size_override("font_size", 16)
	vb.add_child(body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	vb.add_child(buttons)
	var copy := Button.new()
	copy.text = "Copy results"
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_results_text)
		copy.text = "Copied!")
	buttons.add_child(copy)
	var again := Button.new()
	again.text = "Run again"
	again.pressed.connect(func() -> void:
		MainMenu.start_pressed_msec = Time.get_ticks_msec()
		get_tree().reload_current_scene())
	buttons.add_child(again)
	var menu := Button.new()
	menu.text = "Main Menu"
	menu.pressed.connect(NetworkManager.leave_game)
	buttons.add_child(menu)
	copy.grab_focus()
