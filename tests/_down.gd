extends Node
func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(12, 0, 12))
	var e = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {"main": OS.get_environment("W") if OS.get_environment("W") != "" else "gladius", "off": ""}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
	e.erase("bot")
	var hp := {"x": 0.0, "y": -1.6}
	e.drive = func(_e): return {"main": hp, "off": {"x": -0.35, "y": 0.1}, "power": true}
	var f: Fighter = e.f
	for i in 200:
		await get_tree().physics_frame
	var tp := f.torso.global_position
	var r := func(v: Vector3) -> String: return str((v).snapped(Vector3.ONE * 0.01))
	var el: Vector3 = f.arm.R.upper.global_transform * f.arm.R.fore.pa
	print("GOT upper ", r.call(PD.quat_of(f.arm.R.upper) * Vector3.DOWN), " fore ", r.call(PD.quat_of(f.arm.R.fore) * Vector3.DOWN), " elbow ", r.call(el - tp), " hand ", r.call(f.hand_world("R") - tp))
	var bend := (PD.quat_of(f.arm.R.upper) * Vector3.DOWN).angle_to(PD.quat_of(f.arm.R.fore) * Vector3.DOWN)
	var uq := PD.quat_of(f.arm.R.upper)
	var rel := uq.inverse() * PD.quat_of(f.arm.R.fore)
	print("JOINT bend %.2f rad, fore in upper frame: euler %s, upper side axis (x) %s" % [bend, r.call(rel.get_euler()), r.call(uq * Vector3.RIGHT)])
	var w: Weapon = f.weapons.R
	var rigid: Vector3 = (PD.quat_of(f.arm.R.fore) * f.grip_q(w)) * Vector3.UP
	var want: Vector3 = (f.aim_q.R as Quaternion) * Vector3.UP
	print("WRIST bent %.0f° from the forearm; aim pitch %d" % [rad_to_deg(rigid.angle_to(PD.quat_of(w) * Vector3.UP)), rad_to_deg(asin(want.y))])
	var tip := w.global_transform * Vector3(0, w.reach, 0)
	print("TIP blade pitch %d, tip %.2f m up, %.2f ahead; torso up %s" % [rad_to_deg(asin((PD.quat_of(w) * Vector3.UP).y)), tip.y, (tip - f.torso.global_position).z, str((PD.quat_of(f.torso) * Vector3.UP).snapped(Vector3.ONE * 0.01))])
	get_tree().quit()
