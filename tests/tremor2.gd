extends Node
## One shaking hold step by step (tremor.gd found the off hand of two swords held low shaking,
## and the warhammer held forward): where the hand is each step against the trunk, and which
## way the arm is being pushed out of the trunk's box at each of its points (front or aside, the
## rule in Fighter._keep_arm_out). `-- --probe tremor2`. LOAD (gladius+gladius, warhammer),
## HOLD (low, forward, wide), HURT (1 or 0), SIDE (L or R).

func _ready() -> void:
	var load_s := OS.get_environment("LOAD") if OS.get_environment("LOAD") != "" else "gladius+gladius"
	var hold := OS.get_environment("HOLD") if OS.get_environment("HOLD") != "" else "low"
	var hurt := OS.get_environment("HURT") != "0"
	var side := OS.get_environment("SIDE") if OS.get_environment("SIDE") != "" else "L"
	var holds := {
		"low": [{"x": 0.2, "y": -0.9}, {"x": -0.2, "y": -0.9}],
		"forward": [{"x": 0.0, "y": 0.35}, {"x": 0.0, "y": 0.3}],
		"wide": [{"x": 1.6, "y": 0.3}, {"x": -1.6, "y": 0.3}],
		"high": [{"x": 0.2, "y": 1.1}, {"x": -0.2, "y": 1.0}],
	}
	var m := Match.new()
	add_child(m)
	var parts := load_s.split("+")
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "loadout": {"main": parts[0], "off": parts[1] if parts.size() > 1 else ""}})
	var e = m.me
	if OS.get_environment("PLAYER") != "1":
		m.me.f.teleport(Vector3(-12, 0, 0))
		e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": parts[0], "off": parts[1] if parts.size() > 1 else ""}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
		e.erase("bot")
	var f: Fighter = e.f
	var h: Array = holds[hold]
	e.drive = func(_e): return {"main": h[0], "off": h[1], "power": true, "look": {"yaw": 0.0, "pitch": 0.0}}
	if hurt:
		for s in ["R", "L"]:
			f.arm[s].fore.hp *= 0.45
			f.arm[s].upper.hp *= 0.6
	for i in 240:
		await get_tree().physics_frame
	var prev := Vector3.ZERO
	for i in 360:
		await get_tree().physics_frame
		var tq := PD.quat_of(f.torso)
		var hl: Vector3 = tq.inverse() * (f.hand_world(side) - f.torso.global_position)
		var up: VoxelPart = f.arm[side].upper
		var fo: VoxelPart = f.arm[side].fore
		var out_x := -1.0 if side == "R" else 1.0
		var pts := {"elbow": up.global_transform * Vector3(0, -up.half_ext.y, 0), "upmid": up.global_position, "fore": fo.global_position, "hand": f.hand_world(side)}
		var ways := []
		for body in [f.torso, f.head]:
			var bi: Transform3D = body.global_transform.affine_inverse()
			var ee: Vector3 = body.half_ext + Vector3(0.02, 0.0, 0.02) * f.S
			for k in pts:
				var l: Vector3 = bi * (pts[k] as Vector3)
				if absf(l.x) >= ee.x or absf(l.y) >= ee.y or absf(l.z) >= ee.z:
					continue
				var front := ee.z - l.z
				var aside := ee.x - l.x * out_x
				ways.append("%s/%s:%s(%.0f,%.0f mm)" % ["T" if body == f.torso else "H", k, "front" if front < aside or l.z > 0.0 else "aside", front * 1000.0, aside * 1000.0])
		var w = f.weapons[side]
		var tip := Vector3.ZERO
		if w:
			tip = tq.inverse() * (w.global_position + PD.quat_of(w) * Vector3(0, w.reach, 0) - f.torso.global_position)
			# Fighter._keep_weapon_out's test: the blade's segment within 0.22 S of the trunk's middle.
			var wq := PD.quat_of(w)
			var b0: Vector3 = w.global_position + wq * Vector3(0, -0.15, 0)
			var ab: Vector3 = w.global_position + wq * Vector3(0, w.reach, 0) - b0
			for bp in [f.torso, f.head]:
				var c: Vector3 = bp.global_position
				var kk := clampf((c - b0).dot(ab) / maxf(1e-6, ab.length_squared()), 0.0, 1.0)
				var dd: Vector3 = b0 + ab * kk - c
				dd.y *= 0.7
				var rr := (0.2 if bp == f.head else 0.22) * f.S
				if dd.length() < rr:
					ways.append("BLADE-IN-%s(%.0f mm)" % ["T" if bp == f.torso else "H", (rr - dd.length()) * 1000.0])
		if i % 12 == 0 or (hl - prev).length() > 0.002:
			var lead = f.hand_lead[side]
			var ll: Vector3 = tq.inverse() * ((lead as Vector3) - f.torso.global_position) if lead != null else Vector3.ZERO
			var ed = f.elbow_prev[side]
			var edl: Vector3 = tq.inverse() * (ed as Vector3) if ed != null else Vector3.ZERO
			var aq = f.aim_q[side]
			var axl: Vector3 = tq.inverse() * ((aq as Quaternion) * Vector3.UP) if aq != null else Vector3.ZERO
			print("STEP %2d strain %.3f elbow %s aim %s lead %s hand %s  d %5.1f mm  tip %s  elbow_set %s  %s" % [i, float(f.arm_strain[side]), str(edl.snapped(Vector3(0.001, 0.001, 0.001))), str(axl.snapped(Vector3(0.001, 0.001, 0.001))), str(ll.snapped(Vector3(0.001, 0.001, 0.001))), str(hl.snapped(Vector3(0.001, 0.001, 0.001))), (hl - prev).length() * 1000.0, str(tip.snapped(Vector3(0.001, 0.001, 0.001))), str(fo.has_meta("elbow_set")), " ".join(ways)])
		prev = hl
	get_tree().quit()
