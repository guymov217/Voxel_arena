extends Node
## No limb passes into its own body (limp, down or dead too). Both arms are the same arm, mirrored: neither the hand, the forearm nor the elbow of either
## ever goes in through its own chest or head, wherever the mouse sends the hand.

var t

func _deepest(f: Fighter, sd: String, hp: Dictionary) -> Array:
	var worst := 0.0
	var where := ""
	for x in [-2.0, 0.0, 2.0]:
		for y in [-1.4, 0.2, 1.6]:
			hp.x = x if sd == "R" else -x
			hp.y = y
			for i in 45:
				await get_tree().physics_frame
			for k in 3:
				var pt: Vector3 = [f.hand_world(sd), f.arm[sd].fore.global_position, f.arm[sd].upper.global_transform * Vector3(0, -f.arm[sd].upper.half_ext.y, 0)][k]
				for body in [f.torso, f.head]:
					var l: Vector3 = body.global_transform.affine_inverse() * pt
					var pen: float = minf(body.half_ext.x - absf(l.x), minf(body.half_ext.y - absf(l.y), body.half_ext.z - absf(l.z)))
					if pen > worst:
						worst = pen
						where = "x %.0f y %.1f in the %s" % [x, y, body.part_name]
	return [worst, where]

func test_neither_arm_goes_through_the_body() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	for lo in [{"main": "gladius", "off": "roundShield"}, {"main": "gladius", "off": "dagger"}, {"main": "", "off": ""}]:
		var e = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": lo, "team": 1, "pos": Vector3(5, 0, 0), "yaw": 0.0})
		e.erase("bot")
		var hp := {"x": 0.0, "y": 0.0}
		var side := ["R"]
		e.drive = func(_e): return {"main": hp if side[0] == "R" else {"x": 0.1, "y": 0.1}, "off": hp if side[0] == "L" else {"x": -0.35, "y": 0.1}, "power": true}
		var f: Fighter = e.f
		for i in 100:
			await get_tree().physics_frame
		for sd in ["R", "L"]:
			side[0] = sd
			var r: Array = await _deepest(f, sd, hp)
			t.check(r[0] < 0.04, "%s arm with %s stays out of the body (deepest %.3f m, %s)" % [sd, lo.get("off" if sd == "L" else "main") if lo.get("off" if sd == "L" else "main") != "" else "nothing", r[0], r[1]])
		m.entities.erase(e)
		m.combat.fighters.erase(f)
		f.queue_free()
		await get_tree().physics_frame
	m.queue_free()

func _worst_in_body(f: Fighter) -> float:
	var worst := 0.0
	for sd in ["R", "L"]:
		var pts := [f.arm[sd].upper.global_transform * Vector3(0, -f.arm[sd].upper.half_ext.y, 0)]
		if not f.arm[sd].fore.severed:
			pts.append_array([f.arm[sd].fore.global_position, f.hand_world(sd)])
		for pt in pts:
			for body in [f.torso, f.head]:
				if body.severed:
					continue
				var l: Vector3 = body.global_transform.affine_inverse() * pt
				worst = maxf(worst, minf(body.half_ext.x - absf(l.x), minf(body.half_ext.y - absf(l.y), body.half_ext.z - absf(l.z))))
	# The head and the legs: no part's middle inside the chest.
	for q in [f.head, f.by_name.shinL, f.by_name.shinR, f.by_name.thighL, f.by_name.thighR]:
		if q.severed:
			continue
		var l: Vector3 = f.torso.global_transform.affine_inverse() * q.global_position
		var th: Vector3 = f.torso.half_ext
		worst = maxf(worst, minf(th.x - absf(l.x), minf(th.y - absf(l.y), th.z - absf(l.z))))
	return worst

func test_limp_and_dead_arms_stay_out_of_the_body() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var e = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {"main": "gladius", "off": "roundShield"}, "team": 1, "pos": Vector3(5, 0, 0), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {}
	var f: Fighter = e.f
	for i in 60:
		await get_tree().physics_frame
	f.fall(99.0, true)
	var worst := 0.0
	for i in 360:
		await get_tree().physics_frame
		if i > 30:
			worst = maxf(worst, _worst_in_body(f))
	t.check(worst < 0.05, "knocked down and limp, no limb lies inside the chest (deepest %.3f m)" % worst)
	f.blood = 0.0
	worst = 0.0
	for i in 360:
		await get_tree().physics_frame
		if i > 60:
			worst = maxf(worst, _worst_in_body(f))
	t.eq(f.state, "dead", "he bled out")
	t.check(worst < 0.05, "and dead, they still do (deepest %.3f m)" % worst)
	m.queue_free()
