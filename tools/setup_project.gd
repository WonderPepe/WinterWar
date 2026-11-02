extends SceneTree
## One-off helper (not part of the game): writes project settings and the input map
## so project.godot is generated in Godot's own exact format.

func key(physical: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.device = -1  # -1 = any device
	e.physical_keycode = physical
	return e

func mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.device = -1
	e.button_index = button
	return e

func action(name: String, events: Array) -> void:
	ProjectSettings.set_setting("input/" + name, {"deadzone": 0.2, "events": events})

func _init() -> void:
	var s := ProjectSettings
	s.set_setting("application/config/description", "Winter War 1939-40 FPS prototype - Battle of Summa")
	# The version players see (main menu). Raise it for every public release – see RELEASES.md.
	s.set_setting("application/config/version", "0.2.5")
	s.set_setting("application/run/main_scene", "res://ui/main_menu.tscn")
	s.set_setting("application/config/features", PackedStringArray(["4.7", "GL Compatibility"]))

	# Renderer: Compatibility (OpenGL / WebGL 2) everywhere, required for web export
	s.set_setting("rendering/renderer/rendering_method", "gl_compatibility")
	s.set_setting("rendering/renderer/rendering_method.mobile", "gl_compatibility")
	s.set_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
	s.set_setting("rendering/textures/vram_compression/import_etc2_astc", true)

	# Window
	s.set_setting("display/window/size/viewport_width", 1280)
	s.set_setting("display/window/size/viewport_height", 720)
	s.set_setting("display/window/stretch/mode", "canvas_items") # menus/HUD scale with the window (browser!)
	s.set_setting("display/window/stretch/aspect", "expand")

	# Physics
	s.set_setting("physics/3d/physics_engine", "Jolt Physics")
	s.set_setting("physics/common/physics_ticks_per_second", 60)
	s.set_setting("layer_names/3d_physics/layer_1", "world")
	s.set_setting("layer_names/3d_physics/layer_2", "players")
	s.set_setting("layer_names/3d_physics/layer_3", "enemies")
	s.set_setting("layer_names/3d_physics/layer_4", "triggers")

	# Autoloads ("*" = also make it a global name you can use from any script)
	s.set_setting("autoload/NetworkManager", "*res://autoload/network_manager.gd")
	s.set_setting("autoload/Settings", "*res://autoload/settings.gd")

	# Loading screen: winter colours instead of the Godot logo (also used by the web loader)
	s.set_setting("application/boot_splash/bg_color", Color(0.13, 0.16, 0.21))
	s.set_setting("application/boot_splash/show_image", false)
	s.set_setting("rendering/environment/defaults/default_clear_color", Color(0.13, 0.16, 0.21))
	# Smaller shadow map: plenty for one sun with a short shadow distance, cheaper on the web
	s.set_setting("rendering/lights_and_shadows/directional_shadow/size", 2048)

	# Input map. Physical keys = same key POSITION on any keyboard layout (Finnish, US...)
	action("move_forward", [key(KEY_W)])
	action("move_back", [key(KEY_S)])
	action("move_left", [key(KEY_A)])
	action("move_right", [key(KEY_D)])
	action("jump", [key(KEY_SPACE)])
	action("sprint", [key(KEY_SHIFT)])
	action("crouch", [key(KEY_C), key(KEY_CTRL)])
	action("fire", [mouse(MOUSE_BUTTON_LEFT)])
	action("aim", [mouse(MOUSE_BUTTON_RIGHT)])
	action("reload", [key(KEY_R)])
	action("weapon_1", [key(KEY_1)])
	action("weapon_2", [key(KEY_2)])
	action("interact", [key(KEY_F)]) # use / leave the Maxim, take from an ammo crate
	action("bandage", [key(KEY_B)])
	action("pause", [key(KEY_ESCAPE)])
	action("debug_god_mode", [key(KEY_F1)])
	action("debug_enemy_labels", [key(KEY_F2)])
	action("debug_overlay", [key(KEY_F3)])
	action("molotov", [key(KEY_G)])              # T2: Molotov cocktail in the hand
	action("debug_spawn_tank", [key(KEY_F9)])    # T1 test: a tank on a random route (editor only)
	action("debug_destroy_tank", [key(KEY_F10)]) # T1 test: knock out the nearest tank
	s.set_setting("input/release_mouse", null) # replaced by "pause" in M4

	var err := s.save()
	print("project.godot saved: ", error_string(err))
	quit()
