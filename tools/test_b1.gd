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
