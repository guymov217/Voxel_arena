extends Node
## The beasts' new look (each sculpted, laid on its own voxels: FineBody) is drawing only (user:
## nothing of them changed but how they look, and they come apart as they did): in it every beast
## has the same parts, voxels, organs, bones, colliders, joints, weights and hp as in the classic
## look; the same blows do the same to it, cut by cut; and its drawing goes with its voxels, each
## fine cell over one of them and gone with it, a part cut off keeping its look.

var t

func _world() -> TestWorld:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	return w

func _beast(w: TestWorld, species: String, style: String, pos := Vector3(0, 1.0, 0)) -> Beast:
	Physique.forced = style
	var b := Beast.new()
	w.add_child(b)
	b.build_beast(species, pos, 0.0, {"seed": 7})
	Physique.forced = ""
	w.combat.fighters.append(b)
	for p in b.parts:
		p.freeze = true   # still: every blow lands on the same voxels in either look
	return b

func _gone(w: TestWorld, b: Beast) -> void:
	w.combat.fighters.erase(b)
	b.free()   # (its parts are its own children: they go with it)

## A part's colliders: how many, and where and how big all of them are (summed).
func _shapes(p: VoxelPart) -> Array:
	var n := 0
	var sum := Vector3.ZERO
	for c in p.get_children():
		if c is CollisionShape3D and not (c as CollisionShape3D).disabled:
			n += 1
			sum += (c as CollisionShape3D).position
			var sh = (c as CollisionShape3D).shape
			if sh is BoxShape3D:
				sum += (sh as BoxShape3D).size
	return [n, snapped(sum, Vector3.ONE * 0.0001)]

## The fine cells drawn on `p` now: over a voxel of it that is still there.
func _drawn(p: VoxelPart) -> int:
	var par: PackedInt32Array = p.fine.get("par", PackedInt32Array())
	var n := 0
	for s in par.size():
		var j := par[s]
		if j >= 0 and j < p.alive.size() and p.alive[j] == 1:
			n += 1
	return n

func test_every_beast_is_the_same_beast_in_the_new_look() -> void:
	var w := _world()
	var drawn_kinds := 0
	for k in Data.beasts:
		var a := _beast(w, k, "classic", Vector3(-3, 1.0, 0))
		var b := _beast(w, k, "human", Vector3(3, 1.0, 0))
		t.eq(b.parts.map(func(p): return String(p.part_name)), a.parts.map(func(p): return String(p.part_name)), k + ": the same parts")
		var fine := 0
		var orphans := 0
		for i in mini(a.parts.size(), b.parts.size()):
			var pa: VoxelPart = a.parts[i]
			var pb: VoxelPart = b.parts[i]
			var n := "%s %s" % [k, pa.part_name]
			t.eq(pb.fx.size(), pa.fx.size(), n + ": every voxel")
			t.eq(pb.alive_count, pa.alive_count, n + ": all alive")
			t.eq(pb.organ, pa.organ, n + ": the organs where they were")
			t.eq(pb.bone, pa.bone, n + ": the bones where they were")
			t.check(is_equal_approx(pb.mass, pa.mass) and pb.half_ext.is_equal_approx(pa.half_ext), n + ": the same weight and box")
			t.check(pb.pa.is_equal_approx(pa.pa) and pb.ca.is_equal_approx(pa.ca) and (pb.joint != null) == (pa.joint != null), n + ": the same joint")
			t.check(is_equal_approx(pb.hp, pa.hp), n + ": the same hp")
			t.eq(_shapes(pb), _shapes(pa), n + ": the same colliders")
			t.eq(pa.fine.is_empty(), true, n + ": the classic look draws its own voxels")
			if not pb.fine.is_empty():
				fine += 1
				# (each fine cell drawn over one of the part's voxels: none of them loose)
				var par: PackedInt32Array = pb.fine.par
				for s in par.size():
					if par[s] >= pb.fx.size():
						orphans += 1
		t.eq(orphans, 0, k + ": every fine cell over a voxel of its part")
		if FileAccess.file_exists(FineBody.BEAST_DIR + k + ".json"):
			t.check(fine > 0, k + ": drawn in the new look (%d parts)" % fine)
			drawn_kinds += 1
		_gone(w, a)
		_gone(w, b)
		await get_tree().process_frame
	t.check(drawn_kinds == Data.beasts.size(), "every beast sculpted for the new look (%d of %d)" % [drawn_kinds, Data.beasts.size()])
	w.queue_free()

## The same blows (edges and points into the body, the head cut at again and again, a leg or the
## tail) on a beast in the classic look and on one in the new: every voxel lost, every hp, every
## organ hit, every part cut off and every drop of blood the same.
func _blows(b: Beast) -> Array:
	var log := []
	var limb: VoxelPart = null
	for p in b.parts:
		if String(p.part_name).begins_with("legF") or String(p.part_name) == "tail" or String(p.part_name).begins_with("coil"):
			limb = p
			break
	var plan := [[b.torso, Vector3(1, 0.0, 0), "edge"], [b.torso, Vector3(-1, 0.1, 0), "point"], [b.torso, Vector3(0, -0.05, 1), "blunt"]]
	for i in 5:
		plan.append([b.head, Vector3(1, 0.0, 0), "edge"])
	if limb != null:
		for i in 5:
			plan.append([limb, Vector3(1, 0.0, 0), "edge"])
	for k in plan.size():
		var pl: Array = plan[k]
		var p: VoxelPart = pl[0]
		if p == null or not is_instance_valid(p) or p.severed or p.alive_count == 0:
			log.append(["-"])
			continue
		var o: Vector3 = pl[1]
		var side := Vector3(o.x, 0, o.z).normalized()
		var lp := Vector3(side.x * p.half_ext.x, o.y * p.half_ext.y, side.z * p.half_ext.z) * 1.02
		var at := p.global_transform * lp
		var dir := -(p.global_transform.basis * side).normalized()
		seed(2000 + k)
		var res := b.apply_hit(p, {"point": at, "dir": dir, "type": pl[2], "hardness": 1.0, "sharpness": 0.95, "impulse": 120.0, "heavy": 0.8,
			"edge": dir, "axis": (p.global_transform.basis * (Vector3.BACK if side.x != 0.0 else Vector3.RIGHT)).normalized(), "wsz": 1.2})
		var removed: Array = res.get("removed", [])
		log.append([String(p.part_name), snappedf(float(res.get("dmg", 0.0)), 0.001), res.get("organs", []), removed.map(func(r): return (r.indices as Array).size() if r is Dictionary and r.has("indices") else 0)])
	return log

func _state(b: Beast) -> Dictionary:
	var parts := {}
	for p in b.parts:
		parts[String(p.part_name)] = [p.alive.duplicate(), snappedf(p.hp, 0.001), p.severed, p.hanging, p.fractured, p.alive_count]
	return {"parts": parts, "blood": snappedf(b.blood, 0.001), "alive": b.alive}

func test_the_same_blows_do_the_same_to_a_beast_in_the_new_look() -> void:
	var w := _world()
	var cut := 0
	for k in Data.beasts:
		var want := []
		var want_s := {}
		for style in ["classic", "human"]:
			# (each on the same spot, one after the other: the same blows meet the same voxels)
			var b := _beast(w, k, style)
			var got := _blows(b)
			var s := _state(b)
			if style == "classic":
				want = got
				want_s = s
				if b.parts.any(func(p): return p.severed or p.alive_count < p.fx.size() / 2):
					cut += 1
			else:
				t.eq(got, want, k + ": each blow lands the same in the new look (part, harm, organs, voxels lost)")
				for n in want_s.parts:
					t.eq(s.parts[n], want_s.parts[n], "%s %s: the same after the blows" % [k, n])
				t.eq(s.blood, want_s.blood, k + ": the same blood lost")
				t.eq(s.alive, want_s.alive, k + ": alive or not the same")
			_gone(w, b)
			await get_tree().process_frame
	t.check(cut > Data.beasts.size() / 2, "the blows cut deep into most of them (%d of %d)" % [cut, Data.beasts.size()])
	w.queue_free()

## What is drawn of a part is drawn where the part is (what is struck there is that part, and cut
## off it falls from there): the middle of all its fine cells lies in its own voxels' box. A
## scorpion's shins were once drawn a stride off the parts that carried them, legs spread out to
## its sides over legs folded under its body: a blade passed through them, and cut off they were
## drawn sunk in the sand.
func test_a_part_is_drawn_where_it_is() -> void:
	var bad := []
	var n := 0
	for k in Data.beasts:
		for d in Data.beasts[k].parts:
			var cells: PackedInt32Array = FineBody.beast_data(k, str(d.name)).get("cells", PackedInt32Array())
			if cells.is_empty():
				continue
			n += 1
			var mid := Vector3.ZERO
			for c in cells.size() / FineBody.CELL:
				mid += Vector3(cells[c * FineBody.CELL] + 0.5, cells[c * FineBody.CELL + 1] + 0.5, cells[c * FineBody.CELL + 2] + 0.5)
			mid /= float(cells.size() / FineBody.CELL)
			var g := Vector3(int(d.grid[0]), int(d.grid[1]), int(d.grid[2])) * 2.0
			var out: float = maxf(maxf(maxf(-mid.x, mid.x - g.x), maxf(-mid.y, mid.y - g.y)), maxf(-mid.z, mid.z - g.z))
			if out > 1.0:
				bad.append("%s %s by %.1f" % [k, d.name, out])
	t.check(n > 300, "every beast's parts are drawn (%d)" % n)
	t.check(bad.is_empty(), "the middle of a part's drawing out of its own box (fine cells): " + ", ".join(bad))

func test_a_beast_drawn_new_comes_apart_with_its_drawing() -> void:
	var w := _world()
	var checked := 0
	var off_drawn := 0
	var off_n := 0
	for k in Data.beasts:
		var b := _beast(w, k, "human")
		var before := {}
		var cells_of := {}
		for p in b.parts:
			if p.fine.is_empty():
				continue
			before[p] = _drawn(p)
			var per := {}
			var par: PackedInt32Array = p.fine.par
			for s in par.size():
				if par[s] >= 0:
					per[par[s]] = int(per.get(par[s], 0)) + 1
			cells_of[p] = per
		var alive_before := {}
		for p in b.parts:
			alive_before[p] = p.alive.duplicate()
		_blows(b)
		for p in before:
			if not is_instance_valid(p):
				continue
			# (the cells drawn now: those before less every cell over a voxel the blows took)
			var lost := 0
			var per: Dictionary = cells_of[p]
			var was: PackedByteArray = alive_before[p]
			for j in was.size():
				if was[j] == 1 and p.alive[j] == 0:
					lost += int(per.get(j, 0))
			t.eq(_drawn(p), int(before[p]) - lost, "%s %s: its drawing loses the cells of the voxels cut away, no more, no fewer" % [k, p.part_name])
			if lost > 0:
				checked += 1
			if p.severed:
				# (cut off, it keeps its look: what is left of its skin drawn as it was, and what a
				# blow bared drawn as the wound's cells, as on him)
				off_n += 1
				if not p.fine.is_empty() and p.fine.has("par"):
					off_drawn += 1
		_gone(w, b)
		await get_tree().process_frame
	t.check(checked > Data.beasts.size() / 2, "the drawing cut away with the voxels on most of them (%d parts)" % checked)
	t.eq(off_drawn, off_n, "every part cut off keeps its look (%d of %d)" % [off_drawn, off_n])
	w.queue_free()
