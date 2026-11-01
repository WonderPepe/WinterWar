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
	bar.value = 0.0
	start_label.visible = false
	_run()


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
		# and shows through the screen.
		status.text = "The battlefield is ready."
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
