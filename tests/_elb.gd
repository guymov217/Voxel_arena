extends Node
func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(12, 0, 12))
	var e = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {"main": "gladius", "off": ""}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
	e.erase("bot")
	var hp := {"x": 1.8, "y": 0.3}
	e.drive = func(_e): return {"main": hp, "off": {"x": -0.35, "y": 0.1}, "power": true}
	var f: Fighter = e.f
	for i in 120:
		await get_tree().physics_frame
	hp.x = -1.8
	var out := []
	for i in 60:
		await get_tree().physics_frame
		if i % 6 == 0:
			var fore: VoxelPart = f.arm.R.fore
			var j: Generic6DOFJoint3D = fore.joint
			var b := (PD.quat_of(f.arm.R.upper) * Vector3.DOWN).angle_to(PD.quat_of(fore) * Vector3.DOWN)
			out.append("bend %.2f set %s lim [%.2f,%.2f]" % [b, str(fore.get_meta("elbow_set", "-")), j.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT), j.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)])
	print("ELB ", " | ".join(out))
	get_tree().quit()
