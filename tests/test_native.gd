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
