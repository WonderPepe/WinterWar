extends Node
## Screenshots of the Controls screen (main menu + pause menu) and the first-tank-battle
## Molotov hint (not part of the game). Saved in tools/shots/:
##   xvfb-run godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_controls.gd

var _out: String


func _ready() -> void:
	await get_tree().process_frame
	_out = ProjectSettings.globalize_path("res://tools/shots/")
	DirAccess.make_dir_recursive_absolute(_out)
	get_window().size = Vector2i(1280, 720) # a typical browser window, the smallest common case

	var menu: MainMenu = load("res://ui/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await get_tree().create_timer(0.5).timeout
	await _shot("controls_main_menu")
	menu.controls_button.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	await _shot("controls_panel")
	menu.controls_panel.scroll.scroll_vertical = 10000
	await get_tree().create_timer(0.2).timeout
	await _shot("controls_panel_bottom")
	menu.queue_free()
	await get_tree().process_frame

	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	for i in 30:
		await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout
	var pm := game.get_node("PauseMenu")
	pm.open()
	pm.controls_button.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	await _shot("controls_pause")
	pm.controls_panel.close()
	pm.resume()
	pm.free()
	var hud := game.get_node("HUD")
	hud._show_tank_hint()
	await get_tree().create_timer(5.0).timeout # the hint waits for the BATTLE banner to fade
	await _shot("tank_hint")
	get_tree().quit()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + file + ".png")
	print("saved ", file)
