extends Node
## The arms kept out of the body, one call at a time (#298): what each of Fighter._keep_arm_out, _keep_hand_front and _keep_elbow_low costs a call in the
## script and in the C++ core (`-- --probe arm_micro298`, headless; env ARMOR (1: helmet, lorica, manica, greaves; 0: bare), N (calls timed, 6000)).
func _ready() -> void:
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 6000
	var armour := OS.get_environment("ARMOR") != "0"
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 5, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "scutum", "armor": ["helmet", "lorica", "manica", "greaves"] if armour else []}})
	for k in 40:
		await get_tree().physics_frame
	var f: Fighter = m.me.f
	var dt := 1.0 / 120.0
	print("MICRO armour=%s sculpt=%s native=%s" % [armour, f._trunk_sculpt("R") is Dictionary, Greedy.core() != null and Greedy.arm_ok])
	var yq := Quaternion(Vector3.UP, f.yaw)
	var tp: Vector3 = f.torso.global_position
	var tb: Transform3D = f.torso.global_transform
	var lu: float = Fighter.UPPER_LEN * f.S
	var lf: float = Fighter.FORE_LEN * f.S
	var sh: Vector3 = tb * f.shoulder["R"]
	var edir: Vector3 = (tb.basis * Vector3(0.5, -0.8, 0.3)).normalized()
	var goal: Vector3 = tb * Vector3(0.1, 0.0, 0.5)
	for which in ["keep_arm_out", "keep_hand_front", "keep_elbow_low", "all three", "_clear_body", "_elbow_clear", "_hand_off_trunk"]:
		var us := {}
		for native in [false, true]:
			Greedy.use_native = native
			var t0 := Time.get_ticks_usec()
			for i in n:
				f._arm_phase = true
				f._sculpt_memo.clear()
				f._limb_memo.clear()
				f._plate_memo = null
				f._beast_memo = -1
				f._armor_memo.clear()
				f._outline_memo.clear()
				var side := "R" if i % 2 == 0 else "L"
				if which == "keep_arm_out":
					f._keep_arm_out(side, dt)
				elif which == "keep_hand_front":
					f._keep_hand_front(side, dt)
				elif which == "keep_elbow_low":
					f._keep_elbow_low(side, dt)
				elif which == "_clear_body":
					f._clear_body(Vector3(0.1, 0.0, 0.1), yq, tp, side)
				elif which == "_elbow_clear":
					f._elbow_clear(side, sh, edir, lu)
				elif which == "_hand_off_trunk":
					var sc = f._trunk_sculpt(side)
					if sc != null:
						f._hand_off_trunk(side, sc, sh, sh + edir * lu, goal, lu, lf, i % 2 == 0)
				else:
					f._keep_arm_out(side, dt)
					f._keep_elbow_low(side, dt)
				f._arm_phase = false
			us[native] = float(Time.get_ticks_usec() - t0) / float(n)
		print("MICRO %-16s script %6.2f us  native %6.2f us  (%.1fx)" % [which, us[false], us[true], us[false] / maxf(0.001, us[true])])
	Greedy.use_native = true
	get_tree().quit(0)
