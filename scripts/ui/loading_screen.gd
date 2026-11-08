class_name LoadingScreen
extends CanvasLayer
## Shown between the main menu and the battle, with a progress bar. Loading the battle takes a
## moment (especially in a browser): the scene and its 3D models are read, the terrain and the
## forest are built, and every effect is drawn once so the browser can prepare its shaders.
##
## Use: LoadingScreen.go(get_tree(), "res://scenes/game.tscn")
## This screen stays on top while the game starts underneath, and removes itself when ready.
## In a browser the mouse can only be "locked" to the game after a click, so when loading is
## done it asks for one click ("Click to start the battle") – that click locks the mouse and the
## battle begins (no pause menu in between). On desktop the mouse is locked straight away.
##
## B1: under the title it shows the briefing of the first battle (an old photo, the date, the
## weather and the briefing text) from resources/front_reports.tres. Built in code, so the
## scene file does not change. The benchmark (no click) shows no briefing.
##
## B2: the progress bar is replaced by a snowy marching path with a little soldier walking from
## left to right (drawn by code, no image files), snow falling over the whole screen, and a
## phrase for every stretch of the way ("Drafting recruits...", ...). At 100 % he stops and
## the line turns red: "ALARM! TO THE POSITIONS!". The old ProgressBar still counts (hidden);
## the path just reads it. The march lasts at least MIN_MARCH seconds so it can be seen.

const SCENE_PATH: String = "res://ui/loading_screen.tscn"
const TIPS: Array[String] = [
	"Hold the line through 10 battles. If too many Soviets get into the trench, the line breaks.",
	"F next to an ammo crate refills your spare ammunition and bandages.",
	"B puts on a bandage: +50 health, but you can't shoot for 3 seconds.",
	"The Maxim in the bunker overheats in long bursts – fire short bursts.",
	"Right mouse on the Maxim: aim through its own sights.",
	"Crouch (C) in the trench: you are harder to spot and to hit.",
	"Soldiers kneel to fire, then rush forward. Shoot them while they kneel.",
]

const PHOTO_BOX: Vector2 = Vector2(520, 300) ## Largest size of the briefing photo.
const MIN_MARCH: float = 4.0 ## The march takes at least this many seconds (the real game only).
const ARRIVE_HOLD: float = 0.7 ## He stands at the end this long before the battle starts (no click needed).
const MARCH_SIZE: Vector2 = Vector2(960, 96)
const ALARM_TEXT: String = "ALARM! TO THE POSITIONS!"
## [from percent, text] – the owner's phrases; the last one that has been reached is shown.
const PHRASES: Array = [
	[0, "Drafting recruits..."],
	[6, "Mixing Molotov cocktails in the local brewery..."],
	[12, "Digging communication trenches into the frozen ground..."],
	[18, "Reinforcing dugout roofs with heavy pine logs..."],
	[24, "Applying winter wax to wooden cross-country skis..."],
	[30, "Weaving barbed wire obstacles between tree stumps..."],
	[36, "Chopping frozen birch logs for the dugout stove..."],
	[42, "Positioning anti-tank boulders along the defensive line..."],
	[48, "Cleaning the Pystykorva rifle barrels..."],
	[54, "Thawing frozen machine gun mechanisms..."],
	[60, "Camouflaging concrete bunkers with snow and brush..."],
	[66, "Distributing white snow-camouflage suits..."],
	[72, "Intercepting enemy radio transmissions..."],
	[78, "Setting up tripwire mines in the deep snow..."],
	[84, "Sharpening knives and shovels..."],
	[90, "Surrounding enemy columns into a motti..."],
	[95, "Jamming enemy tanks with logs..."],
	[98, "Cocking the Suomi submachine gun..."],
]
const FLAKES: int = 40

## The scene to load next (set by go()).
static var target_scene: String = "res://scenes/game.tscn"
## Ask for a click at the end if the mouse isn't locked yet (not for the benchmark).
static var click_to_start: bool = true

var _target_value: float = 0.0
var _waiting_for_click: bool = false
var _march_on: bool = false ## The marching path is shown (the real game, not the benchmark).
var _elapsed: float = 0.0 ## Seconds since the screen opened.
var _shown: float = 0.0 ## Progress 0..100 shown by the soldier (never ahead of the real loading).
var march: Control
var percent_label: Label
var snow: Control
var _flake_pos := PackedVector2Array()
var _flake_size := PackedFloat32Array()
var _flake_speed := PackedFloat32Array()
var _flake_drift := PackedFloat32Array()

@onready var bar: ProgressBar = $Root/Center/VBox/Bar
@onready var status: Label = $Root/Center/VBox/Status
@onready var tip: Label = $Root/Center/VBox/Tip
@onready var background: Control = $Root/Background
@onready var start_label: Label = $Root/Center/VBox/ClickToStart


## Switch to the loading screen, which then loads `scene`.
static func go(tree: SceneTree, scene: String, ask_click: bool = true) -> void:
	target_scene = scene
	click_to_start = ask_click
	tree.paused = false
	tree.change_scene_to_file(SCENE_PATH)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps going even if the game pauses underneath
	layer = 60 # above the game's own screens (HUD, pause menu, shader warm-up)
	tip.text = "Tip: " + TIPS.pick_random()
	if click_to_start:
		_add_briefing()
		_add_march()
	bar.value = 0.0
	start_label.visible = false
	_run()


## The phrase for `pct` percent (the last one whose percentage has been reached).
static func phrase_for(pct: float) -> String:
	if pct >= 100.0:
		return ALARM_TEXT
	var text: String = PHRASES[0][1]
	for p: Array in PHRASES:
		if pct >= float(p[0]):
			text = p[1]
	return text


## Snow, the marching path and the percentage (all drawn by code).
func _add_march() -> void:
	_march_on = true
	bar.visible = false # still counts, the soldier reads its value
	var vbox: Control = tip.get_parent()
	march = Control.new()
	march.name = "MarchPath"
	march.custom_minimum_size = MARCH_SIZE
	march.mouse_filter = Control.MOUSE_FILTER_IGNORE
	march.draw.connect(_draw_march)
	vbox.add_child(march)
	vbox.move_child(march, bar.get_index())
	percent_label = Label.new()
	percent_label.name = "Percent"
	percent_label.text = "0%"
	percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	percent_label.add_theme_font_size_override("font_size", 24)
	percent_label.add_theme_color_override("font_color", Color(0.64, 0.7, 0.74))
	percent_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(percent_label)
	vbox.move_child(percent_label, bar.get_index())
	# Falling snow over the whole screen, just above the background.
	snow = Control.new()
	snow.name = "Snow"
	snow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	snow.draw.connect(_draw_snow)
	background.get_parent().add_child(snow)
	background.get_parent().move_child(snow, background.get_index() + 1)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in FLAKES:
		_flake_pos.append(Vector2(rng.randf(), rng.randf())) # 0..1 of the screen
		_flake_size.append(rng.randf_range(1.0, 3.0))
		_flake_speed.append(rng.randf_range(0.06, 0.16)) # screen heights per second
		_flake_drift.append(rng.randf_range(0.005, 0.02)) # screen widths per second
	status.text = phrase_for(0.0)


func _draw_snow() -> void:
	var sz: Vector2 = snow.size
	for i in _flake_pos.size():
		snow.draw_circle(_flake_pos[i] * sz, _flake_size[i], Color(1, 1, 1, 0.6))


## A rectangle of the soldier, moved by transform `t` (the soldier is drawn in a 50 × 100 box).
func _soldier_rect(t: Transform2D, r: Rect2, col: Color) -> void:
	var pts := PackedVector2Array([t * r.position, t * Vector2(r.end.x, r.position.y),
			t * r.end, t * Vector2(r.position.x, r.end.y)])
	march.draw_colored_polygon(pts, col)


static func _turn_about(angle: float, pivot: Vector2) -> Transform2D:
	return Transform2D(0.0, pivot) * Transform2D(angle, Vector2.ZERO) * Transform2D(0.0, -pivot)


## The path with the soldier on it. Legs swing and the body bobs while he walks; at the end
## he stands still.
func _draw_march() -> void:
	var w: float = march.size.x
	var ground_y: float = march.size.y - 8.0
	march.draw_rect(Rect2(0, ground_y, w, 4), Color(0.64, 0.7, 0.74))
	# The goal: a post with a small pennant at the right end of the path.
	march.draw_rect(Rect2(w - 22, ground_y - 46, 3, 46), Color(0.24, 0.2, 0.15))
	march.draw_colored_polygon(PackedVector2Array([Vector2(w - 19, ground_y - 46),
			Vector2(w - 5, ground_y - 41), Vector2(w - 19, ground_y - 34)]), Color(0.85, 0.9, 0.95))
	var walking: bool = _shown < 99.9
	var ph: float = _elapsed * TAU / 0.6 if walking else 0.0
	var bob: float = -absf(sin(ph * 0.5)) * 3.0 if walking else 0.0
	var lean: float = deg_to_rad(5.5 + 1.5 * sin(ph * 0.5)) if walking else 0.0
	var x: float = 30.0 + (w - 90.0) * clampf(_shown, 0.0, 100.0) / 100.0
	var k: float = 0.75
	var base := Transform2D(Vector2(k, 0), Vector2(0, k), Vector2(x, ground_y + bob)) \
			* Transform2D(0.0, Vector2(-25, -100))
	var up: Transform2D = base * _turn_about(lean, Vector2(25, 58))
	var leg_a: float = deg_to_rad(3.0 + 25.0 * cos(ph)) if walking else 0.0
	var leg_col := Color("3a4146")
	_soldier_rect(up, Rect2(-2, 22, 14, 30), Color("3e474d")) # backpack
	_soldier_rect(base * _turn_about(leg_a, Vector2(16, 58)), Rect2(12, 58, 8, 42), leg_col)
	_soldier_rect(base * _turn_about(-leg_a, Vector2(26, 58)), Rect2(22, 58, 8, 42), leg_col)
	_soldier_rect(up, Rect2(10, 20, 28, 40), Color("5a656c")) # torso
	var rifle: Transform2D = up * _turn_about(deg_to_rad(25.0), Vector2(23, 49))
	_soldier_rect(rifle, Rect2(20, 25, 6, 48), Color("2e1d0c"))
	_soldier_rect(rifle, Rect2(21, 13, 3, 15), Color("1c2124")) # barrel
	var head := PackedVector2Array()
	for i in 17:
		var a: float = TAU * i / 16.0
		head.append(up * (Vector2(25, 10) + Vector2(cos(a), sin(a)) * 10.0))
	march.draw_colored_polygon(head, Color("d2b48c"))
	var helmet := PackedVector2Array()
	for i in 13: # a half circle on top of the head
		var a: float = PI + PI * i / 12.0
		helmet.append(up * (Vector2(25, 7) + Vector2(cos(a) * 12.0, sin(a) * 12.0)))
	march.draw_colored_polygon(helmet, Color("4a5359"))


## The briefing of the battle the match starts at (battle 1, or the Test Mode battle).
func _add_briefing() -> void:
	var reports := load("res://resources/front_reports.tres") as FrontReports
	if reports == null:
		return
	var battle: int = clampi(MatchDirector.test_start_wave, 1, maxi(reports.dates.size(), 1))
	var r: PackedStringArray = reports.get_report(battle)
	if r.size() != 2:
		return
	var vbox: Control = tip.get_parent()
	var row := HBoxContainer.new()
	row.name = "Briefing"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The photo as an old print (same look as the day screen).
	var tex: Texture2D = reports.get_photo(battle)
	if tex:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var frame := PanelContainer.new()
		var print_style := StyleBoxFlat.new()
		print_style.bg_color = Color(0.88, 0.86, 0.8)
		for side in ["left", "right", "top", "bottom"]:
			print_style.set("content_margin_" + side, 8)
		frame.add_theme_stylebox_override("panel", print_style)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		var k: float = minf(PHOTO_BOX.x / tex.get_width(), PHOTO_BOX.y / tex.get_height())
		pic.custom_minimum_size = (tex.get_size() * k).round()
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = load("res://resources/shaders/old_photo.gdshader")
		pic.material = mat
		frame.add_child(pic)
		box.add_child(frame)
		var credit := Label.new()
		credit.text = "Kuva: SA-kuva"
		credit.add_theme_font_size_override("font_size", 13)
		credit.add_theme_color_override("font_color", Color(0.7, 0.72, 0.76))
		box.add_child(credit)
		row.add_child(box)
	# Date, weather, briefing.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(430, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_briefing_label(r[0], 32, Color(0.95, 0.92, 0.85)))
	col.add_child(_briefing_label(reports.get_weather(battle), 18, Color(0.78, 0.84, 0.92)))
	col.add_child(_briefing_label(r[1], 20, Color(0.92, 0.94, 0.97)))
	row.add_child(col)
	vbox.add_child(row)
	vbox.move_child(row, 1) # right under the title


func _briefing_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	# The bar glides towards the real progress instead of jumping.
	bar.value = move_toward(bar.value, _target_value * 100.0, delta * 120.0)
	_elapsed += delta
	if _march_on:
		_update_march(delta)
	if _waiting_for_click:
		start_label.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 250.0)


## The soldier never gets ahead of the real loading, nor ahead of the minimum march time.
func _update_march(delta: float) -> void:
	_shown = minf(minf(bar.value, _elapsed / MIN_MARCH * 100.0), 100.0)
	status.text = phrase_for(_shown)
	status.add_theme_color_override("font_color", Color(1.0, 0.29, 0.29) if _shown >= 100.0 else Color(0.9, 0.93, 0.97))
	percent_label.text = "%d%%" % int(_shown)
	var sz: Vector2 = snow.size
	for i in _flake_pos.size():
		var p: Vector2 = _flake_pos[i]
		p.y += _flake_speed[i] * delta
		p.x += _flake_drift[i] * delta
		if p.y > 1.02:
			p = Vector2(randf(), -0.02)
		if p.x > 1.0:
			p.x -= 1.0
		_flake_pos[i] = p
	snow.queue_redraw()
	march.queue_redraw()


## The click (or Enter / Space) that starts the battle. Locking the mouse must happen inside
## the browser's own click handling, so it is done right here in _input.
func _input(event: InputEvent) -> void:
	if not _waiting_for_click:
		return
	var mouse_click := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	var key := event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	if mouse_click or key:
		get_viewport().set_input_as_handled()
		start_now()


## Leave the loading screen and start playing.
func start_now() -> void:
	_waiting_for_click = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false
	queue_free()


func _run() -> void:
	_step(0.02, "Loading the battle...")
	await _frames(2) # let the screen appear before the heavy work starts
	# 1) Read the scene and everything it uses (models, textures, sounds).
	if ResourceLoader.load_threaded_request(target_scene) != OK:
		_fail()
		return
	var progress: Array = []
	while true:
		var state := ResourceLoader.load_threaded_get_status(target_scene, progress)
		if state == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if state != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_fail()
			return
		_step(0.05 + 0.6 * float(progress[0] if not progress.is_empty() else 0.0), "Loading the battle...")
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(target_scene) as PackedScene
	# 2) Build it: the terrain, the forest and the trench are made when the scene starts.
	_step(0.7, "Building the trench and the forest...")
	await _frames(2)
	var game: Node = packed.instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	# 3) The shader warm-up draws every effect once (the browser prepares them).
	_step(0.85, "Preparing the effects...")
	await get_tree().process_frame
	while true:
		var warmup := get_tree().get_first_node_in_group("shader_warmup") as ShaderWarmup
		if warmup == null:
			break
		_step(0.85 + 0.14 * warmup.progress, "Preparing the effects...")
		await get_tree().process_frame
	_step(1.0, "Ready")
	bar.value = 100.0
	await _frames(2)
	if _march_on:
		# Let the soldier arrive (at least MIN_MARCH s in all), then stand there a moment.
		while _shown < 99.9:
			await get_tree().process_frame
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not click_to_start:
			await get_tree().create_timer(ARRIVE_HOLD, true).timeout
	if click_to_start and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Browser: one click is needed to lock the mouse. The battle waits (single player)
		# and shows through the screen. Before B2 the status line and the full bar were hidden
		# here (owner); now the soldier stands at the end with the red ALARM line above the prompt.
		if not _march_on:
			status.visible = false
			bar.visible = false
		start_label.visible = true
		background.modulate.a = 0.55
		if NetworkManager.is_single_player():
			get_tree().paused = true
		_waiting_for_click = true
		return
	queue_free()


func _step(value: float, text: String) -> void:
	_target_value = maxf(_target_value, value)
	if not _march_on: # (with the marching path the phrases are the status line)
		status.text = text


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _fail() -> void:
	status.text = "Loading failed – please reload the page."
	push_error("LoadingScreen: could not load %s" % target_scene)
