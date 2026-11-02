extends Node
## Nothing in the arena is armoured by being drawn outside the voxels: every part of every
## creature loses voxels to a hard cut or a hard blow.

var t

func test_every_part_of_every_creature_can_be_hurt() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(12, 0, 12))
	var bad := []
	var n := 0
	for sp in Data.beasts.keys():
		var e = m.spawn_beast({"beast": sp, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": 0.0})
		var f = e.f
		for i in 5:
			await get_tree().physics_frame
		for part in f.parts:
			if part.severed:
				continue
			n += 1
			var before: int = part.alive_count
			var h: Vector3 = part.half_ext
			var pw: Vector3 = part.global_transform * Vector3(h.x, 0, 0)
			var dir: Vector3 = -(part.global_transform.basis * Vector3.RIGHT).normalized()
			f.apply_hit(part, {"impulse": 45.0, "type": "edge", "hardness": 0.8, "sharpness": 0.9, "point": pw, "dir": dir, "axis": part.global_transform.basis * Vector3.FORWARD, "edge": dir, "heavy": 0.5})
			var after_cut: int = part.alive_count
			if not part.severed:
				f.apply_hit(part, {"impulse": 45.0, "type": "blunt", "hardness": 0.8, "point": pw, "dir": dir, "heavy": 0.5})
			if after_cut >= before and part.alive_count >= after_cut:
				bad.append("%s.%s(S %.1f)" % [sp, part.part_name, float(f.S)])
		m.entities.erase(e); m.combat.fighters.erase(f); f.queue_free()
		await get_tree().physics_frame
	t.check(bad.is_empty(), "every one of %d parts of every creature loses voxels to a hard cut or blow (untouched: %s)" % [n, ", ".join(bad)])
	m.queue_free()

## Nothing stays on a body it is not joined to by voxels: the elbow end of the upper arm gone,
## the forearm (and the hand with it) falls; the flesh at the neck gone, the head falls. (The
## flesh that holds a child on is as wide round its joint as the child is across: VoxelPart.
## holds_child.)
func test_a_part_joined_to_nothing_falls() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	var f: Fighter = m.me.f
	for i in 30:
		await get_tree().physics_frame
	var up: VoxelPart = f.arm.R.upper
	var fore: VoxelPart = f.arm.R.fore
	var pt := up.anchor_point(fore)
	var near := []
	for i in up.fx.size():
		if up.alive[i] and up.local_of(i).distance_to(pt) < _joint_r(up, fore):
			near.append(i)
	t.check(not near.is_empty() and near.size() < up.alive_count, "the elbow end of the upper arm (%d of %d voxels)" % [near.size(), up.alive_count])
	up.remove_voxels(near)
	for i in 60:
		await get_tree().physics_frame
	t.check(fore.severed, "the forearm, joined to nothing, has fallen off")
	t.check(not up.severed, "the rest of the upper arm stays on")
	var tor := f.torso
	var neck := []
	var hp := tor.anchor_point(f.head)
	for i in tor.fx.size():
		if tor.alive[i] and tor.local_of(i).distance_to(hp) < _joint_r(tor, f.head):
			neck.append(i)
	tor.remove_voxels(neck)
	for i in 60:
		await get_tree().physics_frame
	t.check(f.head.severed, "the neck's flesh gone, the head falls")
	m.queue_free()

## The flesh round where `child` is jointed onto `par`, all of it: as wide as the child is
## across its root, a little over (2.4 voxels at least).
func _joint_r(par: VoxelPart, child: VoxelPart) -> float:
	return maxf(par.vf * par.part_scale * 2.4, 1.2 * minf(child.half_ext.x, child.half_ext.z))

## Where a limb is rooted in its parent, as a scan over all the parent's voxels finds it: the
## joint point kept in the box, moved onto the nearest flesh if it lies in the air.
func _scanned_anchor(par: VoxelPart, child: VoxelPart) -> Vector3:
	var p := child.pa
	var hx := par.half_ext / 0.95
	var pt := Vector3(clampf(p.x, -hx.x, hx.x), clampf(p.y, -hx.y, hx.y), clampf(p.z, -hx.z, hx.z))
	var best := INF
	var near := pt
	for i in par.fx.size():
		var d := par.local_of(i).distance_squared_to(pt)
		if d < best:
			best = d
			near = par.local_of(i)
	if sqrt(best) > par.vf * par.part_scale * 2.2:
		pt = near
	return pt

## The roots of the limbs (anchor_point) are looked for out from the joint, not over the whole
## parent: at the first wound to a dragon's trunk the scan, once for each limb rooted in it, was
## a fiftieth of a second's hitch. The same points as the scan, for every limb of every creature,
## a man and the giants, in a fraction of the time.
func test_limb_roots_are_where_a_full_scan_puts_them() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(12, 0, 12))
	var kinds: Array = ["man"]
	for e in ["giant", "cyclops", "minotaur", "titan", "troll"]:
		if not Data.enemy_type(e).is_empty():
			kinds.append(e)
	kinds.append_array(Data.beasts.keys())
	var bad := []
	var n := 0
	var moved := 0
	var t_scan := 0
	var t_new := 0
	for k in kinds:
		var e = null
		var f: Fighter = m.me.f
		if k != "man":
			if Data.beasts.has(k):
				e = m.spawn_beast({"beast": k, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": 0.0})
			else:
				var spec: Dictionary = m.enemy_spec({"e": k}, 0, 1)
				spec.pos = Vector3(0, 0.1, 0)
				e = m.spawn_fighter(spec)
			f = e.f
		for par in f.parts:
			for ch in par.child_parts:
				var t0 := Time.get_ticks_usec()
				var want := _scanned_anchor(par, ch)
				var t1 := Time.get_ticks_usec()
				par._anchors.erase(ch)
				var got: Vector3 = par.anchor_point(ch)
				t_new += Time.get_ticks_usec() - t1
				t_scan += t1 - t0
				n += 1
				var p: Vector3 = ch.pa
				var hx: Vector3 = par.half_ext / 0.95
				if not want.is_equal_approx(Vector3(clampf(p.x, -hx.x, hx.x), clampf(p.y, -hx.y, hx.y), clampf(p.z, -hx.z, hx.z))):
					moved += 1
				if got != want:
					bad.append("%s %s>%s %s vs %s" % [k, par.part_name, ch.part_name, str(got), str(want)])
		if e:
			m.entities.erase(e); m.combat.fighters.erase(f); f.queue_free()
			await get_tree().physics_frame
	t.check(bad.is_empty(), "every one of %d limb roots (%d moved onto the flesh) where the scan puts it (%s)" % [n, moved, "; ".join(bad.slice(0, 4))])
	t.check(moved > 0, "some roots lie in the air and are moved onto the flesh (%d)" % moved)
	t.check(t_new * 3 < t_scan, "found in a third of the scan's time or less (%.1f ms against %.1f)" % [t_new / 1000.0, t_scan / 1000.0])
	m.queue_free()

## The collision boxes a holed part should have, [size, position] each in order, worked out as
## fit_collider did when it went over every cell of the box and made every shape anew.
func _boxes_wanted(p: VoxelPart) -> Array:
	var w := p.dims.x; var h := p.dims.y; var d := p.dims.z
	var n := w * h * d
	var total := p.total_coarse
	var live := p.live_coarse
	var solid := PackedByteArray(); solid.resize(n)
	var holes := 0
	var any := 0
	for c in n:
		solid[c] = 1 if (total[c] > 0 and live[c] * 4 >= total[c]) else 0
		if total[c] > 0 and solid[c] == 0:
			holes += 1
		any += solid[c]
	if holes == 0:
		return []
	if any == 0:
		for c in n:
			solid[c] = 1 if live[c] > 0 else 0
	var fleshy := solid.duplicate()
	var on := func(x: int, y: int, z: int) -> bool: return x >= 0 and y >= 0 and z >= 0 and x < w and y < h and z < d and fleshy[x + w * (y + h * z)] != 0
	for z in d:
		for y in h:
			for x in w:
				var c := x + w * (y + h * z)
				if total[c] > 0:
					continue
				solid[c] = 1 if (on.call(x - 1, y, z) or on.call(x + 1, y, z) or on.call(x, y - 1, z) or on.call(x, y + 1, z) or on.call(x, y, z - 1) or on.call(x, y, z + 1)) else 0
	var k := p.half_ext * 2.0 / Vector3(w, h, d)
	var out := []
	for b in Greedy.boxes(w, h, d, solid):
		out.append([Vector3(b[3] - b[0] + 1, b[4] - b[1] + 1, b[5] - b[2] + 1) * k, Vector3((b[0] + b[3] + 1) * 0.5 - w * 0.5, (b[1] + b[4] + 1) * 0.5 - h * 0.5, (b[2] + b[5] + 1) * 0.5 - d * 0.5) * k])
	return out

## A holed part's collision boxes are refitted after every cut by moving and resizing the shapes
## it has (a hundred made and freed at each cut on a gorilla's trunk was a hitch): cut after cut
## on a gorilla's trunk and a man's, the boxes are the very ones worked out from scratch, none
## left over, and the whole box back once the part has no hole.
func test_collision_boxes_follow_the_flesh_cut_after_cut() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(12, 0, 12))
	var e = m.spawn_beast({"beast": "gorilla", "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": 0.0, "harmless": true})
	for i in 5:
		await get_tree().physics_frame
	var bad := []
	var counts := []
	for f in [e.f, m.me.f]:
		var part: VoxelPart = f.torso
		var dirs := [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0.7, 0, 0.7), Vector3(-0.7, 0, 0.7)]
		for k in dirs.size():
			var dir: Vector3 = part.global_transform.basis * dirs[k]
			var pt: Vector3 = part.global_position - dir * part.half_ext.length() * 0.6 + Vector3(0, (k - 2.5) * 0.1 * f.S, 0)
			f.apply_hit(part, {"impulse": 45.0, "type": "edge", "hardness": 0.8, "sharpness": 0.9, "point": pt, "dir": dir, "axis": Vector3.UP, "edge": dir.cross(Vector3.UP).normalized(), "heavy": 0.4, "weapon": true, "mass": 1.5})
			if part.severed:
				break
			var want := _boxes_wanted(part)
			var got := []
			for cs in part.boxes:
				got.append([(cs.shape as BoxShape3D).size, cs.position, cs.get_parent() == part])
			counts.append(got.size())
			var same := got.size() == want.size() and part.split == not want.is_empty()
			for i in mini(got.size(), want.size()):
				same = same and got[i][0].is_equal_approx(want[i][0]) and got[i][1].is_equal_approx(want[i][1]) and got[i][2]
			if not same:
				bad.append("%s cut %d: %d boxes, %d wanted" % ["gorilla" if f == e.f else "man", k + 1, got.size(), want.size()])
		var all: Array = []
		for i in part.fx.size():
			if not part.alive[i]:
				all.append(i)
		part.restore_voxels(all)
		if part.split or not part.boxes.is_empty():
			bad.append("whole again, %d boxes left" % part.boxes.size())
	t.check(bad.is_empty(), "the boxes after each cut are those worked out from scratch (%s): %s" % [str(counts), "; ".join(bad)])
	t.check(counts.size() >= 6 and counts.any(func(c): return c > 10), "the cuts holed the trunks (boxes %s)" % str(counts))
	m.queue_free()

## A man's sword takes a giant apart as it takes a man, only slower: a thigh too broad for the
## blade is chopped through blow by blow, and once the slot is through the blade widens it
## until the leg is off (it used to hang by its sides for good); the same at the neck of a
## giant's head or a beast's. The blows land on one spot, as a player's aimed at a wound do.
func _root_spot(part: VoxelPart) -> Array:
	var vfs: float = part.vf * part.part_scale
	var ra: Array = part._root_axis()
	var ax: int = ra[0]
	var cx: int = 0 if ax != 0 else 2
	var la_ax: int = 3 - ax - cx
	var root: float = maxf(0.0, part.half_ext[ax] - 1.6 * vfs) * (1.0 if ra[1] else -1.0)
	var best := Vector3.ZERO
	var best_d := -INF
	for i in part.fx.size():
		if not part.alive[i]:
			continue
		var v: Vector3 = part.local_of(i)
		if absf(v[ax] - root) > vfs * 0.6 or absf(v[la_ax]) > vfs * 1.2:
			continue
		if v[cx] > best_d:
			best_d = v[cx]
			best = v
	var lp := best
	lp[cx] += vfs * 0.5 + 0.01
	var ld := Vector3.ZERO
	ld[cx] = -1.0
	var la := Vector3.ZERO
	la[la_ax] = 1.0
	return [lp, ld, la]

func _sword_at(c, part: VoxelPart, spot: Array) -> Dictionary:
	var b: Basis = part.global_transform.basis.orthonormalized()
	return c.apply_hit(part, {"impulse": 60.0, "type": "edge", "hardness": 0.9, "sharpness": 1.0, "heavy": 1.0, "wsz": 1.0, "point": part.to_global(spot[0]), "dir": b * spot[1], "axis": b * spot[2], "edge": b * spot[1]})

func _blows_to_sever(c, part: VoxelPart, cap: int) -> int:
	var spot := _root_spot(part)
	for n in cap:
		if part.severed:
			return n
		_sword_at(c, part, spot)
		c.blood = 100.0
		c.alive = true
	return cap if part.severed else -1

func test_a_mans_sword_takes_a_giants_limbs_and_head_off_blow_by_blow() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	m.me.f.teleport(Vector3(12, 0, 12))
	var spec: Dictionary = m.enemy_spec({"e": "giant"}, 0, 1)
	spec.pos = Vector3(0, 0.1, 0)
	var g = m.spawn_fighter(spec).f
	for i in 30:
		await get_tree().physics_frame
	t.check(g.S >= 3.5, "the giant is a giant (S %.1f)" % g.S)
	for pn in ["forearmR", "upperArmR", "shinR", "thighR", "head"]:
		var n := _blows_to_sever(g, g.by_name[pn], 20)
		t.check(n >= 1 and n <= 14, "a man's sword takes the giant's %s off in %s blows at one spot (at most 14)" % [pn, str(n) if n >= 0 else "more than 20"])
	m.entities.erase(m.entities.back()); m.combat.fighters.erase(g); g.queue_free()
	await get_tree().physics_frame
	for sp in ["lion", "gorilla", "elephant"]:
		var e = m.spawn_beast({"beast": sp, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": 0.0})
		var f = e.f
		for i in 30:
			await get_tree().physics_frame
		for part in [f.by_name["legFR"], f.head]:
			var n := _blows_to_sever(f, part, 30)
			t.check(n >= 1 and n <= 24, "a man's sword takes the %s's %s off in %s blows at one spot (at most 24)" % [sp, part.part_name, str(n) if n >= 0 else "more than 30"])
		m.entities.erase(e); m.combat.fighters.erase(f); f.queue_free()
		await get_tree().physics_frame
	m.queue_free()
