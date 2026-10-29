extends Node
## Runs the benchmark from the main menu and prints the results (CPU timings are
## meaningful headless; graphics numbers need a real GPU / browser).

func _ready() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await get_tree().create_timer(0.5).timeout
	get_tree().current_scene.get_node("Center/VBox/BenchmarkButton").pressed.emit()
	await get_tree().create_timer(1.0).timeout
	var ok: bool = get_tree().current_scene.name == "Benchmark"
	print(("PASS" if ok else "FAIL") + "  benchmark scene started")
	await get_tree().create_timer(63.0).timeout
	var bench: Node = get_tree().current_scene
	var enemies: int = get_tree().get_nodes_in_group("enemies").size()
	print(("PASS" if enemies >= 16 else "FAIL") + "  %d soldiers spawned" % enemies)
	print(("PASS" if bench._results_text != "" else "FAIL") + "  results screen shown")
	print("RESULT: done")
	get_tree().quit()
