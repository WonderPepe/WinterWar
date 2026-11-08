extends Node
## Test for the battle briefings (B1): the loading screen shows the briefing of battle 1 (or of
## the Test Mode battle), with date, weather, text and photo; no briefing without the click
## prompt (benchmark). Not part of the game:
##   godot --headless --path . --script tools/run.gd -- tools/test_b1.gd

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _ready() -> void:
	await get_tree().process_frame
	LoadingScreen.target_scene = "res://ui/controls_panel.tscn" # tiny scene instead of the whole game
	LoadingScreen.click_to_start = true
	MatchDirector.test_start_wave = 0
	var ls: Node = load("res://ui/loading_screen.tscn").instantiate()
	add_child(ls)
	await get_tree().process_frame
	var row := ls.get_node_or_null("Root/Center/VBox/Briefing")
	check(row != null and row.get_index() == 1, "battle 1: a briefing under the title")
	var texts: Array[String] = _labels(row)
	check(texts.has("30 November 1939") and texts.has("Weather: Light Snowfall")
			and texts.any(func(t: String) -> bool: return t.begins_with("Soviet forces have crossed the border")),
			"…date, weather and text of 30 November 1939")
	check(_has_photo(row), "…with its photo")
	# B2: the marching path, the phrases, the snow.
	check(ls.get_node_or_null("Root/Center/VBox/MarchPath") != null and ls.get_node_or_null("Root/Center/VBox/Percent") != null
			and ls.get_node_or_null("Root/Snow") != null and not ls.bar.visible, "marching path, percentage and snow built; old bar hidden")
	check(LoadingScreen.phrase_for(0) == "Drafting recruits..." and LoadingScreen.phrase_for(5.9) == "Drafting recruits..."
			and LoadingScreen.phrase_for(6) == "Mixing Molotov cocktails in the local brewery..."
			and LoadingScreen.phrase_for(50) == "Cleaning the Pystykorva rifle barrels..."
			and LoadingScreen.phrase_for(97) == "Jamming enemy tanks with logs..."
			and LoadingScreen.phrase_for(99) == "Cocking the Suomi submachine gun..."
			and LoadingScreen.phrase_for(100) == "ALARM! TO THE POSITIONS!", "phrases follow the percentage; 100 % = ALARM")
	check(ls.status.text == "Drafting recruits...", "status line starts with the first phrase")
	# The soldier never gets ahead of the minimum march time.
	await get_tree().create_timer(1.0).timeout
	check(ls._shown > 10.0 and ls._shown < 40.0, "after ~1 s the soldier has walked a quarter of the minimum time (%.0f %%)" % ls._shown)
	ls.free()

	MatchDirector.test_start_wave = 9
	ls = load("res://ui/loading_screen.tscn").instantiate()
	add_child(ls)
	await get_tree().process_frame
	texts = _labels(ls.get_node_or_null("Root/Center/VBox/Briefing"))
	check(texts.has("13 February 1940") and texts.has("Weather: Low Cloud and Fog\nVisibility: Moderate"),
			"Test Mode battle 9: the briefing of 13 February 1940")
	ls.free()

	MatchDirector.test_start_wave = 0
	LoadingScreen.click_to_start = false
	ls = load("res://ui/loading_screen.tscn").instantiate()
	add_child(ls)
	await get_tree().process_frame
	check(ls.get_node_or_null("Root/Center/VBox/Briefing") == null, "benchmark (no click prompt): no briefing")
	check(ls.get_node_or_null("Root/Center/VBox/MarchPath") == null and ls.bar.visible, "benchmark: the old bar, no marching path")
	ls.free()
	LoadingScreen.click_to_start = true

	print("RESULT: %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _labels(n: Node) -> Array[String]:
	var out: Array[String] = []
	if n == null:
		return out
	for l in n.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return out


func _has_photo(n: Node) -> bool:
	for t in n.find_children("*", "TextureRect", true, false):
		if (t as TextureRect).texture != null:
			return true
	return false
