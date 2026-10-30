extends Node
## Probe: after each blow in a bot duel, how far and how long the struck man's feet leave the sand.

func _ready() -> void:
	var rows := []
	for pair in [["gladius", "axe"], ["warhammer", "gladius"]]:
		for sd in [1]:
			rows.append_array(await _duel(pair[0], pair[1], sd))
	var n := rows.size()
	var air := rows.filter(func(r): return r.air > 0.0)
	var big := rows.filter(func(r): return r.air >= 0.15)
	var hmax := 0.0
	var amax := 0.0
	for r in rows:
		hmax = maxf(hmax, r.h)
		amax = maxf(amax, r.air)
	print("FEET %d blows: feet both off the sand after %d (%.0f%%), for 0.15 s or more after %d (%.0f%%); highest sole %.2f m, longest %.2f s" % [n, air.size(), 100.0 * air.size() / maxf(1, n), big.size(), 100.0 * big.size() / maxf(1, n), hmax, amax])
	var fr := float(Engine.get_meta("fr", 1))
	print("FEET all standing frames %d: both soles >4 cm up %.1f%%, >10 cm %.1f%%" % [int(fr), 100.0 * int(Engine.get_meta("fr_air", 0)) / fr, 100.0 * int(Engine.get_meta("fr_air10", 0)) / fr])
	var cnt: Dictionary = Engine.get_meta("why", {})
	var ks := cnt.keys()
	ks.sort_custom(func(x, y): return cnt[x] > cnt[y])
	for k in ks.slice(0, 14):
		print("FEET why %5d  %s" % [cnt[k], k])
	rows.sort_custom(func(a, b): return a.air > b.air)
	for r in rows.slice(0, 6):
		print("FEET   J %.0f: off %.2f s, sole up %.2f m, fell %s" % [r.J, r.air, r.h, r.fell])
	get_tree().quit()

func _sole_h(f: Fighter) -> float:
	var lo := INF
	for sd in ["L", "R"]:
		var sh: VoxelPart = f.by_name["shin" + sd]
		if not sh.severed:
			lo = minf(lo, _corner(f, sh))
	return lo

## The lowest corner of a shin's box over what is under it (a heel or a toe on the sand is a foot on it).
func _corner(f: Fighter, sh: VoxelPart) -> float:
	var p := sh.global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
	var g := f._ground_under(p, f.ground_level)
	var lo := INF
	var h: Vector3 = sh.half_ext
	for cx in [-1, 1]:
		for cy in [-1, 1]:
			for cz in [-1, 1]:
				lo = minf(lo, (sh.global_transform * Vector3(cx * h.x, cy * h.y, cz * h.z)).y - g)
	return lo

func _duel(wa: String, wb: String, sd: int) -> Array:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	seed(sd)
	var a := w.fighter(Vector3(0, 0, -1.5), 0.0, {"main": wa}, {"name": "A", "slot": 0})
	var b := w.fighter(Vector3(0, 0, 1.5), PI, {"main": wb}, {"name": "B", "slot": 1})
	var bots := {a: Bot.new(a, 0.85, "standard", sd), b: Bot.new(b, 0.85, "standard", sd + 10)}
	var open := []   # {f, J, t, air, h, run, fell}
	var done := []
	w.combat.hit.connect(func(h):
		if float(h.get("J", 0.0)) > 8.0 and h.get("char") is Fighter and (h.char == a or h.char == b) and h.char.state == "stand":
			open.append({"f": h.char, "J": float(h.J), "t": 0.0, "air": 0.0, "h": 0.0, "run": 0.0, "fell": false}))
	for i in 120 * 20:
		for f in [a, b]:
			var o: Fighter = b if f == a else a
			f.blood = 100.0
			f.head.hp = maxf(f.head.hp, 40.0)
			f.torso.hp = maxf(f.torso.hp, 40.0)
			var d: Vector3 = o.torso.global_position - f.torso.global_position
			f.yaw = atan2(d.x, d.z)
			f.control(1.0 / 120.0, bots[f].update(1.0 / 120.0, o))
		await get_tree().physics_frame
		for f in [a, b]:
			if f.state == "stand" and not f.jumping if "jumping" in f else f.state == "stand":
				var shf := _sole_h(f)
				Engine.set_meta("fr", int(Engine.get_meta("fr", 0)) + 1)
				if shf > 0.04:
					Engine.set_meta("fr_air", int(Engine.get_meta("fr_air", 0)) + 1)
					var sw := 0
					var planted_up := 0.0
					for fs in ["L", "R"]:
						var ft = f.feet[fs]
						if ft == null or ft.swing:
							sw += 1
						else:
							var sole: Vector3 = f.by_name["shin" + fs].global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
							planted_up = maxf(planted_up, sole.y - float((ft.anchor as Vector3).y))
					var why := "airborne" if not f.on_ground else ("both feet stepping" if sw == 2 else ("planted foot short of its mark" if planted_up > 0.04 else "planted foot's mark above the sand"))
					var spd := Vector2(f.torso.linear_velocity.x, f.torso.linear_velocity.z).length()
					why += " | " + ("run" if spd > 2.5 else ("walk" if spd > 0.4 else "stand")) + (" | struck" if Engine.get_physics_frames() - f.struck_frame < 60 else "")
					var cnt: Dictionary = Engine.get_meta("why", {})
					cnt[why] = int(cnt.get(why, 0)) + 1
					Engine.set_meta("why", cnt)
				if shf > 0.10:
					Engine.set_meta("fr_air10", int(Engine.get_meta("fr_air10", 0)) + 1)
		for r in open.duplicate():
			r.t += 1.0 / 120.0
			var sh := _sole_h(r.f)
			if r.f.state != "stand":
				r.fell = true
			if sh > 0.04 and r.f.state == "stand":
				r.run += 1.0 / 120.0
				r.air = maxf(r.air, r.run)
				r.h = maxf(r.h, sh)
			else:
				r.run = 0.0
			if r.t > 0.8:
				open.erase(r)
				done.append(r)
	w.queue_free()
	await get_tree().physics_frame
	return done
