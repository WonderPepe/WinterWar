extends Node
## G1 screenshots: ammo crate, HUD (bandages, Soviets in the trench), dusk, end screen,
## main menu difficulty (not part of the game). Needs a GL window (xvfb):
##   godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_g1.gd

func _ready() -> void:
	await get_tree().process_frame
	var menu: Node = load("res://ui/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await _shot("g1_menu", 20)
	menu.queue_free()
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await _wait(1.0)
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.set_physics_process(false)
	var spawner: WaveSpawner = get_tree().get_first_node_in_group("wave_spawner")
	spawner.set_process(false)
	var director: MatchDirector = get_tree().get_first_node_in_group("match_director")
	# The ammo niche in the trench.
	var crate := get_tree().get_first_node_in_group("ammo_crates") as Node3D
	p.global_position = crate.global_position + crate.global_basis * Vector3(0.6, 0, -1.6)
	var d: Vector3 = crate.global_position + Vector3(0, 0.3, 0) - (p.global_position + Vector3(0, 1.6, 0))
	p.input.look_yaw = atan2(-d.x, -d.z)
	p.input.look_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	await _shot("g1_crate")
	# HUD: wave 3/8, soldiers in the trench, bandaging.
	p.global_position = Vector3(-10, -1.4, 61)
	p.input.look_yaw = 0.0
	p.input.look_pitch = 0.02
	spawner.wave_number = 3
	director.in_trench = 2
	p.bandages = 1
	await _shot("g1_hud")
	# Dusk (last wave cleared, before the end screen opens).
	var dusk: DuskLight = game.get_node("Dusk")
	dusk.set_process(false)
	dusk._apply(1.0)
	p.global_position = Vector3(-30, 0.0, 40)
	p.input.look_yaw = deg_to_rad(150.0)
	p.input.look_pitch = deg_to_rad(4.0)
	director.in_trench = 0
	await _shot("g1_dusk", 30)
	p.input.look_yaw = 0.0
	await _shot("g1_dusk_front", 30)
	# End screen.
	director.waves_cleared = 8
	director.end_match(MatchDirector.Result.VICTORY)
	await _shot("g1_end", 10)
	get_tree().paused = false
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(n: String, frames: int = 40) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/shots/%s.png" % n)
	print("saved ", n)
