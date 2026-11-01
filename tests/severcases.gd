extends Node
## A cut-off arm left inside its owner (user: the severed left arm floated inside his body), in the
## cases severinside.gd does not try: the man lying on the sand when it is cut off, his off hand
## on a two-handed haft, the arm hanging by a strip first and then cut through, the arm cut while
## he runs on. Each step for 4 s: is any cut-off piece's middle inside a part of him still on?
## `-- --probe severcases`.

func _inside(f: Fighter, p: VoxelPart) -> String:
	for o in f.parts:
		if o.severed or o.missing:
			continue
		var l: Vector3 = o.global_transform.affine_inverse() * p.global_position
		var e: Vector3 = o.half_ext * 0.85
		if absf(l.x) < e.x and absf(l.y) < e.y and absf(l.z) < e.z:
			return String(o.part_name)
	return ""

func _ready() -> void:
	var bad := 0
	for case in ["down", "two_handed", "hang_then_cut", "running", "down_upper"]:
		var m := Match.new()
		add_child(m)
		var lo := {"main": "longsword" if case == "two_handed" else "gladius", "off": ""}
		m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "loadout": lo})
		var f: Fighter = m.me.f
		var st := {"t": 0.0}
		m.me.drive = func(_e):
			st.t += 1.0 / 120.0
			var inp := {"main": {"x": 0.1, "y": 0.15}, "look": {"yaw": 0.0, "pitch": 0.0}}
			if case == "two_handed" and st.t > 0.3 and st.t < 0.35:
				inp.grip = true
			if case == "running":
				inp.mz = 1.0
				inp.sprint = true
			return inp
		for i in 120:
			await get_tree().physics_frame
		if case.begins_with("down"):
			f.fall(3.0, true)
			for i in 60:
				await get_tree().physics_frame
		var part: VoxelPart = f.by_name["upperArmL" if case in ["hang_then_cut", "down_upper"] else "forearmL"]
		var res := {"removed": [], "severed": [], "dmg": 0.0}
		if case == "hang_then_cut":
			f.hang(part, res)
			for i in 90:
				await get_tree().physics_frame
		f.detach_limb(part, res)
		var worst := ""
		var when := -1.0
		for i in 480:
			await get_tree().physics_frame
			for p in f.parts:
				if p.severed and not p.missing:
					var w := _inside(f, p)
					if w != "" and i > 120:
						worst = "%s in his %s" % [p.part_name, w]
						when = i / 120.0
		print("SEVER %-14s two-handed %s  state %s  %s" % [case, str(f.two_handed), f.state, ("a piece still INSIDE him: %s (at %.1f s)" % [worst, when]) if worst != "" else "every piece clear of him after 1 s"])
		if worst != "":
			bad += 1
		m.queue_free()
		await get_tree().physics_frame
	print("SEVERCASES %d of 5 left a piece inside him" % bad)
	get_tree().quit()
