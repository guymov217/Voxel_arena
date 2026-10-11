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
