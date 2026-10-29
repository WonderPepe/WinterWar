extends Node
## Checks that mouse motion turns the view (real window under a virtual display).
func _ready() -> void:
	await get_tree().process_frame # the root can't take new children while it is adding us
	get_tree().root.add_child(load("res://scenes/game.tscn").instantiate())
	get_tree().root.get_node("Game/PauseMenu").free() # tests drive the game directly
	run()
func run() -> void:
	for i in 20: await get_tree().process_frame
	var p: Player = get_tree().get_nodes_in_group("players")[0]
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for i in 5: await get_tree().process_frame
	print("mouse mode: ", Input.mouse_mode)
	var yaw0 := p.input.look_yaw
	for i in 10:
		var e := InputEventMouseMotion.new()
		e.position = get_tree().root.get_visible_rect().size / 2.0
		e.global_position = e.position
		e.relative = Vector2(20, 0)
		e.screen_relative = Vector2(20, 0)
		Input.parse_input_event(e)
		await get_tree().process_frame
	print("yaw change: ", p.input.look_yaw - yaw0)
	print("MOUSE LOOK ", "WORKS" if absf(p.input.look_yaw - yaw0) > 0.1 else "BROKEN")
	get_tree().quit()
