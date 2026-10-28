extends Node
## The hit-stop holds the clock for a moment and gives it back (`-- --probe impactcheck`, needs a display).
func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
	for i in 5:
		await get_tree().process_frame
	m._impact({"res": {"dmg": 40.0, "severed": []}, "dir": Vector3(1, 0, 0)}, 1.0)
	var held := Engine.time_scale
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400:
		await get_tree().process_frame
	print("IMPACT held at %.2f, back to %.2f after 0.4 s; camera jolt %.3f" % [held, Engine.time_scale, m.cam.jolt.length()])
	get_tree().quit()
