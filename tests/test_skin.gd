extends Node
## The smooth skin over the voxels: every part of every body gets one, its faces look outward,
## a cut shows in it at once, and building it is quick enough to do on every blow.

var t

func _outward(p: VoxelPart, am: ArrayMesh) -> float:
	var a := am.surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var solid := {}
	for i in p.fx.size():
		if p.alive[i] and not p.jaw_slot.has(i):
			solid[Vector3i(p.fx[i], p.fy[i], p.fz[i])] = true
	var vsz: float = p.vf * p.part_scale
	var centre := Vector3(p.grid.x - 1, p.grid.y - 1, p.grid.z - 1) * 0.5
	var at := func(q: Vector3) -> bool:
		var c: Vector3 = q / vsz + centre
		return solid.has(Vector3i(roundi(c.x), roundi(c.y), roundi(c.z)))
	var good := 0
	for i in vs.size():
		if not at.call(vs[i] + ns[i] * vsz * 1.3):
			good += 1
	return float(good) / vs.size()

func test_every_body_gets_a_smooth_skin_facing_out() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(12, 0, 12))
	var bodies := [m.me.f]
	for sp in Data.beasts.keys():
		bodies.append(m.spawn_beast({"beast": sp, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": 0.0}).f)
	var bad := []
	var bad_face := []
	var worst := 1.0
	var ms := 0.0
	var parts := 0
	for f in bodies:
		for p in f.parts:
			var t0 := Time.get_ticks_usec()
			var am := VoxelSkin.build(p, p.jaw_slot)
			ms += (Time.get_ticks_usec() - t0) / 1000.0
			parts += 1
			if am == null:
				bad.append(p.part_name)
				continue
			var o := _outward(p, am)
			if o < 0.9:
				bad_face.append("%s %.0f%% (%s)" % [p.part_name, o * 100.0, str(p.grid)])
			worst = minf(worst, o)
	t.check(bad.is_empty(), "every part of %d bodies has a skin (none for: %s)" % [bodies.size(), ", ".join(bad)])
	t.check(worst > 0.9, "its faces look outward (worst part %.0f%%: %s)" % [worst * 100.0, ", ".join(bad_face)])
	t.check(ms / parts < 25.0, "a part's skin takes %.1f ms on average" % (ms / parts))
	m.queue_free()

func test_a_cut_shows_in_the_skin() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var f: Fighter = m.me.f
	var p := f.torso
	var before := VoxelSkin.build(p).get_faces().size()
	var cut := []
	for i in p.fx.size():
		if p.fx[i] < 4 and p.fy[i] > p.grid.y / 2:
			cut.append(i)
	p.remove_voxels(cut, false)
	var after := VoxelSkin.build(p)
	t.check(after != null and after.get_faces().size() != before, "the skin follows the voxels (%d -> %d faces)" % [before / 3, after.get_faces().size() / 3])
	m.queue_free()
