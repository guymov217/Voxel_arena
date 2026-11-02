extends Node
## Two swords held out in front after turning on the spot (facetremor.gd: turned, the trunk sways
## and the blades shake; not turned, or with empty hands, all is still): step by step, how the
## trunk moves and where each hand and its mark are against the trunk. `-- --probe turntrace`.
## YAW (1.0): where he turns to; INSTANT (1): turned at once, not over a second.

func _yl(f: Fighter, p: Vector3) -> Vector3:
	return (Quaternion(Vector3.UP, f.yaw).inverse() * (p - f.torso.global_position)).snapped(Vector3(0.001, 0.001, 0.001))

func _ready() -> void:
	var yaw := float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 1.0
	var instant := OS.get_environment("INSTANT") != "0"
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {} if OS.get_environment("NOARMS") != "" else ({"main": OS.get_environment("LOAD").split("+")[0], "off": OS.get_environment("LOAD").split("+")[1]} if OS.get_environment("LOAD") != "" else {"main": "gladius", "off": "gladius"})})
	var f: Fighter = m.me.f
	f.teleport(Vector3(-2.1, 0, -5.9))
	if OS.get_environment("NOCOLLIDE") != "":
		for sd in ["R", "L"]:
			f.arm[sd].fore.add_collision_exception_with(f.torso)
			f.arm[sd].upper.add_collision_exception_with(f.torso)
	var ramp := [0.0]
	m.me.drive = func(_e):
		ramp[0] = minf(1.0, ramp[0] + 1.0 / 120.0)
		var yw: float = yaw if instant else yaw * ramp[0]
		if OS.get_environment("NOARMS") != "":
			return {"look": {"yaw": yw, "pitch": 0.0}}
		return {"main": {"x": 0.25, "y": 0.3}, "off": {"x": -0.25, "y": 0.3}, "look": {"yaw": yw, "pitch": 0.0}}
	for i in 240:
		await get_tree().physics_frame
	for i in 240:
		await get_tree().physics_frame
		if i % (int(OS.get_environment("EVERY")) if OS.get_environment("EVERY") != "" else 3) != 0:
			continue
		var tq := PD.quat_of(f.torso)
		var fw := tq * Vector3(0, 0, 1)
		var face := wrapf(atan2(fw.x, fw.z) - f.yaw, -PI, PI)
		var yq := Quaternion(Vector3.UP, f.yaw)
		var lv: Vector3 = yq.inverse() * f.torso.linear_velocity
		var av: Vector3 = yq.inverse() * f.torso.angular_velocity
		var s := "T %3d face %+.3f lv %s av %s" % [i, face, str((lv * 1000.0).snapped(Vector3.ONE)), str(av.snapped(Vector3(0.01, 0.01, 0.01)))]
		for sd in ["R", "L"]:
			var lead = f.hand_lead[sd]
			s += "  %s hand %s lead %s strain %.2f hold %.2f tv %.2f" % [sd, str(_yl(f, f.hand_world(sd))), str(_yl(f, lead)) if lead != null else "-", float(f.arm_strain[sd]), float(f.swing_hold[sd]), (f.target_vel[sd] as Vector3).length()]
		for sd in ["R", "L"]:
			var w = f.weapons[sd]
			if w:
				s += "  W%s touches %s" % [sd, str(w.get_colliding_bodies().map(func(b): return String(b.name)))]
		var bi: Transform3D = f.torso.global_transform.affine_inverse()
		var SD := OS.get_environment("SIDE") if OS.get_environment("SIDE") != "" else "R"
		var up: VoxelPart = f.arm[SD].upper
		var fo: VoxelPart = f.arm[SD].fore
		s += "  [torso frame: half %s  elbowR %s  foreR %s  handR %s  fore half %s]" % [str(f.torso.half_ext.snapped(Vector3(0.001, 0.001, 0.001))), str((bi * (up.global_transform * Vector3(0, -up.half_ext.y, 0))).snapped(Vector3(0.001, 0.001, 0.001))), str((bi * fo.global_position).snapped(Vector3(0.001, 0.001, 0.001))), str((bi * f.hand_world(SD)).snapped(Vector3(0.001, 0.001, 0.001))), str(fo.half_ext.snapped(Vector3(0.001, 0.001, 0.001)))]
		if f.weapons[SD]:
			var tqi := PD.quat_of(f.torso).inverse()
			var wq := PD.quat_of(f.weapons[SD])
			var uq := PD.quat_of(up)
			var fq := PD.quat_of(fo)
			# the forearm's turn about its own length against the upper arm's
			var tw := (uq.inverse() * fq).get_euler()
			s += "  {blade %s edge %s up_fwd %s fore_fwd %s turn %s set %s lock %s}" % [str((tqi * (wq * Vector3.UP)).snapped(Vector3(0.01, 0.01, 0.01))), str((tqi * (wq * Vector3.RIGHT)).snapped(Vector3(0.01, 0.01, 0.01))), str((tqi * (uq * Vector3(0, 0, 1))).snapped(Vector3(0.01, 0.01, 0.01))), str((tqi * (fq * Vector3(0, 0, 1))).snapped(Vector3(0.01, 0.01, 0.01))), str(tw.snapped(Vector3(0.01, 0.01, 0.01))), str(fo.get_meta("elbow_set", "-")), str(fo.get_meta("elbow_locked", "-"))]
		if f.has_meta("dbg_" + SD):
			var dg: Array = f.get_meta("dbg_" + SD)
			var elbow_now: Vector3 = up.global_transform * Vector3(0, -up.half_ext.y, 0)
			s += "  <want elbow %s now %s | goal %s hand %s | mark %s>" % [str(_yl(f, dg[0])), str(_yl(f, elbow_now)), str(_yl(f, dg[1])), str(_yl(f, f.hand_world(SD))), str(_yl(f, dg[2]))]
		for pn in ["upperArmR", "forearmR", "upperArmL", "forearmL", "torso", "thighL", "thighR"]:
			var pp = f.by_name.get(pn)
			if pp and pp.contact_monitor and not pp.get_colliding_bodies().is_empty():
				s += "  %s touches %s" % [pn, str(pp.get_colliding_bodies().map(func(b): return String(b.name)))]
		for sd in ["L", "R"]:
			var ft = f.feet[sd]
			if ft != null:
				s += "  F%s %s %s" % [sd, "sw" if ft.swing else "pl", str(_yl(f, ft.anchor))]
		print(s)
	get_tree().quit()
