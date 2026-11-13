extends Node
## Automated test for P3 "3D resolution cap" (review issue P1; not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_p3.gd
## Uses user://settings.cfg; the file that was there before the test is put back at the end.

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


## Lines of 3D picture for a window `h` pixels tall on a quality level.
func lines(h: int, q: Settings.Quality, capped: bool = true) -> int:
	var p: Dictionary = Settings.PRESETS[q]
	return roundi(h * Settings.scale_for(h, p.render_scale, p.max_lines, capped))


func _ready() -> void:
	await get_tree().process_frame
	var backup: String = FileAccess.get_file_as_string(Settings.SAVE_PATH) if FileAccess.file_exists(Settings.SAVE_PATH) else ""
	var q0: Settings.Quality = Settings.quality
	var r0: Settings.Resolution = Settings.resolution
	var root: Window = get_tree().root
	var size0: Vector2i = root.size
	const L := Settings.Quality.LOW
	const M := Settings.Quality.MEDIUM
	const H := Settings.Quality.HIGH

	# --- The maths, per screen height ---
	check(lines(720, H) == 720 and lines(720, M) == 648 and lines(720, L) == 540, "720p window: unchanged (720 / 648 / 540 lines)")
	check(lines(1080, H) == 1080 and lines(1080, M) == 900 and lines(1080, L) == 720, "1080p: 1080 / 900 / 720 lines")
	check(lines(1440, H) == 1080 and lines(1440, M) == 900 and lines(1440, L) == 720, "1440p: capped to 1080 / 900 / 720 lines")
	check(lines(2160, H) == 1080 and lines(2160, M) == 900 and lines(2160, L) == 720, "4K: capped to 1080 / 900 / 720 lines")
	check(lines(2160, H, false) == 2160 and lines(2160, M, false) == 1944 and lines(2160, L, false) == 1620, "Full: no cap (4K: 2160 / 1944 / 1620 lines)")
	check(is_equal_approx(Settings.scale_for(4320, 0.75, 720, true), 0.25), "never below Godot's smallest scale (0.25)")
	check(is_equal_approx(Settings.scale_for(0, 0.9, 900, true), 0.9), "a window with no height does not break the maths")

	# --- Applied to the real window, and again when its size changes ---
	Settings.set_quality(H)
	Settings.set_resolution(Settings.Resolution.AUTO)
	root.size = Vector2i(3840, 2160)
	await get_tree().process_frame
	await get_tree().process_frame
	if root.size.y == 2160:
		check(is_equal_approx(root.scaling_3d_scale, 0.5) and Settings.render_size() == Vector2i(1920, 1080), "4K window on High + Auto: 3D picture is 1920 x 1080 (scale 0.5)")
		Settings.set_quality(L)
		check(Settings.render_size() == Vector2i(1280, 720), "4K window on Low + Auto: 1280 x 720")
		Settings.set_resolution(Settings.Resolution.FULL)
		check(is_equal_approx(root.scaling_3d_scale, 0.75), "Full: the preset's own 75 % again")
		Settings.set_quality(H)
		check(is_equal_approx(root.scaling_3d_scale, 1.0) and Settings.render_size() == Vector2i(3840, 2160), "Full + High: every pixel of the 4K window")
		Settings.set_resolution(Settings.Resolution.AUTO)
		root.size = Vector2i(1280, 720)
		await get_tree().process_frame
		await get_tree().process_frame
		check(is_equal_approx(root.scaling_3d_scale, 1.0), "window made small again: back to 100 %")
	else:
		print("SKIP  this display can't make a 4K window (%s) - window checks skipped" % root.size)

	# --- Saved and shown in the Settings menu ---
	Settings.set_resolution(Settings.Resolution.FULL)
	var cfg := ConfigFile.new()
	check(cfg.load(Settings.SAVE_PATH) == OK and cfg.get_value("graphics", "resolution") == Settings.Resolution.FULL, "3D resolution saved to user://settings.cfg")
	Settings.resolution = Settings.Resolution.AUTO
	Settings._load()
	check(Settings.resolution == Settings.Resolution.FULL, "... and loaded back")
	var menu: SettingsMenu = load("res://ui/settings_menu.tscn").instantiate()
	add_child(menu)
	menu.open()
	check(menu.resolution.item_count == 2 and menu.resolution.selected == Settings.Resolution.FULL, "Settings menu: Auto / Full, showing the saved choice")
	menu.resolution.item_selected.emit(Settings.Resolution.AUTO)
	var size_3d: Vector2i = Settings.render_size()
	check(Settings.resolution == Settings.Resolution.AUTO and menu.resolution_hint.text == "3D picture: %d × %d" % [size_3d.x, size_3d.y], "choosing Auto in the menu applies it; hint: \"%s\"" % menu.resolution_hint.text)
	menu.queue_free()

	# Clean up: the earlier settings and file back in place.
	root.size = size0
	Settings.quality = q0
	Settings.resolution = r0
	Settings.apply()
	DirAccess.remove_absolute(Settings.SAVE_PATH)
	if backup != "":
		var f := FileAccess.open(Settings.SAVE_PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	print("RESULT: %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
