extends SceneTree
## Screenshots of the menus and HUD for a visual check (not part of the game).

func wait(n: int) -> void:
	for i in n:
		await process_frame

func snap(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://tools/shots/" + file)
	print("saved ", file)

func _initialize() -> void:
	run()

func run() -> void:
	change_scene_to_file("res://ui/main_menu.tscn")
	await wait(30)
	await snap("m4_1_main_menu.png")
	current_scene.get_node("Center/VBox/SinglePlayerButton").pressed.emit()
	await wait(20)
	var pm: Node = current_scene.get_node("PauseMenu")
	pm.open()
	await wait(5)
	await snap("m4_2_pause.png")
	pm.resume()
	pm.free()
	var p: Player = get_nodes_in_group("players")[0]
	p.input.set_process(false)
	var waves: WaveSpawner = get_first_node_in_group("wave_spawner")
	waves._timer = 0.0
	p.input.look_pitch = deg_to_rad(2)
	await wait(5)
	p.take_damage(35, -1, Vector3.ZERO, Vector3.UP)
	p.weapons.hit_confirmed.emit(false)
	await wait(1)
	await snap("m4_3_hud.png")
	p.take_damage(200, -1, Vector3.ZERO, Vector3.UP)
	await wait(15)
	await snap("m4_4_dead.png")
	quit()
