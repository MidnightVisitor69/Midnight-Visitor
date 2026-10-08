extends SceneTree
## One-off generator for client/default_bus_layout.tres (M-001). Writing the
## .tres by hand is guesswork about the resource format; letting the engine
## serialise the buses it just built guarantees a file it can read back.
##   godot --headless --path client --script res://tools/make_bus_layout.gd


func _initialize() -> void:
	AudioServer.add_bus()
	var sfx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(sfx, "SFX")
	AudioServer.set_bus_send(sfx, "Master")
	AudioServer.set_bus_volume_db(sfx, -6.0)

	# Gentle low-pass: the WAVs are already dark, this only rounds off the top.
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 9000.0
	AudioServer.add_bus_effect(sfx, lp, 0)

	# Limiter: overlaps in a fast pack opening must never stack into clipping.
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -3.0
	AudioServer.add_bus_effect(sfx, lim, 1)

	var err := ResourceSaver.save(AudioServer.generate_bus_layout(), "res://default_bus_layout.tres")
	print("save err=", err)
	quit(0 if err == OK else 1)