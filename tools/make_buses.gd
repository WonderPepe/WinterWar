extends SceneTree
## Writes default_bus_layout.tres (the audio "mixer"), not part of the game:
##   godot --headless --path . --script tools/make_buses.gd
## Master
##  ├── SFX       guns, footsteps, impacts – with an outdoor echo (reverb)
##  ├── Ambience  wind and the distant battle – low-pass filter (muffled in the trench/bunker)
##  └── UI        menu and HUD sounds (hit tick)

func _initialize() -> void:
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(1)
	_add_bus("SFX")
	var echo := AudioEffectReverb.new()
	echo.room_size = 0.85    # a big open space
	echo.damping = 0.6       # snow swallows the high tones of the echo
	echo.spread = 1.0
	echo.hipass = 0.15       # keep the boom out of the echo (it would sound like a hall)
	echo.predelay_msec = 120.0 # the echo comes back from the forest edge a moment later
	echo.predelay_feedback = 0.25
	echo.dry = 1.0
	echo.wet = 0.14
	AudioServer.add_bus_effect(1, echo)
	var limiter := AudioEffectHardLimiter.new() # many shots at once must not distort
	AudioServer.add_bus_effect(1, limiter)
	_add_bus("Ambience")
	var muffle := AudioEffectLowPassFilter.new()
	muffle.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(2, muffle)
	AudioServer.set_bus_volume_db(2, -6.0)
	_add_bus("UI")
	var err := ResourceSaver.save(AudioServer.generate_bus_layout(), "res://default_bus_layout.tres")
	print("default_bus_layout.tres: ", error_string(err))
	quit()


func _add_bus(n: String) -> void:
	AudioServer.add_bus()
	var i: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, n)
	AudioServer.set_bus_send(i, "Master")
