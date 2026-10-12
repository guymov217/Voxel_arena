extends Node
## Taking a blow and fighting on, and standing on the sand: a cut that knocks voxels off rocks a
## fighter, it does not throw him down (the pieces never shove the body they came off); a beast
## stands on its feet, not over them; a fast stroke follows the mouse without stopping.

var t

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(0, 0, -10))
	return m

func test_cuts_rock_a_fighter_but_do_not_fell_him() -> void:
	var m := _match()
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": "gladius"}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {}
	var f: Fighter = e.f
	for i in 120:
		await get_tree().physics_frame
	var tilt := 0.0
	var removed := 0
	for h in 5:
		var p: VoxelPart = [f.torso, f.head, f.arm.R.upper][h % 3]
		var tf := p.global_transform
		var r: Dictionary = f.apply_hit(p, {"impulse": 25.0, "type": "edge", "hardness": 0.8, "sharpness": 0.8, "point": tf * Vector3(0, 0, p.half_ext.z), "dir": Vector3(0, 0, -1), "axis": Vector3.UP, "edge": Vector3(1, 0, 0), "heavy": 0.3})
		removed += r.removed.size()
		for i in 84:
			await get_tree().physics_frame
			tilt = maxf(tilt, acos(clampf((PD.quat_of(f.torso) * Vector3.UP).y, -1, 1)))
	t.check(removed > 0, "the cuts took voxels off (%d)" % removed)
	t.check(f.state == "stand" and tilt < 0.6, "and he is still on his feet (leaned %.2f rad at most)" % tilt)
	m.queue_free()

func _box_low(p: VoxelPart) -> float:
	var b := p.global_transform
	var h := p.half_ext
	return b.origin.y - absf(b.basis.x.y) * h.x - absf(b.basis.y.y) * h.y - absf(b.basis.z.y) * h.z

func test_beasts_stand_on_their_feet() -> void:
	var m := _match()
	for id in ["elephant", "goat", "mammoth", "spider"]:
		var e = m.spawn_beast({"beast": id, "pos": Vector3(0, 0, 3), "yaw": 0.0, "team": 1})
		e.drive = func(_e): return {}
		var b: Beast = e.f
		var sum := 0.0
		var n := 0
		for i in 120 * 3:
			await get_tree().physics_frame
			if i > 240:
				for l in b.legs:
					var ft: VoxelPart = b.lower_of(l) if b.lower_of(l) else l
					sum += _box_low(ft)
					n += 1
		t.check(n > 0 and sum / n < 0.04, "the %s's feet are on the sand (%.3f m over it on average)" % [id, sum / maxf(1.0, n)])
		m.entities.erase(e)
		m.combat.fighters.erase(b)
		b.queue_free()
		await get_tree().physics_frame
	m.queue_free()

func test_a_fast_low_stroke_does_not_stall() -> void:
	var m := _match()
	for wn in ["gladius", "longsword"]:
		var e = m.spawn_fighter({"kind": "bot", "name": "S", "loadout": {"main": wn}, "team": 0, "pos": Vector3(4, 0, 0), "yaw": 0.0})
		e.erase("bot")
		var inp := {"main": {"x": 2.0, "y": -1.0}, "power": true, "look": {"yaw": 0.0, "pitch": 0.0}}
		e.drive = func(_e): return inp
		var f: Fighter = e.f
		for i in 150:
			await get_tree().physics_frame
		var w: Weapon = f.weapons.R
		var yaw_of := func() -> float:
			var la: Vector3 = PD.quat_of(w) * Vector3.UP
			return rad_to_deg(atan2(la.x, la.z))
		var y0: float = yaw_of.call()
		for i in 76:
			inp.main = {"x": 2.0 - 4.0 * clampf(i / 36.0, 0.0, 1.0), "y": -1.0}
			await get_tree().physics_frame
		var y1: float = yaw_of.call()
		t.check(y1 - y0 > 60.0, "%s: a fast low stroke sweeps right across (%d° to %d°)" % [wn, int(y0), int(y1)])
		m.entities.erase(e)
		m.combat.fighters.erase(f)
		f.queue_free()
		await get_tree().physics_frame
	m.queue_free()
