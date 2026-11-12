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
