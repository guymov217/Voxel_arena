extends Node

func _ready() -> void:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	var dirs := [Vector3(0, 0, 260), Vector3(260, 0, 0), Vector3(0, 0, -260)]
	var fs := []
	for k in 3:
		fs.append(w.fighter(Vector3(k * 4.0 - 4.0, 0, 0), 0.0, {"main": "gladius", "off": "roundShield"}, {"name": "F%d" % k, "slot": k}))
	for i in 120 * 9:
		for k in 3:
			var f: Fighter = fs[k]
			if i == 60:
				f.fall(1.0, true)
				f.torso.apply_central_impulse(dirs[k])
			f.control(1.0 / 120.0, {"main": {"x": 0.1, "y": 0.1}})
		await get_tree().physics_frame
		if i % 60 == 0:
			var line := "t=%.1f" % (i / 120.0)
			for f in fs:
				line += "  %s %s y=%.2f tilt=%.2f r=%.2f" % [f.display_name, f.state.left(4), f.torso.global_position.y, acos(clampf((PD.quat_of(f.torso) * Vector3.UP).y, -1, 1)), f.rise_t]
			print(line)
	get_tree().quit()
