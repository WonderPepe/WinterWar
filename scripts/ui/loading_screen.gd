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

const PHOTO_BOX: Vector2 = Vector2(520, 340) ## Largest size of the briefing photo.

## The scene to load next (set by go()).
static var target_scene: String = "res://scenes/game.tscn"
## Ask for a click at the end if the mouse isn't locked yet (not for the benchmark).
static var click_to_start: bool = true

var _target_value: float = 0.0
var _waiting_for_click: bool = false

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
	bar.value = 0.0
	start_label.visible = false
	_run()


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
	if _waiting_for_click:
		start_label.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 250.0)


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
	if click_to_start and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Browser: one click is needed to lock the mouse. The battle waits (single player)
		# and shows through the screen. The status line and the full bar are hidden then:
		# "CLICK TO START THE BATTLE" says it all (owner).
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
	status.text = text


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _fail() -> void:
	status.text = "Loading failed – please reload the page."
	push_error("LoadingScreen: could not load %s" % target_scene)
