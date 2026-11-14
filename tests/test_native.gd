extends Node
## The C++ voxel core (native/, class VoxelCore) gives the same boxes and lumps as the GDScript
## it stands in for. Skipped (a single passing check) when the extension is not built.

var t

func _norm(lumps: Array) -> String:
	var out := []
	for l in lumps:
		var a := Array(l)
		a.sort()
		out.append(str(a))
	out.sort()
	return str(out)

func test_native_core_matches_the_gdscript() -> void:
	if Greedy.core() == null:
		t.check(true, "no native core built: the GDScript fallback runs")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 20:
		var w := rng.randi_range(1, 9); var h := rng.randi_range(1, 12); var d := rng.randi_range(1, 7)
		var solid := PackedByteArray(); solid.resize(w * h * d)
		for i in solid.size():
			solid[i] = 1 if rng.randf() < 0.6 else 0
		t.eq(str(Greedy.core().greedy_boxes(w, h, d, solid)), str(Greedy.boxes_gd(w, h, d, solid)), "same boxes %dx%dx%d" % [w, h, d])
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 3, "decrees": [], "hazards": []})
	var f: Fighter = m.me.f
	for p in f.parts:
		for i in p.alive.size():
			if rng.randf() < 0.35:
				p.alive[i] = 0
		Greedy.use_native = false
		var gd := _norm(p.loose_lumps())
		Greedy.use_native = true
		t.eq(_norm(p.loose_lumps()), gd, "same lumps on " + p.name)
	m.queue_free()

## The voxel searches (VoxelPart.voxels_within, update_blood's skin search) pick the very same
## voxels in C++ as in GDScript, down to a radius exactly on a voxel's distance.
func test_native_searches_match_the_gdscript() -> void:
	if Greedy.core() == null:
		t.check(true, "no native core built: the GDScript fallback runs")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 4, "decrees": [], "hazards": []})
	var f: Fighter = m.me.f
	var same := true
	var skin_same := true
	var found := 0
	for p: VoxelPart in f.parts:
		for i in p.alive.size():
			if rng.randf() < 0.3:
				p.alive[i] = 0
		for scale in [1.0, 1.37, 2.6]:
			p.part_scale = scale
			for k in 12:
				var at := p.local_of(rng.randi() % p.fx.size()) + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.03
				var r: float = p.local_of(rng.randi() % p.fx.size()).distance_to(at) if k % 3 == 0 else rng.randf_range(0.0, 0.12) * scale
				Greedy.use_native = false
				var gd := p.voxels_within(at, r)
				var gd1 := p.voxels_within(at, r, 1)
				Greedy.use_native = true
				found += gd.size()
				if p.voxels_within(at, r) != gd or p.voxels_within(at, r, 1) != gd1:
					same = false
				var step: float = p.vf * p.part_scale
				var best := -1
				var bd := INF
				for i in p.fx.size():
					if p.alive[i] == 0:
						continue
					var q := p.local_of(i)
					var depth := minf(minf(p.half_ext.x - absf(q.x), p.half_ext.y - absf(q.y)), p.half_ext.z - absf(q.z))
					if depth > step * 1.6:
						continue
					var d := q.distance_squared_to(at)
					if d < bd:
						bd = d
						best = i
				var got: PackedFloat64Array = Greedy.core().skin_nearest(p.fx, p.fy, p.fz, p.alive, p.grid, p.vf, p.part_scale, p.half_ext, step * 1.6, at)
				if int(got[0]) != best or (best >= 0 and got[1] != bd):
					skin_same = false
	t.check(found > 100, "the searches found voxels (%d)" % found)
	t.check(same, "voxels_within: the same voxels in C++ and GDScript")
	t.check(skin_same, "skin search: the same voxel in C++ and GDScript")
	m.queue_free()

## PD's helpers in C++ give the very floats the GDScript gives (the limb drives are built on them).
func test_native_pd_matches_the_gdscript() -> void:
	if Greedy.core() == null:
		t.check(true, "no native core built: the GDScript fallback runs")
		return
	var nc = Greedy.core()
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 5, "decrees": [], "hazards": []})
	for k in 20:
		await get_tree().physics_frame
	var bad := []
	for k in 400:
		var rv := func(r: float) -> Vector3: return Vector3(rng.randf_range(-r, r), rng.randf_range(-r, r), rng.randf_range(-r, r))
		var qa := Quaternion((rv.call(1.0) as Vector3 + Vector3(0.01, 0, 0)).normalized(), rng.randf_range(-3.0, 3.0))
		var qb := Quaternion((rv.call(1.0) as Vector3 + Vector3(0, 0.01, 0)).normalized(), rng.randf_range(-3.0, 3.0))
		var a: Vector3 = rv.call(3.0)
		var b: Vector3 = rv.call(3.0)
		var mx := rng.randf_range(0.0, 4.0)
		var p: VoxelPart = m.me.f.parts[k % m.me.f.parts.size()]
		if nc.rot_error(qa, qb) != PD.rot_error(qa, qb): bad.append("rot_error")
		if nc.dir_error(a, b) != PD.dir_error(a, b): bad.append("dir_error")
		if nc.clamp_len(a, mx) != PD.clamp_len(a, mx): bad.append("clamp_len")
		var sc := rng.randf_range(0.2, 3.0)
		if nc.torque_for(p, a, sc) != PD.torque_for(p, a, sc): bad.append("torque_for")
		if nc.quat_of(p) != PD.quat_of(p): bad.append("quat_of")
	t.check(bad.is_empty(), "the same floats in C++ and GDScript (off: %s)" % [bad.slice(0, 5)])
	m.queue_free()

func test_native_trunk_matches_the_gdscript() -> void:
	# (#150) A man's arms kept out of his trunk as it is drawn (_limb_out, _elbow_off_trunk,
	# _hand_off_trunk): the C++ gives the script's own floats, in and out of the trunk.
	if Greedy.core() == null:
		t.check(true, "no native core built: the GDScript fallback runs")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 5, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "", "armor": ["helmet", "lorica", "manica", "greaves"]}})
	for k in 30:
		await get_tree().physics_frame
	var f: Fighter = m.me.f
	var o = f._trunk_sculpt("R")
	t.check(o is Dictionary, "a man in a cuirass on his feet has a drawn trunk his arms are kept out of")
	if not (o is Dictionary):
		m.queue_free()
		return
	var bad := []
	var moved := [0, 0, 0]
	var up: VoxelPart = f.arm.R.upper
	var fo: VoxelPart = f.arm.R.fore
	var lu: float = Fighter.UPPER_LEN * f.S
	var lf: float = Fighter.FORE_LEN * f.S
	var bt: Transform3D = f.torso.global_transform
	var he: Vector3 = f.torso.half_ext
	for k in 600:
		var l := Vector3(rng.randf_range(-1.6, 1.6) * he.x, rng.randf_range(-1.3, 1.3) * he.y, rng.randf_range(-1.6, 1.6) * he.z)
		var part: VoxelPart = up if k % 2 == 0 else fo
		var y := rng.randf_range(-0.2, 0.2)
		Greedy.use_native = false
		var a: Vector3 = f._limb_out(o, l, part, y)
		Greedy.use_native = true
		var b: Vector3 = f._limb_out(o, l, part, y)
		if a != b:
			bad.append("out %s" % l)
		if a != Vector3.ZERO:
			moved[0] += 1
		var side := "R" if k % 3 != 0 else "L"
		var sh: Vector3 = bt * f.shoulder[side]
		var dir: Vector3 = bt.basis * Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 0.3), rng.randf_range(-1.0, 1.0)).normalized()
		Greedy.use_native = false
		var ea: Vector3 = f._elbow_off_trunk(side, o, sh, dir, lu)
		Greedy.use_native = true
		var eb: Vector3 = f._elbow_off_trunk(side, o, sh, dir, lu)
		if ea != eb:
			bad.append("elbow %s" % dir)
		if ea != dir:
			moved[1] += 1
		var goal: Vector3 = bt * l
		var elbow: Vector3 = sh + ea * lu
		var straight := k % 2 == 0
		Greedy.use_native = false
		var ha: Vector3 = f._hand_off_trunk(side, o, sh, elbow, goal, lu, lf, straight)
		Greedy.use_native = true
		var hb: Vector3 = f._hand_off_trunk(side, o, sh, elbow, goal, lu, lf, straight)
		if ha != hb:
			bad.append("hand %s" % goal)
		if ha != goal:
			moved[2] += 1
	t.check(bad.is_empty(), "the arms are kept out of the trunk the same in C++ and GDScript, to the bit (off: %s of %d)" % [bad.slice(0, 4), bad.size()])
	t.check(moved[0] > 60 and moved[1] > 60 and moved[2] > 60, "and the points tried were in the trunk as well as out of it (moved out: %s of 600)" % [moved])
	m.queue_free()


func test_native_smooth_matches_the_gdscript() -> void:
	# (#151) The men's smooth skin (FineSmooth: a part's solid, the part beside it joined on at the
	# joint, the blurred shapes, the way each fine voxel faces, where its corners are drawn): the
	# C++ gives the script's own numbers. A forearm with its upper arm at the elbow.
	if Greedy.core() == null:
		t.check(true, "no native core built: the men are drawn as cubes")
		return
	var FS = preload("res://scripts/fighter/fine_smooth.gd")
	var fore := FineBody._fine_at(FineBody.part_data("hero", "forearmR").cells)
	var upper := FineBody._fine_at(FineBody.part_data("hero", "upperArmR").cells)
	t.check(fore.size() > 900 and upper.size() > 900, "the hero's arm has its fine voxels (%d, %d)" % [fore.size() / 3, upper.size() / 3])
	var got := {}
	var took := {}
	for native in [false, true]:
		Greedy.use_native = native
		var t0 := Time.get_ticks_usec()
		var own: Dictionary = FS.solid(fore, PackedInt32Array([2, 6, 2, 3, 9, 3]), 2, false, true)
		var other: Dictionary = FS.solid(upper, PackedInt32Array(), 2, true, false)
		# (The upper arm's grid 28 fine voxels over the forearm's; the elbow at the forearm's top.)
		var sol: Dictionary = FS.joined(own, [[other, Vector3i(0, 28, 0), Vector3(6.0, 28.0, 6.0), 9.5]])
		var shape: Dictionary = FS.blurred(sol, 2)
		var light: Dictionary = FS.blurred(sol, 3)
		var own_shape: Dictionary = FS.blurred(own, 2)
		var own_light: Dictionary = FS.blurred(own, 3)
		got[native] = {"solid": own.f, "size": [own.sx, own.sy, own.sz, own.lo, own.pad], "joined": sol.f, "added": sol.added, "shape": shape.f, "light": light.f,
			"ways": FS.ways(fore, light, sol, own_light), "corners": FS.corners(fore, sol, shape, light, own, own_shape, own_light), "alone": FS.corners(fore, own, own_shape, own_light)}
		took[native] = Time.get_ticks_usec() - t0
	Greedy.use_native = true
	t.check(int(took[false]) > 4 * int(took[true]), "the script works it out itself, and the core many times faster (%d ms, %d ms)" % [int(took[false]) / 1000, int(took[true]) / 1000])
	for k in got[false]:
		t.check(got[false][k] == got[true][k], "the C++ core's %s is the script's own" % k)
	var added: PackedInt32Array = got[true].added
	t.check(added.size() > 100, "the upper arm is joined on at the elbow (%d of its fine voxels)" % added.size())
	var cd: PackedFloat32Array = got[true].corners
	var moved := 0
	var far := 0.0
	for i in range(0, cd.size(), 4):
		var d := Vector3(cd[i], cd[i + 1], cd[i + 2])
		if d != Vector3.ZERO:
			moved += 1
			far = maxf(far, d.length())
	t.check(moved > fore.size() / 3, "the skin's corners are moved onto his shape (%d of them)" % moved)
	t.check(far <= FS.HELD_OUT + 1e-4, "none further than it is held to (%.2f of a fine voxel)" % far)


## What takes a set_instance_transform as a MultiMesh does, and keeps what it was given.
class Kept extends RefCounted:
	var got := {}
	func set_instance_transform(i: int, x: Transform3D) -> void:
		got[i] = x

## A man's drawing work a frame that the C++ core does (user: the frame rate drops sharply in a
## fight): the fine voxels of a shoulder guard hidden under his arm's armour (Fighter._in_reach on
## each, then _cut_off), and what is drawn on the voxels of a limb bent at a break set where the
## bend has each (VoxelPart._bent). The same masks, bit for bit, and the same places.
func test_native_drawing_matches_the_gdscript() -> void:
	var nc = Greedy.core()
	if nc == null or not nc.has_method("guard_reach"):
		t.check(true, "no native core built: the GDScript fallback runs")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	var rv := func(r: float) -> Vector3: return Vector3(rng.randf_range(-r, r), rng.randf_range(-r, r), rng.randf_range(-r, r))
	# An arm's reach (Fighter._arm_reach's table, some of it empty), a guard's voxels round it.
	var off := 0
	var cut_off := 0
	var chg_off := 0
	for k in 30:
		var rows := rng.randi_range(0, 9)
		var r := PackedFloat32Array()
		r.resize(rows * Fighter.REACH_NA)
		for i in r.size():
			r[i] = rng.randf_range(0.03, 0.11) if rng.randf() < 0.7 else 0.0
		var reach := {"key": "", "rows": rows, "y0": rng.randf_range(-0.3, 0.0), "dy": rng.randf_range(0.02, 0.05), "r": r}
		var pts := PackedVector3Array()
		for i in rng.randi_range(1, 400):
			pts.append(Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.45, 0.25), rng.randf_range(-0.2, 0.2)))
		var to_arm := Transform3D(Basis(Quaternion((rv.call(1.0) as Vector3 + Vector3(0.01, 0, 0)).normalized(), rng.randf_range(-3.0, 3.0))), rv.call(0.1))
		var pad := rng.randf_range(0.0, 0.02)
		var qa: PackedVector3Array = to_arm * pts
		var want := PackedByteArray()
		want.resize(pts.size())
		for i in pts.size():
			if Fighter._in_reach(reach, qa[i], pad):
				want[i] = 1
		var got: PackedByteArray = nc.guard_reach(pts, to_arm, r, rows, Fighter.REACH_NA, float(reach.y0), float(reach.dy), pad)
		if got != want:
			off += 1
		# How they hang together (Fighter._guard_links), and what the hidden ones cut off.
		var lk := Fighter._guard_links(pts, PackedVector3Array([pts[0], pts[pts.size() / 2]]), 0.03)
		var flat := PackedInt32Array()
		var at := PackedInt32Array([0])
		for nb in lk[0]:
			flat.append_array(nb)
			at.append(flat.size())
		var mask := PackedByteArray()
		mask.resize(pts.size())
		for i in pts.size():
			mask[i] = 1 if rng.randf() < 0.3 else 0
		if nc.guard_cut(mask, flat, at, lk[1]) != Fighter._cut_off(mask.duplicate(), lk[0], lk[1]):
			cut_off += 1
		var turned := PackedInt32Array()
		for i in pts.size():
			if mask[i] != want[i]:
				turned.append(i)
		if nc.bytes_changed(mask, want) != turned:
			chg_off += 1
	t.eq(off, 0, "the same voxels of a guard within an arm's reach")
	t.eq(cut_off, 0, "the same cut off by them from the rest of the shell")
	t.eq(chg_off, 0, "and the same places where one mask is not the other")
	t.check(nc.bytes_changed(PackedByteArray([1]), PackedByteArray([1, 0, 1])) == PackedInt32Array([0, 1, 2]), "against a mask of another length, every place")
	# A limb bent at a break: what is drawn on its voxels, where the bend has each.
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 3, "decrees": [], "hazards": []})
	var worst := 0.0
	var moved := 0
	var left := 0
	for part_name in ["forearmR", "shinL", "upperArmL"]:
		var p: VoxelPart = m.me.f.by_name[part_name]
		p.set_kink(Vector3.ZERO, 0.8, 40)
		for trial in 6:
			p._sw_q = Quaternion((rv.call(1.0) as Vector3 + Vector3(0, 0.02, 0)).normalized(), rng.randf_range(0.05, 1.8))
			p._bend_x = p._bend_for(p._sw_q)
			var g := p._bend_geom()
			var rows := PackedFloat32Array()
			var slots := PackedInt32Array()
			var want := {}
			var layers := {}
			var pv := p._dangle_pivot()
			var tip: Vector3 = p._across()[2]
			for i in 120:
				var lp := Vector3(rng.randf_range(-p.half_ext.x, p.half_ext.x), rng.randf_range(-p.half_ext.y, p.half_ext.y), rng.randf_range(-p.half_ext.z, p.half_ext.z))
				# (A voxel's middle is on the part's lattice: the bend's layers are a few heights along it.)
				lp[int(g[5])] = snappedf(lp[int(g[5])], p.vf * p.part_scale * 0.5)
				var x := Transform3D(Basis(Quaternion((rv.call(1.0) as Vector3 + Vector3(0.01, 0, 0)).normalized(), rng.randf_range(-3.0, 3.0))).scaled(Vector3.ONE * rng.randf_range(0.2, 1.0)), lp + rv.call(0.01))
				var bx := x.basis
				rows.append_array([bx.x.x, bx.y.x, bx.z.x, x.origin.x, bx.x.y, bx.y.y, bx.z.y, x.origin.y, bx.x.z, bx.y.z, bx.z.z, x.origin.z, lp.x, lp.y, lp.z])
				slots.append(i * 3 + 1)
				if (lp - pv).dot(tip) > 0.0:
					want[i * 3 + 1] = (p._bent(Transform3D(Basis(), lp), g, layers) * Transform3D(Basis(), -lp)) * x
			var kept := Kept.new()
			nc.lay_cells(kept, rows, slots, g[0], g[2], g[1], g[6], g[7], g[5], g[3], g[4], p._bend_x)
			left += 120 - want.size()
			for s in want:
				if not kept.got.has(s):
					worst = INF
					continue
				moved += 1
				var a: Transform3D = want[s]
				var b: Transform3D = kept.got[s]
				worst = maxf(worst, maxf(a.origin.distance_to(b.origin), maxf(a.basis.x.distance_to(b.basis.x), maxf(a.basis.y.distance_to(b.basis.y), a.basis.z.distance_to(b.basis.z)))))
			if kept.got.size() != want.size():
				worst = INF
		p.set_kink(Vector3.ZERO, 0.0, 0)
	t.check(moved > 300 and left > 300, "cells past the break and cells before it (%d, %d)" % [moved, left])
	t.check(worst < 1e-5, "each past the break set where the bend has its voxel, those before it left as they are (off by %.7f at most)" % worst)
	m.queue_free()

## The numbers of FineBody.put_cell that are not the same in two buffers of cells.
func _cells_off(a: PackedFloat32Array, b: PackedFloat32Array) -> int:
	if a.size() != b.size():
		return maxi(a.size(), b.size())
	var off := 0
	for i in a.size():
		if a[i] != b[i]:
			off += 1
	return off

## What a blow changes of the fine look that the C++ core does (user: the frame rate drops in a
## fight): the blood soaked into the skin round a wound (FineBody.colored), the wound's own cells
## (_write_wound, _write_wound_glow), which voxels a wound is looked at for when some are knocked
## out (shown), and what is drawn of a piece cut off (taken). On a man, a beast and a giant, cut
## into, bloodied, bruised, scarred and alight: the same numbers as the script's, every one.
func test_native_wounds_match_the_gdscript() -> void:
	var nc = Greedy.core()
	if nc == null or not nc.has_method("fine_wound"):
		t.check(true, "no native core built: the GDScript fallback runs")
		return
	Physique.forced = "human"
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 5, "decrees": [], "hazards": []})
	var lion = m.spawn_beast({"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(5, 0.1, 6.0), "yaw": PI, "harmless": true})
	var giant = m.spawn_fighter(m.enemy_spec({"e": "cyclops", "boss": true}, 0, 1))
	Physique.forced = ""
	var tp := FineBody.template()
	var res := int(tp.get("res", 2))
	var margin := int(tp.get("margin", 10))
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var parts := [m.me.f.torso, m.me.f.by_name["forearmR"], m.me.f.by_name["thighL"], giant.f.torso, giant.f.by_name["upperArmL"]]
	for bp in lion.f.parts:
		if bp.fine.has("body") and parts.size() < 8:
			parts.append(bp)
	t.check(parts.size() >= 7, "a man's parts, a giant's and a beast's (%d)" % parts.size())
	var seen := 0
	for p: VoxelPart in parts:
		var who := "%s %s" % [String(p.fighter.display_name), p.part_name]
		if not t.check(p.fine.has("body") and p.fine.get("nat", false), "%s: drawn fine, and the core reads its look" % who):
			continue
		for b in [p]:
			b.freeze = true
		var fine: Dictionary = p.fine
		var n := p.fx.size()
		var lps := p.local_positions()
		# Two cuts into him, blood and a bruise round them, a scar, fire and poison.
		for blow in 2:
			var at: Vector3 = lps[rng.randi_range(0, n - 1)]
			var cut := Array(p.voxels_within(at, p.vf * p.part_scale * rng.randf_range(2.0, 3.6)))
			p.remove_voxels(cut)
		p.wound(lps[rng.randi_range(0, n - 1)], p.vf * p.part_scale * 5.0, "blood")
		p.wound(lps[rng.randi_range(0, n - 1)], p.vf * p.part_scale * 4.0, "bruise")
		var bare_all := PackedInt32Array((fine.wound as Dictionary).keys())
		for q in bare_all.size():
			if q % 7 == 0:
				p.scarred[bare_all[q]] = true
			elif q % 5 == 0:
				p.glowing[bare_all[q]] = Vector2(0.5, 0.0)
			elif q % 11 == 0:
				p.glowing[bare_all[q]] = Vector2(0.0, 0.4375)
		for i in range(0, n, 13):
			p.glowing[i] = Vector2(0.25, 0.0)
		# 1. The skin's fine voxels, coloured.
		var of: Dictionary = fine.of
		var na: PackedFloat32Array = fine.get("na", PackedFloat32Array())
		var all := PackedInt32Array(range(n))
		var want := PackedFloat32Array()
		var marked := 0
		for i in all:
			if not of.has(i):
				continue
			var g: Vector2 = p.glowing.get(i, Vector2.ZERO)
			if p.colors[i] != (fine.base as Dictionary).get(i):
				marked += 1
			for s in (of[i] as Array):
				var col := FineBody._color(p, s, i)
				if s < na.size():
					col.a = na[s]
				var cu := FineBody._custom(p, s, i, g)
				want.append_array([0.0, float(s), col.r, col.g, col.b, col.a, cu.r, cu.g, cu.b, cu.a])
		t.check(marked > 10, "%s: blood and a bruise on his skin (%d voxels of it)" % [who, marked])
		t.eq(_cells_off(nc.fine_colored(p, all, false, res, margin, true), want), 0, "%s: his skin's fine voxels coloured as the script colours them (%d)" % [who, want.size() / 10])
		# 2. The wound's cells.
		t.check(bare_all.size() > 20, "%s: voxels bared by the cuts (%d)" % [who, bare_all.size()])
		var fsz: float = fine.fsz
		var cells := PackedFloat32Array()
		for i in bare_all:
			var code: int = (fine.code as PackedInt32Array)[i]
			var g: Vector2 = p.glowing.get(i, Vector2.ZERO)
			var healed: bool = p.scarred.has(i)
			for k in 8:
				var cc := (code >> (2 * k)) & 3
				var at := lps[i] + (Vector3(float(k & 1), float((k >> 1) & 1), float((k >> 2) & 1)) - Vector3(0.5, 0.5, 0.5)) * fsz
				var x := FineBody.mapped(p, fine.d, at, 0.97 if cc == 1 else 1.0)
				if cc == 0:
					x = Transform3D(Basis().scaled(Vector3.ZERO), x.origin)
				var kd := 0 if cc == 1 else (9 if cc == 2 or p.kinds[i] <= 2 else int(p.kinds[i]))
				var cu := VoxelPart.kind_data(kd, 0, 0)
				cu.g = g.x if g.x > 0.0 or healed else -(FineBody.WET_BONE if kd == 6 else float(FineBody.WET[cc]))
				cu.b = g.y
				FineBody.put_cell(cells, x, FineBody.wound_color(p, i, k, cc), cu)
		var whole: PackedFloat32Array = nc.fine_wound(p, bare_all, 0, false, false, res, margin)
		t.eq(_cells_off(whole, cells), 0, "%s: a wound's cells as the script writes them (%d)" % [who, cells.size() / 20])
		var glow: PackedFloat32Array = nc.fine_wound(p, bare_all, 2, false, false, res, margin)
		var only: PackedFloat32Array = nc.fine_wound(p, bare_all, 1, false, false, res, margin)
		var glow_off := 0
		for o in range(0, cells.size(), 20):
			for z in 8:
				if glow[o + 12 + z] != cells[o + 12 + z]:
					glow_off += 1
			for z in 4:
				if only[o + 16 + z] != cells[o + 16 + z]:
					glow_off += 1
		t.eq(glow_off, 0, "%s: and their colours and their glow alone, the same" % who)
		# 3. Voxels knocked out: which are looked at for a wound, and which lie open on it.
		var some := PackedInt32Array([-1, n + 4])
		for i in 60:
			some.append(rng.randi_range(0, n - 1))
		var near := {}
		for i in some:
			if i < 0 or i >= n:
				continue
			near[i] = true
			for dd in VoxelPart.AO_FACES:
				var qv: Vector3i = Vector3i(p.fx[i], p.fy[i], p.fz[i]) + (dd[0] as Vector3i)
				var k := p._cell(qv.x, qv.y, qv.z)
				if k >= 0:
					near[k] = true
		var looked := PackedInt32Array()
		var open := 0
		for i in near:
			var is_open: bool = p.alive[i] == 1 and FineBody._open(p, i)
			open += int(is_open)
			looked.append_array([i, 1 if is_open else 0])
		t.check(nc.fine_show(p, some, false, false) == looked, "%s: the same voxels looked at for a wound, in the same order, the same of them open (%d of %d)" % [who, open, near.size()])
		# 4. A piece cut off: what is drawn of it.
		var idx := p.voxels_within(lps[rng.randi_range(0, n - 1)], p.vf * p.part_scale * 3.2)
		for i in bare_all.slice(0, 12):
			if not idx.has(i):
				idx.append(i)
		Greedy.use_native = false
		var piece: PackedFloat32Array = FineBody.taken(p, idx).get("buf", PackedFloat32Array())
		Greedy.use_native = true
		t.check(piece.size() >= 20 * 8, "%s: a piece of %d voxels is drawn of %d cells" % [who, idx.size(), piece.size() / 20])
		t.eq(_cells_off(nc.fine_taken(p, idx, res, margin), piece), 0, "%s: a piece cut off drawn of the same cells" % who)
		t.check((FineBody.taken(p, idx).get("buf", PackedFloat32Array()) as PackedFloat32Array) == piece, "%s: and FineBody gives the core's" % who)
		# 5. The shading round a cut: the voxels found and each one's bits (VoxelPart._reshade).
		var cut_at := PackedInt32Array([-3, n + 1])
		for i in 40:
			cut_at.append(rng.randi_range(0, n - 1))
		var found := PackedInt32Array()
		var met := {}
		for i in cut_at:
			if i < 0 or i >= n:
				continue
			for ax in range(maxi(p.fx[i] - 1, 0), mini(p.fx[i] + 2, p.grid.x)):
				for ay in range(maxi(p.fy[i] - 1, 0), mini(p.fy[i] + 2, p.grid.y)):
					for az in range(maxi(p.fz[i] - 1, 0), mini(p.fz[i] + 2, p.grid.z)):
						var j := p._cell(ax, ay, az)
						if j >= 0 and not met.has(j) and p.alive[j] == 1:
							met[j] = true
							found.append_array([j, p.shade_bits(j)])
		t.check(found.size() > 200 and nc.reshade(cut_at, p.fx, p.fy, p.fz, p.cellmap, p.alive, p.veil, p.grid, p.bevel) == found, "%s: the same voxels shaded anew round a cut, the same shading (%d)" % [who, found.size() / 2])
		seen += 1
	t.check(seen >= 7, "every one of them looked at (%d)" % seen)
	# A weapon's voxels round where blood struck it, and the one nearest (Weapon.bloody, Match._spray_on).
	var off := 0
	var some_near := 0
	for w: Weapon in [m.me.f.weapons.R, m.me.f.weapons.L, giant.f.weapons.R]:
		if w == null or w.vox.is_empty():
			continue
		var places := w.voxel_places()
		# (Some of it broken off.)
		var alive := w.alive.duplicate()
		for i in range(0, alive.size(), 5):
			alive[i] = 0
		for trial in 40:
			var q := places[rng.randi_range(0, places.size() - 1)] + Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
			var near := PackedInt32Array()
			var best := -1
			var bd := INF
			for i in w.vox.size():
				if alive[i] == 0:
					continue
				var d2 := Vector3(w.vox[i][0], w.vox[i][1], w.vox[i][2]).distance_squared_to(q)
				if d2 < bd:
					bd = d2
					best = i
				if w.vox[i][4] != "grip" and not Vector3(w.vox[i][0], w.vox[i][1], w.vox[i][2]).distance_to(q) > 2.6:
					near.append(i)
			some_near += near.size()
			if nc.points_near(places, alive, w._vgrip, q, 2.6) != near or nc.point_nearest(places, alive, q) != best:
				off += 1
	t.check(some_near > 200, "voxels of the weapons round the points tried (%d)" % some_near)
	t.eq(off, 0, "the same voxels of a weapon round a point, and the same one nearest it")
	m.queue_free()
