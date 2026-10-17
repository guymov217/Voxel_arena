extends Node
## Wear over a fight, the gates and the throw line: a blade dulls and, knocked again and again in
## one place, chips there and finally breaks there; a wave comes in at the gates, not at your
## back; a thrown pot flies at the mark along a flat line, not on a lob.

var t

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	return m

func test_a_blade_dulls_with_use_and_only_so_far() -> void:
	var m := _match()
	var w: Weapon = m.me.f.weapons.R
	t.check(is_equal_approx(w.keenness(), 1.0), "a fresh blade is fully keen")
	for i in 40:
		w.wear_edge(0.02)
	t.check(w.keenness() < 0.5 and w.keenness() >= 1.0 - Weapon.DULL_MAX - 1e-4, "it dulls with use, never to nothing (%.2f)" % w.keenness())
	m.queue_free()

func test_knocks_in_one_place_chip_it_then_break_it_there() -> void:
	var m := _match()
	var w: Weapon = m.me.f.weapons.R
	var n0 := w.alive_count()
	# The voxel half way up the blade.
	var spot := -1
	var best := INF
	for i in w.vox.size():
		var v: Array = w.vox[i]
		if v[4] != "grip":
			var d := absf(float(v[1]) - w.reach / w.vs * 0.5) + absf(float(v[0])) + absf(float(v[2]))
			if d < best:
				best = d
				spot = i
	var first: Dictionary = w.knock(spot, 12.0)
	t.check(first.is_empty(), "one light knock takes nothing off")
	var chipped_at := -1
	var broke := false
	for k in 80:
		var idx := spot
		if w.alive[idx] == 0:
			# Keep knocking the same place: the nearest voxel still there.
			var p0 := Vector3(w.vox[spot][0], w.vox[spot][1], w.vox[spot][2])
			var bd := INF
			for i in w.vox.size():
				if w.alive[i] and w.vox[i][4] != "grip":
					var d := Vector3(w.vox[i][0], w.vox[i][1], w.vox[i][2]).distance_to(p0)
					if d < bd:
						bd = d
						idx = i
		var r: Dictionary = w.knock(idx, 12.0)
		if not r.is_empty() and chipped_at < 0:
			chipped_at = k
		if r.get("broke", false):
			broke = true
			break
	t.check(chipped_at >= 0, "the same spot, knocked again and again, gives way (after %d knocks)" % chipped_at)
	t.check(broke, "and in the end the blade breaks there")
	t.check(w.components().size() == 1, "what is left in the hand is one piece")
	var sy: int = w.vox[spot][1]
	var past := 0
	for i in w.vox.size():
		if w.alive[i] and w.vox[i][1] > sy + 1:
			past += 1
	t.check(past == 0, "it broke at the knocked spot: nothing past it is left (%d)" % past)
	t.check(w.alive_count() < n0 and w.vox.size() - w.alive_count() > n0 * 0.1, "the broken-off part is gone (%d of %d left)" % [w.alive_count(), n0])
	m.queue_free()

func test_waves_come_in_at_the_gates() -> void:
	var m := _match()
	var me: Vector3 = m.me.f.torso.global_position
	for total in [1, 2, 4]:
		for i in total:
			var spec := m.enemy_spec({"beast": "lion"} if i == 0 else {"type": "recruit"}, i, total)
			var p: Vector3 = spec.pos
			t.check(absf(p.x) > Arena.RADIUS - 6.0 and absf(p.z) < 1.5, "enemy %d of %d starts just inside a gate (%.1f, %.1f)" % [i + 1, total, p.x, p.z])
			t.check(p.distance_to(me) > 8.0, "and nowhere near your back (%.1f m off)" % p.distance_to(me))
	m.queue_free()

func test_a_thrown_pot_flies_flat_at_the_mark() -> void:
	var m := _match()
	var from := Vector3(0, 1.5, 0)
	for target in [Vector3(0, 1.0, 6), Vector3(4, 0.3, 9), Vector3(0, 6.0, 40)]:
		var it: Dictionary = m.items.throw_flat("pot_fire", from, target, null, 15.0)
		var v: Vector3 = it.vel
		var line: Vector3 = (target - from).normalized()
		var off := rad_to_deg(v.normalized().angle_to(line))
		t.check(off < 15.0, "to %s it leaves within %.0f° of the line to the mark" % [target, off])
		m.items.remove(it)
	m.queue_free()

## What is cut or crushed away tells: the head's loss closes in the view for good, a stove-in
## chest gets its breath back slowly, a hurt arm swings weaker; and a hard blunt blow leaves a
## crater, not just a number.
func test_lost_voxels_take_function_with_them() -> void:
	var m := _match()
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	var f: Fighter = e.f
	for i in 10:
		await get_tree().physics_frame
	var torso0 := f.torso.function()
	var arm0 := f.arm_func("R")
	var n0 := f.torso.alive_count
	var tf := f.torso.global_transform
	f.apply_hit(f.torso, {"impulse": 22.0, "type": "blunt", "hardness": 0.9, "point": tf * Vector3(0, 0, f.torso.half_ext.z), "dir": -(tf.basis * Vector3.BACK).normalized(), "heavy": 0.3})
	t.check(f.torso.alive_count < n0, "a hard blunt blow crushes a crater (%d voxels)" % (n0 - f.torso.alive_count))
	for k in 4:
		var hf := f.head.global_transform
		f.apply_hit(f.head, {"impulse": 40.0, "type": "edge", "hardness": 0.8, "sharpness": 0.9, "point": hf * Vector3(f.head.half_ext.x, 0, 0), "dir": -(hf.basis * Vector3.RIGHT).normalized(), "axis": hf.basis * Vector3.FORWARD, "edge": -(hf.basis * Vector3.RIGHT).normalized()})
		if f.head.severed or not f.alive:
			break
	t.check(f.eye_floor > 0.05, "a head cut into keeps the view narrowed (%.2f)" % f.eye_floor)
	for k in 3:
		var af: Transform3D = f.arm.R.upper.global_transform
		f.apply_hit(f.arm.R.upper, {"impulse": 30.0, "type": "edge", "hardness": 0.8, "sharpness": 0.9, "point": af * Vector3(f.arm.R.upper.half_ext.x, 0, 0), "dir": -(af.basis * Vector3.RIGHT).normalized(), "axis": af.basis * Vector3.FORWARD, "edge": -(af.basis * Vector3.RIGHT).normalized()})
	t.check(f.arm_func("R") < arm0 * 0.85, "a cut-up arm is a weaker arm (%.2f of %.2f)" % [f.arm_func("R"), arm0])
	t.check(f.torso.function() < torso0, "and the crushed chest works worse (%.2f of %.2f)" % [f.torso.function(), torso0])
	m.queue_free()

## What a fight knocks off the sword stays off: the fight reports it, the smith shows it (and
## charges to mend it), and the next fight starts with it gone until it is mended.
func test_chips_from_a_fight_go_to_the_smith_and_into_the_next_fight() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 2, "headless": true, "loadout": {"main": "gladius", "off": ""}})
	var w: Weapon = m.me.f.weapons.R
	var blade := []
	for i in w.vox.size():
		if w.vox[i][4] != "grip":
			blade.append(i)
	w.remove_voxels(blade.slice(0, 6))
	var wear: Dictionary = m.my_wear()
	t.eq((wear.get("R", []) as Array).size(), 6, "the fight reports the six voxels it knocked off")
	m.queue_free()
	var a := Arms.empty()
	a.main = Data.preset("gladius").duplicate(true)
	a = Arms.add_wear(a, wear)
	t.check(Arms.repair_cost(a, "R") > 0 and Arms.condition(a, "R") < 1.0, "the smith sees the damage and asks to mend it (%d denarii)" % Arms.repair_cost(a, "R"))
	var lo := Arms.loadout(a)
	var m2 := Match.new()
	add_child(m2)
	m2.setup({"mode": "campaign", "stage": 2, "headless": true, "loadout": {"main": lo.main, "off": lo.off}, "worn": lo.worn})
	var w2: Weapon = m2.me.f.weapons.R
	t.eq(w2.vox.size() - w2.alive_count(), 6, "and the next fight starts with those voxels gone")
	m2.queue_free()
	var mended := Arms.repair(a, "R")
	t.eq(Arms.condition(mended.arms, "R"), 1.0, "mended, it is whole again")
