extends Node
## Pots, arrows, zones and the hotbar (throwables.js, items.js, weaponFx.js).

var t

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	m.me.f.state = "dead"
	return m

func _man(m: Match, pos: Vector3, yaw: float, lo: Dictionary, name_: String, team: int, drive: Callable) -> Dictionary:
	var e = m.spawn_fighter({"kind": "bot", "name": name_, "loadout": lo, "team": team, "pos": pos, "yaw": yaw})
	e.erase("bot")
	e.drive = drive
	return e

func _idle(_e) -> Dictionary:
	return {"main": {"x": 0.1, "y": 0.1}}

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_a_thunder_pot_knocks_a_man_down() -> void:
	seed(2)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4), 0.0, {}, "Thrower", 0, _idle)
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	await _steps(120)
	m.items.throw_at("pot_thunder", a.f.hand_world("R") + Vector3(0, 0.3, 0), b.f.torso.global_position, a.f, 12.0)
	var down := false
	for i in 180:
		await get_tree().physics_frame
		if b.f.state != "stand":
			down = true
	t.check(down, "the blast put him down")
	t.check(b.f.concussion > 0.2, "and rang his bell (%.2f)" % b.f.concussion)
	t.check(b.f.last_attacker == a.f, "blamed on the thrower")
	m.queue_free()

## A thrown anvil is thirty kilos of iron at a throw's speed (user: it hardly wounded and hardly took a voxel): what it lands on is pulped over the width of the anvil itself, the bone broken, the
## wound bled; on a head it ends the man (no cap of a quarter of the brain), on a limb it takes most of it.
func test_an_anvil_pulps_what_it_lands_on() -> void:
	seed(4)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -8), 0.0, {}, "Thrower", 0, _idle)
	var men := []
	for i in 3:
		men.append(_man(m, Vector3(-3.0 + 3.0 * i, 0, 0), PI, {}, "Target%d" % i, 1, _idle))
	await _steps(90)
	var before := {}
	for e in men:
		for p in e.f.parts:
			before[p] = p.alive_count
	# A head from behind, a trunk from behind, and a forearm from the front (the shield arm that was in the way).
	var throws := [["head", 3.0], ["torso", 3.0], ["forearmL", -3.0]]
	for i in 3:
		var f: Fighter = men[i].f
		var prt: VoxelPart = f.by_name.get(throws[i][0])
		var at: Vector3 = prt.global_position
		m.items.throw_flat("pot_anvil", at + Vector3(0, 0.15, float(throws[i][1])), at, a.f, 7.2)
	await _steps(240)
	var f0: Fighter = men[0].f
	var f1: Fighter = men[1].f
	var f2: Fighter = men[2].f
	var head: VoxelPart = f0.head
	t.check(not f0.alive, "an anvil on the head ends the man")
	t.check(head.alive_count < int(before[head]) / 4, "and little of the head is left (%d of %d voxels)" % [head.alive_count, int(before[head])])
	var trunk: VoxelPart = f1.torso
	t.check(int(before[trunk]) - trunk.alive_count > 900, "an anvil on the trunk pulps a great hole in it (%d voxels gone)" % (int(before[trunk]) - trunk.alive_count))
	var lost := 0
	for p in f2.parts:
		lost += int(before[p]) - p.alive_count
	t.check(lost > 300, "and a limb it lands on is crushed (%d voxels gone from him)" % lost)
	t.check(f2.blood < 100.0 or f1.blood < 50.0, "the wounds bleed")
	m.queue_free()

## The discus (user: it did not look good and did not work well): a round plate, not a square tile; spun flat; it strikes the part it meets for what its speed makes of it and glances off
## on (a ricochet), skips on the sand and lies there a while, where a hit used to burst it on the spot and wound whoever stood near. The boomerang is gone, and a saved bag that holds one
## loses it quietly.
func test_a_discus_is_a_round_plate_that_strikes_glances_off_and_skips() -> void:
	seed(6)
	var g := Items.visual("pot_discus")
	t.check(g.get_child_count() == 2 and g.get_children().all(func(n): return n is MeshInstance3D and (n as MeshInstance3D).mesh is CylinderMesh), "it is two round plates, the discus and its boss")
	g.free()
	t.check(not Items.TYPES.has("boomerang") and not (Data.shop.throwables as Dictionary).has("boomerang"), "there is no boomerang")
	t.eq(Throwables.bag_clamp({"boomerang": 3, "anvil": 1}), {"anvil": 1}, "a bag with one in it is kept without")
	var m := _match()
	var a := _man(m, Vector3(0, 0, -6), 0.0, {}, "Thrower", 0, _idle)
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	var c := _man(m, Vector3(3.0, 0, 0), PI, {}, "Bystander", 1, _idle)
	await _steps(60)
	var hits := []
	m.combat.hit.connect(func(h): hits.append(h))
	var at: Vector3 = b.f.torso.global_position
	var it: Dictionary = m.items.throw_flat("pot_discus", at + Vector3(0, 0.05, -5.0), at, a.f, 18.0)
	t.check(absf((it.spin as Vector3).x) < 0.001 and absf((it.spin as Vector3).z) < 0.001 and absf((it.spin as Vector3).y) > 10.0, "it spins flat, about its own axis")
	await _steps(60)
	t.check(hits.any(func(h): return h.char == b.f and float(h.J) > 8.0), "it struck the man it met (%s)" % str(hits.map(func(h): return [h.char.display_name, snappedf(float(h.J), 0.1)])))
	t.check(not hits.any(func(h): return h.char == c.f), "and not the one standing by")
	t.check(m.items.list.has(it) and bool(it.get("bounced", false)), "it was not spent on him: it glanced off (a ricochet)")
	t.check(float((it.get("struck", {}) as Dictionary).size()) == 1, "and it will not strike the same man twice in the flight")
	# It glances off, falls and skips on the sand (a plate, light: it takes a few hops to lie still).
	var skipped := false
	var vy_before := 0.0
	for i in 120 * 8:
		await get_tree().physics_frame
		if not m.items.list.has(it) or it.grounded:
			break
		if float(it.vel.y) > vy_before + 1.0 and float(it.p.y) < 0.4:
			skipped = true
		vy_before = float(it.vel.y)
	t.check(skipped, "it skipped on the sand (a hop, not a burst)")
	t.check(m.items.list.has(it) and it.grounded, "and lies there (%s)" % str(it.p))
	await _steps(120 * 6)
	t.check(not m.items.list.has(it), "and is gone after a few seconds")
	m.queue_free()

## The net (user: the thrown net looked bad, a lattice of thin boxes thrown like a pot; it must work in physics as a net does, and be thrown as one): a mesh of ropes with no stiffness, only a
## length they cannot be drawn past, gathered up in the hand, flung open by the throw, held back by the air at its middle while its weighted rim leads, so that it comes down a bowl.
func _fly(net: NetSim, secs: float, chars := []) -> void:
	for i in int(secs * 120.0):
		net.advance(1.0 / 120.0, chars)

func _stretch(net: NetSim) -> float:
	var worst := 0.0
	for e in net.EA.size():
		worst = maxf(worst, (net.P[net.EA[e]] - net.P[net.EB[e]]).length() / net.cell)
	return worst

func test_a_net_is_a_mesh_of_ropes_flung_open_and_held_back_by_the_air() -> void:
	var g := Items.visual("net")
	t.check(g.get_child_count() >= 8 and g.get_children().all(func(n): return n is MeshInstance3D and ((n as MeshInstance3D).mesh as BoxMesh).size.x < 0.4), "in the hand it is a gathered heap of rope and lead, not a lattice laid out flat")
	g.free()
	var net := NetSim.make(1.0, 4)
	var rim := 0
	for k in net.n:
		rim += net.RIM[k]
	t.check(net.n == 57 and net.EA.size() == 96 and rim >= 20, "knitted of 57 knots and 96 ropes, the rim weighted (%d, %d, %d)" % [net.n, net.EA.size(), rim])
	net.launch(Vector3(0, 1.5, 0), Vector3(0, 3.0, 9.0), Vector3(0, 0.9, 0.3), 1.0)
	t.check(net.reach < 0.3, "it leaves the hand gathered up (%.2f m across)" % net.reach)
	_fly(net, 0.1)
	t.check(net.reach > 0.3 and net.reach < 0.75, "the throw flings it open: half way in a tenth of a second (%.2f m)" % net.reach)
	_fly(net, 0.45)
	t.check(net.reach > 0.9, "and it is open in half a second (%.2f m of its 1)" % net.reach)
	t.check(_stretch(net) < 1.2, "its ropes are never drawn far past their length (%.2f)" % _stretch(net))
	_fly(net, 0.4)
	var mid := 0
	var rim_y := 0.0
	for k in net.n:
		if net.UV[k] == Vector2(4, 4):
			mid = k
		if net.RIM[k] == 1:
			rim_y += net.P[k].y / float(rim)
	t.check(net.P[mid].y > rim_y + 0.1, "the air holds its middle back while the weighted rim leads: it falls a bowl (middle %.2f m, rim %.2f m)" % [net.P[mid].y, rim_y])
	_fly(net, 5.0)
	t.check(net.low < 0.05 and net.rest_t > 1.0 and _stretch(net) < 1.2, "it comes down on the sand, lies there in a heap and is still (%.2f m, %.1f s)" % [net.low, net.rest_t])

func test_a_thrown_net_comes_down_over_a_man_and_holds_him() -> void:
	seed(7)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -5.5), 0.0, {}, "Thrower", 0, _idle)
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	await _steps(60)
	var tgt: Vector3 = b.f.torso.global_position
	var it: Dictionary = m.items.throw_net("net", a.f.hand_world("R") + Vector3(0, 0.3, 0), tgt, a.f, 9.0)
	var net: NetSim = it.net
	var caught_at := -1.0
	for i in 240:
		await get_tree().physics_frame
		if caught_at < 0.0 and b.f.net_timer > 0.0:
			caught_at = net.age
	t.check(caught_at > 0.45 and caught_at < 1.6, "it came down over him in about the time of its flight (%.2f s)" % caught_at)
	t.check(a.f.net_timer == 0.0, "and not over the man who threw it")
	t.check(b.f.net_timer > 1.0 and b.f.net_timer <= 3.0 and net.caught.has(b.f) and m.items.list.has(it), "he is held in it for his three seconds, and it hangs on him (%.1f s)" % b.f.net_timer)
	var on := 0
	for k in net.n:
		for part in b.f.parts:
			if Social.box_distance(part, net.P[k]) < 0.12:
				on += 1
				break
	t.check(on >= 25, "most of its knots lie on him (%d of %d)" % [on, net.n])
	# A net thrown over a man comes to lie on his head and hang from it: the middle of it is caught on his crown.
	var on_head := 0
	var top := 0.0
	for k in net.n:
		if net._pin_part[k] == b.f.head:
			on_head += 1
		top = maxf(top, net.P[k].y)
	t.check(net.held_for.get(b.f, 0.0) > 0.5, "it counts the time he is held (%.1f s)" % float(net.held_for.get(b.f, 0.0)))
	t.check(on_head >= 3 and top > b.f.head.global_position.y, "and its middle hangs on his head (%d knots caught on it, the highest %.2f m, his head at %.2f)" % [on_head, top, b.f.head.global_position.y])
	await _steps(120 * 4)
	t.check(b.f.net_timer == 0.0 and not net.caught.has(b.f), "he is out of it after his three seconds, and it lets him go")
	await _steps(120 * 6)
	t.check(not m.items.list.has(it), "and it lies on the sand a while and is gone")
	m.queue_free()

func test_a_man_who_runs_out_from_under_a_net_is_not_caught() -> void:
	seed(7)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -7.0), 0.0, {}, "Thrower", 0, _idle)
	var run := [false]
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, func(_e): return {"main": {"x": 0.1, "y": 0.1}, "mx": 1.0 if run[0] else 0.0, "sprint": run[0]})
	await _steps(60)
	var tgt: Vector3 = b.f.torso.global_position
	var it: Dictionary = m.items.throw_net("net", a.f.hand_world("R") + Vector3(0, 0.3, 0), tgt, a.f, 9.0)
	run[0] = true
	await _steps(300)
	t.check(b.f.net_timer == 0.0 and absf(b.f.torso.global_position.x) > 1.5, "a man who runs from under it is not held (he is %.1f m to the side)" % absf(b.f.torso.global_position.x))
	t.check(m.items.list.has(it) and (it.net as NetSim).caught.is_empty() and (it.net as NetSim).low < 0.1, "and it comes down on the sand empty")
	m.queue_free()

## The parts of `men` as boxes: [their inverse transform, their half extents], to ask how deep a point is in any of them.
func _boxes_of(men: Array, thrower, age: float) -> Array:
	var out := []
	for f in men:
		if f == thrower and age < 0.4:
			continue
		for part in f.parts:
			if not part.severed:
				out.append([part.global_transform.affine_inverse(), part.half_ext])
	return out

## How deep a point is in any of the boxes (a part's own box, not the net's padded one): the deepest, 0 when it is in none.
func _depth_in(p: Vector3, boxes: Array) -> float:
	var worst := 0.0
	for bx in boxes:
		var l: Vector3 = (bx[0] as Transform3D) * p
		var he: Vector3 = bx[1]
		var d := minf(he.x - absf(l.x), minf(he.y - absf(l.y), he.z - absf(l.z)))
		if d > worst:
			worst = d
	return worst

## The deepest any knot of the net, or the middle of a rope of it, is in any body of `men` (the one who threw it left out for the first moments, while it is at his hand).
func _clip(net: NetSim, men: Array, thrower) -> Vector2:
	var boxes := _boxes_of(men, thrower, net.age)
	var knots := 0.0
	var ropes := 0.0
	for k in net.n:
		knots = maxf(knots, _depth_in(net.P[k], boxes))
	for e in net.EA.size():
		if e % 2 == 0:
			ropes = maxf(ropes, _depth_in((net.P[net.EA[e]] + net.P[net.EB[e]]) * 0.5, boxes))
	return Vector2(knots, ropes)

## The net as it is drawn, found as the shader finds it (off the texture of the knots' places and the boxes it is given): along every thread of every square (its ropes, and the two threads
## drawn between them), at a sixth of its length, where the thread is drawn: a rope is put out of the boxes (the way of least depth), a thread between the ropes is not drawn where
## it lies in one. Against the bodies' own boxes as they are now: [the deepest a point of it is in a body, the deepest the middle of a stretch between two points drawn is].
func _drawn_clip(net: NetSim, men: Array, thrower) -> Vector2:
	var gf := net.grid_bytes().to_float32_array()
	var bf := net.box_bytes().to_float32_array()
	var side := net.grid_side()
	var boxes := []
	for j in net.box_count:
		var i := j * 16
		var inv := Transform3D(Basis(Vector3(bf[i], bf[i + 1], bf[i + 2]), Vector3(bf[i + 4], bf[i + 5], bf[i + 6]), Vector3(bf[i + 8], bf[i + 9], bf[i + 10])), Vector3(bf[i + 3], bf[i + 7], bf[i + 11]))
		boxes.append([inv, Vector3(bf[i + 12], bf[i + 13], bf[i + 14])])
	var real := _boxes_of(men, thrower, net.age)
	var knot := func(gx: int, gy: int) -> Vector3:
		var i: int = (gy * side + gx) * 4
		return Vector3(gf[i], gf[i + 1], gf[i + 2])
	var inside := func(p: Vector3) -> bool:
		for bx in boxes:
			var l: Vector3 = (bx[0] as Transform3D) * p
			var he: Vector3 = bx[1]
			if absf(l.x) < he.x and absf(l.y) < he.y and absf(l.z) < he.z:
				return true
		return false
	var push := func(p: Vector3) -> Vector3:
		for bx in boxes:
			var inv: Transform3D = bx[0]
			var he: Vector3 = bx[1]
			var l: Vector3 = inv * p
			var e := Vector3(he.x - absf(l.x), he.y - absf(l.y), he.z - absf(l.z))
			if e.x > 0.0 and e.y > 0.0 and e.z > 0.0:
				if e.x <= e.y and e.x <= e.z:
					l.x = (1.0 if l.x >= 0.0 else -1.0) * he.x
				elif e.y <= e.z:
					l.y = (1.0 if l.y >= 0.0 else -1.0) * he.y
				else:
					l.z = (1.0 if l.z >= 0.0 else -1.0) * he.z
				p = inv.affine_inverse() * l
		return p
	var pts := 0.0
	var mids := 0.0
	for q in net._quads:
		var gx: int = q[0]
		var gy: int = q[1]
		var k00: Vector3 = knot.call(gx, gy)
		var k10: Vector3 = knot.call(gx + 1, gy)
		var k01: Vector3 = knot.call(gx, gy + 1)
		var k11: Vector3 = knot.call(gx + 1, gy + 1)
		for line in 8:
			var fixed_at: float = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0][line % 4]
			var is_rope: bool = line % 4 == 0 or line % 4 == 3
			var prev = null
			for si in 7:
				var f := float(si) / 6.0
				var u: float = fixed_at if line < 4 else f
				var v: float = f if line < 4 else fixed_at
				var p0: Vector3 = k00.lerp(k10, u).lerp(k01.lerp(k11, u), v)
				var p
				if is_rope:
					p = push.call(p0)
				elif inside.call(p0):
					prev = null
					continue
				else:
					p = p0
				pts = maxf(pts, _depth_in(p, real))
				if prev != null:
					mids = maxf(mids, _depth_in(((prev as Vector3) + (p as Vector3)) * 0.5, real))
				prev = p
	return Vector2(pts, mids)

## (user: the net must look caught on the man and never pass through him, in any situation.) A net thrown at a man standing, running at the thrower, lying, three standing close, and
## at a stride off: not a knot of it and not the middle of a rope of it is ever in a man's body, at any step of the throw and the fall and the holding; and it ends on him, or on the sand.
func test_a_net_never_goes_through_a_man() -> void:
	seed(9)
	var worst := Vector2.ZERO
	var worst_drawn := Vector2.ZERO
	var scenes := ["standing", "running at him", "lying", "three together", "point blank", "running across"]
	for scene in scenes:
		var m := _match()
		var a := _man(m, Vector3(0, 0, -5.0), 0.0, {}, "Thrower", 0, _idle)
		var mv := [0.0, 0.0]
		var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, func(_e): return {"main": {"x": 0.1, "y": 0.1}, "mx": mv[0], "mz": mv[1], "sprint": mv[0] != 0.0 or mv[1] != 0.0})
		var men := [a.f, b.f]
		var kind := "net"
		var aim: Vector3
		await _steps(60)
		match scene:
			"running at him":
				mv[1] = 1.0   # (forward: he faces the thrower)
			"lying":
				b.f.die("test")
				await _steps(90)
			"three together":
				var c := _man(m, Vector3(0.7, 0, 0.3), PI, {}, "Second", 1, _idle)
				var d := _man(m, Vector3(-0.7, 0, -0.2), PI, {}, "Third", 1, _idle)
				men.append(c.f)
				men.append(d.f)
				kind = "pot_bignet"
				await _steps(40)
			"point blank":
				a.f.teleport(Vector3(0, 0, -1.9))
				await _steps(40)
			"running across":
				mv[0] = 1.0
		aim = b.f.torso.global_position
		var it: Dictionary = m.items.throw_net(kind, a.f.hand_world("R") + Vector3(0, 0.3, 0), aim, a.f, 9.0)
		var net: NetSim = it.net
		var deepest := Vector2.ZERO
		var drawn := Vector2.ZERO
		for i in 360:
			await get_tree().physics_frame
			if not m.items.list.has(it):
				break
			if i % 3 == 0:
				var cl := _clip(net, men, a.f)
				deepest = Vector2(maxf(deepest.x, cl.x), maxf(deepest.y, cl.y))
				var dr := _drawn_clip(net, men, a.f)
				drawn = Vector2(maxf(drawn.x, dr.x), maxf(drawn.y, dr.y))
		t.check(deepest.x < 0.010, "%s: not a knot of it is in a body (%.1f mm at the worst)" % [scene, deepest.x * 1000.0])
		t.check(deepest.y < 0.025, "%s: nor the middle of a rope (%.1f mm at the worst)" % [scene, deepest.y * 1000.0])
		t.check(drawn.x < 0.006, "%s: nor a thread of it as it is drawn (%.1f mm at the worst)" % [scene, drawn.x * 1000.0])
		t.check(drawn.y < 0.015, "%s: nor a stretch of thread between two of them (%.1f mm at the worst)" % [scene, drawn.y * 1000.0])
		worst = Vector2(maxf(worst.x, deepest.x), maxf(worst.y, deepest.y))
		worst_drawn = Vector2(maxf(worst_drawn.x, drawn.x), maxf(worst_drawn.y, drawn.y))
		m.queue_free()
	t.check(worst.x < 0.010 and worst.y < 0.025 and worst_drawn.x < 0.006 and worst_drawn.y < 0.015, "in every throw (%.1f and %.1f mm; drawn %.1f and %.1f mm)" % [worst.x * 1000.0, worst.y * 1000.0, worst_drawn.x * 1000.0, worst_drawn.y * 1000.0])

## A net that holds a man hangs on him (its knots that lie on him catch there) and goes where he goes; when he is out of it, it lets go.
func test_a_net_that_holds_a_man_hangs_on_him_and_goes_with_him() -> void:
	seed(7)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -5.5), 0.0, {}, "Thrower", 0, _idle)
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	await _steps(60)
	var it: Dictionary = m.items.throw_net("net", a.f.hand_world("R") + Vector3(0, 0.3, 0), b.f.torso.global_position, a.f, 9.0)
	var net: NetSim = it.net
	await _steps(200)
	t.check(net.caught.has(b.f) and net.pinned >= net.n / 4, "it has caught on him: %d of its %d knots ride on his body" % [net.pinned, net.n])
	# He is carried off at two metres a second (a shove, a friend dragging him): what hangs on him goes too, and nothing of it is in him on the way.
	var x0: Vector3 = b.f.torso.global_position
	var deepest := 0.0
	for i in 90:
		for part in b.f.parts:
			part.linear_velocity = Vector3(2.0, part.linear_velocity.y, 0.0)
		await get_tree().physics_frame
		var bx := _boxes_of([b.f], null, 9.0)
		for k in net.n:
			deepest = maxf(deepest, _depth_in(net.P[k], bx))
	var moved := Vector2(b.f.torso.global_position.x - x0.x, b.f.torso.global_position.z - x0.z).length()
	var off := Vector2(net.center.x - b.f.torso.global_position.x, net.center.z - b.f.torso.global_position.z).length()
	t.check(moved > 0.8 and off < 0.7 and net.pinned >= net.n / 6, "and goes where he goes (he went %.1f m, it is %.2f m from him, %d knots on him)" % [moved, off, net.pinned])
	t.check(deepest < 0.012, "never in him on the way (%.1f mm)" % [deepest * 1000.0])
	await _steps(120 * 3)
	t.check(b.f.net_timer == 0.0 and net.pinned == 0 and not net.caught.has(b.f), "when his time is out it lets go of him: nothing of it is caught on him")
	m.queue_free()

## A guest is not told when the man is out of the net he sees fall over him: it lets him go when the time of such a net is out (Throwables.NET_HOLD), as the host does by the man's own clock.
func test_a_guest_lets_a_man_out_of_the_net_he_sees_fall_over_him_when_its_time_is_out() -> void:
	seed(7)
	var m := _match()
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	await _steps(60)
	var its := Items.new()
	its.headless = true
	add_child(its)
	var it: Dictionary = its.throw_net("net", Vector3(0, 1.8, -3.5), b.f.torso.global_position, null, 9.0)
	var net: NetSim = it.net
	var caught_at := -1.0
	var out_at := -1.0
	for i in 120 * 7:
		await get_tree().physics_frame
		its.update_guest_nets(1.0 / 120.0, [b.f])
		if caught_at < 0.0 and net.caught.has(b.f):
			caught_at = net.age
		if caught_at > 0.0 and out_at < 0.0 and not net.caught.has(b.f):
			out_at = net.age
	t.check(caught_at > 0.0, "the net a guest sees come down over a man holds him (at %.2f s)" % caught_at)
	t.check(out_at > caught_at + 2.8 and out_at < caught_at + 3.5 and net.pinned == 0, "and lets him go when its three seconds are out (%.2f s on)" % (out_at - caught_at))
	m.queue_free()
	its.queue_free()

func test_a_net_man_nets_the_man_who_stands_before_him() -> void:
	seed(8)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4.5), 0.0, {}, "Retiarius", 0, _idle)
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	var c := _man(m, Vector3(1.6, 0, -1.2), PI, {}, "Bystander", 0, _idle)
	await _steps(60)
	m.use_ability(a.f, {"type": "net", "target": b.f})
	await _steps(240)
	t.check(b.f.net_timer > 0.0, "the net he threw is on the man he threw it at")
	t.check(a.f.net_timer == 0.0, "and not on him")
	m.queue_free()

func test_a_guest_draws_the_net_in_the_air_from_the_hosts_word_of_where_it_is() -> void:
	var items := Items.new()
	items.headless = true
	add_child(items)
	items.apply_snapshot([[7, "net", 0.0, 1.8, -3.0, 0.0, 1.0, 8.0]])
	var it: Dictionary = items.list[0] if items.list.size() == 1 else {}
	t.check(not it.is_empty() and it.has("net"), "a net the host has in the air is a net here, falling by its own ropes")
	if it.is_empty():
		items.queue_free()
		return
	var net: NetSim = it.net
	var z0 := net.center.z
	for i in 60:
		items.update_guest_nets(1.0 / 120.0, [])
	t.check(net.center.z > z0 + 1.0 and items.has_nets(), "it flies on between the host's words (%.1f m on)" % (net.center.z - z0))
	items.apply_snapshot([[7, "net", 0.0, 1.0, 3.0, 0.0, 0.0, 0.0]])
	t.check(absf(net.center.z - 3.0) < absf(z0 + 1.0 + 1.0 - 3.0), "and the host's next word draws it back toward where it is (%.1f m from there)" % absf(net.center.z - 3.0))
	items.apply_snapshot([])
	t.check(items.list.is_empty(), "and when the host has none in the air it is gone")
	items.queue_free()

func test_an_archer_draws_looses_and_the_arrow_sticks() -> void:
	seed(3)
	var m := _match()
	var phase := [0]
	var a := _man(m, Vector3(0, 0, -5), 0.0, {"main": "bow"}, "Archer", 0, func(_e):
		return {"main": {"x": 0.3, "y": 0.45}, "power": phase[0] == 1, "look": {"yaw": 0.0, "pitch": 0.0}})
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	var hits := []
	m.combat.hit.connect(func(h): if h.char == b.f: hits.append(h))
	await _steps(90)
	# Aim straight at him: the look the archer looses along.
	var d: Vector3 = b.f.torso.global_position - a.f.weapons.R.global_position
	a.drive = func(_e): return {"main": {"x": 0.3, "y": 0.45}, "power": phase[0] == 1, "look": {"yaw": atan2(d.x, d.z), "pitch": atan2(d.y - 0.15, Vector2(d.x, d.z).length()) - 0.04}}
	# (A bot's shot scatters like a man's, at a mark of its own choosing: it may take him more than
	# one arrow, as it would a man.)
	var flew := false
	for shot in 3:
		phase[0] = 1
		await _steps(150)
		phase[0] = 2
		await _steps(4)
		flew = flew or m.items.list.any(func(it): return it.type == "pot_arrow")
		await _steps(60)
		if hits.any(func(h): return h.type == "point"):
			break
	t.check(flew, "an arrow is in the air")
	t.check(not hits.is_empty() and hits.any(func(h): return h.type == "point"), "it went in (%d hits)" % hits.size())
	var bleed := 0.0
	for p in b.f.parts:
		bleed += p.bleed
	t.check(bleed > 0.5, "and he bleeds (%.1f)" % bleed)
	m.queue_free()

func test_greek_fire_sets_a_man_alight_and_burns_him() -> void:
	seed(4)
	var m := _match()
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	await _steps(60)
	var p: Vector3 = b.f.torso.global_position + Vector3(0, 0, 0.2)
	m.throwables.explode("pot_fire", p, null, Vector3(0, 0, -1), b.f, b.f.torso)
	await _steps(5)
	t.check(Fire.is_burning(b.f), "he is on fire")
	var hp0: float = b.f.torso.hp
	var alive0: int = b.f.torso.alive_count
	await _steps(120 * 4)
	t.check(b.f.torso.hp < hp0, "it hurts (%.0f -> %.0f)" % [hp0, b.f.torso.hp])
	t.check(b.f.torso.alive_count < alive0, "and burns the flesh away (%d -> %d voxels)" % [alive0, b.f.torso.alive_count])
	m.queue_free()

func test_olive_oil_makes_a_runner_slip() -> void:
	seed(5)
	var m := _match()
	var b := _man(m, Vector3(0, 0, -3), 0.0, {}, "Runner", 1, func(_e): return {"main": {"x": 0.1, "y": 0.1}, "mz": 1.0, "sprint": true, "look": {"yaw": 0.0, "pitch": 0.0}})
	m.throwables.add_zone("oil", Vector3(0, 0, 0), 2.6, 14.0)
	var slipped := false
	for i in 300:
		await get_tree().physics_frame
		if b.f.state != "stand":
			slipped = true
			break
	t.check(slipped, "he ran into the oil and went down")
	m.queue_free()

func test_the_hotbar_eats_bread_and_bots_throw_pots() -> void:
	seed(6)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4), 0.0, {}, "Kit", 0, _idle)
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	a.inventory = {"bread": 1, "smoke": 1}
	a.f.blood = 40.0
	t.eq(Throwables.hotbar_of(a.inventory), ["bread", "smoke"], "the hotbar in shop order")
	t.check(m.throwables.use_item(a, 0), "bread used")
	t.check(a.f.blood > 70.0, "blood back (%.0f)" % a.f.blood)
	t.eq(Throwables.hotbar_of(a.inventory), ["smoke"], "the bread is gone")
	m.throwables.use_item(a, 0)
	t.check(m.items.list.any(func(it): return it.type == "pot_smoke"), "a bot throws the pot at once")
	await _steps(150)
	t.check(m.throwables.zones.any(func(z): return z.type == "smoke"), "and it made a cloud of sand and smoke")
	# A player readies it in hand instead, and F throws it.
	a.kind = "local"
	a.inventory = {"thunderPot": 1}
	m.throwables.use_item(a, 0)
	t.check(a.f.held_item != null, "a player holds the pot first")
	m.throwables.throw_held(a, {"look": {"yaw": 0.0, "pitch": 0.0}, "throwPower": 0.8})
	t.check(a.f.held_item == null and m.items.list.any(func(it): return it.type == "pot_thunder"), "and throws it")
	m.queue_free()

func test_a_pot_leaves_from_the_hand_that_holds_it() -> void:
	seed(9)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4), 0.0, {}, "Kit", 0, _idle)
	a.kind = "local"
	await _steps(30)
	var pot_from := func() -> Vector3:
		var it = m.items.list.filter(func(i): return i.type == "pot_thunder").back()
		return it.p
	a.inventory = {"thunderPot": 2}
	m.throwables.use_item(a, 0)
	var side: String = a.f.held_item.side
	var hand: Vector3 = a.f.hand_world(side)
	m.throwables.throw_held(a, {"look": {"yaw": 0.0, "pitch": 0.0}, "throwPower": 0.8})
	t.check(pot_from.call().distance_to(hand) < 0.25, "it leaves the %s hand it was held in (%.2f m off)" % [side, pot_from.call().distance_to(hand)])
	# Readied in the left hand, and the left forearm taken off: it goes from the right one,
	# not from the forearm lying on the sand.
	m.throwables.use_item(a, 0)
	t.eq(a.f.held_item.side, "L", "readied in the free left hand")
	var fore: VoxelPart = a.f.arm.L.fore
	a.f.detach_limb(fore, {"removed": [], "severed": []})
	fore.global_position += Vector3(2.0, 0, 0)
	m.throwables.throw_held(a, {"look": {"yaw": 0.0, "pitch": 0.0}, "throwPower": 0.8})
	var from: Vector3 = pot_from.call()
	t.check(from.distance_to(a.f.hand_world("R")) < 0.25, "the good hand throws it (%.2f m from it, %.2f m from the cut-off one)" % [from.distance_to(a.f.hand_world("R")), from.distance_to(a.f.hand_world("L"))])
	t.eq(a.f.item_hand(), "R", "the next is readied in the right hand")
	m.queue_free()

## Both hands full (a sword and a shield): the pot is not put in a fist round the shield's grip.
## The shield hand puts the shield out of sight (hidden, touching nothing, still his), holds the
## pot, throws it from there, and has the very same shield back once the arm has come through;
## the same when the pot is put back in the kit, and for a bot that throws at once. Dying with
## the shield put away, it is dropped on the sand like his other arms (user).
func test_a_full_hand_puts_its_weapon_away_to_throw_and_takes_it_back() -> void:
	seed(4)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4), 0.0, {"main": "gladius", "off": "roundShield"}, "Kit", 0, _idle)
	a.kind = "local"
	await _steps(40)
	var f: Fighter = a.f
	var shield: Weapon = f.weapons.L
	t.check(shield != null and shield.is_shield, "a shield in the left hand")
	a.inventory = {"thunderPot": 3}
	m.throwables.use_item(a, 0)
	t.eq(f.held_item.side, "L", "the pot goes to the shield hand")
	t.check(f.weapons.L == null and f.stowed.L == shield, "which puts the shield away for it")
	t.check(not shield.visible and shield.collision_layer == 0 and shield.collision_mask == 0, "out of sight, touching nothing")
	t.check(f.weapons.R != null, "the sword stays in the right hand")
	await _steps(20)
	var hand: Vector3 = f.hand_world("L")
	m.throwables.throw_held(a, {"look": {"yaw": 0.0, "pitch": 0.0}, "throwPower": 0.8})
	f.throw_anim = {"side": "L", "phase": "follow", "t": 0.35}
	var it = m.items.list.filter(func(i): return i.type == "pot_thunder").back()
	t.check(it != null and (it.p as Vector3).distance_to(hand) < 0.3, "the pot leaves from that hand (%.2f m off)" % ((it.p as Vector3).distance_to(hand) if it else -1.0))
	t.check(f.weapons.L == null, "the shield still away while the arm comes through")
	await _steps(60)
	t.check(f.weapons.L == shield and f.stowed.L == null, "then the same shield is back in the hand")
	t.check(shield.visible and shield.collision_layer != 0 and not shield.freeze, "seen and solid again")
	t.check(shield.grip_world().distance_to(f.hand_world("L")) < 0.15, "held at its grip (%.2f m)" % shield.grip_world().distance_to(f.hand_world("L")))
	# Readied and put back in the kit: the shield comes back too.
	m.throwables.use_item(a, 0)
	t.check(f.stowed.L == shield, "readied again, the shield away")
	m.throwables.use_item(a, 0)
	await _steps(4)
	t.check(f.held_item == null and f.weapons.L == shield, "put back in the kit, the shield in the hand again")
	# A bot throws at once, from the shield hand, and has its shield back after (at a man far off:
	# its pot is not to land on the one being tested).
	_man(m, Vector3(3, 0, 16), PI, {}, "Mark", 1, _idle)
	var b := _man(m, Vector3(3, 0, -4), 0.0, {"main": "gladius", "off": "roundShield"}, "Bot", 0, _idle)
	await _steps(40)
	var bs: Weapon = b.f.weapons.L
	b.inventory = {"thunderPot": 1}
	m.throwables.use_item(b, 0)
	t.check(b.f.weapons.L == null and b.f.stowed.L == bs, "a bot's shield goes out of sight for the throw")
	await _steps(70)
	t.check(b.f.weapons.L == bs and bs.visible, "and is back in its hand after")
	# Killed with the shield put away: it falls on the sand.
	m.throwables.use_item(a, 0)
	t.check(f.stowed.L == shield, "readied once more")
	f.die("test")
	t.check(f.stowed.L == null and shield.holder == null and shield.visible and m.combat.loose_weapons.has(shield), "dead, the shield is dropped, seen, loose")
	m.queue_free()

func test_a_crossbow_shoots_a_bolt_on_a_thrust() -> void:
	seed(7)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4), 0.0, {"main": "crossbow"}, "Shooter", 0, func(_e): return {"main": {"x": 0.0, "y": 0.2}, "thrust": 1.0})
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	await _steps(60)
	t.check(m.items.list.any(func(it): return it.type == "pot_bolt") or a.f.weapons.R.get_meta("reload", 0.0) > 0.0, "a bolt went off")
	m.queue_free()

## The physician's supplies do what the stall says: a bandage stops every bleed (and beside a
## fallen friend it is his, and he is up twice as fast), bread brings blood back, wine gives
## the breath back and makes him a little drunk for a while, and no more than that.
func test_the_physicians_supplies_do_what_they_say() -> void:
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4), 0.0, {}, "Medic", 0, _idle)
	var b := _man(m, Vector3(0.8, 0, -4), 0.0, {}, "Friend", 0, _idle)
	await _steps(20)
	# Bandage on himself.
	a.f.torso.bleed = 2.0
	a.f.arm.R.fore.artery = 1.0
	a.inventory = {"bandage": 2, "bread": 1, "wine": 1}
	m.throwables.use_item(a, Throwables.hotbar_of(a.inventory).find("bandage"))
	t.check(a.f.torso.bleed == 0.0 and a.f.arm.R.fore.artery == 0.0, "the bandage stops his bleeding")
	# Bandage beside a fallen friend.
	b.f.fall(6.0, true)
	b.f.torso.bleed = 2.0
	await _steps(5)
	var t0: float = b.f.down_timer
	m.throwables.use_item(a, Throwables.hotbar_of(a.inventory).find("bandage"))
	t.check(b.f.torso.bleed == 0.0, "the friend's bleeding is stopped")
	t.check(b.f.down_timer <= 0.5 and b.f.help_t > 0.0, "and he is helped up (down %.1f s → %.1f s)" % [t0, b.f.down_timer])
	await _steps(120 * 2)
	t.eq(String(b.f.state), "stand", "two seconds later he stands")
	# Bread.
	a.f.blood = 40.0
	m.throwables.use_item(a, Throwables.hotbar_of(a.inventory).find("bread"))
	t.check(absf(a.f.blood - 80.0) < 1.0, "bread: blood back (%.0f)" % a.f.blood)
	# Wine, under a drunk decree.
	a.f.mods.drunk = 0.5
	a.f.stamina = 10.0
	m.throwables.use_item(a, Throwables.hotbar_of(a.inventory).find("wine"))
	t.check(a.f.stamina >= a.f.breath_cap() - 0.01, "wine: full breath (%.0f)" % a.f.stamina)
	t.check(float(a.f.mods.drunk) >= 0.3, "and drunk")
	a.f.wine_timer = 0.01
	await _steps(3)
	t.check(absf(float(a.f.mods.drunk) - 0.5) < 0.01, "when it wears off he is as drunk as the decree had him (%.2f)" % float(a.f.mods.drunk))
	m.queue_free()

## The bag: nine kinds at most, one heavy thing, three pots, five of something light; an old
## save carrying more is cut down to that.
func test_the_bag_holds_nine_kinds_and_sensible_stacks() -> void:
	t.eq(Throwables.stack_max("anvil"), 1, "one anvil")
	t.eq(Throwables.stack_max("nailPot"), 3, "three nail pots")
	t.eq(Throwables.stack_max("bread"), 5, "five loaves")
	var inv := {"nailPot": 3}
	t.check(not Throwables.bag_has_room(inv, "nailPot"), "no fourth nail pot")
	t.check(Throwables.bag_has_room(inv, "bread"), "room for bread beside them")
	var nine := {}
	for id in (Data.shop.throwables.keys() as Array).slice(0, 9):
		nine[id] = 1
	var tenth: String = Data.shop.throwables.keys()[9]
	t.check(not Throwables.bag_has_room(nine, tenth), "no tenth kind")
	var old := Net.sanitize_kit({"nailPot": 9, "anvil": 4, "bread": 9})
	t.eq([int(old.nailPot), int(old.anvil), int(old.bread)], [3, 1, 5], "an old bag cut down to what it may hold")

## Knocked down but awake, a man still throws: the arm comes up off the sand as he winds up,
## and the pot leaves his hand.
func test_a_man_on_the_sand_still_throws() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": "gladius", "off": ""}})
	var f: Fighter = m.me.f
	var inp := {"main": {"x": 0.2, "y": 0.2}, "look": {"yaw": 0.0, "pitch": 0.0}}
	m.me.drive = func(_e): return inp.duplicate()
	m.me.inventory = {"greekFire": 2}
	for i in 60:
		await get_tree().physics_frame
	f.fall(4.0, true)
	for i in 40:
		await get_tree().physics_frame
	t.eq(f.state, "down", "he is down")
	inp.useItem = 0
	await get_tree().physics_frame
	inp.erase("useItem")
	await get_tree().physics_frame
	t.check(f.held_item != null, "the pot is readied in his hand")
	inp.charging = 0.6
	var hy := -9.0
	for i in 30:
		await get_tree().physics_frame
		hy = maxf(hy, f.hand_world("L").y - f.torso.global_position.y)
	t.check(hy > 0.4, "the throwing arm comes up off the sand (%.2f m above the chest)" % hy)
	inp.erase("charging")
	inp.throw = true
	await get_tree().physics_frame
	inp.erase("throw")
	for i in 30:
		await get_tree().physics_frame
	t.check(f.held_item == null and int(m.me.inventory.greekFire) == 1, "and the pot is thrown")
	m.queue_free()

## The wind-up sets the throw: a flick tosses a pot a few paces, short of a far mark; held to the
## full it flies hard and reaches it.
func test_the_wind_up_sets_how_hard_a_pot_flies() -> void:
	var far := {}
	for power in [0.3, 1.0]:
		var m := _match()
		var a := _man(m, Vector3(0, 0, -6), 0.0, {}, "Thrower", 0, _idle)
		a.kind = "local"
		a.inventory = {"smoke": 1}
		await _steps(30)
		m.throwables.use_item(a, 0)
		var from: Vector3 = a.f.torso.global_position
		m.throwables.throw_held(a, {"look": {"yaw": 0.0, "pitch": 0.0}, "throwPower": power, "aimAt": from + Vector3(0, 0, 14.0)})
		var it = null
		for x in m.items.list:
			if x.type == "pot_smoke":
				it = x
		t.check(it != null, "thrown (power %.1f)" % power)
		var reach := 0.0
		for i in 240:
			await get_tree().physics_frame
			if it == null or not m.items.list.has(it):
				break
			reach = maxf(reach, (it.p as Vector3).z - from.z)
		far[power] = reach
		m.queue_free()
	t.check(float(far[0.3]) < 9.0, "a flick falls well short of a mark 14 m off (%.1f m)" % far[0.3])
	t.check(float(far[1.0]) > 12.5, "a full wind-up reaches it (%.1f m)" % far[1.0])

## A banana peel under a sole floors whoever steps on it, a man or a beast (user: the banana peels
## did nothing; they looked for a man's shins only).
func test_a_banana_peel_floors_a_man_and_a_beast() -> void:
	seed(6)
	var m := _match()
	var man := _man(m, Vector3(-2, 0, 0), 0.0, {}, "Walker", 1, _idle)
	var lion = m.spawn_beast({"beast": "lion", "team": 1, "pos": Vector3(3, 0.1, 0), "yaw": 0.0, "harmless": true})
	await _steps(120)
	for c in [man.f, lion.f]:
		var sole: Vector3 = c.soles()[0][1]
		var it: Dictionary = m.items.spawn("banana", Vector3(sole.x, 0.06, sole.z), Vector3.ZERO, null)
		it.grounded = true
	var man_down := false
	var lion_down := false
	for i in 30:
		await get_tree().physics_frame
		man_down = man_down or man.f.state != "stand"
		lion_down = lion_down or float(lion.f.down_t) > 0.0
	t.check(man_down, "the man stepped on the peel and went down")
	t.check(lion_down, "and the lion went over on its side")
	m.queue_free()

## Olive oil floors anyone who moves in it, a walker as well as a runner; standing still in it a
## man keeps his feet (user: the oil pot did nothing: only a runner went down, and in a fight
## nobody runs).
func test_olive_oil_floors_a_walker_but_not_one_standing_still() -> void:
	seed(7)
	var m := _match()
	var walker := _man(m, Vector3(-1.0, 0, -2.5), 0.0, {}, "Walker", 1, func(_e): return {"main": {"x": 0.1, "y": 0.1}, "mz": 0.5, "look": {"yaw": 0.0, "pitch": 0.0}})
	var still := _man(m, Vector3(1.2, 0, 0.5), 0.0, {}, "Still", 1, _idle)
	m.throwables.add_zone("oil", Vector3(0, 0, 0), 2.6, 14.0)
	var down := false
	var still_down := false
	for i in 600:
		await get_tree().physics_frame
		down = down or walker.f.state != "stand"
		still_down = still_down or still.f.state != "stand"
	t.check(down, "a man walking through the oil went down")
	t.check(not still_down, "one standing still in it kept his feet")
	m.queue_free()

## A caltrop goes into the foot of whatever steps on it: a man's, a lion's, the Cerberus's (user:
## the caltrops did nothing to the Cerberus; make sure they work on everyone), and it limps.
func test_a_caltrop_goes_into_any_foot() -> void:
	seed(8)
	var m := _match()
	var man := _man(m, Vector3(-3, 0, 0), 0.0, {}, "Man", 1, _idle)
	var lion = m.spawn_beast({"beast": "lion", "team": 1, "pos": Vector3(0.5, 0.1, 0), "yaw": 0.0, "harmless": true})
	var dog = m.spawn_beast({"beast": "cerberus", "team": 1, "pos": Vector3(5, 0.1, 0), "yaw": 0.0, "harmless": true})
	await _steps(120)
	var who := [man.f, lion.f, dog.f]
	var feet := []
	for c in who:
		var so: Array = c.soles()
		t.check(so.size() == (2 if c == man.f else 4), "%s stands on %d soles" % [c.display_name, so.size()])
		var part: VoxelPart = so[0][0]
		feet.append([part, part.hp, part.bleed])
		var it: Dictionary = m.items.spawn("caltrop", Vector3((so[0][1] as Vector3).x, 0.03, (so[0][1] as Vector3).z), Vector3.ZERO, null)
		it.grounded = true
	await _steps(20)
	for k in who.size():
		var c = who[k]
		var p: VoxelPart = feet[k][0]
		t.check(p.hp < float(feet[k][1]) or p.bleed > float(feet[k][2]), "%s: the spike went into the foot" % c.display_name)
		t.check(c.slow_timer > 0.0, "%s limps" % c.display_name)
	m.queue_free()

## A thunder pot going off beside a man in armour blows plates off the side of him turned to it,
## and wears the rest; a smaller blast does it on a smaller scale (user: the pots did no harm to
## armour at all, the thunder pot least of all).
func test_a_blast_blows_plates_off_armour() -> void:
	seed(9)
	var m := _match()
	var b := _man(m, Vector3(0, 0, 0), PI, {"armor": ["helmet", "lorica", "manica", "greaves"]}, "Armoured", 1, _idle)
	var c := _man(m, Vector3(6, 0, 0), PI, {"armor": ["helmet", "lorica", "manica", "greaves"]}, "Also armoured", 1, _idle)
	await _steps(120)
	var plates := func(f: Fighter) -> int:
		var n := 0
		for p in f.parts:
			for ad in p.get_meta("armor", []):
				n += int(ad.alive)
		return n
	var b0: int = plates.call(b.f)
	var c0: int = plates.call(c.f)
	# (In front of him, at his knees: the pot burst at his feet.)
	m.throwables.explode("pot_thunder", b.f.torso.global_position + Vector3(0, -0.7, -0.6), null)
	m.throwables.blast(c.f.torso.global_position + Vector3(0, -0.3, -0.5), 2.6, 22.0, null)
	await _steps(10)
	var b1: int = plates.call(b.f)
	var c1: int = plates.call(c.f)
	t.check(b0 - b1 >= 12, "the thunder pot blew %d plates off him (of %d)" % [b0 - b1, b0])
	t.check(b1 > b0 / 3, "not every last one: the side away from it held (%d left)" % b1)
	t.check(c0 - c1 >= 2, "the smaller blast took %d off the other" % (c0 - c1))
	m.queue_free()

## A honey pot broken on a man brings a swarm down on him, the thrower's: they sting him (his blood
## goes down), a blade swung fast through one kills it, a man they cover swats at them and kills
## some, and they leave him when he is dead (user: the honey pot did nothing; it must bring bees
## that attack the man it hit, that he can kill and that can kill him).
func test_a_honey_pot_brings_bees_that_sting_and_can_be_killed() -> void:
	seed(10)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -3), 0.0, {"main": "gladius", "off": ""}, "Thrower", 0, _idle)
	var b := _man(m, Vector3(0, 0, 0), PI, {"main": "gladius", "off": ""}, "Target", 1, _idle)
	await _steps(60)
	m.throwables.explode("pot_honey", b.f.torso.global_position, a.f, Vector3(0, 0, 1), b.f, b.f.torso)
	t.eq(m.throwables.hives.size(), 1, "a swarm on the man it broke on")
	t.eq(m.throwables.hives[0].bees.size(), Throwables.BEES, "of %d bees" % Throwables.BEES)
	t.check(m.throwables.hives[0].target == b.f, "on him, not on the thrower")
	var blood0: float = b.f.blood
	await _steps(600)
	t.check(b.f.blood < blood0 - 3.0, "they stung him: his blood %.1f, was %.1f" % [b.f.blood, blood0])
	t.check(b.f.last_attacker == a.f, "the thrower's bees")
	# The rule: a blade going fast through a bee kills it; still, it does not.
	var w: Weapon = a.f.weapons.R
	var mid: Vector3 = w.global_transform * w.local_box().get_center()
	w.linear_velocity = Vector3.ZERO
	w.angular_velocity = Vector3.ZERO
	t.check(not m.throwables._swatted(mid), "a blade held still kills nothing")
	w.linear_velocity = Vector3(6, 0, 0)
	t.check(m.throwables._swatted(mid), "swung through a bee, it kills it")
	w.linear_velocity = Vector3.ZERO
	# A bot they cover swats about his head at them, and kills some.
	var c = m.spawn_fighter({"kind": "bot", "name": "Swatter", "loadout": {"main": "gladius", "off": ""}, "team": 1, "pos": Vector3(4, 0.1, 0), "yaw": PI})
	await _steps(30)
	m.throwables.bees_on(c.f, a.f, c.f.head.global_position + Vector3(0, 0.3, 0))
	var hv: Dictionary = m.throwables.hives.back()
	await _steps(1200)
	var left: int = hv.bees.filter(func(x): return x.on).size()
	t.check(left < Throwables.BEES, "he swatted %d of them out of the air" % (Throwables.BEES - left))
	# Dead, they leave him.
	b.f.die("test")
	await _steps(600)
	t.check(not m.throwables.hives.any(func(h): return h.target == b.f), "he is dead: his bees have left him")
	m.queue_free()

## Every box of a size and a colour that things are drawn of is one mesh, as it is one material
## (Items._box): a pot's hundred and twenty nails were three hundred meshes made in the step it broke.
func test_boxes_of_a_size_and_colour_are_one_mesh() -> void:
	var meshes := func(g: Node3D) -> Array:
		var out := []
		for c in g.get_children():
			if c is MeshInstance3D:
				out.append(c.mesh)
		return out
	var a := Items.visual("nail")
	var b := Items.visual("nail")
	var c := Items.visual("bread")
	var ma: Array = meshes.call(a)
	var mb: Array = meshes.call(b)
	var mc: Array = meshes.call(c)
	t.check(ma.size() >= 1 and ma.size() == mb.size(), "a nail is drawn of boxes (%d)" % ma.size())
	var same := ma.size() == mb.size()
	var whole := true
	for i in mini(ma.size(), mb.size()):
		same = same and is_same(ma[i], mb[i])
		var bm := ma[i] as BoxMesh
		whole = whole and bm != null and bm.size.x > 0.0 and bm.size.y > 0.0 and bm.size.z > 0.0 and bm.material != null
	t.check(same, "two nails are drawn of the same meshes")
	t.check(whole, "each a box of its size, in its material")
	var other := true
	for x in mc:
		for y in ma:
			other = other and not is_same(x, y)
	t.check(mc.size() >= 2 and other, "a loaf of bread of its own")
	a.free()
	b.free()
	c.free()

## The chest armour's box, that an arm's plates gone into the chest are not drawn inside (Fighter.
## _clip_arm_armor), follows the plates left on the chest: worked out from where each plate is drawn,
## kept from when the piece was laid on him (a plate knocked off had every other one's place worked
## out again in the frame after the blow), as it is when all of it is worked out anew.
func test_the_chest_armours_box_follows_the_plates_left() -> void:
	var m := _match()
	var e := _man(m, Vector3(0, 0, 0), PI, {"armor": ["helmet", "lorica", "manica", "greaves"]}, "Armoured", 1, _idle)
	await _steps(20)
	var f: Fighter = e.f
	f._clip_arm_armor()
	t.check(f.torso.has_meta("armor_box"), "a man in a cuirass has its box")
	var box0: AABB = f.torso.get_meta("armor_box", AABB())
	var kept := 0
	for ad in f.torso.get_meta("armor", []):
		if ad.get("box_o") is PackedVector3Array:
			kept += 1
	t.check(kept >= 1 and box0.size.x > 0.0, "where its plates are drawn is kept (%d pieces)" % kept)
	# The plates of the top of it knocked off: the box comes down with them.
	var gone := 0
	for ad in f.torso.get_meta("armor", []):
		if Fighter._cosmetic(String(ad.id)):
			continue
		var top := -INF
		for ci in ad.cells.size():
			if ad.on[ci] == 1:
				top = maxf(top, (ad.pts[ci] as Vector3).y)
		for ci in ad.cells.size():
			if ad.on[ci] == 1 and (ad.pts[ci] as Vector3).y > top - f.torso.half_ext.y * 0.5:
				f._knock_plate(f.torso, ad, ci, Vector3.UP, 1.0, false)
				gone += 1
	t.check(gone >= 4 and not f.torso.has_meta("armor_box"), "plates knocked off the top of it (%d): its box is to be worked out again" % gone)
	f._clip_arm_armor()
	var box1: AABB = f.torso.get_meta("armor_box", AABB())
	for ad in f.torso.get_meta("armor", []):
		ad.erase("box_o")
	f.torso.remove_meta("armor_box")
	f._clip_arm_armor()
	var box2: AABB = f.torso.get_meta("armor_box", AABB())
	t.check(box1.is_equal_approx(box2), "from the places kept, the same box as worked out anew")
	t.check(box1.end.y < box0.end.y - 0.001, "lower than it was (%.3f, was %.3f)" % [box1.end.y, box0.end.y])
	m.queue_free()

## (#298k) What a man's armour makes of his arms for the C++ core (Fighter._arm_rec: which limbs wear armour, the outline each is kept out of) is worked out once while his armour stays as it
## is, across the steps, and afresh once it changes (armor_changed: _add_armor, set_armor_pieces): the same as asked afresh every time, bare and in each set of armour put on and taken off.
func _rec_digest(rec: Array) -> String:
	return "%d %s %d %s %d %d" % [(rec[0] as Dictionary).size(), str(rec[1]), (rec[2] as Dictionary).size(), str(rec[3]), (rec[0] as Dictionary).hash(), (rec[2] as Dictionary).hash()]

func _sculpt_digest(o) -> String:
	return "none" if o == null else "%d %d" % [(o as Dictionary).size(), (o as Dictionary).hash()]

## (And the trunk's outline each arm is kept out of, Fighter._trunk_sculpt, kept the same way: as worked out afresh, and none while someone has hold of him.)
func _recs_now(f: Fighter) -> Array:
	var out := []
	f._arm_phase_begin()
	var kept := [f._arm_rec("L"), f._arm_rec("R")]
	var again := [f._arm_rec("L"), f._arm_rec("R")]
	var sc_kept := [f._trunk_sculpt("L"), f._trunk_sculpt("R")]
	f._arm_phase_begin()
	var sc_again := [f._trunk_sculpt("L"), f._trunk_sculpt("R")]
	f._arm_phase_begin()
	f.set_meta("rolled_by", f)
	var sc_held := [f._trunk_sculpt("L"), f._trunk_sculpt("R")]
	f._arm_phase = false
	var sc_held_fresh := [f._trunk_sculpt("L"), f._trunk_sculpt("R")]
	f.remove_meta("rolled_by")
	var fresh := [f._arm_rec("L"), f._arm_rec("R")]
	var sc_fresh := [f._trunk_sculpt("L"), f._trunk_sculpt("R")]
	for i in 2:
		out.append(_rec_digest(kept[i]) == _rec_digest(fresh[i]) and is_same(kept[i], again[i])
				and _sculpt_digest(sc_kept[i]) == _sculpt_digest(sc_fresh[i]) and _sculpt_digest(sc_again[i]) == _sculpt_digest(sc_fresh[i])
				and sc_held[i] == null and sc_held_fresh[i] == null)
	_sculpts_seen[_sculpt_digest(sc_fresh[0])] = true
	out.append(_rec_digest(fresh[0]) + " / " + _rec_digest(fresh[1]))
	return out

var _sculpts_seen := {}
func test_the_arm_records_follow_his_armour() -> void:
	_sculpts_seen.clear()
	var m := _match()
	var e := _man(m, Vector3(0, 0, 0), PI, {"armor": []}, "Bare", 1, _idle)
	await _steps(10)
	var f: Fighter = e.f
	var bare := _recs_now(f)
	t.check(bare[0] and bare[1], "a bare man's records are as worked out afresh, and kept")
	var seen := {bare[2]: true}
	# (Kept across arm phases while nothing changes: the same record object, not one worked out again.)
	f._arm_phase_begin()
	var r0 = f._arm_rec("R")
	f._arm_phase_begin()
	t.check(is_same(r0, f._arm_rec("R")), "the record is kept from one arm phase to the next")
	f._arm_phase = false
	for ids in [["lorica", "manica"], ["manicaL", "vambraces"], ["lorica", "manica", "manicaL", "vambraces"], []]:
		f.set_armor_pieces(ids)
		await _steps(3)
		var now := _recs_now(f)
		t.check(now[0] and now[1], "after %s, the records are as worked out afresh" % str(ids))
		seen[now[2]] = true
	t.check(seen.size() >= 3, "the records changed with the armour put on and taken off (%d different)" % seen.size())
	t.check(_sculpts_seen.size() >= 2 and _sculpts_seen.has("none"), "and the trunk's outline with them: one in armour, none bare (%d different)" % _sculpts_seen.size())
	# (A cuirass on a man at a station of the yard: the same by the forge's bench, which says so with armor_changed.)
	var before := f._armor_ver
	f.armor_changed()
	t.check(f._armor_ver == before + 1, "armor_changed counts a change")
	m.queue_free()

## What Fighter._clip_arm_armor leaves of an arm's plates, as the old pass over every plate of every
## piece of it did (the C++ core now names the few plates it has anything to decide on, VoxelCore.
## clip_plates; without the core every plate is looked at): the same plates hidden after each frame,
## for boxes of every size and place, some plates knocked off, the arms swung about.
func _clip_pass_old(f: Fighter) -> Array:
	var out := []
	var box: AABB = f.torso.get_meta("armor_box", AABB())
	var ol: Dictionary = f.torso.get_meta("armor_outline", {})
	var ol_pad: float = f.torso.vf * f.torso.part_scale * 0.25
	var tinv := f.torso.get_global_transform_interpolated().affine_inverse()
	for n in ["upperArmL", "upperArmR"]:
		var p: VoxelPart = f.by_name.get(n)
		if p == null or p.severed or p.missing:
			continue
		var to_t := tinv * p.get_global_transform_interpolated()
		for ad in p.get_meta("armor", []):
			if Fighter._cosmetic(String(ad.id)) or ad.node == null or not is_instance_valid(ad.node) or not ad.has("xf"):
				continue
			var want: PackedByteArray = (ad.clip as PackedByteArray).duplicate()
			for ci in ad.cells.size():
				if ad.on[ci] == 0:
					continue
				var q: Vector3 = to_t * (ad.xf[ci] as Transform3D).origin
				want[ci] = 1 if box.has_point(q) and (ol.is_empty() or FineArmor.in_outline(ol, q, ol_pad)) else 0
			out.append([ad, want])
	return out

func test_the_arm_armours_clip_pass_is_the_old_pass() -> void:
	var m := _match()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var turn := [0]
	var drive := func(_e) -> Dictionary:
		turn[0] += 1
		var k: int = turn[0] / 12
		var r2 := RandomNumberGenerator.new()
		r2.seed = k
		return {"main": {"x": r2.randf_range(-1.0, 1.0), "y": r2.randf_range(-1.0, 1.0)}, "off": {"x": r2.randf_range(-1.0, 1.0), "y": r2.randf_range(-1.0, 1.0)}}
	var e := _man(m, Vector3(0, 0, 0), PI, {"armor": ["helmet", "lorica", "manica", "greaves"]}, "Armoured", 1, drive)
	await _steps(20)
	var f: Fighter = e.f
	f._clip_arm_armor()   # (what it keeps: the box, the outline, where each plate is drawn)
	var he: Vector3 = f.torso.half_ext
	var real_outline: Dictionary = f.torso.get_meta("armor_outline", {})
	var frames := 0
	var differ := 0
	var turned := 0
	var hid_most := 0
	var pieces := 0
	for k in 90:
		await _steps(1)
		# (The chest's box anywhere about him, and now and then a plate of an arm knocked off.)
		var sz := Vector3(he.x * rng.randf_range(0.3, 3.0), he.y * rng.randf_range(0.3, 3.0), he.z * rng.randf_range(0.3, 3.0))
		var c := Vector3(rng.randf_range(-1.0, 1.0) * he.x * 2.0, rng.randf_range(-1.0, 1.0) * he.y, rng.randf_range(-1.0, 1.0) * he.z * 2.0)
		f.torso.set_meta("armor_box", AABB(c - sz * 0.5, sz))
		# (Under the box, his outline: a plate is hidden when it is within both. Half the frames, the box alone.)
		f.torso.set_meta("armor_outline", real_outline if k % 2 == 1 else {})
		if k % 7 == 3:
			for n in ["upperArmL", "upperArmR"]:
				for ad in f.by_name[n].get_meta("armor", []):
					if ad.get("xf") != null:
						var on: PackedByteArray = ad.on
						on[rng.randi_range(0, on.size() - 1)] = 0
						ad["on"] = on
		var old := _clip_pass_old(f)
		var was := []
		for pr in old:
			was.append((pr[0].clip as PackedByteArray).duplicate())
		f._clip_arm_armor()
		frames += 1
		pieces = maxi(pieces, old.size())
		for i in old.size():
			var now: PackedByteArray = old[i][0].clip
			if now != old[i][1]:
				differ += 1
			for ci in now.size():
				if now[ci] != was[i][ci]:
					turned += 1
			hid_most = maxi(hid_most, now.count(1))
	t.check(pieces >= 1, "an armoured man's arm wears a piece (%d)" % pieces)
	t.eq(differ, 0, "after every frame, the plates hidden are the ones the old pass over every plate hid")
	t.check(turned > 100 and hid_most > 3, "plates went into the box and came out of it (%d turns, up to %d hidden)" % [turned, hid_most])
	# (And with no core to name them, the same.)
	Greedy.use_native = false
	for k in 20:
		await _steps(1)
		var old := _clip_pass_old(f)
		f._clip_arm_armor()
		for pr in old:
			if (pr[0].clip as PackedByteArray) != pr[1]:
				differ += 1
	Greedy.use_native = true
	t.eq(differ, 0, "and the same without the C++ core")
	# (What his arms are told to his shells, asked of him every frame: kept per arm, the cone the same as worked out from the look.)
	for n in ["upperArmL", "upperArmR"]:
		var up: VoxelPart = f.by_name[n]
		var c1 := f._limb_cone(up)
		var d := FineBody.part_data(String(up.fine.get("build", "")), String(up.part_name))
		var fresh := Fighter.limb_cone(d.cells, -Vector3(up.grid) * up.vf * up.part_scale * 0.5, up.vf * up.part_scale / float(Data.body_res)) if not d.is_empty() else {}
		t.check(not c1.is_empty() and c1 == fresh and is_same(c1, f._limb_cone(up)), "the cone of %s: as the look has it, and kept" % n)
	m.queue_free()
