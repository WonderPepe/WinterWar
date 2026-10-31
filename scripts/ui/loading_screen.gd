class_name LoadingScreen
extends CanvasLayer
## Shown between the main menu and the battle, with a progress bar. Loading the battle takes a
## moment (especially in a browser): the scene and its 3D models are read, the terrain and the
## forest are built, and every effect is drawn once so the browser can prepare its shaders.
##
## Use: LoadingScreen.go(get_tree(), "res://scenes/game.tscn")
## This screen stays on top while the game starts underneath, and removes itself when ready.

const SCENE_PATH: String = "res://ui/loading_screen.tscn"
const TIPS: Array[String] = [
	"Hold the line until dusk. If too many Soviets get into the trench, the line breaks.",
	"F next to an ammo crate refills your spare ammunition and bandages.",
	"B puts on a bandage: +50 health, but you can't shoot for 3 seconds.",
	"The Maxim in the bunker overheats in long bursts – fire short bursts.",
	"Right mouse on the Maxim: aim through its own sights.",
	"Crouch (C) in the trench: you are harder to spot and to hit.",
	"Soldiers kneel to fire, then rush forward. Shoot them while they kneel.",
]

## The scene to load next (set by go()).
static var target_scene: String = "res://scenes/game.tscn"

var _target_value: float = 0.0

@onready var bar: ProgressBar = $Root/Center/VBox/Bar
@onready var status: Label = $Root/Center/VBox/Status
@onready var tip: Label = $Root/Center/VBox/Tip


## Switch to the loading screen, which then loads `scene`.
static func go(tree: SceneTree, scene: String) -> void:
	target_scene = scene
	tree.paused = false
	tree.change_scene_to_file(SCENE_PATH)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps going even if the game pauses underneath
	layer = 60 # above the game's own screens (HUD, pause menu, shader warm-up)
	tip.text = "Tip: " + TIPS.pick_random()
	bar.value = 0.0
	_run()


func _process(delta: float) -> void:
	# The bar glides towards the real progress instead of jumping.
	bar.value = move_toward(bar.value, _target_value * 100.0, delta * 120.0)


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
