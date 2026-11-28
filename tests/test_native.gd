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

## The search over the cells round a point (VoxelCore.within_cells: what VoxelPart.voxels_within asks when each voxel of the part has a cell of its own, docs/PERF_RESEARCH.md, section 27)
## names the very voxels the search over every voxel names (VoxelCore.within) and the script's own, in the same order and down to the limit: for a man's parts and a lion's trunk, whole and
## cut about, scaled, round a voxel and off the part, with a radius from nothing to the whole of it, exactly on a voxel's distance, a hair either side, and with no number at all.
func test_native_within_cells_matches_the_full_search() -> void:
	var nc = Greedy.core()
	if nc == null or not Greedy.cells_ok:
		t.check(true, "no native core with the cell search built: the GDScript lines run")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 4, "decrees": [], "hazards": []})
	var lion = m.spawn_beast({"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(5, 0.1, 6.0), "yaw": PI, "harmless": true})
	var parts: Array = m.me.f.parts.duplicate()
	parts.append_array(lion.f.parts)
	var bad := []
	var asked := 0
	var found := 0
	var limited := 0
	var empty := 0
	var biggest := 0
	var single := 0
	for p: VoxelPart in parts:
		if p.fx.size() == 0:
			continue
		biggest = maxi(biggest, p.fx.size())
		if not p._cells_single():
			continue
		single += 1
		for i in p.alive.size():
			if rng.randf() < 0.25:
				p.alive[i] = 0
		for scale in [1.0, 1.37, 2.6]:
			p.part_scale = scale
			var step: float = p.vf * p.part_scale
			for k in (14 if p.fx.size() < 3000 else 28):
				var at := p.local_of(rng.randi() % p.fx.size())
				var r := rng.randf_range(0.0, 3.0) * step
				match k % 14:
					0: at += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.03
					1: r = p.local_of(rng.randi() % p.fx.size()).distance_to(at)   # (exactly a voxel's distance)
					2: r = p.local_of(rng.randi() % p.fx.size()).distance_to(at) + 1e-6
					3: r = maxf(0.0, p.local_of(rng.randi() % p.fx.size()).distance_to(at) - 1e-6)
					4: r = 0.0
					5: r = -step
					6: r = 1000.0   # (the whole part)
					7: at = Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
					8: at = Vector3(50.0, -40.0, 30.0)   # (far off the part)
					9: at = Vector3(NAN, 0.0, 0.0)
					10: r = NAN
					11: r = INF
					12: at += Vector3(step * 0.5, 0.0, 0.0)   # (between two voxels)
					13: r = step * 0.5001
				var limit: int = [0, 1, 2, 5, 40][rng.randi() % 5]
				var want: PackedInt32Array = nc.within(p.fx, p.fy, p.fz, p.alive, p.grid, p.vf, p.part_scale, at, r, limit)
				var got: PackedInt32Array = nc.within_cells(p.cell_map(), p.fx, p.fy, p.fz, p.alive, p.grid, p.vf, p.part_scale, at, r, limit)
				var api: PackedInt32Array = p.voxels_within(at, r, limit)
				asked += 1
				found += want.size()
				if limit > 0 and want.size() == limit:
					limited += 1
				if want.is_empty():
					empty += 1
				if got != want or api != want:
					bad.append("%s s=%.2f k=%d limit=%d: cells %d, api %d, all %d" % [p.name, scale, k, limit, got.size(), api.size(), want.size()])
				if k % 3 == 0:
					# (And the very first lines, over every voxel in script.)
					var brute := PackedInt32Array()
					var lps := p.local_positions()
					for i in lps.size():
						if p.alive[i] and lps[i].distance_to(at) < r:
							brute.append(i)
							if limit > 0 and brute.size() >= limit:
								break
					if brute != want:
						bad.append("%s s=%.2f k=%d limit=%d: script %d, all %d" % [p.name, scale, k, limit, brute.size(), want.size()])
	t.check(bad.is_empty(), "the cell search names the very voxels the search over all of them names (%d searches; unlike: %s)" % [asked, str(bad.slice(0, 6))])
	t.check(single >= 10 and asked > 500 and found > 1500 and limited > 20 and empty > 40 and biggest > 3000, "what was asked covers the cases (%d parts with a cell a voxel, %d searches, %d voxels found, %d cut at the limit, %d finding none, the biggest part %d voxels)" % [single, asked, found, limited, empty, biggest])
	# A cell map of another size than the grid's, and arrays that are not the part's: the full search answers, as it did.
	var q: VoxelPart = m.me.f.parts[0]
	var all: PackedInt32Array = nc.within(q.fx, q.fy, q.fz, q.alive, q.grid, q.vf, q.part_scale, Vector3.ZERO, 1.0, 0)
	t.check(nc.within_cells(PackedInt32Array([1, 2, 3]), q.fx, q.fy, q.fz, q.alive, q.grid, q.vf, q.part_scale, Vector3.ZERO, 1.0, 0) == all, "with a cell map that is not the grid's, every voxel is looked at")
	t.check(all.size() > 0, "and the part has voxels in the unit sphere (%d)" % all.size())
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


## (#298) A man's arms kept out of his own body (_keep_arm_out, _keep_hand_front, _keep_elbow_low): the C++ core gives the very
## impulses the script gives, to the bit. The four bodies (trunk, head, upper arm, forearm) are thrown into random places round him
## with random speeds; out of the script's run and out of the C++ they come with the same speeds, to the last bit, in a cuirass
## (the trunk as it is drawn) and bare (its box), with one hand on a haft or two, a hand or no hand.
func _arm_bodies(f: Fighter, side: String) -> Array:
	return [f.torso, f.head, f.arm[side].upper, f.arm[side].fore]

func _arm_live(bodies: Array) -> Array:
	var out := []
	for b: RigidBody3D in bodies:
		out.append(PhysicsServer3D.body_get_state(b.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY))
		out.append(PhysicsServer3D.body_get_state(b.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY))
	return out

func _arm_set_speeds(bodies: Array, speeds: Array) -> void:
	for i in bodies.size():
		(bodies[i] as RigidBody3D).linear_velocity = speeds[i * 2]
		(bodies[i] as RigidBody3D).angular_velocity = speeds[i * 2 + 1]

func test_native_arms_keep_out_like_the_gdscript() -> void:
	if Greedy.core() == null or not Greedy.arm_ok:
		t.check(true, "no native core with the arms built: the GDScript fallback runs")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var bad := []
	var pushed := {"out": 0, "front": 0, "low": 0, "clear": 0, "hand": 0}
	var drawn_seen := [0, 0]
	for armour in [true, false]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 5, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "scutum", "armor": ["helmet", "lorica", "manica", "greaves"] if armour else []}})
		for k in 30:
			await get_tree().physics_frame
		var f: Fighter = m.me.f
		var rv := func(r: float) -> Vector3: return Vector3(rng.randf_range(-r, r), rng.randf_range(-r, r), rng.randf_range(-r, r))
		for k in 500:
			var side := "R" if k % 2 == 0 else "L"
			var bodies := _arm_bodies(f, side)
			var up: VoxelPart = bodies[2]
			var fo: VoxelPart = bodies[3]
			# (what is put back after: where each was and how fast it went)
			var saved := []
			for b: RigidBody3D in bodies:
				saved.append([b.global_transform, b.linear_velocity, b.angular_velocity])
			var he: Vector3 = f.torso.half_ext
			var tb: Transform3D = f.torso.global_transform
			for part: VoxelPart in [up, fo]:
				var q := Quaternion((rv.call(1.0) as Vector3 + Vector3(0.01, 0, 0)).normalized(), rng.randf_range(-3.1, 3.1))
				var at: Vector3 = tb.origin + tb.basis * Vector3(rng.randf_range(-1.5, 1.5) * he.x, rng.randf_range(-1.3, 1.3) * he.y, rng.randf_range(-1.7, 1.7) * he.z)
				part.global_transform = Transform3D(Basis(q), at)
			var speeds := []
			for i in 4:
				speeds.append((rv.call(1.0 if i == 0 else 3.0) as Vector3) if k % 5 != 0 else Vector3.ZERO)
				speeds.append((rv.call(8.0) as Vector3) if k % 5 != 0 else Vector3.ZERO)
			var was_two := f.two_handed
			f.two_handed = k % 3 == 0
			var was_severed := fo.severed
			fo.severed = k % 11 == 0
			var dt := 1.0 / 120.0 if k % 4 != 0 else rng.randf_range(0.005, 0.03)
			for which in ["out", "front", "low"]:
				f._arm_phase = true
				f._sculpt_memo.clear()
				f._limb_memo.clear()
				f._plate_memo = null
				f._beast_memo = -1
				_arm_set_speeds(bodies, speeds)
				Greedy.use_native = false
				if which == "out":
					f._keep_arm_out(side, dt)
				elif which == "front":
					f._keep_hand_front(side, dt)
				else:
					f._keep_elbow_low(side, dt)
				var a := _arm_live(bodies)
				_arm_set_speeds(bodies, speeds)
				f._sculpt_memo.clear()
				f._limb_memo.clear()
				f._plate_memo = null
				f._beast_memo = -1
				Greedy.use_native = true
				if which == "out":
					f._keep_arm_out(side, dt)
				elif which == "front":
					f._keep_hand_front(side, dt)
				else:
					f._keep_elbow_low(side, dt)
				var b2 := _arm_live(bodies)
				f._arm_phase = false
				if a != b2:
					bad.append("%s %s k=%d" % [which, side, k])
				if a != speeds:
					pushed[which] += 1
				if which == "out" and f._trunk_sculpt(side) is Dictionary:
					drawn_seen[0] += 1
				elif which == "out":
					drawn_seen[1] += 1
			# (And what is asked of the arm's reach: a hand's mark out of the trunk and the head, the elbow's way, the hand's goal.)
			var yq := Quaternion(Vector3.UP, rng.randf_range(-PI, PI))
			var tp: Vector3 = f.torso.global_position
			var lu: float = Fighter.UPPER_LEN * f.S
			var lf: float = Fighter.FORE_LEN * f.S
			var sh: Vector3 = tb * f.shoulder[side]
			for rep in 3:
				var tgt := Vector3(rng.randf_range(-1.6, 1.6) * he.x, rng.randf_range(-1.3, 1.3) * he.y, rng.randf_range(-1.7, 1.7) * he.z)
				var edir: Vector3 = tb.basis * Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 0.3), rng.randf_range(-1.0, 1.0)).normalized()
				var goal: Vector3 = tb * Vector3(rng.randf_range(-1.7, 1.7) * he.x, rng.randf_range(-1.3, 1.3) * he.y, rng.randf_range(-1.8, 1.8) * he.z)
				var elb: Vector3 = sh + edir * lu
				var res := []
				for native in [false, true]:
					Greedy.use_native = native
					f._arm_phase = rep != 1
					f._sculpt_memo.clear()
					f._limb_memo.clear()
					f._plate_memo = null
					f._armor_memo.clear()
					f._outline_memo.clear()
					var face0: String = f.elbow_face[side]
					var sc = f._trunk_sculpt(side)
					var row := [f._clear_body(tgt, yq, tp, side), f._elbow_clear(side, sh, edir, lu), f._hand_off_trunk(side, sc, sh, elb, goal, lu, lf, k % 2 == 0) if sc != null else goal, f._elbow_off_trunk(side, sc, sh, edir, lu) if sc != null else edir]
					f.elbow_face[side] = face0
					res.append(row)
				f._arm_phase = false
				Greedy.use_native = true
				if res[0] != res[1]:
					bad.append("reach %s k=%d rep=%d" % [side, k, rep])
				if (res[0][0] as Vector3) != tgt:
					pushed["clear"] += 1
				if (res[0][2] as Vector3) != goal:
					pushed["hand"] += 1
			f.two_handed = was_two
			fo.severed = was_severed
			for i in 4:
				(bodies[i] as RigidBody3D).global_transform = saved[i][0]
				(bodies[i] as RigidBody3D).linear_velocity = saved[i][1]
				(bodies[i] as RigidBody3D).angular_velocity = saved[i][2]
		m.queue_free()
	Greedy.use_native = true

	t.check(bad.is_empty(), "the arms are kept out of the body the same in C++ and GDScript, to the bit (off: %s of %d)" % [bad.slice(0, 4), bad.size()])
	t.check(pushed.out > 300 and pushed.front > 40 and pushed.low > 30 and pushed.clear > 200 and pushed.hand > 100, "and the bodies tried were pushed as well as let alone (pushed: %s of 1000 a kind, 3000 asked of the reach)" % [pushed])
	t.check(drawn_seen[0] > 200 and drawn_seen[1] > 200, "in a cuirass (the trunk as it is drawn) and bare (its box): %s" % [drawn_seen])

## The arm's drive itself, as far as it has been moved to the C++ core (a shield's or an empty hand's arm whole, VoxelCore.arm_free; a blade's mark, its
## elbow and its drive, arm_mark, arm_elbow and arm_blade; docs/PERF_RESEARCH.md, section 20): from the same man in the same state the script's own branch
## and the core's leave every body the same speeds, every field of his the same and his elbow set the same, to the bit.
func _arm_state(f: Fighter) -> Dictionary:
	var out := {}
	for pr in f.get_script().get_script_property_list():
		var v = f.get(pr.name)
		if v is Dictionary and (v as Dictionary).size() == 2 and (v as Dictionary).has("L") and (v as Dictionary).has("R"):
			out[pr.name] = (v as Dictionary).duplicate(true)
	for nm in ["power_now", "stamina", "grab_bend", "grab_deep", "grab_low", "thrust_lean", "two_handed", "two_front", "two_main", "two_gap", "haft_i", "haft_lp", "haft_raw", "low_hand"]:
		out[nm] = f.get(nm)
	return out

func _arm_restore(f: Fighter, st: Dictionary) -> void:
	for k in st:
		f.set(k, (st[k] as Dictionary).duplicate(true) if st[k] is Dictionary else st[k])
	f._arm_refs = []   # (the fields were put back as copies: the core is handed the new ones)

## (To find the step where a port parts from the script: `ARM_ONLY=zweihander,spear` runs only the loadouts of those main weapons, `ARM_STEPS=n` n steps of each in place of 600, and
## `ARM_KEEP_OFF=1` leaves the arm's keeping out of his body out of it.)
func test_native_arm_drive_matches_the_gdscript() -> void:
	if Greedy.core() == null or not Greedy.arm_drive_ok:
		t.check(true, "no native core with the arm's drive built: the GDScript drive runs")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var rng2 := RandomNumberGenerator.new()   # (the thrusts' own draws: the others' are what they were)
	rng2.seed = 41
	var lines := 0
	var driven_in := 0
	var by_depth := 0
	var laid := 0
	var bad := []
	var driven := 0
	var homes := 0
	var blades := 0
	var downs := 0
	var two_offs := 0   # (the hand on a haft below the guard hand, VoxelCore.arm_off_two's: steps of it)
	var plain_two := 0   # (the main hand of a man with both hands on the weapon, taken by the core as a plain step: the front hand's place, the haft drive)
	var plain := 0
	var old_core := 0   # (steps of a man with both hands on the weapon driven with a core that has the arm's drive but not the two-handed arms': the script's own for those)
	var two_was := Greedy.two_ok
	var sets := 0
	var stills := 0
	var kept := 0
	var reaches := {}
	for lo in [{"main": "gladius", "off": "scutum", "armor": ["helmet", "lorica", "manica", "greaves"]}, {"main": "gladius", "off": ""}, {"main": "mace", "off": "scutum"},
			{"main": "spear", "off": ""}, {"main": "dagger", "off": "scutum"}, {"main": "bow", "off": ""}, {"main": "spear", "off": "scutum"},
			{"main": "zweihander", "off": ""}, {"main": "warhammer", "off": ""}, {"main": "longsword", "off": "", "armor": ["helmet", "lorica", "manica", "greaves"]}, {"main": "trident", "off": ""}]:
		if OS.get_environment("ARM_ONLY") != "" and not (OS.get_environment("ARM_ONLY").split(",") as Array).has(lo.main):
			continue
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 5, "decrees": [], "hazards": [], "loadout": lo})
		for k in 30:
			await get_tree().physics_frame
		var f: Fighter = m.me.f
		var rv := func(r: float) -> Vector3: return Vector3(rng.randf_range(-r, r), rng.randf_range(-r, r), rng.randf_range(-r, r))
		var held_mark = null
		for k in (int(OS.get_environment("ARM_STEPS")) if OS.get_environment("ARM_STEPS") != "" else 600):
			# (By turns the shield's or the empty hand's arm, and the blade's.)
			var side: String = f.two_off() if k % 2 == 0 else f.two_side
			var bodies := _arm_bodies(f, side)
			if f.weapons[side] != null:
				bodies.append(f.weapons[side])
			var speeds := []
			for i in bodies.size():
				speeds.append((rv.call(1.0 if i == 0 else 3.0) as Vector3) if k % 5 != 0 else Vector3.ZERO)
				speeds.append((rv.call(8.0) as Vector3) if k % 5 != 0 else Vector3.ZERO)
			var inp := {"main": {"x": rng.randf_range(-1.6, 1.6), "y": rng.randf_range(-1.3, 1.5)}, "off": {"x": rng.randf_range(-1.6, 1.6), "y": rng.randf_range(-1.3, 1.5)},
				"thrust": [0.0, 0.25, 0.4, 0.6][k % 4] if k % 9 >= 6 else 0.0, "offThrust": [0.0, 0.25, 0.6][k % 3] if k % 7 < 2 else 0.0}
			# (A blade held all but still for a while, its mark creeping and nothing else asked of him: its line turns a thousandth of a radian a
			# step, where the engine's own shortest arc between two lines and a library's part ways.)
			var still := k % 300 >= 100 and k % 300 < 200
			if still:
				inp.thrust = 0.0
				if held_mark == null:
					held_mark = inp.main.duplicate()
				held_mark.x += rng.randf_range(-0.003, 0.003)
				held_mark.y += rng.randf_range(-0.003, 0.003)
				inp.main = held_mark.duplicate()
			else:
				held_mark = null
			# (A thrust along the blade's line held for a spell, VoxelCore.arm_armed's as the script's: a stab of the key, laid on the crosshair while it is
			# drawn back; the player's mouse driving it in depth, the line turned to the crosshair while it is not yet driven; and with no crosshair at all.)
			var stab := k % 300 >= 200 and k % 300 < 290
			if stab:
				inp.thrust = [0.6, 1.0, 0.8][k % 3]
				var ph := (k % 300 - 200) / 30
				var mark: Vector3 = f.torso.global_position + Quaternion(Vector3.UP, f.yaw) * Vector3(rng2.randf_range(-1.0, 1.0), rng2.randf_range(-0.6, 0.9), rng2.randf_range(0.4, 3.0))
				if ph == 1:
					inp["depthOn"] = true
					inp["depth"] = 0.0 if k % 8 < 3 else rng2.randf_range(-1.2, 1.2)
				if ph != 2 and k % 6 != 1:
					inp["aimAt"] = mark
				# (Held level and still by turns: what a couched spear learns of its line then, it does not learn in a thrust.)
				if k % 4 == 1:
					inp.main = {"x": rng2.randf_range(-0.2, 0.2), "y": rng2.randf_range(-0.15, 0.2)}
					for i in speeds.size():
						speeds[i] = Vector3.ZERO
			if k % 11 == 0:
				inp.off["tuck"] = 0.7
			if k % 13 == 0:
				inp["jabL" if side == "L" else "jabR"] = true   # (a punch asked for: the core hands the step back to the script)
			# (The wheel turned, the swing's button down, and where he looks (a spear lies on that line), by turns.)
			if k % 5 == 3:
				inp["twist"] = rng.randf_range(-1.2, 1.2)
			if k % 6 == 3:
				inp["power"] = true
			if k % 4 == 3:
				inp["look"] = {"yaw": f.yaw + rng.randf_range(-0.5, 0.5), "pitch": rng.randf_range(-1.0, 1.0)}
			# (A bot's man with a ringing head by turns: his hand wanders; a player's mark is eased.)
			f.player = k % 4 != 1
			f.is_bot = k % 4 == 1 or k % 10 == 9   # (a bot's blade turns its edge to lead the stroke)
			f.concussion = 0.5 if k % 4 == 1 else 0.0
			f.daze_t = 0.1 if k % 10 == 3 else 0.0
			# (A man down by turns, his arm at a fallen man's mark; and the trunk turned by the other fist's punch.)
			f.state = "down" if k % 6 == 5 and not still and not stab else "stand"
			if k % 12 == 11 and not still and not stab:
				f.state = "rising"
			# (What the arm's keeping out of his body asks of him: staggering, limp, flung, by turns; and an arm at rest far off not kept this step.)
			f.stagger = 0.5 if k % 14 == 5 else 0.0
			f.limp = k % 16 == 7
			if k % 15 == 4:
				speeds[0] = Vector3(3.5, 0.0, 2.5)
			var keep_dt: float = -1.0 if k % 5 == 4 else (1.0 / 120.0 if k % 3 != 0 else 1.0 / 60.0)
			if OS.get_environment("ARM_KEEP_OFF") != "":
				keep_dt = -1.0
			if still:
				f.player = false
				f.is_bot = false
				f.concussion = 0.0
				inp.erase("jabL")
				inp.erase("jabR")
			f.jab_twist_was = 0.2 if k % 8 == 2 else 0.0
			if f.state == "down":
				downs += 1
			var power := k % 4 == 0
			var dt := 1.0 / 120.0 if k % 6 != 0 else rng.randf_range(0.005, 0.02)
			var t_pos: Vector3 = f.torso.global_position
			var t_rot := PD.quat_of(f.torso)
			var yaw_q := Quaternion(Vector3.UP, f.yaw + (0.0 if still else rng.randf_range(-0.2, 0.2)))
			var st := _arm_state(f)
			if k % 9 == 0:
				(st["fist_home"] as Dictionary)[side] = 0.2   # (a fist on its way home: the brisker fold, the upper arm rolled)
			if k % 7 == 1 and f.weapons[side] != null:
				(st["behind_t"] as Dictionary)[side] = 1.5   # (a blade long behind him: it is turned back to the front)
			if k % 10 == 7:
				(st["swing_hold"] as Dictionary)[side] = 0.2   # (a fast stroke a moment ago: the weapon out at the end of the arm, the elbow set)
			if stab and k % 14 == 3 and (st["thrust_line"] as Dictionary)[side] is Dictionary:
				(st["thrust_line"] as Dictionary)[side].t += rng2.randf_range(0.04, 0.3)   # (its clock sent on: to the drive, the hold at the arm's end, past the lunge)
			var fore_k: VoxelPart = f.arm[side].fore
			# (A frost thawing on the blade's forearm by turns: such a step is the script's, handed back by the core with nothing changed.)
			var frost := k % 17 == 5 and side == f.two_side
			fore_k.frozen_until = VoxelPart.clock() + 1.0 if frost else 0.0
			var set0 = (fore_k.get_meta("elbow_set") if fore_k.has_meta("elbow_set") else null)
			var hinge := fore_k.joint as Generic6DOFJoint3D
			var lim0 := [hinge.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT), hinge.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)]
			# (Whether the core takes the blade's step as a plain one: asked of it as _drive_arm asks, on the same state, and that state put back.)
			if side == f.two_side and f.weapons[side] != null and (not f.two_handed or two_was):
				_arm_restore(f, st)
				_arm_set_speeds(bodies, speeds)
				var e_was = f.elbow_prev[side]
				if f._drive_blade_plain(side, inp, f.weapons[side], f.arm[side].upper, fore_k, e_was, f.arm_func(side), -1.0 if frost else f.arm_func(side), power, 0.9, 0.95, t_pos, t_rot, yaw_q, dt):
					plain += 1
					if f.two_handed:
						plain_two += 1
					reaches[snappedf(float(f.weapons[side].reach), 0.01)] = true
			# (Both hands on the weapon and the other hand's joint gone for a step by turns: the front hand's place is left as it was, the haft not driven.)
			var off_wj = null
			var off_nulled := false
			if f.two_handed and k % 17 == 9:
				off_wj = f.weapon_joints[f.two_off()]
				f.weapon_joints[f.two_off()] = null
				off_nulled = true
			var res := []
			var modes := [[false, true], [true, true]]
			if f.two_handed and two_was and k % 4 == 1:
				modes.append([true, false])   # (and once more with a core that has the arm's drive but not the two-handed arms': the script's own drive for those, the same to the bit)
			for mode in modes:
				_arm_restore(f, st)
				_arm_set_speeds(bodies, speeds)
				if set0 == null:
					fore_k.remove_meta("elbow_set")
				else:
					fore_k.set_meta("elbow_set", set0)
				hinge.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lim0[0])
				hinge.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, lim0[1])
				f._arm_phase = true
				f._sculpt_memo.clear()
				f._limb_memo.clear()
				f._rec_memo.clear()
				f._plate_memo = null
				f._beast_memo = -1
				Greedy.arm_drive_ok = mode[0]
				Greedy.two_ok = mode[1] and two_was
				# (As Fighter.control's loop over the arms does: the drive, then the arm kept out of his body unless the core's own call has done that.)
				f._arm_kept = false
				f._drive_arm(side, inp, true, power, 0.9, 0.95, t_pos, t_rot, yaw_q, dt, keep_dt)
				if keep_dt >= 0.0:
					if f._arm_kept:
						f._arm_kept = false
						kept += 1
					else:
						f._keep_arm_out(side, keep_dt)
						f._keep_elbow_low(side, keep_dt)
				res.append([_arm_live(bodies), _arm_state(f), [(fore_k.get_meta("elbow_set") if fore_k.has_meta("elbow_set") else null),
					hinge.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT), hinge.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)]])
			if off_nulled:
				f.weapon_joints[f.two_off()] = off_wj
			Greedy.arm_drive_ok = true
			Greedy.two_ok = two_was
			fore_k.frozen_until = 0.0
			f._arm_phase = false
			f.player = true
			f.is_bot = false
			f.concussion = 0.0
			f.daze_t = 0.0
			f.state = "stand"
			f.jab_twist_was = 0.0
			f.stagger = 0.0
			f.limp = false
			if res[0][0] != res[1][0]:
				var first := -1
				for vi in (res[0][0] as Array).size():
					if res[0][0][vi] != res[1][0][vi]:
						first = vi
						break
				var diffs := []
				for vi in (res[0][0] as Array).size():
					if res[0][0][vi] != res[1][0][vi]:
						diffs.append("%d:%s" % [vi, ((res[0][0][vi] as Vector3) - (res[1][0][vi] as Vector3)) * 1e6])
				bad.append("speeds of %s, %s, k=%d, the %s (script minus core, in micro) with %s, stab %s, still %s, state %s, two_front %s" % [lo.main, side, k, ", ".join(PackedStringArray(diffs)), str(inp.keys()), stab, still, f.state, f.two_front != null])
			if res[0][1] != res[1][1]:
				var names := []
				for nm in res[0][1]:
					if res[0][1][nm] != res[1][1][nm]:
						names.append("%s %s / %s" % [nm, str(res[0][1][nm]), str(res[1][1][nm])])
				bad.append("his fields of %s, k=%d: %s" % [lo.main, k, ", ".join(PackedStringArray(names)).left(400)])
			if res[0][2] != res[1][2]:
				bad.append("his elbow's set, k=%d" % k)
			if res.size() > 2:
				old_core += 1
				if res[2] != res[0]:
					bad.append("the two-handed arms by the script, the others by the core, of %s, k=%d" % [lo.main, k])
			if res[1][2][0] != null:
				sets += 1
			var q_was = (st["aim_q"] as Dictionary)[side]
			var q_now = (res[1][1]["aim_q"] as Dictionary)[side]
			if q_was is Quaternion and q_now is Quaternion:
				var turned: float = ((q_was as Quaternion) * Vector3.UP).angle_to((q_now as Quaternion) * Vector3.UP)
				if turned > 0.0007 and turned < 0.004:
					stills += 1
			var tl_now = (res[1][1]["thrust_line"] as Dictionary)[side]
			if tl_now is Dictionary and side == f.two_side:
				lines += 1
				if float(tl_now.t) > Fighter.THRUST_DRAW + Fighter.THRUST_DRIVE:
					driven_in += 1
				if inp.get("depthOn", false):
					by_depth += 1
				if inp.get("aimAt") is Vector3:
					laid += 1
			if res[1][0] != speeds:
				driven += 1
			if side == f.two_side:
				blades += 1
			elif f.two_handed and f.weapons[f.two_side] != null:
				two_offs += 1
			if float((res[1][1]["fist_home"] as Dictionary)[side]) > 0.0:
				homes += 1
			_arm_set_speeds(bodies, speeds.map(func(_v): return Vector3.ZERO))
		m.queue_free()
		await get_tree().physics_frame
	t.check(bad.is_empty(), "the core's arm drive leaves what the script's does, to the bit (%d differ: %s)" % [bad.size(), ", ".join(PackedStringArray(bad.slice(0, 6)))])
	t.check(driven > 5500 and homes > 120 and blades == 3300 and downs > 100, "and it was the drive at work: %d of 6600 steps pushed a body, %d with a fist on its way home, %d a blade's arm, %d of a man down" % [driven, homes, blades, downs])
	t.check(two_offs > 1000, "the hand on a haft below the guard hand among them (two-handers' own): %d of 6600 steps" % two_offs)
	t.check(plain_two > 400 or not two_was, "and the guard hand's, both hands on the weapon, in the core's own call: %d steps of 1500" % plain_two)
	t.check(old_core > 150 or not two_was, "and with a core that lacks the two-handed arms, the script's own drive for them, the rest the core's: %d steps" % old_core)
	t.check(plain > 1100 and plain < 2900 and sets > 300 and reaches.size() >= 4, "the blade's steps the core takes as plain ones and those it hands back to the script both: %d of 3300 its own (the bow's none), %d steps left an elbow set, blades of %s m" % [plain, sets, reaches.keys()])
	t.check(stills > 60, "a blade all but still among them: %d steps turned its line between 0.0007 and 0.004 of a radian" % stills)
	t.check(kept > 1400, "and the arm kept out of his body after the drive, in the core's own call: %d of 6600 steps" % kept)
	t.check(lines > 200 and driven_in > 40 and by_depth > 40 and laid > 80, "a thrust along the blade's line among them: %d steps with a line, %d of them past the drive, %d driven in depth by the mouse, %d with a crosshair to lay it on" % [lines, driven_in, by_depth, laid])

## The plates of an arm's armour the clip is to change, named in one call (VoxelCore.clip_plates_flip for Fighter._clip_arm_armor, docs/PERF_RESEARCH.md, section 27) are the plates the script's
## lines turn: each drawn plate inside the box of his chest's armour and within his outline there (or the box alone, no outline) is hidden, the others drawn, and a plate whose clip
## is not what that says is named, nothing else. Boxes of every size, plates on the faces of it and a hair outside, outlines of every kind, plates that are not there and a point that is no number.
func test_native_clip_plates_flip_matches_the_script() -> void:
	var nc = Greedy.core()
	if nc == null or not Greedy.flip_ok:
		t.check(true, "no native core with the clip call built: the GDScript lines run")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	var rv := func(r: float) -> Vector3: return Vector3(rng.randf_range(-r, r), rng.randf_range(-r, r), rng.randf_range(-r, r))
	var off := 0
	var asked := 0
	var flips := 0
	var in_out := 0
	var with_outline := 0
	var outlined_in := 0
	var outlined_out := 0
	for k in 160:
		var n := rng.randi_range(0, 260)
		var origins := PackedVector3Array()
		var on := PackedByteArray()
		var clip := PackedByteArray()
		on.resize(n)
		clip.resize(n)
		for i in n:
			origins.append(rv.call(0.15))
			on[i] = 0 if rng.randf() < 0.15 else 1
			clip[i] = 1 if rng.randf() < 0.45 else 0
		var to_t := Transform3D(Basis(Quaternion((rv.call(1.0) as Vector3 + Vector3(0.01, 0, 0)).normalized(), rng.randf_range(-3.0, 3.0))), rv.call(0.06))
		var bsz := Vector3(rng.randf_range(0.04, 0.5), rng.randf_range(0.04, 0.5), rng.randf_range(0.04, 0.5))
		var box := AABB((rv.call(0.06) as Vector3) - bsz * 0.5, bsz)
		if k % 5 == 0:
			# (On the faces and corners of the box, and a hair outside them, in the box's own frame; and a point that is not a number.)
			to_t = Transform3D.IDENTITY
			origins = PackedVector3Array([box.position, box.position + box.size, box.position - Vector3.ONE * 1e-6, box.position + box.size + Vector3.ONE * 1e-6, Vector3(NAN, 0.0, 0.0), box.position + Vector3(box.size.x, 0.0, 0.0), box.get_center()])
			n = origins.size()
			on.resize(n)
			clip.resize(n)
			on.fill(1)
			for i in n:
				clip[i] = 1 if rng.randf() < 0.5 else 0
		# The outline: none, or a table like the one the shell was laid out by (rows of 64 ways, how far each reaches; some rows and ways empty), as an int or a float margin.
		var ol := {}
		var pad := 0.01
		if k % 4 != 0:
			var rows := rng.randi_range(8, 40)
			var margin := rng.randi_range(0, 4)
			var fsz := rng.randf_range(0.01, 0.06)
			var tab := PackedFloat32Array()
			tab.resize(rows * 64)
			for r in rows:
				var reach := rng.randf_range(0.04, 0.3) if rng.randf() > 0.2 else 0.0
				for a in 64:
					tab[r * 64 + a] = reach * rng.randf_range(0.5, 1.0) if rng.randf() > 0.1 else 0.0
			# (His middle at about the middle of the rows, where the plates are.)
			ol = {"tab": tab, "rows": rows, "margin": margin if k % 8 != 1 else float(margin), "fsz": fsz, "h": Vector3(rng.randf_range(0.0, 0.3), fsz * float(rows - margin) * 0.5 + rng.randf_range(-0.03, 0.03), rng.randf_range(0.0, 0.3)), "thick": rng.randf_range(0.0, 0.03)}
			pad = rng.randf_range(0.0, 0.03)
			with_outline += 1
			if k % 16 == 2:
				# (the table shorter than the rows say: the script reads past it as the core does, a zero)
				ol["tab"] = tab.slice(0, tab.size() * 3 / 4)
		var want := PackedInt32Array()
		for i in n:
			if on[i] == 0:
				continue
			var q: Vector3 = to_t * origins[i]
			var inside := box.has_point(q) and (ol.is_empty() or _in_outline_script(ol, q, pad))
			if inside:
				in_out += 1
				if not ol.is_empty():
					outlined_in += 1
			elif not ol.is_empty() and box.has_point(q):
				outlined_out += 1
			if inside != (clip[i] == 1):
				want.append(i)
		asked += n
		flips += want.size()
		var got: PackedInt32Array = nc.clip_plates_flip(to_t, origins, on, clip, box, ol, pad)
		if got != want:
			off += 1
	t.eq(off, 0, "the same plates for the clip to change as the script's lines name")
	t.check(asked > 3000 and flips > 800 and in_out > 400 and with_outline > 100 and outlined_in > 100 and outlined_out > 100, "what was asked covers the cases (%d plates, %d to turn, %d inside, %d outlines, %d of them inside the outline and %d in the box and outside it)" % [asked, flips, in_out, with_outline, outlined_in, outlined_out])
	# (Arrays that are not the plates': the script was given nothing to decide on, and now nothing is named; the older call names every place.)
	t.check(nc.clip_plates_flip(Transform3D.IDENTITY, PackedVector3Array(), PackedByteArray([1, 1, 0]), PackedByteArray([0, 0, 0]), AABB(), {}, 0.0).is_empty(), "against arrays of another length, none")

## FineArmor.in_outline, but as one that cannot stop on a table that is too short (the script's own reads past the end of one: an error and a nil; the core takes a zero).
func _in_outline_script(ol: Dictionary, q: Vector3, pad: float) -> bool:
	var tab: PackedFloat32Array = ol.tab
	var need: int = int(ol.rows) * 64
	if tab.size() < need:
		var full := tab.duplicate()
		full.resize(need)
		var ol2 := ol.duplicate()
		ol2["tab"] = full
		return FineArmor.in_outline(ol2, q, pad)
	return FineArmor.in_outline(ol, q, pad)

## What is asked of every body in one go, in the C++ core (VoxelCore.pack_parts, record_vel; docs/PERF_RESEARCH.md, section 20): a snapshot's rows of the bodies' places are to the
## byte what Match.pack_xf writes (the bodies of a fight, and places and turns made up: far off, scaled, mirrored, turned right round), and the velocities the combat keeps of
## every body before a step are the same entries in the same order (a chain's head and what lies loose with them).
func test_native_bulk_matches_the_gdscript() -> void:
	if Greedy.core() == null or not Greedy.bulk_ok:
		t.check(true, "no native core with the calls for every body built: the GDScript lines run")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 5, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "scutum"}})
	var arms := [{"main": "flail"}, {"main": "spear"}, {"main": "gladius", "off": "scutum"}]
	for i in arms.size():
		m.spawn_fighter({"kind": "bot", "name": "V%d" % i, "loadout": arms[i], "team": 1, "pos": Vector3(-2.0 + 2.0 * i, 0, 3.0), "yaw": PI})
	m.spawn_loose_weapon(Data.preset("flail"), Vector3(4, 1.5, 0))
	m.spawn_loose_weapon(Data.preset("gladius"), Vector3(-4, 1.5, 0))
	var bad := []
	var rows := 0
	var vels := 0
	var vels_all := 0
	var moving := 0
	var chains := 0
	for k in 480:
		await get_tree().physics_frame
		if k % 4 != 0:
			continue
		for e in m.entities:
			if not is_instance_valid(e.f):
				continue
			var bodies: Array = e.f.parts.duplicate()
			for w in e.f.weapons.values():
				if w:
					bodies.append(w)
			Greedy.bulk_ok = false
			var a := Match.pack_parts(bodies)
			Greedy.bulk_ok = true
			var b := Match.pack_parts(bodies)
			rows += bodies.size()
			if a != b or b.size() != bodies.size() * 14:
				bad.append("rows, k=%d" % k)
		# (The velocities three ways: every line in script, the bodies listed in script and recorded in one call, and the lists given to the core to be gone over there.)
		var all_ok: bool = Greedy.vel_all_ok
		Greedy.bulk_ok = false
		Greedy.vel_all_ok = false
		m.combat.record_velocities()
		var va: Dictionary = m.combat.vel.duplicate(true)
		Greedy.bulk_ok = true
		m.combat.record_velocities()
		var vb: Dictionary = m.combat.vel.duplicate(true)
		vels += vb.size()
		if va.keys() != vb.keys() or va.values() != vb.values():
			bad.append("velocities, k=%d" % k)
		if all_ok:
			Greedy.vel_all_ok = true
			# (A man gone from the list and a weapon too, as the match leaves them for a frame.)
			var gone := Node.new()
			m.combat.fighters.append(gone)
			gone.free()
			var dropped := Node.new()
			m.combat.loose_weapons.append(dropped)
			dropped.free()
			m.combat.record_velocities()
			m.combat.fighters.pop_back()
			var vc: Dictionary = m.combat.vel
			vels_all += vc.size()
			if va.keys() != vc.keys() or va.values() != vc.values():
				bad.append("velocities of every body in one call, k=%d" % k)
		Greedy.vel_all_ok = all_ok
		for v in vb.values():
			if (v[0] as Vector3).length() > 0.3:
				moving += 1
		for e in m.entities:
			if is_instance_valid(e.f):
				for w in e.f.weapons.values():
					if w and w.chain_head and vb.has(w.chain_head.get_instance_id()):
						chains += 1
		for w in m.combat.loose_weapons:
			if is_instance_valid(w) and w.chain_head and vb.has(w.chain_head.get_instance_id()):
				chains += 1
	# Places and turns made up.
	var probe := Node3D.new()
	add_child(probe)
	var made := 0
	var clamped := 0
	for k in 900:
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if axis.length() < 0.05:
			axis = Vector3.UP
		var bs := Basis(Quaternion(axis.normalized(), rng.randf_range(-PI, PI)))
		match k % 12:
			1: bs = Basis.IDENTITY
			2: bs = Basis(Quaternion([Vector3.RIGHT, Vector3.UP, Vector3.BACK][(k / 12) % 3], PI))
			3: bs = bs.scaled(Vector3(rng.randf_range(0.3, 2.5), rng.randf_range(0.3, 2.5), rng.randf_range(0.3, 2.5)))
			4: bs = bs.scaled(Vector3(-1, 1, 1))
			5: bs = bs.scaled(Vector3(-1.3, -0.7, -1.1))
			6: bs = Basis(bs.x + Vector3(0.02, -0.01, 0.015), bs.y, bs.z + Vector3(0.0, 0.03, 0.0))
			7: bs = Basis(Quaternion(axis.normalized(), PI - rng.randf_range(0.0, 0.0002)))
		var r := 8.0
		if k % 6 == 0:
			r = 150.0
		elif k % 6 == 1:
			r = 0.004
		var org := Vector3(rng.randf_range(-r, r), rng.randf_range(-r, r), rng.randf_range(-r, r))
		if k % 10 == 9:
			org = (org * 512.0).round() / 512.0 + Vector3(0.5, -0.5, 1.5) / 512.0   # (on the halves: where the rounding turns)
		probe.global_transform = Transform3D(bs, org)
		Greedy.bulk_ok = false
		var a := Match.pack_parts([probe, probe])
		Greedy.bulk_ok = true
		var b := Match.pack_parts([probe, probe])
		made += 1
		if absi(b.decode_s16(0)) == 32767:
			clamped += 1
		if a != b:
			bad.append("a made-up place, k=%d" % k)
	Greedy.bulk_ok = true
	probe.queue_free()
	m.queue_free()
	t.check(bad.is_empty(), "the calls for every body are the script's lines to the byte (%d rows, %d velocities, %d made-up places; unlike: %s)" % [rows, vels, made, str(bad.slice(0, 6))])
	t.check(rows > 5000 and vels > 5000 and moving > 500 and chains > 100 and clamped > 30, "what was asked covers the cases (%d rows, %d velocities, %d of them moving, %d chain heads, %d places past the int16's end)" % [rows, vels, moving, chains, clamped])
	t.check(not Greedy.vel_all_ok or vels_all == vels, "and the core's own lists gave as many velocities as the script's (%d and %d)" % [vels_all, vels])

## The ground under a man and the height his hips ride at in the C++ core (VoxelCore.ground_ride for Fighter._ground_ride; docs/PERF_RESEARCH.md, section 23): from the same
## man in the same state the script's lines and the core's say the same of whether he stands on it, leave the hips' height, the stoop and the knees' give the same and every
## part of him the same speed, to the bit. Standing, getting up and lying; feet planted, stepping and none; on a ledge, sunk in, both soles in the air; a big man stooping;
## over the sand and over a man lying under his feet, dead and alive.
func test_native_ground_ride_matches_the_gdscript() -> void:
	if Greedy.core() == null or not Greedy.ride_ok:
		t.check(true, "no native core with the hips' height built: the GDScript lines run")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 57
	var bad := []
	var stood := 0
	var in_air := 0
	var held_up := 0
	var let_down := 0
	var stooped := 0
	var on_ledge := 0
	var asked := 0
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 5, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "scutum"}})
	for k in 30:
		await get_tree().physics_frame
	var f: Fighter = m.me.f
	var e2m = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": f.torso.global_position + Vector3(0.1, 0, 0.1), "yaw": 0.0})
	e2m.erase("bot")
	e2m.drive = func(_e): return {}
	var under: Fighter = e2m.f
	await get_tree().physics_frame
	PhysicsServer3D.body_set_state(under.torso.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(f.torso.global_position.x, f.ground_level + 0.13, f.torso.global_position.z)))
	under.torso.linear_velocity = Vector3.ZERO
	under.torso.angular_velocity = Vector3.ZERO
	var rv := func(r: float) -> Vector3: return Vector3(rng.randf_range(-r, r), rng.randf_range(-r, r), rng.randf_range(-r, r))
	var bodies: Array = f.parts.duplicate()
	var s_was: float = f.S
	var state_was: String = f.state
	var t_pos: Vector3 = f.torso.global_position
	var t_rot: Quaternion = PD.quat_of(f.torso)
	f._ground_ray(f.space, t_pos)
	for k in 1600:
		var speeds := []
		for i in bodies.size():
			speeds.append(rv.call(1.5) as Vector3)
			speeds.append(rv.call(3.0) as Vector3)
		f.S = 1.5 if k % 10 == 0 else s_was
		var rising := k % 9 == 0
		var st := "rising" if rising else ("down" if k % 14 == 1 else "stand")
		var feet_in := {}
		for sd in ["L", "R"]:
			var sole: Vector3 = f.by_name["shin" + sd].global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
			# (A foot's plant about its sole: by turns well under it, sunk in; up on a ledge; none at all; stepping.)
			var drop := rng.randf_range(-0.03, 0.03)
			if k % 7 == (0 if sd == "L" else 3):
				drop = rng.randf_range(0.04, 0.12)
			elif k % 5 == 2:
				drop = rng.randf_range(-0.08, -0.02)   # (both soles up off their plants)
			feet_in[sd] = {"anchor": Vector3(sole.x + rng.randf_range(-0.2, 0.2), sole.y + drop, sole.z + rng.randf_range(-0.2, 0.2)), "from": sole, "swing": k % (3 if sd == "L" else 5) == 0, "s": 0.4, "land": sole, "half": 0, "slip": 0.0} if k % (11 if sd == "L" else 13) != 0 else null
		var sole_l: Vector3 = f.by_name["shinL"].global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
		# (The ground found under the trunk: about the soles, by turns well under them, or so far down that he is in the air.)
		var gy: float = sole_l.y + rng.randf_range(-0.04, 0.04) - (rng.randf_range(0.11, 0.2) * f.S if k % 6 == 0 else 0.0) - (0.9 if k % 17 == 0 else 0.0) + (rng.randf_range(0.1, 0.45) if k % 4 == 3 else 0.0)
		var hit := {"position": Vector3(t_pos.x, gy, t_pos.z), "collider": null}
		var e2 := rng.randf_range(0.0, 1.0)
		var walk_amt := rng.randf_range(0.0, 1.0)
		var crouch_h := rng.randf_range(0.0, 1.0) if k % 4 == 0 else 0.0
		var one_leg := k % 16 == 0
		var support := rng.randf_range(0.2, 1.0) if k % 12 != 0 else 0.0
		var bob := rng.randf_range(0.0, 0.03)
		var lv0: Vector3 = speeds[bodies.find(f.torso) * 2]
		var standing := st != "down"
		var total_mass := rng.randf_range(60.0, 90.0)
		var dt := 1.0 / 120.0 if k % 6 != 0 else rng.randf_range(0.005, 0.02)
		var hop := rng.randf_range(0.01, 1.0) if k % 15 == 0 else 0.0
		var jump := 0.2 if k % 19 == 0 else 0.0
		var stoop_in := rng.randf_range(0.03, 0.9) if k % 5 == 0 else 0.0
		var lowered_in := rng.randf_range(0.6, 1.3) if k % 8 == 0 else -1.0
		var stance_in := rng.randf_range(0.8, 1.2) if k % 3 != 0 else 0.0
		var sag := rng.randf_range(0.0, 0.05) if k % 2 == 0 else 0.0
		var air := rng.randf_range(0.0, 0.3)
		under.state = "stand" if k % 3 != 0 else "dead"
		var res := []
		for native in [false, true]:
			f.state = st
			f.feet["L"] = (feet_in.L as Dictionary).duplicate(true) if feet_in.L != null else null
			f.feet["R"] = (feet_in.R as Dictionary).duplicate(true) if feet_in.R != null else null
			f.hop_phase = hop
			f.jump_t = jump
			f.stoop = stoop_in
			f.lowered = lowered_in
			f.stance_h = stance_in
			f.land_sag = sag
			f.air_time = air
			f.ground_level = -99.0
			_arm_set_speeds(bodies, speeds)
			var grounded: bool = f._ground_ride_native(hit, t_pos, t_rot, rising, e2, walk_amt, crouch_h, one_leg, support, bob, lv0, standing, total_mass, dt) if native else f._ground_ride(hit, t_pos, t_rot, rising, e2, walk_amt, crouch_h, one_leg, support, bob, lv0, standing, total_mass, dt)
			res.append([_arm_live(bodies), grounded, f.ground_level, f.stance_h, f.lowered, f.land_sag, [f.feet.L, f.feet.R]])
		var what := ""
		if res[0][0] != res[1][0]:
			what = "speeds"
		for j in range(1, 7):
			if res[0][j] != res[1][j]:
				what += " %s" % ["", "grounded", "ground_level", "stance_h", "lowered", "land_sag", "feet"][j]
		if what != "":
			bad.append("k=%d:%s (%s | %s)" % [k, what, str(res[0].slice(1, 6)), str(res[1].slice(1, 6))])
		var got: Array = res[1][0]
		var ti := bodies.find(f.torso) * 2
		if res[1][1]:
			stood += 1
		else:
			in_air += 1
		if (got[ti] as Vector3) != (speeds[ti] as Vector3):
			held_up += 1
		for i in bodies.size():
			if bodies[i] != f.torso and (got[i * 2] as Vector3) != (speeds[i * 2] as Vector3):
				let_down += 1
				break
		if float(res[1][4]) >= 0.0:
			stooped += 1
		if res[1][1] and float(t_pos.y - gy) >= float(f.torso_y) * 1.2:
			on_ledge += 1
		if st == "stand" and hop <= 0.0 and ((feet_in.L == null or feet_in.L.swing) or (feet_in.R == null or feet_in.R.swing)):
			asked += 1
		_arm_set_speeds(bodies, speeds.map(func(_v): return Vector3.ZERO))
	under.state = "stand"
	f.S = s_was
	f.state = state_was
	f.hop_phase = 0.0
	f.jump_t = 0.0
	f.stoop = 0.0
	f.lowered = -1.0
	f.land_sag = 0.0
	f.air_time = 0.0
	f.feet["L"] = null
	f.feet["R"] = null
	m.queue_free()
	await get_tree().physics_frame
	t.check(bad.is_empty(), "the core's height of the hips leaves what the script's does, to the bit (%d differ: %s)" % [bad.size(), "; ".join(PackedStringArray(bad.slice(0, 3)))])
	t.check(stood > 800 and in_air > 80 and held_up > 400 and let_down > 20 and stooped > 20 and asked > 400 and on_ledge > 20, "and it was at work: %d of 1600 stood on the ground and %d did not; the trunk held up in %d, every part let down (both soles in the air) in %d, a big man's stoop in %d, a foot off its plant (the ground under it asked) in %d, held by a foot on a ledge in %d" % [stood, in_air, held_up, let_down, stooped, asked, on_ledge])

## A standing leg's whole step in the C++ core (VoxelCore.leg_plant: Fighter._leg_plant and the leg's end after it in one call; docs/PERF_RESEARCH.md, section 23): from the
## same man in the same state the script's lines and the core's leave the foot's record the same (where it stands, where it steps from and to, how far through its step),
## the other foot's untouched, the trunk, the thigh and the shin the same speeds and the knees' give the same, to the bit. Feet standing, stepping, landing, slipping,
## hopping, left behind and gathered in; over the sand and over a man lying under them, alive and dead.
func test_native_leg_plant_matches_the_gdscript() -> void:
	if Greedy.core() == null or not Greedy.plant_ok:
		t.check(true, "no native core with the leg's step built: the GDScript lines run")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var bad := []
	var stepping := 0
	var landed := 0
	var lifted := 0
	var hopped := 0
	var pushed := 0
	var on_body := 0
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 5, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "scutum"}})
	for k in 30:
		await get_tree().physics_frame
	var f: Fighter = m.me.f
	var e2 = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": f.torso.global_position + Vector3(0.1, 0, 0.1), "yaw": 0.0})
	e2.erase("bot")
	e2.drive = func(_e): return {}
	var under: Fighter = e2.f
	await get_tree().physics_frame
	# (His trunk laid flat under the man's feet: what the rays for the ground meet there.)
	# (Put there in the physics' own record, which is what a ray asks: a body's place set on its node reaches it at the next step.)
	PhysicsServer3D.body_set_state(under.torso.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(f.torso.global_position.x, f.ground_level + 0.13, f.torso.global_position.z)))
	under.torso.linear_velocity = Vector3.ZERO
	under.torso.angular_velocity = Vector3.ZERO
	var probe_ray := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.DOWN, VoxelPart.LAYER_BODY | VoxelPart.LAYER_CORPSE, f._own_rids())
	var on_live := 0
	var rv := func(r: float) -> Vector3: return Vector3(rng.randf_range(-r, r), rng.randf_range(-r, r), rng.randf_range(-r, r))
	for k in 1600:
		var side := "L" if k % 2 == 0 else "R"
		var os := "R" if side == "L" else "L"
		var thigh: VoxelPart = f.by_name["thigh" + side]
		var shin: VoxelPart = f.by_name["shin" + side]
		var bodies := [f.torso, thigh, shin]
		var speeds := []
		for i in 3:
			speeds.append(rv.call(1.5) as Vector3)
			speeds.append(rv.call(5.0) as Vector3)
		var sole: Vector3 = shin.global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
		var o_sole: Vector3 = f.by_name["shin" + os].global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
		var on_sand := Vector3(sole.x, f.ground_level, sole.z)
		var ft := {"anchor": on_sand + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.02, 0.02) - (0.2 if k % 9 == 0 else 0.0), rng.randf_range(-0.2, 0.2)), "from": on_sand + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.0, 0.12) if k % 5 == 0 else 0.0, rng.randf_range(-0.2, 0.2)),
			"swing": k % 3 == 0, "s": rng.randf_range(0.0, 1.0) if k % 4 != 0 else 0.98, "land": on_sand + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)), "half": rng.randi_range(-1, 3), "slip": rng.randf_range(0.0, 0.6) if k % 6 == 0 else 0.0}
		if k % 7 == 0:
			ft["gather"] = k % 14 == 0
		if k % 8 == 0:
			ft["late"] = rng.randf_range(0.0, 0.3)
		if k % 5 == 1:
			ft["lift"] = rng.randf_range(0.0, 0.1)
		if k % 3 != 1:
			ft["target_y"] = sole.y + rng.randf_range(-0.08, 0.04)
		var oft = {"anchor": Vector3(o_sole.x, f.ground_level + rng.randf_range(-0.03, 0.03), o_sole.z), "from": o_sole, "swing": k % 5 == 0, "s": 0.4, "land": o_sole, "half": 0, "slip": 0.0} if k % 11 != 0 else null
		var leg_now := {side: rng.randf_range(0.0, 1.0) if k % 10 != 0 else 0.05, os: rng.randf_range(0.0, 1.0) if k % 13 != 0 else 0.05}
		var leg_f: float = leg_now[side]
		var strength := maxf(0.15, leg_f)
		var t_pos: Vector3 = f.torso.global_position
		var t_rot: Quaternion = PD.quat_of(f.torso)
		var yaw_q := Quaternion(Vector3.UP, f.yaw + rng.randf_range(-0.4, 0.4))
		var t_inv := t_rot.inverse()
		var ground_y: float = f.ground_level + rng.randf_range(-0.03, 0.06)
		var h_speed := rng.randf_range(0.0, 4.5) if k % 4 != 1 else rng.randf_range(0.0, 0.25)
		var sprint := k % 6 == 0
		var step_len: float = (minf(float(Fighter.GAIT.run_stride), 0.3 + 0.17 * h_speed) if sprint else minf(float(Fighter.GAIT.walk_stride), 0.28 + 0.12 * h_speed)) * f.S
		var mdir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		var move_dir := mdir.normalized() if k % 4 != 1 else Vector3.ZERO
		var hop_k := rng.randf_range(0.0, 1.0)
		var wants_move := k % 3 != 2
		var move_amt: float = minf(1.0, h_speed / 2.5)
		var leg_avg := rng.randf_range(0.3, 1.0)
		var dt := 1.0 / 120.0 if k % 6 != 0 else rng.randf_range(0.005, 0.02)
		var hip := t_pos + t_rot * (thigh.pa)
		var l1 := 8 * Fighter.V * f.S
		var l2 := 8 * Fighter.V * f.S
		var gait := rng.randf_range(0.0, 20.0)
		var hop := rng.randf_range(0.01, 1.0) if k % 12 == 0 else 0.0
		var vs := Vector3(rng.randf_range(-3, 3), rng.randf_range(-0.5, 0.5), rng.randf_range(-3, 3))
		var sag := rng.randf_range(0.0, 0.05) if k % 2 == 0 else 0.0
		var stance_was: Vector2 = f.stance[side]
		var st := Vector2(rng.randf_range(-0.2, 0.3), rng.randf_range(-0.05, 0.15))
		f.jump_t = 0.2 if k % 19 == 0 else 0.0
		# (The other man underfoot by turns a live one, who is not ground, and a dead one, who is: what a ray hits there is asked of the script.)
		under.state = "stand" if k % 3 != 0 else "dead"
		f._ground_ray(f.space, t_pos)
		probe_ray.from = Vector3(sole.x, t_pos.y, sole.z)
		probe_ray.to = probe_ray.from + Vector3(0, -2.2 * f.S, 0)
		if f.space.intersect_ray(probe_ray):
			if under.alive:
				on_live += 1
			else:
				on_body += 1
		var res := []
		for native in [false, true]:
			f.feet[side] = ft.duplicate(true)
			f.feet[os] = (oft as Dictionary).duplicate(true) if oft != null else null
			f.gait_phase = gait
			f.hop_phase = hop
			f.v_smooth = vs
			f.land_sag = sag
			f.stance[side] = st
			_arm_set_speeds(bodies, speeds)
			if native:
				f._leg_plant_native(side, thigh, shin, strength, leg_f, leg_now, t_pos, t_rot, yaw_q, ground_y, h_speed, step_len, move_dir, hop_k, sprint, wants_move, move_amt, leg_avg, dt)
			else:
				var pose := f._leg_plant(side, thigh, shin, leg_f, leg_now, hip, t_pos, yaw_q, t_inv, ground_y, h_speed, step_len, move_dir, hop_k, sprint, wants_move, move_amt, leg_avg, l1, l2, dt)
				f._leg_end(side, thigh, shin, pose[0], pose[1], strength, leg_f, false, true, true, false, true, ground_y, dt)
			res.append([_arm_live(bodies), (f.feet[side] as Dictionary).duplicate(true), (f.feet[os] as Dictionary).duplicate(true) if f.feet[os] != null else null, f.land_sag])
		f.stance[side] = stance_was
		if ft.swing:
			stepping += 1
			if not res[1][1].swing:
				landed += 1
		elif res[1][1].swing:
			lifted += 1
		if hop > 0.0:
			hopped += 1
		if res[1][0] != speeds:
			pushed += 1
		var what := ""
		if res[0][1] != res[1][1]:
			what = "foot"
			for key in res[0][1]:
				if not res[1][1].has(key) or res[0][1][key] != res[1][1][key]:
					what += " " + str(key)
			for key in res[1][1]:
				if not res[0][1].has(key):
					what += " +" + str(key)
		elif res[0][0] != res[1][0]:
			what = "speeds"
			for i in 6:
				if res[0][0][i] != res[1][0][i]:
					what += " %d" % i
		elif res[0][2] != res[1][2]:
			what = "other foot"
		elif res[0][3] != res[1][3]:
			what = "land_sag"
		if what != "":
			bad.append("k=%d: %s" % [k, what])
		_arm_set_speeds(bodies, speeds.map(func(_v): return Vector3.ZERO))
	under.state = "stand"
	f.jump_t = 0.0
	f.hop_phase = 0.0
	f.land_sag = 0.0
	f.feet["L"] = null
	f.feet["R"] = null
	m.queue_free()
	await get_tree().physics_frame
	t.check(bad.is_empty(), "the core's step of a standing leg leaves what the script's does, to the bit (%d differ: %s)" % [bad.size(), ", ".join(PackedStringArray(bad.slice(0, 5)))])
	t.check(pushed > 1500 and stepping > 400 and landed > 100 and lifted > 100 and hopped > 80 and on_body > 300 and on_live > 600, "and it was at work: %d of 1600 pushed a body; %d feet stepping (%d set down), %d lifted to step, %d hopping; %d over a dead man lying under them (ground) and %d over a live one (not)" % [pushed, stepping, landed, lifted, hopped, on_body, on_live])


## The end of a leg's step in the C++ core (VoxelCore.leg_tail; docs/PERF_RESEARCH.md, section 20): from the same man in the same state the script's own lines and the
## core's leave his trunk, the thigh and the shin the same speeds and the foot's plant the same, to the bit.
func test_native_leg_end_matches_the_gdscript() -> void:
	if Greedy.core() == null or not Greedy.leg_ok:
		t.check(true, "no native core with the leg's end built: the GDScript lines run")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var bad := []
	var held := 0
	var capped := 0
	var pushed := 0
	var raised := 0
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 5, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "scutum"}})
	for k in 30:
		await get_tree().physics_frame
	var f: Fighter = m.me.f
	var rv := func(r: float) -> Vector3: return Vector3(rng.randf_range(-r, r), rng.randf_range(-r, r), rng.randf_range(-r, r))
	for k in 900:
		var side := "L" if k % 2 == 0 else "R"
		var thigh: VoxelPart = f.by_name["thigh" + side]
		var shin: VoxelPart = f.by_name["shin" + side]
		var bodies := [f.torso, thigh, shin]
		var speeds := []
		for i in 3:
			speeds.append(rv.call(1.5) as Vector3)
			speeds.append(rv.call(5.0) as Vector3)
		var sole: Vector3 = shin.global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
		# (The foot's plant about the sole, by turns well under it: the ground under the foot is asked then. A stepping foot by turns, its step's height about the sole's.)
		var ft := {"anchor": sole + Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.03, 0.01) - (0.2 if k % 9 == 0 else 0.0), rng.randf_range(-0.1, 0.1)), "from": sole, "swing": k % 3 == 0, "s": 0.3, "land": sole, "half": 0, "slip": 0.0}
		if k % 3 == 0 and k % 4 != 0:
			ft["target_y"] = sole.y + rng.randf_range(-0.08, 0.04)
		var thigh_q := Quaternion(Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf_range(-0.5, 0.5)), rng.randf_range(-1.0, 0.6))
		var bend := rng.randf_range(0.0, 1.8)
		var strength := rng.randf_range(0.03, 1.0)
		var leg_f := rng.randf_range(0.0, 1.0)
		var kicking := k % 11 == 0
		var standing := k % 13 != 0
		var grounded := k % 7 != 0
		var rising := k % 17 == 0
		var on_hit := k % 5 != 0
		var ground_y: float = f.ground_level + rng.randf_range(-0.03, 0.06)
		var dt := 1.0 / 120.0 if k % 6 != 0 else rng.randf_range(0.005, 0.02)
		f.kick_wn = 1.5 if k % 22 == 0 else 1.0
		f.jump_t = 0.2 if k % 19 == 0 else 0.0
		var res := []
		for native in [false, true]:
			f.feet[side] = ft.duplicate(true) if k % 23 != 0 else null
			_arm_set_speeds(bodies, speeds)
			Greedy.leg_ok = native
			f._leg_end(side, thigh, shin, thigh_q, bend, strength, leg_f, kicking, standing, grounded, rising, on_hit, ground_y, dt)
			res.append([_arm_live(bodies), (f.feet[side] as Dictionary).duplicate(true) if f.feet[side] != null else null])
		Greedy.leg_ok = true
		if res[0][0] != res[1][0]:
			bad.append("speeds, k=%d" % k)
		elif res[0][1] != res[1][1]:
			bad.append("the foot, k=%d" % k)
		if res[1][0] != speeds:
			pushed += 1
		var down: bool = standing and grounded and not kicking and not rising and k % 23 != 0
		if down and not ft.swing:
			held += 1
			if res[1][1] != null and (res[1][1].anchor as Vector3) != (ft.anchor as Vector3):
				raised += 1
		elif down and ft.has("target_y") and f.jump_t <= 0.0:
			capped += 1
		_arm_set_speeds(bodies, speeds.map(func(_v): return Vector3.ZERO))
	f.kick_wn = 1.0
	f.jump_t = 0.0
	f.feet["L"] = null
	f.feet["R"] = null
	m.queue_free()
	await get_tree().physics_frame
	t.check(bad.is_empty(), "the core's end of a leg's step leaves what the script's does, to the bit (%d differ: %s)" % [bad.size(), ", ".join(PackedStringArray(bad.slice(0, 6)))])
	t.check(pushed > 800 and held > 250 and capped > 60 and raised > 15, "and it was at work: %d of 900 steps pushed a body, %d held a planted foot (%d of them stood on what lay under it), %d kept a stepping foot down" % [pushed, held, raised, capped])

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
	var count := 0
	func set_instance_transform(i: int, x: Transform3D) -> void:
		got[i] = x
	func get_instance_count() -> int:
		return count

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
	var near_off := 0
	var near_asked := 0
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
		if nc.has_method("guard_cut_near"):
			# (The same worked out round the voxels under the arm only, from the guard's own base: masks of every thickness.)
			var none := PackedByteArray()
			none.resize(pts.size())
			var base: PackedByteArray = nc.guard_cut(none, flat, at, lk[1])
			for dens in [0.0, 0.01, 0.03, 0.1, 0.3, 0.6, 0.9, 1.0]:
				var mk := PackedByteArray()
				mk.resize(pts.size())
				for i in pts.size():
					mk[i] = 1 if rng.randf() < dens else 0
				near_asked += 1
				if nc.guard_cut_near(mk, flat, at, lk[1], base) != Fighter._cut_off(mk.duplicate(), lk[0], lk[1]):
					near_off += 1
		var turned := PackedInt32Array()
		for i in pts.size():
			if mask[i] != want[i]:
				turned.append(i)
		if nc.bytes_changed(mask, want) != turned:
			chg_off += 1
	t.eq(off, 0, "the same voxels of a guard within an arm's reach")
	t.eq(cut_off, 0, "the same cut off by them from the rest of the shell")
	if nc.has_method("guard_cut_near"):
		# A guard as the voxels of a shell are laid (a lattice, each voxel next to twenty-six; the outer rim held on the rest of the shell): small masks, the likeliest.
		var pts2 := PackedVector3Array()
		var rest2 := PackedVector3Array()
		var hv := 0.01
		for ix in 9:
			for iy in 7:
				for iz in 4:
					pts2.append(Vector3(ix, iy, iz) * hv)
		for iy in 7:
			for iz in 4:
				rest2.append(Vector3(-1, iy, iz) * hv)   # (held on the shell at one end only: a wall across it cuts the rest off)
		var lk2 := Fighter._guard_links(pts2, rest2, hv)
		var flat2 := PackedInt32Array()
		var at2 := PackedInt32Array([0])
		for nb in lk2[0]:
			flat2.append_array(nb)
			at2.append(flat2.size())
		var none2 := PackedByteArray()
		none2.resize(pts2.size())
		var base2: PackedByteArray = nc.guard_cut(none2, flat2, at2, lk2[1])
		var held := 0
		for b in lk2[1]:
			held += b
		t.check(held > 10 and held < pts2.size() / 2, "some of the lattice held on the shell (%d of %d)" % [held, pts2.size()])
		var lat_off := 0
		var orphaned := 0
		for k in 400:
			var mk2 := PackedByteArray()
			mk2.resize(pts2.size())
			var cnt := rng.randi_range(0, 40) if k % 4 else rng.randi_range(40, pts2.size())
			for c in cnt:
				mk2[rng.randi_range(0, pts2.size() - 1)] = 1
			if k % 2 == 0:
				# (A wall across the lattice, a layer thick, with a hole or two in it now and then.)
				var wx := rng.randi_range(1, 7)
				for i in pts2.size():
					if int(roundf(pts2[i].x / hv)) == wx:
						mk2[i] = 1
				for hole in rng.randi_range(0, 2) if k % 4 == 0 else 0:
					for i in pts2.size():
						if int(roundf(pts2[i].x / hv)) == wx and int(roundf(pts2[i].y / hv)) == rng.randi_range(0, 6) and int(roundf(pts2[i].z / hv)) == rng.randi_range(0, 3):
							mk2[i] = 0
			near_asked += 1
			var want2 := Fighter._cut_off(mk2.duplicate(), lk2[0], lk2[1])
			if nc.guard_cut_near(mk2, flat2, at2, lk2[1], base2) != want2 or nc.guard_cut(mk2, flat2, at2, lk2[1]) != want2:
				lat_off += 1
			if want2 != mk2:
				orphaned += 1
		t.eq(lat_off, 0, "on a lattice, the same cut off by a few voxels or by many")
		t.check(orphaned > 20, "masks that cut some voxels off from the shell (%d of 400)" % orphaned)
	t.eq(near_off, 0, "the same cut off as the whole guard's search finds, by the search round the voxels under the arm (%d masks)" % near_asked)
	t.eq(chg_off, 0, "and the same places where one mask is not the other")
	t.check(nc.bytes_changed(PackedByteArray([1]), PackedByteArray([1, 0, 1])) == PackedInt32Array([0, 1, 2]), "against a mask of another length, every place")
	# An arm's plates against the box of the chest's armour (Fighter._clip_arm_armor): the plates the script has anything to decide on.
	if nc.has_method("clip_plates"):
		var plate_off := 0
		var asked := 0
		for k in 60:
			var n := rng.randi_range(0, 220)
			var origins := PackedVector3Array()
			var on := PackedByteArray()
			var clip := PackedByteArray()
			on.resize(n)
			clip.resize(n)
			for i in n:
				origins.append(rv.call(0.15))
				on[i] = 0 if rng.randf() < 0.15 else 1
				clip[i] = 1 if rng.randf() < 0.2 else 0
			var to_t := Transform3D(Basis(Quaternion((rv.call(1.0) as Vector3 + Vector3(0.01, 0, 0)).normalized(), rng.randf_range(-3.0, 3.0))), rv.call(0.2))
			var box := AABB(rv.call(0.2), Vector3(rng.randf_range(0.02, 0.4), rng.randf_range(0.02, 0.4), rng.randf_range(0.02, 0.4)))
			if k % 5 == 0:
				# (On the faces and corners of the box, and a hair outside them, in the box's own frame; and a point that is not a number.)
				to_t = Transform3D.IDENTITY
				origins = PackedVector3Array([box.position, box.position + box.size, box.position - Vector3.ONE * 1e-6, box.position + box.size + Vector3.ONE * 1e-6, Vector3(NAN, 0.0, 0.0), box.position + Vector3(box.size.x, 0.0, 0.0), box.get_center()])
				n = origins.size()
				on.resize(n)
				clip.resize(n)
				on.fill(1)
				clip.fill(0)
			var want := PackedInt32Array()
			for i in n:
				if on[i] == 0:
					continue
				if box.has_point(to_t * origins[i]) or clip[i] == 1:
					want.append(i)
			asked += want.size()
			var got: PackedInt32Array = nc.clip_plates(to_t, origins, on, clip, box)
			if got != want:
				plate_off += 1
		t.eq(plate_off, 0, "the same plates of an arm's armour for the script to decide on")
		t.check(asked > 500, "some plates in the box (%d)" % asked)
		t.check(nc.clip_plates(Transform3D.IDENTITY, PackedVector3Array(), PackedByteArray([1, 1, 0]), PackedByteArray([0, 0, 0]), AABB()) == PackedInt32Array([0, 1, 2]), "against arrays of another length, every place")
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

## A limb in armour bent at a break (VoxelPart._lay_bend): every plate of the piece set where the
## bend has it and every fine voxel of its shell with it, by the C++ core in one call
## (lay_plates), the same places as the script's (_bent, FineArmor.sync): plates knocked off and
## put away passed over, the shell's hidden voxels left hidden, each tile's place noted.
func test_native_bent_armour_matches_the_gdscript() -> void:
	var nc = Greedy.core()
	if nc == null or not nc.has_method("lay_plates"):
		t.check(true, "no native core built: the GDScript fallback runs")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 53
	var rv := func(r: float) -> Vector3: return Vector3(rng.randf_range(-r, r), rng.randf_range(-r, r), rng.randf_range(-r, r))
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 3, "decrees": [], "hazards": []})
	var off := 0
	var plates_set := 0
	var voxels_set := 0
	var hidden := 0
	var passed := 0
	for part_name in ["forearmR", "shinL", "upperArmL"]:
		var p: VoxelPart = m.me.f.by_name[part_name]
		p.set_kink(Vector3.ZERO, 0.8, 40)
		for trial in 5:
			p._sw_q = Quaternion((rv.call(1.0) as Vector3 + Vector3(0, 0.02, 0)).normalized(), rng.randf_range(0.05, 1.8))
			p._bend_x = p._bend_for(p._sw_q)
			var g := p._bend_geom()
			# A piece of sixty plates along the limb, a shell of some fine voxels over each.
			var base := []
			var on := PackedByteArray()
			var clip := PackedByteArray()
			var of := {}
			var rel := []
			var vclip := PackedByteArray()
			for ci in 60:
				var lp := Vector3(rng.randf_range(-p.half_ext.x, p.half_ext.x), rng.randf_range(-p.half_ext.y, p.half_ext.y), rng.randf_range(-p.half_ext.z, p.half_ext.z)) * 1.2
				base.append(Transform3D(Basis(Quaternion((rv.call(1.0) as Vector3 + Vector3(0.01, 0, 0)).normalized(), rng.randf_range(-3.0, 3.0))).scaled(Vector3.ONE * rng.randf_range(0.3, 1.0)), lp))
				on.append(0 if rng.randf() < 0.15 else 1)
				clip.append(1 if rng.randf() < 0.1 else 0)
				var over := []
				for q in rng.randi_range(0, 6):
					over.append(rel.size())
					rel.append(Transform3D(Basis(Quaternion((rv.call(1.0) as Vector3 + Vector3(0, 0.01, 0)).normalized(), rng.randf_range(-1.0, 1.0))).scaled(Vector3.ONE * rng.randf_range(0.2, 0.6)), rv.call(0.5)))
					vclip.append(1 if rng.randf() < 0.2 else 0)
				if not over.is_empty():
					of[ci] = over
			var sh := {"of": of, "rel": rel}
			var pk := FineArmor.bend_pack(sh, base.size())
			# As the script lays it.
			var want_plate := {}
			var want_voxel := {}
			var want_now := {}
			var layers := {}
			for ci in base.size():
				if on[ci] == 0 or clip[ci] == 1:
					passed += 1
					continue
				var bxf := p._bent(base[ci], g, layers)
				want_plate[ci] = bxf
				want_now[ci] = bxf
				for s in of.get(ci, []):
					var hide: bool = vclip[int(s)] == 1
					hidden += int(hide)
					want_voxel[int(s)] = Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO) if hide else bxf * (rel[int(s)] as Transform3D)
			var plates := Kept.new()
			plates.count = base.size()
			var shell := Kept.new()
			var now := {}
			nc.lay_plates(plates, shell, FineArmor.place_rows(base), on, clip, pk.of_at, pk.of, pk.rel, vclip, now, g[0], g[2], g[1], g[6], g[7], g[5], g[3], g[4], p._bend_x)
			plates_set += plates.got.size()
			voxels_set += shell.got.size()
			if plates.got.size() != want_plate.size() or shell.got.size() != want_voxel.size() or now.size() != want_now.size():
				off += 1
				continue
			for ci in want_plate:
				if not plates.got.has(ci) or plates.got[ci] != want_plate[ci] or now.get(ci) != want_now[ci]:
					off += 1
			for s in want_voxel:
				if not shell.got.has(s) or shell.got[s] != want_voxel[s]:
					off += 1
		p.set_kink(Vector3.ZERO, 0.0, 0)
	t.check(plates_set > 500 and voxels_set > 1500 and hidden > 100 and passed > 100, "plates and the fine voxels of their shells laid round the bend, some hidden, some passed over (%d, %d, %d, %d)" % [plates_set, voxels_set, hidden, passed])
	t.eq(off, 0, "every plate and every fine voxel of its shell set where the script sets it, to the float")
	m.queue_free()

## A bruise's swelling (FineBody.swell): the skin's fine voxels raised and made larger by the C++
## core (fine_swell), the same places and the same swelling as the script's, blow on blow up to
## the limit. (Without a screen a man has no drawing: one that keeps nothing stands in for it
## here, and what is held to is what the swelling keeps, fine.xf and fine.swell.)
func test_native_swelling_matches_the_gdscript() -> void:
	var nc = Greedy.core()
	if nc == null or not nc.has_method("fine_swell"):
		t.check(true, "no native core built: the GDScript fallback runs")
		return
	Physique.forced = "human"
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 5, "decrees": [], "hazards": []})
	var giant = m.spawn_fighter(m.enemy_spec({"e": "cyclops", "boss": true}, 0, 1))
	Physique.forced = ""
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var swollen := 0
	var full := 0
	var off := 0
	for p: VoxelPart in [m.me.f.torso, m.me.f.by_name["thighL"], m.me.f.by_name["forearmR"], giant.f.by_name["upperArmL"]]:
		var who := "%s %s" % [String(p.fighter.display_name), p.part_name]
		if not t.check(p.fine.has("body") and p.fine.get("nat", false), "%s: drawn fine, and the core reads its look" % who):
			continue
		var fine: Dictionary = p.fine
		var count := (fine.par as PackedInt32Array).size()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = count
		fine.mm = mm
		var lps := p.local_positions()
		var vox := p.vf * p.part_scale
		var blows := []
		for b in 7:
			# (Every third blow where the one before it fell: the swelling there at its limit.)
			var at: Vector3 = blows[b - 1][0] if b % 3 == 2 else lps[rng.randi_range(0, lps.size() - 1)]
			blows.append([at, vox * rng.randf_range(3.0, 6.5), rng.randf_range(0.3, 0.6)])
		var got := []
		for native in [true, false]:
			if fine.has("xf0"):
				fine.xf = (fine.xf0 as Array).duplicate()
				fine.swell = {}
			Greedy.use_native = native
			for b in blows:
				FineBody.swell(p, b[0], b[1], b[2])
			Greedy.use_native = true
			got.append([(fine.xf as Array).duplicate(), (fine.swell as Dictionary).duplicate()])
		fine.erase("mm")
		var xa: Array = got[0][0]
		var xb: Array = got[1][0]
		var sa: Dictionary = got[0][1]
		var sb: Dictionary = got[1][1]
		if not t.check(xa.size() == count and xb.size() == count and sa.size() == sb.size(), "%s: as many fine voxels swollen by the core as by the script (%d, %d)" % [who, sa.size(), sb.size()]):
			continue
		for s in count:
			if (xa[s] as Transform3D) != (xb[s] as Transform3D):
				off += 1
		for s in sb:
			if not sa.has(s) or float(sa[s]) != float(sb[s]):
				off += 1
			swollen += 1
			if float(sb[s]) >= FineBody.SWELL_MAX:
				full += 1
	t.check(swollen > 400 and full > 10, "fine voxels swollen by the blows, some to the limit (%d, %d)" % [swollen, full])
	t.eq(off, 0, "every fine voxel raised where the script raises it and swollen as much, to the float")
	m.queue_free()

## A man and a beast as they are first made (VoxelPart.setup, FineBody.build): where each voxel
## is, the maps of its cells, its shading, its drawing and its fine voxels' own colours, by the
## C++ core the same as by the script, number for number; and one made again of what was kept of
## the first (Fighter._listed, Beast._listed_beasts) the same as one made anew. Then, cut into:
## the maps and the shading of a part with voxels gone.
func test_native_build_matches_the_gdscript() -> void:
	var nc = Greedy.core()
	if nc == null or not nc.has_method("shade_all") or not nc.has_method("fine_own"):
		t.check(true, "no native core built: the GDScript fallback runs")
		return
	Physique.forced = "human"
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 5, "decrees": [], "hazards": []})
	var made := []
	for how in ["core", "script", "kept"]:
		if how != "kept":
			Fighter._listed.clear()
			Beast._listed_beasts.clear()
		Greedy.use_native = how != "script"
		var man = m.spawn_fighter({"kind": "bot", "name": "Quintus Rufus", "loadout": {"main": "", "off": "", "armor": ["lorica", "greaves"]}, "team": 1, "pos": Vector3(-6.0 + 3.0 * made.size(), 0.1, 4.0), "yaw": 0.0, "skin": 0xd9a57a, "build": "hero"})
		var lion = m.spawn_beast({"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(-6.0 + 5.0 * made.size(), 0.1, 9.0), "yaw": PI, "harmless": true})
		Greedy.use_native = true
		made.append([how, man.f, lion.f])
	var giant = m.spawn_fighter(m.enemy_spec({"e": "cyclops", "boss": true}, 0, 1))
	Physique.forced = ""
	t.check(Fighter._listed.size() >= 1 and Beast._listed_beasts.size() == 1, "a man's and a lion's voxels kept for the next of them")
	var voxels := 0
	var fines := 0
	var off := []
	for other in [1, 2]:
		for who in [1, 2]:
			var a: Fighter = made[0][who]
			var b: Fighter = made[other][who]
			for pa: VoxelPart in a.parts:
				var pb: VoxelPart = b.by_name[pa.part_name]
				var what := "%s %s, by the core and %s" % ["man" if who == 1 else "lion", pa.part_name, "by the script" if other == 1 else "of what was kept"]
				voxels += pa.fx.size()
				var same := pa.fx == pb.fx and pa.fy == pb.fy and pa.fz == pb.fz and pa.bone == pb.bone and pa.kinds == pb.kinds and pa.organ == pb.organ and pa.alive == pb.alive
				same = same and pa.cellmap == pb.cellmap and pa.ao == pb.ao and pa.bev == pb.bev and pa.local_positions() == pb.local_positions()
				same = same and pa.cell_map() == pb.cell_map() and pa.live_cell == pb.live_cell and pa.live_coarse == pb.live_coarse and pa.total_coarse == pb.total_coarse and pa._dead == pb._dead
				# (A man's face is his own, by where he stands in the list: painted on his head's voxels.)
				if pa != a.head:
					same = same and pa.colors == pb.colors
				# (Without the core a man's skin is not the smooth one: another look, its own shades.
				# What the core makes of the look he has is held to the script below.)
				if other == 2 and pa.fine.has("body") and pb.fine.has("body"):
					fines += (pa.fine.own as PackedColorArray).size()
					same = same and (pa.fine.own as PackedColorArray) == (pb.fine.own as PackedColorArray) and (pa.fine.par as PackedInt32Array) == (pb.fine.par as PackedInt32Array) and (pa.fine.base as Dictionary).size() == (pb.fine.base as Dictionary).size()
				elif pa.fine.has("body") != pb.fine.has("body"):
					same = false
				if not same:
					off.append(what)
	t.check(voxels > 60000 and fines > 20000, "men and lions made three ways, part by part (%d voxels, %d fine ones)" % [voxels, fines])
	t.eq(off.size(), 0, "each part the same made by the core, by the script and of what was kept%s" % ("" if off.is_empty() else ": " + ", ".join(off.slice(0, 4))))
	# His fine voxels' own colours as the core made them, beside the script's (FineBody._own); and
	# the drawing made of them: the look's own, his colours in it, the fine voxels over a voxel
	# gone put away.
	var own_n := 0
	var own_off := 0
	var painted := 0
	var buf_off := 0
	for f: Fighter in [made[0][1], made[0][2], giant.f]:
		for p: VoxelPart in f.parts:
			if not p.fine.has("body"):
				continue
			var fine: Dictionary = p.fine
			var par: PackedInt32Array = fine.par
			var shade: PackedFloat32Array = fine.shade
			var cells: PackedInt32Array = fine.cells
			var own: PackedColorArray = fine.own
			var n := par.size()
			for s in n:
				var j := par[s]
				if j < 0:
					continue
				own_n += 1
				if cells[s * FineBody.CELL + 8] != 0:
					painted += 1
				if own[s] != FineBody._own(p, j, shade[s], fine.sk, fine.beast, cells[s * FineBody.CELL + 8], fine.d):
					own_off += 1
			# (Without a screen no drawing is made: one stands in for the look's, some voxels gone.)
			var tmpl := PackedFloat32Array()
			tmpl.resize(n * 20)
			for q in tmpl.size():
				tmpl[q] = float((q * 37) % 101) * 0.25 - 3.0
			var alive := p.alive.duplicate()
			for i in range(0, alive.size(), 7):
				alive[i] = 0
			for na: PackedFloat32Array in [fine.na as PackedFloat32Array, PackedFloat32Array()]:
				var got: Array = nc.fine_own(p.colors, p.kinds, alive, par, shade, cells, (fine.d as Dictionary).get("palette", []), (fine.d as Dictionary).get("cloth", []), fine.sk, fine.beast, tmpl, na)
				var want := tmpl.duplicate()
				for s in n:
					var j := par[s]
					var o := s * 20
					if j < 0 or alive[j] == 0:
						for q in 12:
							want[o + q] = 0.0
					want[o + 12] = own[s].r
					want[o + 13] = own[s].g
					want[o + 14] = own[s].b
					want[o + 15] = na[s] if na.size() == n else 1.0
				if got.size() != 2 or (got[0] as PackedColorArray) != own or (got[1] as PackedFloat32Array) != want:
					buf_off += 1
	t.check(own_n > 40000 and painted > 5000, "the fine voxels of a man, a lion and a giant (%d, %d of them painted by the build)" % [own_n, painted])
	t.eq(own_off, 0, "each one's own colour as the core makes it, the script's to the float")
	t.eq(buf_off, 0, "and the drawing made of them, the script's to the float")
	# The drawing a part is given as it is made, beside the script's voxel by voxel.
	var rows_off := 0
	var rows_n := 0
	for p: VoxelPart in [made[0][1].torso, made[0][1].by_name["shinL"], made[0][2].torso]:
		var got: PackedFloat32Array = nc.part_rows(p.local_positions(), p.colors, p.kinds, p.ao, p.bev)
		var want := PackedFloat32Array()
		for i in p.fx.size():
			var x: Transform3D = Transform3D(Basis(), p.local_positions()[i])
			var c := p.colors[i]
			var cu := p._custom(i)
			want.append_array([x.basis.x.x, x.basis.y.x, x.basis.z.x, x.origin.x, x.basis.x.y, x.basis.y.y, x.basis.z.y, x.origin.y, x.basis.x.z, x.basis.y.z, x.basis.z.z, x.origin.z, c.r, c.g, c.b, c.a, cu.r, cu.g, cu.b, cu.a])
		rows_n += want.size() / 20
		if got != want:
			rows_off += 1
	t.check(rows_n > 5000, "the drawings of three parts (%d voxels)" % rows_n)
	t.eq(rows_off, 0, "a part's drawing as the core makes it, the script's voxel by voxel")
	# Cut into: the maps of its cells and the shading of every voxel, some of them gone.
	var cut_off := 0
	var gone := 0
	for p: VoxelPart in [made[0][1].torso, made[0][2].torso, made[0][2].by_name.get("head", made[0][2].parts[1])]:
		p.freeze = true
		var lps := p.local_positions()
		for blow in 3:
			p.remove_voxels(Array(p.voxels_within(lps[(blow * 977 + 131) % lps.size()], p.vf * p.part_scale * 3.2)))
		gone += p.fx.size() - p.alive_count
		p.bevel = not p.bevel
		var both: Array = nc.shade_all(p.fx, p.fy, p.fz, p.cellmap, p.alive, p.veil, p.grid, p.bevel)
		for i in p.fx.size():
			var s := p.shade_bits(i)
			if both[0][i] != s & 0xffffff or both[1][i] != s >> 24:
				cut_off += 1
		p.bevel = not p.bevel
		p._index_cells()
		var by_core := [p._cell_map, p.live_cell, p.live_coarse, p.total_coarse, p._dead]
		Greedy.use_native = false
		p._index_cells()
		Greedy.use_native = true
		var by_script := [p._cell_map, p.live_cell, p.live_coarse, p.total_coarse, p._dead]
		for k in 5:
			if by_core[k] != by_script[k]:
				cut_off += 1
	t.check(gone > 300, "voxels cut out of a man and a lion (%d)" % gone)
	t.eq(cut_off, 0, "the shading and the maps of a part cut into, by the core as by the script")
	# What was kept is each one's own: the man and the lion made of what was kept cut into and
	# bloodied, the ones it was kept of are as they were, and one made after is whole.
	var shared := 0
	for who in [1, 2]:
		var cut: VoxelPart = (made[2][who] as Fighter).torso
		cut.freeze = true
		cut.remove_voxels(Array(cut.voxels_within(cut.local_positions()[cut.fx.size() / 3], cut.vf * cut.part_scale * 3.0)))
		cut.wound(cut.local_positions()[cut.fx.size() / 2], cut.vf * cut.part_scale * 6.0, "blood")
		if cut.alive_count == cut.fx.size():
			shared += 1   # (nothing cut: nothing tried)
		var before: VoxelPart = (made[1][who] as Fighter).torso
		var after: VoxelPart
		if who == 1:
			after = m.spawn_fighter({"kind": "bot", "name": "Quintus Rufus", "loadout": {"main": "", "off": "", "armor": []}, "team": 1, "pos": Vector3(8.0, 0.1, 4.0), "yaw": 0.0, "skin": 0xd9a57a, "build": "hero"}).f.torso
		else:
			after = m.spawn_beast({"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(14.0, 0.1, 9.0), "yaw": PI, "harmless": true}).f.torso
		for p: VoxelPart in [before, after]:
			if p.alive_count != p.fx.size() or p.alive.count(0) > 0 or p.colors == cut.colors or p.alive == cut.alive:
				shared += 1
		if before.colors != after.colors or before.ao != after.ao or before.kinds != after.kinds:
			shared += 1
	t.eq(shared, 0, "one cut into and bloodied: the others made of the same are whole, and so is the next")
	m.queue_free()
