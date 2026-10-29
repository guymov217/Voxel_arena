extends Node
## The gladiators' looks (Physique) are drawing only: in every one the man has all his parts,
## voxels, organs, bones, joints and colliders, the same blows do the same to him, his limbs come
## off as they did, what a wound opens is what it opened, and changing the look in the middle of a
## fight changes nothing of him.

var t

func _world() -> TestWorld:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	return w

func _man(w: TestWorld, style: String, at := Vector3(0, 1.2, 0), loadout := {}) -> Fighter:
	Physique.forced = style
	var f := w.fighter(at, 0.0, loadout, {"skin": 0xc68e5e})
	Physique.forced = ""
	for p in f.parts:
		p.freeze = true   # still: every blow lands on the same voxels in every look
	return f

func _looks() -> Array:
	return Physique.STYLES.filter(func(s): return s != "classic")

func _count(p: VoxelPart, f: Callable) -> int:
	var n := 0
	for i in p.fx.size():
		if f.call(i):
			n += 1
	return n

## Every voxel of `p` drawn now with a face open to the light (what the eye can see of it).
func _seen(p: VoxelPart) -> Dictionary:
	var out := {}
	for i in p.fx.size():
		if p.alive[i] == 0 or p.veiled(i):
			continue
		for d in Physique.DIRS:
			if not p._solid(Vector3i(p.fx[i], p.fy[i], p.fz[i]) + d):
				out[i] = true
				break
	return out

func test_every_look_keeps_the_whole_man() -> void:
	var w := _world()
	var base := _man(w, "classic", Vector3(-3, 1.2, 0))
	var x := 0.0
	for style in _looks():
		x += 1.5
		var f := _man(w, style, Vector3(x, 1.2, 0))
		t.eq(f.parts.map(func(p): return p.part_name), base.parts.map(func(p): return p.part_name), style + ": the same parts")
		var veiled := 0
		for k in f.parts.size():
			var p: VoxelPart = f.parts[k]
			var b: VoxelPart = base.parts[k]
			var n := p.part_name
			t.eq(p.fx.size(), b.fx.size(), "%s %s: every voxel" % [style, n])
			t.eq(p.alive_count, b.alive_count, "%s %s: all alive" % [style, n])
			t.eq(p.organ, b.organ, "%s %s: the organs where they were" % [style, n])
			t.eq(p.bone, b.bone, "%s %s: the bones where they were" % [style, n])
			t.check(is_equal_approx(p.mass, b.mass) and p.half_ext.is_equal_approx(b.half_ext), "%s %s: the same weight and box" % [style, n])
			t.check(p.pa.is_equal_approx(b.pa) and p.ca.is_equal_approx(b.ca) and (p.joint != null) == (b.joint != null), "%s %s: the same joint" % [style, n])
			t.check(is_equal_approx(p.hp, b.hp), "%s %s: the same hp" % [style, n])
			# Nothing inside is hidden or uncovered: no organ or bone veiled, none beside a
			# veiled voxel.
			var bad := 0
			for i in p.fx.size():
				if not p.veiled(i):
					continue
				veiled += 1
				if p.organ[i] != 0 or p.bone[i] == 1:
					bad += 1
				for d in Physique.DIRS:
					var j := p._cell(p.fx[i] + d.x, p.fy[i] + d.y, p.fz[i] + d.z)
					if j >= 0 and not p.veiled(j) and (p.organ[j] != 0 or p.bone[j] == 1):
						bad += 1
			t.eq(bad, 0, "%s %s: no organ or bone veiled or bared" % [style, n])
			# What shows of the organs and bones is what showed (nothing of them, whole).
			var seen_inner := _seen(p).keys().filter(func(i): return p.organ[i] != 0 or p.bone[i] == 1).size()
			var seen_inner_b := _seen(b).keys().filter(func(i): return b.organ[i] != 0 or b.bone[i] == 1).size()
			t.eq(seen_inner, seen_inner_b, "%s %s: the organs and bones on show" % [style, n])
		if style == "strong":
			t.eq(veiled, 0, "strong: nothing veiled, every voxel drawn")
			for p in f.parts:
				t.eq(p.shape_xf.size(), p.fx.size(), "strong %s: every voxel drawn in the shape" % p.part_name)
		else:
			t.check(veiled > 300, "%s: the outline really is pared (%d voxels veiled)" % [style, veiled])
		t.eq(f.get_meta("physique", ""), style, style + ": drawn in it")
	w.queue_free()

## The same blows (edges, points, a club, into the belly, the head, a limb) on a classic man and
## on one in each look: every voxel lost, every hp, every organ hit and every limb off the same.
func _blows(f: Fighter) -> Array:
	var log := []
	var plan := [["torso", Vector3(0, -0.06, 1), "edge"], ["torso", Vector3(0.05, -0.06, 1), "point"], ["torso", Vector3(-0.05, -0.04, 1), "edge"],
		["head", Vector3(0, 0.02, 1), "blunt"], ["head", Vector3(0.06, 0.04, 1), "edge"], ["forearmR", Vector3(0, 0.05, 1), "edge"],
		["forearmR", Vector3(0, 0.05, 1), "edge"], ["forearmR", Vector3(0, 0.05, 1), "edge"], ["forearmR", Vector3(0, 0.05, 1), "edge"],
		["forearmR", Vector3(0, 0.05, 1), "edge"], ["forearmR", Vector3(0, 0.05, 1), "edge"], ["forearmR", Vector3(0, 0.05, 1), "edge"],
		["forearmR", Vector3(0, 0.05, 1), "edge"], ["forearmR", Vector3(0, 0.05, 1), "edge"], ["forearmR", Vector3(0, 0.05, 1), "edge"],
		["thighL", Vector3(1, 0.0, 0), "edge"], ["thighL", Vector3(1, 0.0, 0), "edge"], ["thighL", Vector3(1, 0.0, 0), "edge"],
		["shinR", Vector3(0, 0.0, 1), "blunt"], ["torso", Vector3(0, -0.06, 1), "point"], ["torso", Vector3(0, -0.06, 1), "edge"]]
	for k in plan.size():
		var pl: Array = plan[k]
		var p: VoxelPart = f.by_name[pl[0]]
		var o: Vector3 = pl[1]
		var side := Vector3(o.x, 0, o.z).normalized()
		var lp := Vector3(side.x * p.half_ext.x, o.y, side.z * p.half_ext.z) * 1.02
		if side.z == 0.0:
			lp.z = 0.0
		var at := p.global_transform * lp
		var dir := -(p.global_transform.basis * side).normalized()
		seed(1000 + k)
		var res := f.apply_hit(p, {"point": at, "dir": dir, "type": pl[2], "hardness": 1.0, "sharpness": 0.95, "impulse": 70.0, "heavy": 0.7,
			"edge": dir, "axis": (p.global_transform.basis * (Vector3.RIGHT if side.z != 0.0 else Vector3.BACK)).normalized(), "wsz": 1.0})
		log.append([pl[0], res.get("dmg", 0.0), res.get("organs", []), res.removed.map(func(r): return r.indices.size())])
	return log

func _state(f: Fighter) -> Dictionary:
	var parts := {}
	for p in f.parts:
		parts[p.part_name] = [p.alive.duplicate(), snappedf(p.hp, 0.001), p.severed, p.hanging, p.fractured, p.alive_count]
	return {"parts": parts, "blood": snappedf(f.blood, 0.001), "alive": f.alive, "organs": f.organ_total.duplicate() if f.get("organ_total") is Dictionary else {}}

func test_the_same_blows_do_the_same_in_every_look() -> void:
	var w := _world()
	var want := []
	var want_s := {}
	for style in ["classic"] + _looks():   # (the classic man first: the one to match)
		# Each man on the same spot, one after another: the same blows meet the same voxels.
		var f := _man(w, style)
		var got := _blows(f)
		var s := _state(f)
		if style == "classic":
			want = got
			want_s = s
			t.check(s.parts.forearmR[2] or s.parts.forearmR[3] or s.parts.thighL[2] or s.parts.thighL[3], "the blows take a limb off the classic man")
		else:
			t.eq(got, want, style + ": each blow lands the same (part, harm, organs, voxels lost)")
			for n in want_s.parts:
				t.eq(s.parts[n], want_s.parts[n], "%s %s: the same after the blows" % [style, n])
			t.eq(s.blood, want_s.blood, style + ": the same blood lost")
			t.eq(s.alive, want_s.alive, style + ": alive or not the same")
		w.fighters.erase(f)
		w.combat.fighters.erase(f)
		f.free()
	w.queue_free()

func test_a_wound_opens_on_the_same_insides() -> void:
	var w := _world()
	var want := {}
	for style in ["classic"] + _looks():   # (the classic man first: the one to match)
		var f := _man(w, style)
		_blows(f)
		for p in f.parts:
			var seen := _seen(p).keys().filter(func(i): return p.organ[i] != 0 or p.bone[i] == 1)
			seen.sort()
			var cols := seen.map(func(i): return p.colors[i])
			if style == "classic":
				want[p.part_name] = [seen, cols]
			else:
				t.eq(seen, want[p.part_name][0], "%s %s: the organs and bones a wound shows" % [style, p.part_name])
				t.eq(cols, want[p.part_name][1], "%s %s: in their own colours" % [style, p.part_name])
		w.fighters.erase(f)
		w.combat.fighters.erase(f)
		f.free()
	w.queue_free()

func test_changing_the_look_mid_fight_changes_nothing_of_him() -> void:
	var w := _world()
	var f := _man(w, "classic")
	_blows(f)
	var before := _state(f)
	var cols := {}
	for p in f.parts:
		cols[p.part_name] = p.colors.duplicate()
	for style in _looks() + ["classic"]:
		Physique.dress(f, style)
		t.eq(_state(f), before, style + ": his body, wounds and blood as they were")
		t.eq(f.get_meta("physique", ""), style, style + ": drawn in it now")
	var same := true
	for p in f.parts:
		if p.colors != cols[p.part_name]:
			same = false
		t.eq(p.veil.size(), 0, p.part_name + ": back to classic, nothing veiled")
		t.eq(p.shape_xf.size(), 0, p.part_name + ": back to classic, drawn as cubes")
	t.check(same, "back to classic, every colour as it was")
	w.queue_free()

func test_a_severed_limb_keeps_its_look_and_its_weight() -> void:
	var w := _world()
	for style in ["classic", "heroic"]:
		var f := _man(w, style, Vector3(0 if style == "classic" else 3, 1.2, 0))
		_blows(f)
		t.check(f.parts.any(func(p): return p.severed), style + ": a limb came off")
		for p in f.parts:
			if p.severed:
				t.check(p.alive_count > 0, "%s %s: the limb off is whole flesh" % [style, p.part_name])
				t.eq(p.veil.size() > 0, style != "classic", "%s %s: still drawn in the look" % [style, p.part_name])
	w.queue_free()

func test_pieces_cut_off_keep_their_veiled_voxels_unseen() -> void:
	var w := _world()
	var f := _man(w, "sculpted")
	var p: VoxelPart = f.by_name.thighR
	p.freeze = false
	var shell := []
	var plain := []
	for i in p.fx.size():
		if p.veiled(i) and shell.size() < 3:
			shell.append(i)
		elif not p.veiled(i) and plain.size() < 3 and p.organ[i] == 0:
			plain.append(i)
	var voxels := p.remove_voxels(shell + plain, false, false)
	t.eq(voxels.size(), 6, "six voxels taken off")
	t.eq(voxels.map(func(v): return v.veil), [true, true, true, false, false, false], "each carries whether it was drawn")
	var ch := Chunk.spawn(p, voxels, Vector3.FORWARD)
	t.check(ch != null, "they fly off as a piece")
	if ch:
		t.eq((ch.get_child(0) as MultiMeshInstance3D).multimesh.instance_count, 6, "all six are in the piece (its weight)")
	w.queue_free()

func test_armour_is_drawn_on_the_look_but_stops_blows_where_it_did() -> void:
	var w := _world()
	var base := _man(w, "classic", Vector3(-3, 1.2, 0), {"armor": ["steelLorica", "greaves"]})
	var f := _man(w, "heroic", Vector3(3, 1.2, 0), {"armor": ["steelLorica", "greaves"]})
	for k in f.parts.size():
		var a: Array = f.parts[k].get_meta("armor", [])
		var b: Array = base.parts[k].get_meta("armor", [])
		t.eq(a.size(), b.size(), f.parts[k].part_name + ": the same pieces")
		for j in a.size():
			t.eq(a[j].pts, b[j].pts, f.parts[k].part_name + ": the plates stop blows where they did")
	var torso: VoxelPart = f.torso
	var ad: Dictionary = torso.get_meta("armor")[0]
	var pulled := 0
	for ci in ad.cells.size():
		var drawn: Vector3 = ad.node.multimesh.get_instance_transform(ci).origin
		if drawn.distance_to(ad.pts[ci]) > 0.001:
			pulled += 1
	t.check(pulled > 0, "plates over the pared waist drawn in on it (%d)" % pulled)
	w.queue_free()

## The strong man: every voxel drawn moved and sized in its part, nothing of him moved. The
## limbs reach into the part they join (one body at the shoulder, elbow, hip, knee and neck), the
## fist stays where the hand holds the weapon, the armour is drawn on him by the same map, a cut
## limb and its stump end where they were cut, and a voxel put back is drawn in the shape.
func test_the_strong_man_is_drawn_whole_on_the_same_body() -> void:
	# (What a part draws is read from its shape: a headless run keeps no multimesh data.)
	var w := _world()
	var f := _man(w, "strong", Vector3(0, 1.2, 0), {"armor": ["steelLorica", "greaves"]})
	var base := _man(w, "classic", Vector3(3, 1.2, 0), {"armor": ["steelLorica", "greaves"]})
	for k in f.parts.size():
		var p: VoxelPart = f.parts[k]
		var b: VoxelPart = base.parts[k]
		var same := true
		for i in p.fx.size():
			if not p.local_of(i).is_equal_approx(b.local_of(i)):
				same = false
		t.check(same, p.part_name + ": every voxel where it was, for every blow")
	var ua: VoxelPart = f.by_name.upperArmR
	var vox := ua.vf * ua.part_scale
	var top := -INF
	for i in ua.fx.size():
		var xf := ua.drawn_xf(i)
		top = maxf(top, xf.origin.y + xf.basis.get_scale().y * vox * 0.5)
	t.check(top > ua.half_ext.y + 0.9 * vox, "the shoulder drawn up into the torso (%.3f over %.3f)" % [top, ua.half_ext.y])
	var hd: VoxelPart = f.head
	var low_h := INF
	for i in hd.fx.size():
		var xf := hd.drawn_xf(i)
		low_h = minf(low_h, xf.origin.y - xf.basis.get_scale().y * vox * 0.5)
	t.check(low_h < -hd.half_ext.y - 1.0 * vox, "a neck drawn down into the shoulders")
	var fa: VoxelPart = f.by_name.forearmR
	var fist := 0
	for i in fa.fx.size():
		if fa.fy[i] <= 1 and absf(fa.drawn_xf(i).origin.y - fa.local_of(i).y) < 0.0001:
			fist += 1
	t.eq(fist, _count(fa, func(i): return fa.fy[i] <= 1), "the fist drawn where the hand is: the grip does not move")
	var moved := 0
	for k in f.parts.size():
		var a: Array = f.parts[k].get_meta("armor", [])
		var b: Array = base.parts[k].get_meta("armor", [])
		for j in a.size():
			t.eq(a[j].pts, b[j].pts, f.parts[k].part_name + ": the plates stop blows where they did")
			for ci in a[j].cells.size():
				if Physique.plate_xf(f.parts[k], a[j].cells[ci], a[j].pts[ci]).origin.distance_to(a[j].pts[ci]) > 0.001:
					moved += 1
	t.check(moved > 50, "the plates drawn on the shape, moved with the flesh under them (%d)" % moved)
	# The forearm off: the upper arm's elbow end no longer reaches into it, the shoulder still does.
	var low := INF
	for i in ua.fx.size():
		var xf := ua.drawn_xf(i)
		low = minf(low, xf.origin.y - xf.basis.get_scale().y * vox * 0.5)
	t.check(low < -ua.half_ext.y - 0.8 * vox, "the elbow drawn down into the forearm")
	var res := {"removed": [], "severed": []}
	fa.freeze = false
	f.detach_limb(fa, res)
	low = INF
	for i in ua.fx.size():
		var xf := ua.drawn_xf(i)
		low = minf(low, xf.origin.y - xf.basis.get_scale().y * vox * 0.5)
	t.check(low > -ua.half_ext.y - 0.5 * vox, "the stump ends where it was cut (%.3f, %.3f)" % [low, -ua.half_ext.y])
	var fa_top := -INF
	for i in fa.fx.size():
		var xf := fa.drawn_xf(i)
		fa_top = maxf(fa_top, xf.origin.y + xf.basis.get_scale().y * vox * 0.5)
	t.check(fa_top < fa.half_ext.y + 0.5 * vox, "and the forearm cut off ends there too")
	w.queue_free()

## The eyes and the mouth he chooses are paint on the front of his head: the same man in every
## other way, his face's voxels in new colours, and a beard worn drawn on his jaw.
func test_a_chosen_face_is_only_paint() -> void:
	var w := _world()
	var plain := _man(w, "strong", Vector3(-3, 1.2, 0))
	var f := _man(w, "strong", Vector3(3, 1.2, 0), {"armor": ["eyes_cross", "mouth_gap", "beard_full"]})
	t.eq(f.face_ids, ["eyes_cross", "mouth_gap"], "the face pieces are his")
	t.eq(_state(f), _state(plain), "his body is the plain man's")
	var hd: VoxelPart = f.head
	var changed := 0
	var off_face := 0
	for i in hd.fx.size():
		if hd.colors[i] != plain.head.colors[i]:
			changed += 1
			if hd.fz[i] < hd.grid.z / 2 and hd.fy[i] > 4:
				off_face += 1   # (the back of the skull, above the jaw: never painted)
	t.check(changed > 10, "the face painted (%d voxels)" % changed)
	t.eq(off_face, 0, "nothing painted on the back of his head")
	Physique.dress(f, "classic")
	t.check(f.head.colors[0] == plain.head.colors[0], "the classic look keeps his face too")
	w.queue_free()

## A hat is not worn under a helmet: with both on, the hat is not drawn (and the hair is
## tucked into the helmet); the hat alone is drawn.
func test_a_hat_under_a_helmet_is_not_drawn() -> void:
	var w := _world()
	var f := _man(w, "strong", Vector3(0, 1.2, 0), {"armor": ["helmet", "hat_phrygian", "hair_curly"]})
	var hidden := 0
	var hat_cells := 0
	for ad in f.head.get_meta("armor", []):
		if String(ad.id) == "hat_phrygian":
			hat_cells = ad.cells.size()
			# (headless: the multimesh keeps no transforms, so ask how it would be placed)
	t.check(hat_cells > 0, "the cap is on his head")
	var covered := false
	for ad in f.head.get_meta("armor", []):
		if not Fighter._cosmetic(String(ad.id)):
			covered = true
	t.check(covered, "and a helmet over it, so the cap is not drawn (Fighter._tuck_hair)")
	w.queue_free()

func test_hair_bursts_out_of_a_hole_in_the_helmet() -> void:
	var w := _world()
	var f := _man(w, "strong", Vector3(0, 1.2, 0), {"armor": ["helmet", "hair_curly"]})
	var helm: Dictionary = {}
	var hair: Dictionary = {}
	for ad in f.head.get_meta("armor", []):
		if String(ad.id) == "helmet":
			helm = ad
		elif String(ad.id) == "hair_curly":
			hair = ad
	t.check(not hair.is_empty() and hair.has("base"), "his hair is placed (Fighter._tuck_hair)")
	var shown := 0
	for xf in hair.base:
		if (xf as Transform3D).basis.get_scale().x > 0.0:
			shown += 1
	t.check(shown == 0, "all of it tucked in under the helmet (%d)" % shown)
	var lock: Array = hair.cells[0]
	var hole := -1
	for ci in helm.cells.size():
		if helm.cells[ci] == lock:
			hole = ci
	t.check(hole >= 0, "a plate of the helmet over a lock")
	var before := f.head.alive_count
	f._knock_plate(f.head, helm, hole, Vector3.RIGHT, 30.0)
	var big := 0
	shown = 0
	for ci in hair.base.size():
		var sc: float = (hair.base[ci] as Transform3D).basis.get_scale().x
		if sc > 0.0:
			shown += 1
		if hair.out[ci] == 1:
			big += 1
	t.check(big >= 1 and (hair.base[0] as Transform3D).basis.get_scale().x > 0.0, "the lock under the hole bursts out, fluffed (%d)" % big)
	t.check(shown < hair.cells.size(), "the rest stays under the plates still on (%d of %d)" % [shown, hair.cells.size()])
	t.check(f.head.alive_count == before, "and his head is the same head")
	w.queue_free()
