extends Node
## A cut is the size of the blade that made it (user: a wound was a hand's breadth across whatever
## opened it, and one hard cut down an arm took a third of the arm): as wide as the blade is thick
## where it landed, as long as its own keen run reaches from there, and as deep as the blow drove
## it, as ever. An open cut still draws the next blow near it in, so a limb is chopped off by blows
## about one place; a bone the blade went through is broken; a limb it went most of the way through
## hangs. A paw's claws, which are no blade, open what they did.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(12, 0.02, 12))
	return m

var _men := 0
## A bare man standing still.
func _man(m: Match) -> Fighter:
	_men += 1
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(-9.0 + (_men % 7) * 3.0, 0.1, -6.0 + int(_men / 7) * 3.0), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {}
	return e.f

func _weapon(d: Dictionary, scale := 1.0) -> Weapon:
	var w := Weapon.new()
	add_child(w)
	w.setup(d.duplicate(true), scale)
	return w

## The rows of a weapon that carry an edge, low to high.
func _edge_rows(w: Weapon) -> Array:
	var rows := []
	for i in w.vox.size():
		if w.alive[i] and w.vox[i][4] == "edge" and not rows.has(int(w.vox[i][1])):
			rows.append(int(w.vox[i][1]))
	rows.sort()
	return rows

## A weapon's blade measured at an edge voxel of `row`, touched at that voxel's middle.
func _at_row(w: Weapon, row: int) -> Vector3:
	for i in w.vox.size():
		if w.alive[i] and w.vox[i][4] == "edge" and int(w.vox[i][1]) == row:
			return w.blade_at(i, w.global_transform * (Vector3(w.vox[i][0], w.vox[i][1], w.vox[i][2]) * w.vs))
	return Vector3.ZERO

## The measure of a preset's blade, touched `share` of the way up its edge.
func _blade(key: String, share := 0.5, scale := 1.0) -> Vector3:
	var w := _weapon(Data.preset(key), scale)
	var rows := _edge_rows(w)
	var b := _at_row(w, rows[clampi(int(round(share * (rows.size() - 1))), 0, rows.size() - 1)])
	w.queue_free()
	return b

## The middle of a voxel row of `part` on its `face` (a unit vector of its own frame), a little
## `up` its length from there (metres): where a blade is laid across it.
func _spot(part: VoxelPart, face: Vector3, up := 0.0) -> Vector3:
	var best := -1
	var bd := INF
	for i in part.fx.size():
		var d: float = absf(part.local_of(i).y)
		if d < bd:
			bd = d
			best = i
	return part.global_transform * (face * part.half_ext + Vector3(0, part.local_of(best).y + up, 0))

## One cut of `J` across `part`, come in at `face` (a unit vector of its own frame) with the blade
## lying along `axis` (its own frame too): what it took, as {n, rows (along the part), lo and hi
## (how far along the blade from the place it touched), deep, dmg, res}.
func _cut(f: Fighter, part: VoxelPart, face: Vector3, axis: Vector3, J: float, blade: Vector3, up := 0.0) -> Dictionary:
	var b := part.global_transform.basis.orthonormalized()
	var at := _spot(part, face, up)
	var was := part.alive.duplicate()
	var hit := {"impulse": J, "type": "edge", "hardness": 0.9, "sharpness": 0.7, "point": at, "dir": b * -face, "axis": b * axis, "edge": b * -face, "heavy": clampf((J - 15.0) / 50.0, 0.0, 1.0), "wsz": 1.0, "weapon": true, "mass": 1.6}
	if blade != Vector3.ZERO:
		hit["blade"] = blade
	part.hp = 1000.0
	var res: Dictionary = f.apply_hit(part, hit)
	var lp: Vector3 = part.global_transform.affine_inverse() * at
	var rows := {}
	var lo := INF
	var hi := -INF
	var deep := 0.0
	var n := 0
	for i in was.size():
		if was[i] == 1 and part.alive[i] == 0:
			n += 1
			rows[part.fy[i]] = true
			var d: Vector3 = part.local_of(i) - lp
			lo = minf(lo, d.dot(axis))
			hi = maxf(hi, d.dot(axis))
			deep = maxf(deep, d.dot(-face))
	return {"n": n, "rows": rows.keys(), "lo": lo, "hi": hi, "deep": deep, "dmg": float(res.get("dmg", 0.0)), "res": res}

func test_a_blade_is_measured_where_it_touched() -> void:
	var v: float = Data.weapon_voxel
	var g := _weapon(Data.preset("gladius"))
	var rows := _edge_rows(g)
	var mid := _at_row(g, rows[int(rows.size() / 2)])
	t.check(absf(mid.x - v) < 1e-4, "a gladius is one voxel thick across its flat (%.1f cm)" % (mid.x * 100.0))
	t.check(absf(mid.y + mid.z - rows.size() * v) < 1e-4, "its keen run is its edge, end to end (%.0f cm of %d rows)" % [(mid.y + mid.z) * 100.0, rows.size()])
	t.check(absf(mid.y - mid.z) < v * 1.01, "touched at its middle, it reaches as far back as on (%.0f and %.0f cm)" % [mid.y * 100.0, mid.z * 100.0])
	var top := _at_row(g, rows[-1])
	t.check(absf(top.z - 0.5 * v) < 1e-4 and absf(top.y - (rows.size() - 0.5) * v) < 1e-4, "touched with the end of its edge, the run is all behind it (%.0f cm back, %.0f on)" % [top.y * 100.0, top.z * 100.0])
	# A blow further up than the edge goes is the end of the edge's, no further.
	var tip_i := -1
	for i in g.vox.size():
		if g.vox[i][4] == "edge" and int(g.vox[i][1]) == int(rows[-1]):
			tip_i = i
			break
	var past := g.blade_at(tip_i, g.global_transform * (Vector3(g.vox[tip_i][0], float(rows[-1]) + 3.0, 0) * g.vs))
	t.check(absf(past.z) < 1e-4 and absf(past.y - rows.size() * v) < 1e-4, "and a touch told from beyond it is its end's (%.1f cm on)" % (past.z * 100.0))
	# The run stops where the edge is broken: the voxels of one row gone, a blow above them reaches down to them only.
	var gone := []
	var cut_row: int = rows[4]
	for i in g.vox.size():
		if int(g.vox[i][1]) == cut_row and g.vox[i][4] == "edge":
			gone.append(i)
	g.remove_voxels(gone)
	var above := _at_row(g, rows[8])
	t.check(absf(above.y - 3.5 * v) < 1e-4, "an edge with a gap in it cuts as far as the gap (%.0f cm back, the gap %d rows down)" % [above.y * 100.0, 4])
	t.check(g.blade_at(gone[0], g.global_position) == Vector3.ZERO, "and a voxel that is gone measures nothing")
	g.queue_free()
	var runs := {}
	for key in ["dagger", "gladius", "longsword", "axe", "spear"]:
		var b := _blade(key)
		runs[key] = b.y + b.z
		t.check(absf(b.x - v) < 1e-4, "%s: one voxel thick where it cuts" % key)
	t.check(runs.dagger < runs.gladius and runs.gladius < runs.longsword, "a longer blade has the longer run: a dagger %.0f cm, a gladius %.0f, a longsword %.0f" % [runs.dagger * 100.0, runs.gladius * 100.0, runs.longsword * 100.0])
	t.check(runs.spear < runs.gladius and runs.spear > 2.0 * v, "a spear cuts with its head only (%.0f cm), an axe with its bit (%.0f cm)" % [runs.spear * 100.0, runs.axe * 100.0])
	var big := _blade("gladius", 0.5, 2.0)
	t.check(absf(big.x - 2.0 * v) < 1e-4 and absf(big.y + big.z - 2.0 * runs.gladius) < 1e-4, "a blade made twice the size is twice as thick and twice as long (%.0f cm, %.0f cm)" % [big.x * 100.0, (big.y + big.z) * 100.0])
	# A blade built two voxels thick.
	var d := {"name": "Slab", "kind": "weapon", "sharpness": 0.8, "voxels": []}
	for y in 4:
		d.voxels.append([0, y, 0, "wood", "grip"])
	for y in range(4, 14):
		for z in 2:
			d.voxels.append([0, y, z, "steel", "edge"])
	var slab := _weapon(d)
	var sb := _at_row(slab, 9)
	t.check(absf(sb.x - 2.0 * v) < 1e-4, "a blade built two voxels thick measures two (%.0f cm)" % (sb.x * 100.0))
	slab.queue_free()

func test_a_cut_is_as_thin_as_the_blade() -> void:
	var m := _match()
	var a := _man(m)
	var b := _man(m)
	await _steps(40)
	var blade := _blade("gladius")
	var vf: float = a.by_name.upperArmL.vf * a.by_name.upperArmL.part_scale
	for J in [30.0, 65.0]:
		var pa: VoxelPart = a.by_name.upperArmL if J < 40.0 else a.by_name.thighL
		var pb: VoxelPart = b.by_name.upperArmL if J < 40.0 else b.by_name.thighL
		var face := Vector3(1, 0, 0) if J < 40.0 else Vector3(0, 0, 1)
		var axis := Vector3(0, 0, 1) if J < 40.0 else Vector3(1, 0, 0)
		var paw: Dictionary = _cut(a, pa, face, axis, J, Vector3.ZERO)
		var cut: Dictionary = _cut(b, pb, face, axis, J, blade)
		t.check(cut.n > 0 and cut.rows.size() == 1, "a blade laid on a row of %s takes that row and no other (%d rows, %d voxels, at a blow of %.0f)" % [pb.part_name, cut.rows.size(), cut.n, J])
		t.check(paw.rows.size() >= 3 and cut.n * 2 < paw.n, "where a paw's breadth of claws takes several (%d rows, %d voxels)" % [paw.rows.size(), paw.n])
		t.check(absf(cut.deep - paw.deep) < vf * 1.01, "as deep as the blow drives it, the same (%.1f and %.1f cm)" % [cut.deep * 100.0, paw.deep * 100.0])
		t.check(absf(cut.dmg - paw.dmg) < 0.01, "and the harm is the blow's, the same (%.1f and %.1f)" % [cut.dmg, paw.dmg])
	# A thicker blade opens a wider cut.
	var thick: Dictionary = _cut(a, a.by_name.thighR, Vector3(0, 0, 1), Vector3(1, 0, 0), 45.0, Vector3(blade.x * 2.0, blade.y, blade.z))
	var thin: Dictionary = _cut(b, b.by_name.thighR, Vector3(0, 0, 1), Vector3(1, 0, 0), 45.0, blade)
	t.check(thin.rows.size() == 1 and thick.rows.size() == 3, "a blade twice as thick opens a cut as much wider (%d rows to %d)" % [thin.rows.size(), thick.rows.size()])
	# On a giant's voxels, bigger than the blade is thick: a row of them, never nothing.
	var giant = m.spawn_fighter(m.enemy_spec({"e": "cyclops"}, 0, 1).merged({"pos": Vector3(6, 0.1, -9), "yaw": 0.0}, true))
	giant.erase("bot")
	giant.drive = func(_e): return {}
	await _steps(10)
	var gt: VoxelPart = giant.f.by_name.thighL
	var gc: Dictionary = _cut(giant.f, gt, Vector3(0, 0, 1), Vector3(1, 0, 0), 45.0, blade)
	t.check(gc.n > 0 and gc.rows.size() <= 2, "a giant's bigger voxels: a row of them (%d rows, %d voxels of %.1f cm)" % [gc.rows.size(), gc.n, gt.vf * gt.part_scale * 100.0])
	m.queue_free()

func test_a_cut_is_as_long_as_the_blade() -> void:
	var m := _match()
	var a := _man(m)
	var b := _man(m)
	var c := _man(m)
	var d := _man(m)
	await _steps(40)
	var vf: float = a.torso.vf * a.torso.part_scale
	var knife := _blade("dagger", 0.5, 0.6)
	var dagger := _blade("dagger")
	var long := _blade("longsword")
	# Across the chest from the front, the blade level.
	var least: Dictionary = _cut(a, a.torso, Vector3(0, 0, 1), Vector3(1, 0, 0), 45.0, knife)
	var small: Dictionary = _cut(b, b.torso, Vector3(0, 0, 1), Vector3(1, 0, 0), 45.0, dagger)
	var wide: Dictionary = _cut(c, c.torso, Vector3(0, 0, 1), Vector3(1, 0, 0), 45.0, long)
	t.check(least.n > 0 and least.hi - least.lo <= knife.y + knife.z, "a small knife's cut across the chest is no longer than the knife's edge (%.0f cm of %.0f)" % [(least.hi - least.lo + vf) * 100.0, (knife.y + knife.z) * 100.0])
	t.check(small.hi - small.lo <= dagger.y + dagger.z and small.hi - small.lo > least.hi - least.lo + 2.0 * vf, "a dagger's is longer, and no longer than the dagger's (%.0f cm of %.0f)" % [(small.hi - small.lo + vf) * 100.0, (dagger.y + dagger.z) * 100.0])
	t.check(wide.hi - wide.lo > small.hi - small.lo + vf and wide.hi - wide.lo > 2.0 * c.torso.half_ext.x - 3.0 * vf, "a longsword's runs right across it (%.0f cm of the chest's %.0f)" % [(wide.hi - wide.lo + vf) * 100.0, c.torso.half_ext.x * 200.0])
	# Touched with the end of the edge: what is cut lies back along the blade, none of it beyond the end.
	var tip := _blade("gladius", 1.0)
	var end: Dictionary = _cut(d, d.torso, Vector3(0, 0, 1), Vector3(1, 0, 0), 45.0, tip)
	t.check(end.n > 0 and end.hi < tip.z + 1e-4 and end.lo < -3.0 * vf, "a cut made with the end of the edge runs back along the blade and stops at its end (%.0f cm back, %.1f on)" % [-end.lo * 100.0, end.hi * 100.0])
	m.queue_free()

## The blows a limb is chopped off by land about one place, not on one line: an open cut within a
## hand's breadth draws the blade in, down its middle, so the cut stays as thin as the blade and
## goes deeper blow by blow.
func test_a_limb_is_chopped_off_by_blows_about_one_place() -> void:
	var m := _match()
	var a := _man(m)
	var b := _man(m)
	await _steps(40)
	var blade := _blade("gladius")
	var one: VoxelPart = a.by_name.upperArmL
	var k0 := 0
	while not one.severed and k0 < 12:
		_cut(a, one, Vector3(1, 0, 0), Vector3(0, 0, 1), 45.0, blade)
		k0 += 1
		await _steps(4)
	t.check(one.severed and k0 >= 2, "blows on one line take an arm off, and not at the first (%d blows)" % k0)
	var arm: VoxelPart = b.by_name.upperArmL
	var rows := {}
	var k := 0
	var broke := -1
	var hung := -1
	for up in [0.0, 0.04, -0.04, 0.02, -0.03, 0.035, -0.02, 0.01, -0.01, 0.03, -0.035, 0.0]:
		var c: Dictionary = _cut(b, arm, Vector3(1, 0, 0), Vector3(0, 0, 1), 45.0, blade, up)
		k += 1
		if broke < 0 and arm.fracture >= 2:
			broke = k
		if hung < 0 and arm.hanging:
			hung = k
		if arm.severed:
			break
		for r in c.rows:
			rows[r] = true
		await _steps(4)
	t.check(arm.severed and k <= k0 + 2, "blows up to 4 cm apart take it off as soon, or nearly (%d blows)" % k)
	t.check(rows.size() <= 2, "all of them into the one cut, as thin as the blade to the last (%d rows of the arm's %d)" % [rows.size(), arm.grid.y])
	t.check(broke > 0 and broke < k, "its bone broken when the blade was through it, before the arm came off (blow %d of %d)" % [broke, k])
	# A blow well away from the cut opens a cut of its own.
	var th: VoxelPart = b.by_name.thighL
	var first: Dictionary = _cut(b, th, Vector3(0, 0, 1), Vector3(1, 0, 0), 30.0, blade)
	var far: Dictionary = _cut(b, th, Vector3(0, 0, 1), Vector3(1, 0, 0), 30.0, blade, 0.14)
	t.check(not first.rows.is_empty() and not far.rows.is_empty() and absi(int(far.rows[0]) - int(first.rows[0])) >= 4, "a blow a foot's breadth off opens its own (rows %s and %s)" % [str(first.rows), str(far.rows)])
	m.queue_free()

## A blade's thin cut across a limb is through its bone when it has taken most of the bone's width
## there, however small a share of the whole bone that is; a nick, or a graze of its edge by a light
## blow, is no break; a cut along the limb, or a paw's, counts the share of the whole bone.
func test_a_blade_through_a_bone_breaks_it() -> void:
	var m := _match()
	var a := _man(m)
	await _steps(40)
	var fo: VoxelPart = a.by_name.forearmL
	var axis_i: int = fo._root_axis()[0]
	var along := Vector3.ZERO
	along[axis_i] = 1.0   # (the normal of a plane across the limb)
	var layer_of := func(p: VoxelPart, i: int) -> int:
		return p.fx[i] if axis_i == 0 else (p.fy[i] if axis_i == 1 else p.fz[i])
	var bones := []
	for i in fo.fx.size():
		if fo.alive[i] and fo.bone[i]:
			bones.append(i)
	var mid_layer: int = layer_of.call(fo, bones[int(bones.size() / 2)])
	var row := bones.filter(func(i): return layer_of.call(fo, i) == mid_layer)
	var width_b := fo.bone_across(along)
	t.check(row.size() >= 3 and row.size() * 5 < bones.size(), "a layer of the forearm's bone is a small share of it (%d of %d)" % [row.size(), bones.size()])
	t.check(width_b >= 2.0 and width_b <= row.size() + 2.0, "and its width across is what a layer holds (%.1f voxels)" % width_b)
	t.check(fo.bone_across(Vector3(1, 0, 0) if axis_i != 0 else Vector3(0, 1, 0)) == 0.0, "a plane along the limb takes none of it across")
	a._edge_on_bone(fo, row.slice(0, 1), Vector3.ZERO, Vector3(0, 0, -1), 10.0, {}, along)
	t.check(fo.fracture == 0, "a nick, or a graze of its edge by a light blow, leaves the bone whole")
	a._edge_on_bone(fo, row.slice(0, int(ceil(row.size() * 0.5))), Vector3.ZERO, Vector3(0, 0, -1), 30.0, {}, along)
	t.check(fo.fracture == 1, "a notch half through it cracks it (level %d)" % fo.fracture)
	var sh: VoxelPart = a.by_name.shinL
	var sb := []
	for i in sh.fx.size():
		if sh.alive[i] and sh.bone[i]:
			sb.append(i)
	var s_axis: int = sh._root_axis()[0]
	var s_along := Vector3.ZERO
	s_along[s_axis] = 1.0
	var s_layer := func(i: int) -> int:
		return sh.fx[i] if s_axis == 0 else (sh.fy[i] if s_axis == 1 else sh.fz[i])
	var s_mid: int = s_layer.call(sb[int(sb.size() / 2)])
	var srow := sb.filter(func(i): return s_layer.call(i) == s_mid)
	a._edge_on_bone(sh, srow, Vector3.ZERO, Vector3(0, 0, -1), 30.0, {}, s_along)
	t.check(sh.fracture == 2 and sh.fractured, "a blade clean across the shin's bone breaks it, though it took %d of its %d voxels" % [srow.size(), sb.size()])
	# Along the limb the same voxels are a notch (as they are for a cut told nothing of a blade).
	var th: VoxelPart = a.by_name.shinR
	var tb := []
	for i in th.fx.size():
		if th.alive[i] and th.bone[i]:
			tb.append(i)
	var t_axis: int = th._root_axis()[0]
	var t_layer := func(i: int) -> int:
		return th.fx[i] if t_axis == 0 else (th.fy[i] if t_axis == 1 else th.fz[i])
	var t_mid: int = t_layer.call(tb[int(tb.size() / 2)])
	var trow := tb.filter(func(i): return t_layer.call(i) == t_mid)
	var lengthwise := Vector3(1, 0, 0) if t_axis != 0 else Vector3(0, 1, 0)
	a._edge_on_bone(th, trow, Vector3.ZERO, Vector3(0, 0, -1), 30.0, {}, lengthwise)
	t.check(th.fracture == 1, "(cut along the limb, the same voxels are a notch: level %d)" % th.fracture)
	var ph: VoxelPart = a.by_name.thighR
	var pb := []
	for i in ph.fx.size():
		if ph.alive[i] and ph.bone[i]:
			pb.append(i)
	var p_axis: int = ph._root_axis()[0]
	var p_layer := func(i: int) -> int:
		return ph.fx[i] if p_axis == 0 else (ph.fy[i] if p_axis == 1 else ph.fz[i])
	var p_mid: int = p_layer.call(pb[int(pb.size() / 2)])
	var prow := pb.filter(func(i): return p_layer.call(i) == p_mid)
	a._edge_on_bone(ph, prow, Vector3.ZERO, Vector3(0, 0, -1), 30.0, {})
	t.check(ph.fracture == 1, "(told nothing of a blade, they are a notch too: level %d)" % ph.fracture)
	m.queue_free()

## A limb a blade has gone most of the way through hangs, at whatever slant the cut runs: counted by
## the layers of its voxels alone, a slanting cut as thin as its blade thinned none of them enough.
func test_a_limb_cut_most_of_the_way_through_at_a_slant_hangs() -> void:
	var m := _match()
	var a := _man(m)
	await _steps(40)
	var blade := _blade("gladius")
	var th: VoxelPart = a.by_name.thighL
	var slant := Vector3(cos(deg_to_rad(35.0)), sin(deg_to_rad(35.0)), 0.0)
	var k := 0
	var layers := 1.0
	while not th.hanging and not th.severed and k < 12:
		_cut(a, th, Vector3(0, 0, 1), slant, 45.0, blade)
		k += 1
		if th.hanging:
			layers = th.thin_ratio()
		await _steps(4)
	t.check(th.hanging and not th.severed, "a thigh cut most of the way through at a slant hangs (after %d blows)" % k)
	t.check(layers >= float(a.mods.get("sever", 0.3)), "though no layer of its voxels is that thin (the thinnest %.2f)" % layers)
	# Along the limb, or out through its end, a plane is no section of it.
	var up: VoxelPart = a.by_name.upperArmR
	t.check(up.left_across(Vector3.ZERO, Vector3(1, 0, 0), 0.02, []) == 1.0, "a plane along a limb is no cut across it")
	t.check(up.left_across(Vector3(0, up.half_ext.y, 0), Vector3(0, 1, 0), 0.02, []) == 1.0, "nor one out through its end")
	t.check(up.left_across(Vector3.ZERO, Vector3(0, 1, 0), 0.02, []) == 1.0 and up.left_across(Vector3.ZERO, Vector3(0, 1, 0), 0.02, Array(up.voxels_within(Vector3.ZERO, 1.0))) == 0.0, "a whole limb is whole across, one with nothing left across is cut through")
	m.queue_free()

## The blow the combat makes of a weapon's touch carries its blade: a gladius come edge first into a
## bare arm opens a cut one row wide.
func test_a_weapons_blow_cuts_as_thin_as_its_blade() -> void:
	var m := _match()
	var a := _man(m)
	await _steps(40)
	var arm: VoxelPart = a.by_name.upperArmL
	var w := Weapon.new()
	w.setup(Data.preset("gladius").duplicate(true))
	m.add_child(w)
	var rows := _edge_rows(w)
	var touch := -1
	for i in w.vox.size():
		if w.vox[i][4] == "edge" and int(w.vox[i][1]) == int(rows[int(rows.size() / 2)]) and int(w.vox[i][0]) > 0:
			touch = i
			break
	# Its blade lying front to back along the arm's outer side, its edge towards the arm, flying into it.
	var b := arm.global_transform.basis.orthonormalized()
	var at := _spot(arm, Vector3(1, 0, 0))
	var wb := Basis(b * Vector3(-1, 0, 0), b * Vector3(0, 0, 1), b * Vector3(0, 1, 0))
	var v: Array = w.vox[touch]
	w.global_transform = Transform3D(wb, at - wb * (Vector3(v[0], v[1], v[2]) * w.vs))
	w.thrown_t = 1.0
	w.thrower = m.me.f
	var was := arm.alive.duplicate()
	m.combat.vel[w.get_instance_id()] = [b * Vector3(-12, 0, 0), Vector3.ZERO]
	m.combat.vel[arm.get_instance_id()] = [Vector3.ZERO, Vector3.ZERO]
	var h: Dictionary = m.combat._blow({"att": w, "vic": arm, "J": 0.0, "rank": int(Combat.TYPE_RANK.get("edge", 0)), "type": "edge", "mat": str(v[3]), "box": w.box_of[touch], "p": at})
	var got := {}
	var n := 0
	for i in was.size():
		if was[i] == 1 and arm.alive[i] == 0:
			got[arm.fy[i]] = true
			n += 1
	t.check(not h.is_empty() and str(h.get("type", "")) == "edge" and n > 0, "a gladius flying edge first into a bare arm cuts it (%d voxels)" % n)
	t.check(got.size() == 1, "one row of the arm wide, as thin as the blade (%d rows)" % got.size())
	m.queue_free()
