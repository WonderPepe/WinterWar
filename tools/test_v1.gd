extends Node
## Test for V1 (enemy muzzle flashes easier to see at dusk / night): darkness per battle look,
## flash size and brightness unchanged by day and a little more at night, the brief glow only in
## the dark, only near the camera and from at most two lights. Not part of the game:
##   godot --headless --path . --script tools/run.gd -- tools/test_v1.gd
## (How much easier to see: tools/shots_flash.gd, needs a GL window.)

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _ready() -> void:
	await get_tree().process_frame
	run()


func lit_lights(fx: ImpactEffects) -> int:
	var n: int = 0
	for l in fx._flash_lights:
		if l.visible:
			n += 1
	return n


func run() -> void:
	var d: Array[float] = []
	for i in 10:
		d.append((load("res://resources/weather/battle_%02d.tres" % (i + 1)) as WeatherData).darkness())
	print("darkness per battle: ", d)
	var w10 := load("res://resources/weather/battle_10.tres") as WeatherData
	check(d[2] == 0.0 and d[3] == 0.0 and d[6] == 0.0 and d[7] == 0.0, "day and fog battles (3, 4, 7, 8) are not dark")
	check(w10.end_look.darkness() > d[9] and w10.end_look.darkness() > 0.9, "battle 10: darker as the dusk deepens")
	check(d[1] > 0.9 and d[5] > 0.9, "battles 2 and 6 are night")
	check(d[0] > 0.3 and d[0] < 0.7, "battle 1 (moonlit) is half dark")

	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var dusk := game.get_node("Dusk") as DuskLight
	var fx := get_tree().get_first_node_in_group("impact_effects") as ImpactEffects
	var cam := get_viewport().get_camera_3d()
	var near: Vector3 = cam.global_position - cam.global_basis.z * 30.0
	var far: Vector3 = cam.global_position - cam.global_basis.z * 150.0

	await get_tree().create_timer(0.2).timeout # the warm-up flash goes out
	dusk._show_battle(3)
	check(ImpactEffects.darkness == 0.0, "DuskLight passes the darkness on (battle 3: 0)")
	fx.spawn_flash(near)
	check(is_equal_approx(fx._flash_quad.size.x, 0.35) and fx._flash_mat.albedo_color.is_equal_approx(ImpactEffects.FLASH_COLOR),
			"day: the flash is exactly as before (0.35 m, same colour)")
	check(lit_lights(fx) == 0, "day: no glow")

	await get_tree().create_timer(0.15).timeout
	dusk._show_battle(6)
	check(ImpactEffects.darkness > 0.9, "battle 6: dark")
	fx.spawn_flash(far)
	check(fx._flash_quad.size.x > 0.37 and fx._flash_quad.size.x < 0.42, "night: the flash is a little bigger (%.3f m)" % fx._flash_quad.size.x)
	check(fx._flash_mat.albedo_color.r > 1.05 and fx._flash_mat.albedo_color.r < 1.25, "night: and brighter (×%.2f)" % fx._flash_mat.albedo_color.r)
	check(lit_lights(fx) == 0, "night: no glow for a flash far from the camera")
	for i in 5:
		fx.spawn_flash(near)
	check(lit_lights(fx) == 2, "night: many flashes nearby light at most two lights")
	var ok_energy: bool = true
	for l in fx._flash_lights:
		ok_energy = ok_energy and not l.shadow_enabled and l.omni_range <= 4.0 and l.light_energy <= 0.5
	check(ok_energy, "the glow is small, weak and casts no shadow")
	await get_tree().create_timer(0.15).timeout
	check(lit_lights(fx) == 0, "the glow goes out after the flash")

	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(ImpactEffects.darkness == 0.0, "the darkness does not outlive the match")
	print("TEST V1 DONE: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)
