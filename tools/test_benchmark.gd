extends Node
## Runs the benchmark from the main menu and prints the results (CPU timings are
## meaningful headless; graphics numbers need a real GPU / browser).

func _ready() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await get_tree().create_timer(0.5).timeout
	get_tree().current_scene.get_node("Center/VBox/BenchmarkButton").pressed.emit()
	for i in 100: # through the loading screen
		await get_tree().create_timer(0.1).timeout
		if get_tree().current_scene and get_tree().current_scene.name == "Benchmark":
			break
	var ok: bool = get_tree().current_scene.name == "Benchmark"
	print(("PASS" if ok else "FAIL") + "  benchmark scene started")
	# Count the soldiers during the whole run, not only at the end: the player fires at them, so
	# one may just have fallen when the run ends (A7: was flaky, "15 soldiers spawned").
	var enemies := 0
	for i in 63:
		await get_tree().create_timer(1.0).timeout
		enemies = maxi(enemies, get_tree().get_nodes_in_group("enemies").size())
	var bench: Node = get_tree().current_scene
	print(("PASS" if enemies >= 24 else "FAIL") + "  %d soldiers spawned (most at once; V10c: 24)" % enemies)
	print(("PASS" if bench._results_text != "" else "FAIL") + "  results screen shown")
	print(("PASS" if get_tree().root.get_node_or_null("LoadingScreen") == null else "FAIL") + "  loading screen gone")
	print("RESULT: done")
	get_tree().quit()
