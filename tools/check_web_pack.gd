extends SceneTree
## Checks the EXPORTED game data (export/web/index.pck), not the project files:
##   godot --headless --main-pack export/web/index.pck --script <full path>/tools/check_web_pack.gd
## Found in P2: a "@export var x: PackedStringArray = []" lost its values when the export
## converted scenes to binary – the web build then showed parts that should be hidden.

func _initialize() -> void:
	run()


func run() -> void:
	await process_frame
	var fails := 0
	var vm: Node = load("res://scenes/weapons/mosin_viewmodel.tscn").instantiate()
	root.add_child(vm)
	var gun: Node = load("res://scenes/weapons/maxim_mg.tscn").instantiate()
	root.add_child(gun)
	await process_frame
	for check in [
		[(vm.get("hidden_part_names") as PackedStringArray).size() == 3, "Mosin hidden parts kept in the export"],
		[(vm.get("bolt_part_names") as PackedStringArray).size() == 5, "Mosin bolt parts kept in the export"],
		[(gun.get("turning_part_names") as PackedStringArray).size() > 10, "Maxim turning parts kept in the export"],
		[not (vm.find_child("LP_Clip", true, false) as Node3D).visible, "loose clip hidden in the export"],
	]:
		print(("PASS  " if check[0] else "FAIL  ") + check[1])
		if not check[0]:
			fails += 1
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit()
