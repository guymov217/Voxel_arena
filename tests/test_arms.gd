extends Node
## Both arms are the same arm, mirrored: neither the hand, the forearm nor the elbow of either
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
