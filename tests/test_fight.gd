extends Node
## Fighters stand, walk, and hurt each other (as the web game's strikes and sim tests).

var t

func _world() -> TestWorld:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	return w

func _step(w: TestWorld, n: int, inputs: Callable) -> void:
	for i in n:
		for f in w.fighters:
			f.control(1.0 / 120.0, inputs.call(f, i))
		await get_tree().physics_frame

func test_a_fighter_stands_and_walks() -> void:
	var w := _world()
	var f := w.fighter(Vector3.ZERO, 0.0, {"main": "gladius", "off": "roundShield"}, {"name": "A"})
	await _step(w, 360, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}})
	t.eq(f.state, "stand", "still standing after 3 s")
	t.check(f.torso.global_position.y > 1.0, "torso at standing height (%.2f)" % f.torso.global_position.y)
	var z0 := f.torso.global_position.z
	await _step(w, 360, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}, "mz": 1.0})
	t.eq(f.state, "stand", "walked without falling")
	t.check(f.torso.global_position.z - z0 > 2.0, "walked forward (%.2f m)" % (f.torso.global_position.z - z0))
	w.queue_free()

## Standing still, the legs are still: the foot's grip on the sand braked as the whole leg set
## the thighs and shins buzzing, a turn back and forth every step.
func test_standing_still_the_legs_do_not_buzz() -> void:
	var w := _world()
	var f := w.fighter(Vector3.ZERO, 0.0, {"main": "gladius", "off": "roundShield"}, {"name": "A"})
	await _step(w, 360, func(_f, _i): return {"main": {"x": 0.2, "y": 0.2}})
	var acc := 0.0
	var flips := 0
	var last := {}
	for i in 240:
		await _step(w, 1, func(_f, _i): return {"main": {"x": 0.2, "y": 0.2}})
		for n in ["thighL", "thighR", "shinL", "shinR"]:
			var av: Vector3 = f.by_name[n].angular_velocity
			acc += av.length_squared()
			if last.has(n) and (last[n] as Vector3).dot(av) < 0.0 and av.length() > 0.05:
				flips += 1
			last[n] = av
	var rms := sqrt(acc / (240.0 * 4.0))
	t.check(rms < 0.3, "the legs hold still (%.3f rad/s)" % rms)
	t.check(flips < 40, "not turning back and forth (%d turns)" % flips)
	w.queue_free()

## A jump with a two-handed weapon is a jump: up and down where he stood (in the air, the arms'
## pull on the haft had nothing under him to push back and flew him metres aside).
func test_a_jump_with_two_hands_lands_where_it_left() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": "warhammer", "off": ""}})
	var f: Fighter = m.me.f
	var inp := {"main": {"x": 0.3, "y": -1.0}, "power": false}
	m.me.drive = func(_e): return inp
	for i in 150:
		await get_tree().physics_frame
	t.check(f.two_handed, "the war hammer in both hands")
	var p0: Vector3 = f.torso.global_position
	inp.jump = true
	await get_tree().physics_frame
	inp.erase("jump")
	var top := 0.0
	var far := 0.0
	for i in 360:
		await get_tree().physics_frame
		top = maxf(top, f.torso.global_position.y - p0.y)
		far = maxf(far, Vector2(f.torso.global_position.x - p0.x, f.torso.global_position.z - p0.z).length())
	t.check(top > 0.3 and top < 1.6, "a jump (up %.2f m)" % top)
	t.check(far < 1.5, "that comes down near where it left (%.2f m off)" % far)
	m.queue_free()
	await get_tree().process_frame

## Throwable means something: the same blade made to be thrown leaves the hand faster.
func test_a_throwing_weapon_flies_faster() -> void:
	var speeds := []
	for made in [false, true]:
		var w := _world()
		var d: Dictionary = Data.preset("gladius").duplicate(true)
		d.throwable = made
		var f := w.fighter(Vector3.ZERO, 0.0, {"main": d}, {"name": "A"})
		await _step(w, 90, func(_f, _i): return {"main": {"x": 0.1, "y": 0.2}})
		var wp: Weapon = f.throw_weapon("R", f.torso.global_position + Vector3(0, 1, 8), 1.0)
		speeds.append(wp.linear_velocity.length())
		w.queue_free()
		await get_tree().physics_frame
	t.check(speeds[1] > speeds[0] * 1.1, "made to be thrown, it flies faster (%.1f vs %.1f m/s)" % [speeds[1], speeds[0]])

func test_a_sword_sweep_cuts_a_dummy() -> void:
	var w := _world()
	var a := w.fighter(Vector3(0, 0, 0), 0.0, {"main": "gladius"}, {"name": "a", "slot": 0})
	var b := w.fighter(Vector3(0, 0, 1.1), PI, {}, {"name": "dummy", "slot": 1})
	var hits := []
	w.combat.hit.connect(func(h):
		if h.char == b:
			hits.append(h)
			if OS.get_environment("DEBUG_HITS") != "":
				print("     hit J=%.1f type=%s part=%s dmg=%.1f removed=%d" % [h.J, h.type, h.part.part_name, h.res.dmg, h.res.removed.size()]))
	await _step(w, 720, func(f, i):
		if f == b:
			return {"main": {"x": 0.0, "y": 0.0}}
		var ph := fmod(i / 120.0 * 0.6, 1.0)
		var k := 0.0 if ph < 0.5 else (ph - 0.5) / 0.5
		return {"main": {"x": 1.5 - 3.0 * k, "y": 0.3}, "power": k > 0.0})
	var edge := hits.filter(func(h): return h.type == "edge")
	t.check(edge.size() > 0, "the blade hit (%d hits, %d edge)" % [hits.size(), edge.size()])
	t.check(b.total_hp() < 1000.0 - 20.0, "real damage (%.0f hp lost)" % (1000.0 - b.total_hp()))
	w.queue_free()

func test_two_bots_fight() -> void:
	var w := _world()
	var a := w.fighter(Vector3(0, 0, -1.5), 0.0, {"main": "gladius", "off": "roundShield"}, {"name": "A", "slot": 0, "bot": true})
	var b := w.fighter(Vector3(0, 0, 1.5), PI, {"main": "axe"}, {"name": "B", "slot": 1, "bot": true})
	var bots := {a: Bot.new(a, 0.8, "standard", 1), b: Bot.new(b, 0.8, "standard", 2)}
	var hits := [0]
	w.combat.hit.connect(func(h): hits[0] += 1)
	await _step(w, 120 * 25, func(f, _i):
		var o: Fighter = b if f == a else a
		var d: Vector3 = o.torso.global_position - f.torso.global_position
		f.yaw = atan2(d.x, d.z)
		return bots[f].update(1.0 / 120.0, o))
	var lost := 2000.0 - a.total_hp() - b.total_hp()
	t.check(hits[0] > 3, "blows landed (%d)" % hits[0])
	t.check(lost > 30.0, "they hurt each other (%.0f hp)" % lost)
	for f in [a, b]:
		t.check(is_finite(f.torso.global_position.y), "physics stayed sane")
	print("   duel: hits=%d lost=%.0f A=%s B=%s" % [hits[0], lost, a.state, b.state])
	w.queue_free()

## Swept hard across the body and back, the sword arm bends like an arm: the elbow stays on its
## own side of the chest, and the blade never passes through its owner's torso.
func test_the_arm_keeps_to_its_side() -> void:
	var w := _world()
	var f := w.fighter(Vector3.ZERO, 0.0, {"main": "longsword"}, {"name": "A"})
	var worst_x := -1.0
	var inside := 0
	await _step(w, 720, func(_f, i):
		var ph := fmod(i / 120.0 * 0.5, 1.0)
		var x := -2.0 + 4.0 * absf(ph * 2.0 - 1.0)
		return {"main": {"x": x, "y": 0.2 if i % 240 < 120 else -0.4}, "power": true})
	for i in 480:
		var ph := fmod(i / 120.0 * 0.7, 1.0)
		f.control(1.0 / 120.0, {"main": {"x": -2.0 + 4.0 * absf(ph * 2.0 - 1.0), "y": 0.3}, "power": true})
		await get_tree().physics_frame
		var inv := PD.quat_of(f.torso).inverse()
		var elbow: Vector3 = inv * (f.arm.R.fore.global_transform * f.arm.R.fore.ca - f.torso.global_position)
		worst_x = maxf(worst_x, elbow.x)
		var wpn: Weapon = f.weapons.R
		var q := PD.quat_of(wpn)
		for k in 6:
			var p: Vector3 = wpn.global_position + q * Vector3(0, wpn.reach * (0.2 + 0.16 * k), 0)
			var d: Vector3 = inv * (p - f.torso.global_position)
			if absf(d.x) < f.torso.half_ext.x * 0.8 and absf(d.y) < f.torso.half_ext.y * 0.8 and absf(d.z) < f.torso.half_ext.z * 0.8:
				inside += 1
	t.eq(f.state, "stand", "still on his feet")
	t.check(worst_x < 0.03 * f.S, "the right elbow stays right of the chest (x %.2f)" % worst_x)
	t.check(inside < 10, "the blade stays out of his own chest (%d samples inside)" % inside)
	w.queue_free()

## Holding F draws the arm back above the shoulder; a spear then flies point first, and a sword
## or an axe turns end over end about its side axis.
func test_throws_wind_up_and_fly_true() -> void:
	var w := _world()
	var f := w.fighter(Vector3.ZERO, 0.0, {"main": "gladius"}, {"name": "A"})
	await _step(w, 120, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}})
	var rest_y: float = f.hand_world("R").y - f.torso.global_position.y
	await _step(w, 60, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}, "charging": 0.8})
	var wound_y: float = f.hand_world("R").y - f.torso.global_position.y
	t.check(wound_y > rest_y + 0.2 * f.S, "the arm is drawn back high (hand %.2f -> %.2f)" % [rest_y, wound_y])
	var spins := {}
	for k in ["gladius", "axe", "spear"]:
		var g := w.fighter(Vector3(4.0 + spins.size() * 2.0, 0, 0), 0.0, {"main": k}, {"name": k})
		await _step(w, 60, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}})
		var wp: Weapon = g.throw_weapon("R", null, 0.9, Vector3(0, 0.1, 1).normalized())
		var v := wp.linear_velocity
		spins[k] = [wp.angular_velocity.length(), absf(wp.angular_velocity.normalized().dot(v.normalized()))]
	t.check(spins.spear[0] < 1.0, "the spear flies straight (spin %.1f)" % spins.spear[0])
	for k in ["gladius", "axe"]:
		t.check(spins[k][0] > 5.0 and spins[k][1] < 0.2, "the %s turns end over end (spin %.1f, along the flight %.2f)" % [k, spins[k][0], spins[k][1]])
	w.queue_free()

## H takes the off hand onto the haft and lets go again.
func test_h_switches_the_grip() -> void:
	var w := _world()
	var f := w.fighter(Vector3.ZERO, 0.0, {"main": "gladius"}, {"name": "A"})
	await _step(w, 60, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}})
	t.check(not f.two_handed, "one hand to begin with")
	await _step(w, 1, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}, "grip": true})
	await _step(w, 60, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}})
	t.check(f.two_handed and f.weapon_joints.L != null, "both hands on it after H")
	t.check(f.hand_world("L").distance_to(f.weapons.R.global_transform * f.weapons.R.grip_off) < 0.12, "the off hand is on the haft")
	await _step(w, 1, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}, "grip": true})
	await _step(w, 10, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}})
	t.check(not f.two_handed and f.weapons.R != null, "one hand again, the sword still held")
	w.queue_free()

## Cut through at the waist, a man comes apart: the pelvis and legs go as a half of their own,
## he goes down and bleeds out. With both shins smashed he cannot stand, and crawls on his arms.
func test_a_man_cut_in_half_falls_and_smashed_legs_mean_crawling() -> void:
	var w := _world()
	var a := w.fighter(Vector3(0, 0, 0), 0.0, {}, {"name": "A"})
	await _step(w, 60, func(_f, _i): return {})
	var torso: VoxelPart = a.torso
	var p: Vector3 = torso.global_position + Vector3(0.24, -0.1, 0)
	var res: Dictionary = a.apply_hit(torso, {"impulse": 70.0, "type": "edge", "hardness": 0.9, "sharpness": 1.0, "point": p, "dir": Vector3(-1, 0, 0), "axis": Vector3(0, 0, 1), "edge": Vector3(-1, 0, 0), "heavy": 1.0})
	# A trunk takes many full blows into one wound before it comes apart.
	for i in 12:
		if not res.get("halved", []).is_empty():
			break
		var pp: Vector3 = torso.global_position + Vector3(0.24, -0.1 + 0.005 * (i % 3), 0)
		var r2: Dictionary = a.apply_hit(torso, {"impulse": 70.0, "type": "edge", "hardness": 0.9, "sharpness": 1.0, "point": pp, "dir": Vector3(-1, 0, 0), "axis": Vector3(0, 0, 1), "edge": Vector3(-1, 0, 0), "heavy": 1.0})
		if not r2.get("halved", []).is_empty():
			res = r2
	await _step(w, 30, func(_f, _i): return {})
	t.check(not res.get("halved", []).is_empty(), "the legs went with the lower half (%s)" % [res.get("halved", [])])
	t.check(a.by_name.thighL.severed and a.by_name.thighR.severed, "both legs are off him")
	t.check(a.state != "stand" and a.blood <= 40.0, "he is down (%s) and bleeding out (%.0f)" % [a.state, a.blood])
	# Another man: both shins smashed to splinters (left on, useless).
	var b := w.fighter(Vector3(4, 0, 0), 0.0, {}, {"name": "B"})
	await _step(w, 60, func(_f, _i): return {})
	for n in ["shinL", "shinR"]:
		var sh: VoxelPart = b.by_name[n]
		sh.fractured = true
		sh.hp = 5.0
	t.check(not b.can_stand(), "two smashed shins cannot hold him up")
	await _step(w, 120, func(_f, _i): return {})
	t.eq(b.state, "down", "down he goes")
	var z0: float = b.torso.global_position.z
	await _step(w, 360, func(_f, _i): return {"mz": 1.0})
	t.check(b.crawling or b.torso.global_position.z - z0 > 0.4, "and crawls forward (%.2f m)" % (b.torso.global_position.z - z0))
	w.queue_free()

## Blow after blow into the same cut goes deeper each time (the blade follows the wound) until
## the limb comes off; armour is knocked off where it is struck, plate by plate.
func test_blows_follow_the_wound_and_knock_armour_off() -> void:
	seed(3)   # the game's dice (randf) the same whatever tests ran before
	var w := _world()
	var a := w.fighter(Vector3(0, 0, 0), 0.0, {"armor": ["manica"]}, {"name": "A"})
	await _step(w, 60, func(_f, _i): return {})
	var th: VoxelPart = a.by_name.thighL
	var cuts := 0
	var gone := []
	for i in 12:
		if th.severed:
			break
		var p: Vector3 = th.global_position + PD.quat_of(th) * Vector3(th.half_ext.x * 1.05, 0, 0)
		var dir := (th.global_position - p).normalized()
		var res: Dictionary = a.apply_hit(th, {"impulse": 16.0, "type": "edge", "hardness": 0.9, "sharpness": 0.9, "point": p, "dir": dir, "axis": PD.quat_of(th) * Vector3(0, 0, 1), "edge": dir, "heavy": 0.0})
		cuts += 1
		gone.append(res.removed.reduce(func(s, r): return s + r.indices.size(), 0))
	t.check(th.severed, "the thigh came off in %d blows (voxels per blow %s)" % [cuts, gone])
	t.check(cuts >= 2, "not in one ordinary blow")
	var up: VoxelPart = a.by_name.upperArmR
	var ad: Dictionary = up.get_meta("armor")[0]
	var before: int = ad.alive
	var pa: Vector3 = up.global_position + PD.quat_of(up) * Vector3(-up.half_ext.x * 1.1, 0, 0)
	var r2: Dictionary = a.apply_hit(up, {"impulse": 40.0, "type": "blunt", "hardness": 0.8, "point": pa, "dir": (up.global_position - pa).normalized()})
	t.check(r2.get("armor", false) and ad.alive < before and ad.alive > 0, "plates knocked off where it struck (%d -> %d of %d)" % [before, ad.alive, ad.pts.size()])
	w.queue_free()

## Thrown at a man four metres off, a blade or a point lands where it was aimed, hurts by its
## speed and sharpness, and one that bites deep stays stuck in him.
func test_thrown_weapons_hurt_and_stick() -> void:
	var report := []
	var stuck := 0
	var landed := 0
	for k in ["gladius", "axe", "spear", "dagger", "javelin"]:
		var w := _world()
		var a := w.fighter(Vector3(0, 0, 0), 0.0, {"main": k}, {"name": "A", "slot": 0})
		var b := w.fighter(Vector3(0, 0, 4.0), PI, {}, {"name": "B", "slot": 1})
		await _step(w, 90, func(_f, _i): return {"main": {"x": 0.1, "y": 0.2}})
		var hits := []
		w.combat.hit.connect(func(h): if h.char == b: hits.append(h))
		var wp: Weapon = a.throw_weapon("R", b.torso.global_position, 1.0)
		await _step(w, 90, func(_f, _i): return {})
		var removed := 0
		var J := 0.0
		for h in hits:
			removed += h.res.removed.reduce(func(s, r): return s + r.indices.size(), 0)
			J = maxf(J, h.J)
		if not hits.is_empty():
			landed += 1
		if wp.stuck != null:
			stuck += 1
		report.append("%s J %.0f -%d voxels%s" % [k, J, removed, " stuck" if wp.stuck != null else ""])
		w.queue_free()
	print("   throws: ", ", ".join(report))
	t.check(landed >= 4, "the throws land where they were aimed (%d of 5)" % landed)
	t.check(stuck >= 2, "points and edges that bite deep stay in (%d)" % stuck)

## A weapon stuck in a man leaves a wound its own shape: the flesh where the blade sits is
## gone, along the blade's line, and no more than that.
func test_a_stuck_weapon_leaves_a_wound_its_own_shape() -> void:
	var w := _world()
	var b := w.fighter(Vector3(0, 0, 0), 0.0, {}, {"name": "B", "slot": 1})
	await _step(w, 60, func(_f, _i): return {})
	var jv := Weapon.new()
	jv.setup(Data.preset("javelin"), 1.0)
	w.add_child(jv)
	# Point first into the chest from the front, the tip a hand's width inside.
	var dir := Vector3(0, 0, -1)
	var tip: Vector3 = b.torso.global_position + Vector3(0, 0.05, 0.02)
	var basis := Basis(Quaternion(Vector3.UP, dir))
	jv.global_transform = Transform3D(basis, tip - dir * jv.reach)
	jv.linear_velocity = Vector3.ZERO
	var was: PackedByteArray = b.torso.alive.duplicate()
	t.check(jv.impale(b, b.torso, tip), "the javelin sticks in")
	var gone := []
	for i in was.size():
		if was[i] != 0 and b.torso.alive[i] == 0:
			gone.append(i)
	t.check(gone.size() >= 3 and gone.size() <= Weapon.WOUND_MAX, "a wound was opened where it sits (%d voxels)" % gone.size())
	var off := 0.0
	for i in gone:
		var p: Vector3 = b.torso.world_of(i) - tip
		off = maxf(off, (p - dir * p.dot(dir)).length())
	t.check(off < 0.07, "all of it along the javelin's line (at most %.3f m off it)" % off)
	w.queue_free()

## Every weapon, one hand or two, short or long, comes down onto a man lying on the sand with
## a blow that hurts (from where a fighter would stand over him).
func test_every_weapon_comes_down_hard_on_a_man_on_the_sand() -> void:
	for spec in [["gladius", 1.25, 8.0], ["axe", 1.25, 8.0], ["longsword", 1.25, 8.0], ["warhammer", 1.25, 8.0], ["dagger", 0.9, 4.0]]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": spec[0], "off": ""}})
		var f: Fighter = m.me.f
		var ve = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": f.torso.global_position * Vector3(1, 0, 1) + Vector3(0, 0, spec[1]), "yaw": PI})
		ve.erase("bot")
		ve.drive = func(_e): return {}
		var v: Fighter = ve.f
		var st := {"y": 0.15, "power": false}
		m.me.drive = func(_e): return {"main": {"x": 0.1, "y": st.y}, "power": st.power, "look": {"yaw": 0.0, "pitch": -0.5}}
		var r := {"J": 0.0}
		m.combat.hit.connect(func(h):
			if h.get("attacker") == f and h.get("char") == v:
				r.J = maxf(r.J, float(h.J)))
		for i in 90:
			if v.state == "stand":
				v.fall(30.0, true)
			await get_tree().physics_frame
		for rep in 2:
			for i in 60:
				st.y = lerpf(0.15, 1.4, minf(1.0, i / 40.0))
				st.power = false
				if v.state == "stand":
					v.fall(30.0, true)
				await get_tree().physics_frame
			for i in 90:
				st.y = lerpf(1.4, -1.6, minf(1.0, i / 40.0))
				st.power = true
				if v.state == "stand":
					v.fall(30.0, true)
				await get_tree().physics_frame
		t.check(r.J > float(spec[2]), "%s comes down on the man on the sand (hardest blow J %.1f)" % [spec[0], r.J])
		m.queue_free()
		await get_tree().process_frame

## A shield takes the blows that come at a man through it, and pays for them like any weapon:
## chipped where it is struck, broken up in the end.
func test_a_shield_takes_blows_and_breaks_under_them() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": "gladius", "off": "roundShield"}})
	var f: Fighter = m.me.f
	m.me.drive = func(_e): return {"off": {"x": -0.2, "y": 0.35}}
	for i in 90:
		await get_tree().physics_frame
	var sh: Weapon = f.weapons.L
	var n0 := 0
	for a in sh.alive:
		n0 += int(a)
	var blocked := 0
	for k in 40:
		var c: Vector3 = sh.global_transform * sh.local_box().get_center()
		var dir: Vector3 = (c - (c + (c - f.torso.global_position).normalized() * 0.5)).normalized()
		var p: Vector3 = c + dir * 0.15
		var r: Dictionary = f.apply_hit(f.arm.L.fore, {"impulse": 40.0, "type": "point", "hardness": 0.9, "sharpness": 1.0, "point": p, "dir": dir})
		if r.get("blocked", false):
			blocked += 1
		await get_tree().physics_frame
	var n1 := 0
	for a in sh.alive:
		n1 += int(a)
	t.check(blocked > 25, "the shield took the blows (%d of 40)" % blocked)
	t.check(n1 < n0 * 0.7, "and it is battered and broken by them (%d of %d voxels left)" % [n1, n0])
	m.queue_free()
