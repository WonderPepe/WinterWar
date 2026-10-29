extends SceneTree
## Launcher for the test and screenshot scripts in this folder:
##   godot --headless --path . --script tools/run.gd -- tools/test_m1.gd
## The test scripts are normal Nodes that are loaded only after the game's autoloads
## (NetworkManager, Settings) exist - a --script file itself is compiled too early to use them.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: godot --headless --path . --script tools/run.gd -- tools/<script>.gd")
		quit(1)
		return
	var path: String = args[0]
	if not path.begins_with("res://"):
		path = "res://" + path
	var runner: Node = load(path).new()
	runner.name = "TestRunner"
	runner.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(runner)
