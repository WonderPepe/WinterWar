extends Node
## V1: how easy an ENEMY muzzle flash is to spot, per battle look and distance. For each look it
## takes a picture without and with one flash at 60 m and 120 m in front of the trench and prints
## how much the flash stands out (sum of the brightness change around it, and the biggest change).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . --script tools/run.gd -- tools/shots_flash.gd
## Pictures (flash_<look>_<distance>.png, zoomed crop around the flash) go to the user data folder.

const STEPS: Array = [[3, 0.0, "03_day"], [4, 0.0, "04_day"], [7, 0.0, "07_fog"], [9, 0.0, "09"], [5, 0.0, "05"],
		[1, 0.0, "01_moon"], [10, 0.0, "10_dusk"], [10, 1.0, "10_end"], [2, 0.0, "02_night"], [6, 0.0, "06_night"]]
const DISTANCES: Array = [60.0, 120.0]
const BOX: int = 40 ## Half size (pixels) of the area measured around the flash.


func _ready() -> void:
	await get_tree().process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	for i in 30:
		await get_tree().process_frame
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	get_tree().get_first_node_in_group("wave_spawner").set_process(false)
	var dusk: DuskLight = game.get_node("Dusk")
	dusk.set_process(false)
	(game.get_node("HUD") as CanvasLayer).visible = false
	p.global_position = Vector3(-30, 0.0, 40)
	p.input.look_yaw = 0.0
	p.input.look_pitch = 0.0
	var effects := get_tree().get_first_node_in_group("impact_effects") as ImpactEffects
	var cam := get_viewport().get_camera_3d()
	print("look        dist   darkness  sum_diff    peak")
	for s in STEPS:
		dusk._show_battle(s[0])
		dusk._apply_blend(s[1])
		for i in 45:
			await get_tree().process_frame
		for d: float in DISTANCES:
			var pos: Vector3 = _ground(p.global_position + Vector3(0, 0, -d)) + Vector3(0, 1.0, 0)
			Engine.time_scale = 0.001 # snow stands still and the 50 ms flash (and its light) stays on
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var before: Image = get_viewport().get_texture().get_image()
			effects.spawn_flash(pos)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var after: Image = get_viewport().get_texture().get_image()
			Engine.time_scale = 1.0
			var c: Vector2 = cam.unproject_position(pos)
			var sum: float = 0.0
			var peak: float = 0.0
			for y in range(int(c.y) - BOX, int(c.y) + BOX):
				for x in range(int(c.x) - BOX, int(c.x) + BOX):
					if x < 0 or y < 0 or x >= after.get_width() or y >= after.get_height():
						continue
					var e: float = absf(after.get_pixel(x, y).get_luminance() - before.get_pixel(x, y).get_luminance())
					sum += e
					peak = maxf(peak, e)
			var darkness: float = ImpactEffects.darkness
			print("%-11s %4d   %5.2f     %7.2f   %5.3f" % [s[2], d, darkness, sum, peak])
			var crop: Image = after.get_region(Rect2i(int(c.x) - BOX, int(c.y) - BOX, BOX * 2, BOX * 2))
			crop.resize(BOX * 8, BOX * 8, Image.INTERPOLATE_NEAREST)
			crop.save_png("user://flash_%s_%d.png" % [s[2], d])
			for i in 10: # let the flash go out
				await get_tree().process_frame
	get_tree().quit()


func _ground(at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 200, 0), at + Vector3(0, -200, 0))
	var hit: Dictionary = get_viewport().world_3d.direct_space_state.intersect_ray(q)
	return hit.position if hit else at
