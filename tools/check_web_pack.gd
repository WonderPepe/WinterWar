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
		[vm.get_node_or_null("Model/GripR") != null and vm.get_node_or_null("Model/Bolt/BoltGrip") != null, "W2: hand grip points in the export"],
		[gun.get("_belt_anim") != null and gun.get("_turn_pivot") != null, "W2: Maxim belt animation re-pointed in the export"],
		[ResourceLoader.exists("res://assets/audio/steam_hiss.wav"), "W2: steam sound in the export"],
		[(load("res://resources/difficulty/normal.tres") as DifficultyData).waves.size() == 8, "G2: wave list kept in the export"],
		[(load("res://resources/difficulty/hard.tres") as DifficultyData).waves[9].mg_teams == 3, "G2: wave list values kept in the export"],
		[(load("res://resources/enemies/soviet_officer.tres") as EnemyData).kind == EnemyData.Kind.OFFICER, "G2: officer data in the export"],
		[ResourceLoader.exists("res://scenes/enemies/soviet_mg_gunner.tscn"), "G2: machine-gunner scene in the export"],
		[ResourceLoader.exists("res://assets/audio/officer_whistle_placeholder.wav"), "G2: whistle sound in the export"],
		[(load("res://resources/front_reports.tres") as FrontReports).texts.size() == 8, "front reports in the export"],
	]:
		print(("PASS  " if check[0] else "FAIL  ") + check[1])
		if not check[0]:
			fails += 1
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit()
