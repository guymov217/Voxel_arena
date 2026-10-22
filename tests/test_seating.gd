extends Node
## Limbs stay on the body: what the physics leaves open of a joint under load is millimetres
## (measured: elbows 6–9 mm on average, open past 3 cm in 3–7% of the steps of a duel; the
## shoulders 2–7 mm) and on screen it is closed entirely (_seat_drawing); a limb cut off is
## left to fall; and a blade driven at a head (bug #240) hits it and comes away, never lodged
## in it or stuck.

var t

func _tip(w: Weapon) -> Vector3:
	var best := -INF
	var tip := Vector3.ZERO
	for i in w.vox.size():
		if w.alive.size() > i and w.alive[i] == 0:
			continue
		var v: Array = w.vox[i]
		if float(v[1]) > best:
			best = float(v[1])
			tip = w.global_transform * (Vector3(v[0], v[1], v[2]) * w.vs)
	return tip

func _inside(p: Vector3, part: VoxelPart) -> bool:
	var l: Vector3 = part.global_transform.affine_inverse() * p
	return absf(l.x) < part.half_ext.x and absf(l.y) < part.half_ext.y and absf(l.z) < part.half_ext.z

func _gap(p: VoxelPart, drawn: bool) -> float:
	var par: VoxelPart = p.parent_part
	var tp := par.get_global_transform_interpolated() if drawn else par.global_transform
	var tc := p.get_global_transform_interpolated() if drawn else p.global_transform
	if drawn:
		return (tp * p.pa + par.draw_shift).distance_to(tc * p.ca + p.draw_shift)
	return (tp * p.pa).distance_to(tc * p.ca)

func test_joints_stay_closed_through_a_fight() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 11, "loadout": {"main": "longsword", "off": ""}})
	var a = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {"main": "zweihander", "off": ""}, "team": 0, "pos": Vector3(3, 0, 0), "yaw": 0.0, "diff": 1.0})
	var b = m.spawn_fighter({"kind": "bot", "name": "B", "loadout": {"main": "hammer", "off": "roundShield"}, "team": 1, "pos": Vector3(3, 0, 1.4), "yaw": PI, "diff": 1.0})
	var hold := [{}]
	m.me.drive = func(_e): return hold[0]
	var n := 0
	var sum := 0.0
	var wide := 0
	var drawn_worst := 0.0
	var wep_off := 0.0
	for i in 1200:
		var ph := float(i % 240) / 240.0
		hold[0] = {"main": {"x": 1.8 * sin(ph * TAU), "y": 0.3 + 0.9 * cos(ph * TAU)}, "power": true, "thrust": 1.0 if (i / 120) % 4 == 3 else 0.0, "look": {"yaw": 0.0, "pitch": 0.0}}
		await get_tree().physics_frame
		if i < 2:
			continue   # the off hand is put on the haft at spawn
		for e in [m.me, a, b]:
			var f: Fighter = e.f
			f._seat_drawing()   # (what _process does for the screen; headless it is not called)
			for p: VoxelPart in f.parts:
				if p.parent_part == null or p.severed or p.hanging or p.missing or p.parent_part.severed or p.joint == null:
					continue
				var g := _gap(p, false)
				n += 1
				sum += g
				if g > 0.03:
					wide += 1
				drawn_worst = maxf(drawn_worst, _gap(p, true))
			for side in ["R", "L"]:
				var w: Weapon = f.weapons[side]
				if w and w.welded:
					wep_off = maxf(wep_off, (w.draw_shift - f.arm[side].fore.draw_shift).length())
	var mean_mm := 1000.0 * sum / maxf(1.0, float(n))
	var wide_pct := 100.0 * float(wide) / maxf(1.0, float(n))
	t.check(mean_mm < 12.0, "the joints of three men in a fight stay within millimetres: mean %.1f mm" % mean_mm)
	t.check(wide_pct < 8.0, "and are open past 3 cm in under 8%% of the readings (%.2f%%)" % wide_pct)
	t.check(drawn_worst < 0.0005, "on screen every joint is closed (worst drawn %.2f mm)" % (1000.0 * drawn_worst))
	t.check(wep_off < 0.0005, "and the weapon is drawn with the hand that holds it")
	m.queue_free()

func test_a_cut_limb_is_left_to_fall() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var f: Fighter = m.me.f
	for i in 60:
		await get_tree().physics_frame
	f.detach_limb(f.by_name.forearmL, {"removed": [], "severed": []})
	for i in 120:
		await get_tree().physics_frame
	f._seat_drawing()
	var fore: VoxelPart = f.by_name.forearmL
	t.check(fore.draw_shift == Vector3.ZERO, "a forearm cut off is drawn where it fell")
	t.check(_gap(fore, false) > 0.15, "and lies away from the elbow (%.2f m)" % _gap(fore, false))
	t.check(f.by_name.upperArmL.draw_shift.length() < 0.02 and not f.by_name.upperArmL.severed, "the upper arm stays on the shoulder")
	m.queue_free()

## Bug #240: thrusts and swings at a man's head, with a gladius and a zweihander. The blade
## hits the head and comes away: never left inside it with the hand at rest, never stuck, and
## never out of the hand.
func test_a_blade_at_the_head_hits_and_comes_away() -> void:
	for key in ["gladius", "zweihander"]:
		var reach := 0.9 if key == "gladius" else 1.25   # the man a blade's length off
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 7, "loadout": {"main": key, "off": ""}})
		var f: Fighter = m.me.f
		var ve = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": "", "off": ""}, "team": 1, "pos": Vector3(0, 0, reach), "yaw": PI, "mods": {"toughness": 8.0}})
		ve.erase("bot")
		ve.drive = func(_e): return {}
		var hold := [{}]
		m.me.drive = func(_e): return hold[0]
		for i in 60:
			await get_tree().physics_frame
		var head_hits := [0]   # (a lambda holds a copy of an int; an array it shares)
		m.combat.hit.connect(func(h):
			if h.attacker == f and h.get("char") == ve.f and String(h.part.part_name) == "head":
				head_hits[0] += 1)
		var lodged := 0
		var stuck := 0
		var lost := 0
		for k in 8:
			ve.f.teleport(Vector3(0, 0, reach))
			ve.f.yaw = PI
			f.teleport(Vector3(0, 0, 0))
			f.yaw = 0.0
			for i in 30:
				await get_tree().physics_frame
			ve.f.blood = 100.0
			ve.f.head.hp = 100.0
			if k % 2 == 0:
				hold[0] = {"main": {"x": 0.1, "y": 0.55}, "power": true, "look": {"yaw": 0.0, "pitch": 0.0}}
				for i in 50:
					await get_tree().physics_frame
				hold[0] = {"main": {"x": 0.1, "y": 0.55}, "power": true, "thrust": 1.0, "look": {"yaw": 0.0, "pitch": 0.0}}
			else:
				hold[0] = {"main": {"x": 0.9 if k % 4 == 1 else -0.9, "y": 0.9}, "power": true, "look": {"yaw": 0.0, "pitch": 0.0}}
			for i in 70:
				if k % 2 == 1 and i > 10:
					hold[0].main = {"x": -0.9 if k % 4 == 1 else 0.9, "y": 0.5}
				await get_tree().physics_frame
			hold[0] = {"main": {"x": 0.1, "y": 0.1}, "look": {"yaw": 0.0, "pitch": 0.1}}
			for i in 100:
				await get_tree().physics_frame
				var w: Weapon = f.weapons.R
				if w == null:
					lost += 1
					break
				if w.stuck != null:
					stuck += 1
				if not ve.f.head.severed and _inside(_tip(w), ve.f.head):
					lodged += 1
		t.check(head_hits[0] > 0, "%s: the head is hit (%d blows)" % [key, head_hits[0]])
		t.check(lodged == 0, "%s: the blade is never left in the head with the hand at rest (%d frames)" % [key, lodged])
		t.check(stuck == 0 and lost == 0, "%s: never stuck (%d) nor out of the hand (%d)" % [key, stuck, lost])
		m.queue_free()
		await get_tree().process_frame
