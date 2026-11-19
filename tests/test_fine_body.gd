extends Node
## The new look's body (FineBody): a man as he is built, in voxels half the size of his own, over
## the game's parts (user: the gladiators were blocks; keep the old ones as an option). Drawing
## only: every voxel that is hit, cut and bled, every collider, mass and hp is the game's, in any
## look. Three builds; a wound opens on skin, fat and flesh, an old one on a scar; a prosthetic and
## a lost limb stay as they are; armour sits on him.

var t

func _world() -> TestWorld:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	return w

func _man(w: TestWorld, style: String, at := Vector3(0, 1.2, 0), build := "", body = null, armor := []) -> Fighter:
	Physique.forced = style
	var opts := {"skin": 0xc68e5e}
	if build != "":
		opts["build"] = build
	if body != null:
		opts["body"] = body
	var f := w.fighter(at, 0.0, {"armor": armor}, opts)
	Physique.forced = ""
	for p in f.parts:
		p.freeze = true
	return f

func test_the_new_look_draws_him_fine() -> void:
	var w := _world()
	var f := _man(w, "human")
	t.eq(f.get_meta("physique", ""), "human", "drawn in the new look")
	var cells := 0
	for p in f.parts:
		if p == f.head:
			t.check(p.fine.has("wtab") and not p.fine.has("body"), "his head is the fine head")
			continue
		if not t.check(p.fine.has("body"), "%s: drawn fine" % p.part_name):
			return
		var par: PackedInt32Array = p.fine.par
		cells += par.size()
		var over := 0
		for s in par.size():
			if par[s] >= 0:
				over += 1
		t.eq(over, par.size(), "%s: every fine voxel over one of the part's own" % p.part_name)
		var hid := 0
		for v in (p.fine.hid as PackedByteArray):
			hid += v
		t.check(hid > 0 and hid < p.fx.size(), "%s: its voxels under the skin not drawn, those deep in him drawn under it (%d of %d hidden)" % [p.part_name, hid, p.fx.size()])
		t.eq(p.shape_xf.size(), p.fx.size(), "%s: every voxel of it still there for every blow" % p.part_name)
	t.check(cells > 9000, "a man in some ten thousand fine voxels (%d)" % cells)
	Physique.dress(f, "strong")
	for p in f.parts:
		t.check(p.fine.is_empty(), "%s: the strong gladiators keep their own looks" % p.part_name)
	Physique.dress(f, "classic")
	t.check(f.torso.shape_xf.is_empty(), "the classic blocks draw the voxels as they are")
	Physique.dress(f, "human")
	t.check(f.torso.fine.has("body"), "and the new look puts it back")

func test_three_builds() -> void:
	var w := _world()
	var hero := _man(w, "human", Vector3(0, 1.2, 0), "hero")
	var champ := _man(w, "human", Vector3(3, 1.2, 0), "champion")
	var brute := _man(w, "human", Vector3(6, 1.2, 0), "brute")
	t.eq(hero.get_meta("build", ""), "hero", "a man drawn in the build he chose")
	t.eq(brute.get_meta("build", ""), "brute", "and another in his")
	# Their outline at the chest and at the waist (FineBody.plate_at: a plate laid on the box's
	# side there drawn on him).
	var hx: float = hero.torso.half_ext.x
	var chest := Vector3(hx + 0.02, 0.1, 0.0)
	var waist := Vector3(hx + 0.02, -0.12, 0.0)
	var wh: float = FineBody.plate_at(hero.torso, waist).origin.x
	var wc: float = FineBody.plate_at(champ.torso, waist).origin.x
	var wb: float = FineBody.plate_at(brute.torso, waist).origin.x
	var ch: float = FineBody.plate_at(hero.torso, chest).origin.x
	var cc: float = FineBody.plate_at(champ.torso, chest).origin.x
	t.check(wb > wc and wb > wh, "the brute the thickest at the waist (%.3f, %.3f, %.3f)" % [wh, wc, wb])
	t.check(ch > cc, "the hero broader in the chest than the champion (%.3f, %.3f)" % [ch, cc])
	t.check(ch - wh > cc - wc, "the hero's chest over the narrowest waist (%.3f, %.3f)" % [ch - wh, cc - wc])
	t.check(FineBody.head_scale("brute") > FineBody.head_scale("hero"), "a bigger head on the brute")

func test_who_is_built_how() -> void:
	var w := _world()
	Physique.forced = "human"
	var me := w.fighter(Vector3(0, 1.2, 0), 0.0, {}, {"skin": 0xc68e5e})
	t.eq(Physique.build_of(me), "hero", "a player who chose nothing: the hero")
	var heavy := w.fighter(Vector3(3, 1.2, 0), 0.0, {"main": "warhammer"}, {"bot": true, "name": "Hammer Man"})
	t.eq(Physique.build_of(heavy), "brute", "a man with a war hammer: the brute")
	var a := w.fighter(Vector3(6, 1.2, 0), 0.0, {"main": "gladius"}, {"bot": true, "name": "Same Name"})
	var b := w.fighter(Vector3(9, 1.2, 0), 0.0, {"main": "gladius"}, {"bot": true, "name": "Same Name"})
	b.slot = a.slot
	t.eq(Physique.build_of(a), Physique.build_of(b), "a man drawn alike on every screen (his name and place)")
	Physique.forced = ""

func test_a_wound_opens_on_skin_fat_and_flesh() -> void:
	var w := _world()
	var f := _man(w, "human")
	var p: VoxelPart = f.torso
	var hole := Array(p.voxels_within(Vector3(0.0, -0.05, p.half_ext.z), 0.06))
	t.check(hole.size() > 3, "a hole cut in his belly (%d voxels)" % hole.size())
	var over := 0
	for i in hole:
		over += ((p.fine.of as Dictionary).get(i, []) as Array).size()
	t.check(over > 0, "his skin over them goes with them (%d fine voxels)" % over)
	p.remove_voxels(hole)
	var wound: Dictionary = p.fine.wound
	t.check(wound.size() > 0, "the voxels round it bared (%d)" % wound.size())
	for i in hole:
		t.check(not wound.has(i), "a voxel gone is not drawn in the wound")
		break
	# What is drawn there: skin, fat, then flesh or what the voxel is.
	var codes := {}
	var layers := {}
	for i in wound:
		var code: int = (p.fine.code as PackedInt32Array)[i]
		for k in 8:
			var cc := (code >> (2 * k)) & 3
			if cc > 0:
				codes[cc] = true
				if cc == 3 and p.kinds[i] == 0:
					layers["muscle"] = FineBody.wound_color(p, i, k, cc)
				elif cc == 2:
					layers["fat"] = FineBody.wound_color(p, i, k, cc)
	t.check(codes.has(2) and codes.has(3), "the fat under the skin and the flesh under it (%s)" % str(codes.keys()))
	if layers.has("fat"):
		var fat: Color = layers.fat
		t.check(fat.r > fat.b and fat.g > fat.b, "the fat yellow (%s)" % str(fat))
	if layers.has("muscle"):
		var mu: Color = layers.muscle
		t.check(mu.r > mu.g * 2.0, "the muscle red (%s)" % str(mu))
	# Put back, the wound closes again.
	p.restore_voxels(hole)
	t.eq((p.fine.wound as Dictionary).size(), 0, "the voxels put back: nothing bared")

func test_open_wounds_are_dents_and_old_scars_are_marks() -> void:
	var w := _world()
	var dent := []
	for x in range(6, 10):
		for y in range(13, 16):
			dent.append((x * 22 + y) * 10 + 9)
	# The last fight's wound, still open: the dent, in the pink of a scar, no flesh open in it.
	var b := Body.empty()
	b.scars = {"torso": dent}
	b.fresh = {"torso": dent}
	var f := _man(w, "human", Vector3(0, 1.2, 0), "", b)
	var p: VoxelPart = f.torso
	var wound: Dictionary = p.fine.wound
	t.check(wound.size() > 0, "the open wound's dent drawn (%d voxels)" % wound.size())
	var pink := 0
	for i in wound:
		if p.scarred.has(i):
			var c := FineBody.wound_color(p, i, 0, 3)
			if c.is_equal_approx(p.colors[i]) or c.r > c.g:
				pink += 1
	t.check(pink > 0, "its rim in the pink of the scar, no flesh open in it (%d)" % pink)
	# An old wound, healed over: a mark on the skin and nothing taken from him (user: a dent is a
	# disadvantage to the man who has it).
	var b2 := Body.empty()
	b2.scars = {"torso": dent}
	var f2 := _man(w, "human", Vector3(4, 1.2, 0), "", b2)
	var clean := _man(w, "human", Vector3(8, 1.2, 0))
	var p2: VoxelPart = f2.torso
	t.check(p2.fx.size() - p2.alive_count <= 2, "an old wound takes a voxel or two from him at the most (%d)" % (p2.fx.size() - p2.alive_count))
	t.check((p2.fine.wound as Dictionary).size() < (wound.size() as int) / 2, "and its dent drawn is a good deal smaller than the open wound's (%d against %d)" % [(p2.fine.wound as Dictionary).size(), wound.size()])
	var paler := 0
	for i in dent:
		if i < p2.fx.size() and p2.colors[i] != clean.torso.colors[i]:
			paler += 1
	t.check(paler > 0, "only a mark on the skin where it was (%d voxels paler)" % paler)

func test_prosthetics_and_lost_limbs_stay_as_they_are() -> void:
	var w := _world()
	var b := Body.empty()
	b.missing = ["shinL", "forearmL", "forearmR"]
	b = Body.apply(Body.apply(b, "peg:shinL"), "hook:forearmL")
	var f := _man(w, "human", Vector3(0, 1.2, 0), "", b)
	t.eq(f.by_name.shinL.prosthetic, "peg", "a peg for his left shin")
	t.check(f.by_name.shinL.fine.is_empty(), "the peg drawn as it was fitted")
	t.check(f.by_name.forearmL.fine.is_empty(), "the hook too")
	t.check(f.by_name.forearmR.fine.is_empty(), "nothing drawn of the hand he lost")
	t.check(f.by_name.thighL.fine.has("body") and f.by_name.upperArmR.fine.has("body"), "the rest of him the new look")

func test_the_same_fight_in_any_look() -> void:
	# Two men alike, one in each look: the same blows leave them alike in everything that counts.
	var w := _world()
	var a := _man(w, "human", Vector3(0, 1.2, 0))
	var b := _man(w, "strong", Vector3(4, 1.2, 0))
	for k in a.parts.size():
		var pa: VoxelPart = a.parts[k]
		var pb: VoxelPart = b.parts[k]
		t.eq(pa.fx.size(), pb.fx.size(), "%s: the same voxels" % pa.part_name)
		t.check(absf(pa.mass - pb.mass) < 0.0001, "%s: the same mass" % pa.part_name)
		t.check(pa.half_ext.is_equal_approx(pb.half_ext), "%s: the same box" % pa.part_name)
	for n in ["torso", "thighL", "forearmR", "head"]:
		var pa: VoxelPart = a.by_name[n]
		var pb: VoxelPart = b.by_name[n]
		var at := Vector3(0.01, 0.02, pa.half_ext.z)
		var ia := Array(pa.voxels_within(at, 0.07))
		var ib := Array(pb.voxels_within(at, 0.07))
		t.eq(ia, ib, "%s: a blow there takes the same voxels" % n)
		pa.remove_voxels(ia)
		pb.remove_voxels(ib)
		t.eq(pa.alive, pb.alive, "%s: the same voxels left" % n)
		t.eq(pa.shape_count(), pb.shape_count(), "%s: the same collider" % n)
		t.check(absf(pa.integrity - pb.integrity) < 0.0001, "%s: as whole as the other" % n)
	var ka: VoxelPart = a.by_name.forearmL
	var kb: VoxelPart = b.by_name.forearmL
	ka.set_kink(Vector3.ZERO, 0.8, 40)
	kb.set_kink(Vector3.ZERO, 0.8, 40)
	t.eq(ka.kink.size(), kb.kink.size(), "a bone broken alike")

func test_armour_sits_on_him() -> void:
	var w := _world()
	var f := _man(w, "human", Vector3(0, 1.2, 0), "champion", null, ["lorica", "helmet"])
	var p: VoxelPart = f.torso
	var placed := 0
	var pulled := 0
	for ad in p.get_meta("armor", []):
		if String(ad.id) != "lorica":
			continue
		for ci in ad.cells.size():
			var at: Vector3 = ad.pts[ci]
			var drawn := Physique.plate_xf(p, ad.cells[ci], at, String(ad.id)).origin
			placed += 1
			if Vector2(drawn.x, drawn.z).length() < Vector2(at.x, at.z).length() - 0.005:
				pulled += 1
	t.check(placed > 0 and pulled > placed / 3, "the cuirass drawn in on his waist and his sides (%d of %d plates)" % [pulled, placed])
	# Where he narrows fast (his shoulders up to his neck) a tile on the side leans in with him,
	# not stood straight up out of him like a tooth.
	var cell := p.vf * p.part_scale * float(Data.body_res)
	var hy := float(p.grid.y) * p.vf * p.part_scale * 0.5
	var steep := 0
	var leaning := 0
	for ad in p.get_meta("armor", []):
		if String(ad.id) != "lorica":
			continue
		for ci in ad.cells.size():
			var at: Vector3 = ad.pts[ci]
			if at.y > hy - cell * 0.25 or at.y < -hy + cell * 0.25 or Vector2(at.x, at.z).length() < 0.01:
				continue
			var kd: float = FineBody.k_at(p, p.fine.d, at - Vector3(0.0, cell * 0.5, 0.0))
			var ku: float = FineBody.k_at(p, p.fine.d, at + Vector3(0.0, cell * 0.5, 0.0))
			if kd - ku < 0.2:
				continue
			steep += 1
			var dir := Vector3(at.x, 0.0, at.z).normalized()
			if Physique.plate_xf(p, ad.cells[ci], at, String(ad.id)).basis.y.normalized().dot(dir) < -0.2:
				leaning += 1
	t.check(steep == 0 or leaning == steep, "the cuirass's tiles lean in where he narrows to his neck (%d of %d)" % [leaning, steep])
	var h: VoxelPart = f.head
	var c: Vector3 = h.fine.wc
	var far := 0
	var n := 0
	for ad in h.get_meta("armor", []):
		if String(ad.id) != "helmet":
			continue
		var plate := h.vf * h.part_scale * float(Data.body_res)
		for ci in ad.cells.size():
			var v := Physique.plate_xf(h, ad.cells[ci], ad.pts[ci] as Vector3, String(ad.id)).origin - c
			n += 1
			# (Each plate's middle half a plate off the head there: on it, not floating over it.)
			if v.length() > FineHead.outline(h, v.normalized()) + plate * 0.75:
				far += 1
	t.check(n > 0 and far == 0, "the helmet on his head, not floating over it (%d of %d plates off it)" % [far, n])

func _piece(p: VoxelPart, id: String) -> Dictionary:
	for ad in p.get_meta("armor", []):
		if String(ad.id) == id:
			return ad
	return {}

## A helmet and a cuirass on the new look are each one shell of fine voxels lying on him (user: the
## helmet's tiles lay over one another), each voxel a plate's: a plate knocked off takes its own;
## the classic look draws the plates again.
func test_armour_is_one_shell() -> void:
	var w := _world()
	var f := _man(w, "human", Vector3(0, 1.2, 0), "hero", null, ["helmet", "lorica"])
	var h: VoxelPart = f.head
	var ad := _piece(h, "helmet")
	t.check(ad.has("shell"), "the helmet drawn as one shell on the new head")
	if not ad.has("shell"):
		return
	t.check(not (ad.node as Node3D).visible, "its plates' own tiles not drawn")
	var mm: MultiMesh = ad.shell.mm
	t.check(mm.instance_count > ad.cells.size() * 4, "a shell of many fine voxels (%d for %d plates)" % [mm.instance_count, ad.cells.size()])
	var c: Vector3 = h.fine.wc
	var cell := h.vf * h.part_scale * float(Data.body_res)
	var far := 0
	var sunk := 0
	var rel: Array = ad.shell.rel
	var plate_of: PackedInt32Array = ad.shell.plate
	var xk: PackedByteArray = ad.shell.xk
	var bowl := 0
	var kinds := {}
	for s in mm.instance_count:
		var pc := int(plate_of[s])
		kinds[int(xk[s])] = int(kinds.get(int(xk[s]), 0)) + 1
		if xk[s] != 0:
			continue   # (the crest, its plume, the brim: off the head, as they stand on a galea)
		bowl += 1
		var v := (Physique.plate_xf(h, ad.cells[pc], ad.pts[pc] as Vector3, "helmet") * (rel[s] as Transform3D)).origin - c
		var rr := FineHead.outline(h, v.normalized())
		if v.length() > rr + cell * 0.8:
			far += 1
		if v.length() < rr - cell * 0.6:
			sunk += 1
	t.check(far < bowl / 20 and sunk < bowl / 20, "lying on his head: not off it, not in it (%d off, %d in, of %d)" % [far, sunk, bowl])
	# A galea as the arena wore it: a crest along the top with its plume, a brim at the brow.
	t.check(int(kinds.get(FineArmor.CREST, 0)) > 4 and int(kinds.get(FineArmor.PLUME, 0)) > 8, "a crest along its top with a plume on it (%d, %d)" % [int(kinds.get(FineArmor.CREST, 0)), int(kinds.get(FineArmor.PLUME, 0))])
	t.check(int(kinds.get(FineArmor.BRIM, 0)) > 20, "a brim round it at the brow (%d)" % int(kinds.get(FineArmor.BRIM, 0)))
	# A plate knocked off: its own voxels gone, the rest still on him.
	var of: Dictionary = ad.shell.of
	var ci: int = int(of.keys()[0])
	f._knock_plate(h, ad, ci, Vector3.FORWARD, 30.0)
	var now: Dictionary = ad.shell.now
	t.check((now[ci] as Transform3D).basis.get_scale().length() < 0.0001, "a plate knocked off takes its voxels of the shell (%d)" % (of[ci] as Array).size())
	var others := 0
	for cj in of:
		if int(cj) != ci and (now[int(cj)] as Transform3D).basis.get_scale().length() > 0.0001:
			others += 1
	t.eq(others, of.size() - 1, "and leaves the others on him")
	var lor := _piece(f.torso, "lorica")
	t.check(lor.has("shell") and (lor.shell.mm as MultiMesh).instance_count > lor.cells.size(), "the cuirass one shell too")
	# The classic look: the plates again.
	Physique.dress(f, "strong")
	t.check(not ad.has("shell") and (ad.node as Node3D).visible, "the classic look draws the helmet's plates again")

## A piece's cells (VoxelPart.piece_cells: 20 numbers each): [where, colour, data] of each.
func _cells(buf: PackedFloat32Array) -> Array:
	var out := []
	for k in buf.size() / 20:
		var o := k * 20
		out.append([Vector3(buf[o + 3], buf[o + 7], buf[o + 11]), Color(buf[o + 12], buf[o + 13], buf[o + 14], buf[o + 15]), Color(buf[o + 16], buf[o + 17], buf[o + 18], buf[o + 19])])
	return out

## A piece cut off a man of the new look is drawn of what was drawn of him there (user: the piece
## that fell from him was a piece of a square character that had nothing to do with him; every
## piece that falls from a character must be a piece that is literally his): his head's fine
## voxels and the flesh behind them, not the head's own boxes with the classic look's face on
## them; his arm's skin and the fat and the flesh the cut bares; a plate of his armour its own
## voxels of the shell. In the classic looks, his own voxels as they are drawn.
func test_a_piece_cut_off_him_is_a_piece_of_him() -> void:
	var w := _world()
	var f := _man(w, "human", Vector3(0, 1.2, 0), "hero", null, ["lorica"])
	var h: VoxelPart = f.head
	# His face: the front of his head, one voxel deep.
	var face := []
	var over := 0
	var hid := 0
	for i in h.fx.size():
		if h.alive[i] == 1 and h.fz[i] == h.grid.z - 1:
			face.append(i)
			over += ((h.fine.of as Dictionary).get(i, []) as Array).size()
			hid += 1 if int((h.fine.hid as PackedByteArray)[i]) == 1 and (h.fine.of as Dictionary).has(i) else 0
	t.check(face.size() > 20 and over > face.size(), "his face: %d of his head's voxels, %d fine ones drawn over them" % [face.size(), over])
	var eye: Color = Color.BLACK
	var skin_c: Color = f.skin
	var vox := h.remove_voxels(face, false)
	var pc := h.piece_cells(vox)
	t.check(not pc.is_empty() and pc.get("mesh") is Mesh, "what was drawn of his face goes with the piece")
	if not pc.is_empty():
		var cells := _cells(pc.buf)
		t.check(cells.size() >= over, "his face's own fine voxels (%d for %d)" % [cells.size(), over])
		# Behind his skin: flesh (wet, red), not the hollow back of a mask.
		var flesh := 0
		var far := 0.0
		var dark := 0
		for c in cells:
			var col: Color = c[1]
			if col.r > 0.5 and col.g < 0.2 and col.b < 0.2 and (c[2] as Color).g < 0.0:
				flesh += 1
			elif col.r + col.g + col.b < 0.6:
				dark += 1
			var at: Vector3 = c[0]
			far = maxf(far, maxf(absf(at.x) - h.half_ext.x, maxf(absf(at.y) - h.half_ext.y, absf(at.z) - h.half_ext.z)))
		t.check(flesh > hid / 3, "with flesh behind his skin (%d slabs of it, for %d of his head's voxels under the shell)" % [flesh, hid])
		t.check(dark > 0, "his eyes and his brows as they were drawn (%d dark fine voxels)" % dark)
		t.check(far < h.vf * h.part_scale * 1.5, "where they were on him (%.3f m off his head's box at most)" % far)
	var ch := Chunk.spawn(h, vox, Vector3.FORWARD)
	t.check(ch != null, "cut off, it falls as a piece")
	if ch != null and not pc.is_empty():
		t.eq(ch.boxes, 0, "none of his head's own boxes is drawn on it (the classic look's square face)")
		t.eq(ch.cells, (pc.buf as PackedFloat32Array).size() / 20, "it is drawn of his own")
	# A slice off his arm: his skin as it was drawn, and what the cut bares under it.
	var arm: VoxelPart = f.by_name["upperArmL"]
	var slice := Array(arm.voxels_within(Vector3(arm.half_ext.x, 0.0, 0.0), arm.vf * arm.part_scale * 2.6))
	var skin := 0
	for i in slice:
		skin += ((arm.fine.of as Dictionary).get(i, []) as Array).size()
	var avox := arm.remove_voxels(slice, false)
	var apc := arm.piece_cells(avox)
	t.check(slice.size() > 8 and not apc.is_empty(), "a slice off his arm (%d voxels): what was drawn of it goes with it" % slice.size())
	if not apc.is_empty():
		var cells := _cells(apc.buf)
		var fat := 0
		var red := 0
		for c in cells:
			var col: Color = c[1]
			if col.r > 0.7 and col.g > 0.5 and col.b < 0.55 and col.g > col.b * 1.3 and (c[2] as Color).g < 0.0:
				fat += 1
			elif col.r > 0.5 and col.g < 0.2:
				red += 1
		t.check(cells.size() > skin and skin > 0, "his skin's fine voxels (%d) and what the cut bares (%d cells in all)" % [skin, cells.size()])
		t.check(fat > 0 and red > 0, "fat under his skin and flesh under it (%d, %d)" % [fat, red])
	var ca := Chunk.spawn(arm, avox, Vector3.RIGHT)
	t.check(ca != null and ca.boxes == 0 and ca.cells > 0, "it falls drawn of that, none of his arm's own boxes")
	# A plate knocked off his cuirass: its own voxels of the shell.
	var lor := _piece(f.torso, "lorica")
	t.check(lor.has("shell"), "his cuirass is a shell")
	if lor.has("shell"):
		f.torso.freeze = false
		var ci := -1
		for c in (lor.shell.of as Dictionary):
			if ((lor.shell.of as Dictionary)[c] as Array).size() > 3:
				ci = int(c)
				break
		var own: int = ((lor.shell.of as Dictionary)[ci] as Array).size()
		t.eq(FineArmor.taken(lor, ci).size() / 20, own, "a plate's own voxels of the shell")
		var before := Chunk.all.size()
		f._knock_plate(f.torso, lor, ci, Vector3.FORWARD, 30.0)
		t.check(Chunk.all.size() == before + 1, "a plate knocked off flies off as a piece")
		if Chunk.all.size() == before + 1:
			var cp: Chunk = Chunk.all[Chunk.all.size() - 1]
			t.check(cp.cells == own and cp.boxes == 0, "drawn of its own voxels of the shell, not as a cube of its stuff (%d cells for %d, %d boxes)" % [cp.cells, own, cp.boxes])
		t.eq(FineArmor.taken(lor, ci).size(), 0, "off him, nothing of it is left to take")
		f.torso.freeze = true
	# The classic look: his own voxels, as they are drawn on him.
	var g := _man(w, "classic", Vector3(3, 1.2, 0))
	var ga: VoxelPart = g.by_name["upperArmL"]
	var gs := Array(ga.voxels_within(Vector3(ga.half_ext.x, 0.0, 0.0), ga.vf * ga.part_scale * 2.6))
	var gvox := ga.remove_voxels(gs, false)
	t.check(ga.piece_cells(gvox).is_empty(), "the classic look draws his own voxels")
	var cg := Chunk.spawn(ga, gvox, Vector3.RIGHT)
	t.check(cg != null and cg.cells == 0 and cg.boxes == gs.size(), "and a piece of him is those, as they were drawn")

## What a cut leaves of a limb on him stays only where it touches him (user: a piece hung in the
## air by his shoulder where his arm was cut off): the far side of the arm's top, with nothing of
## the arm between it and his trunk, falls as a piece of its own.
func test_nothing_of_a_stump_hangs_in_the_air() -> void:
	var w := _world()
	var f := _man(w, "human")
	var arm: VoxelPart = f.by_name["upperArmL"]
	var top := arm.grid.y - 1
	# The arm's two top layers, by how far from his trunk they lie (his left arm: out along +x).
	var inner := []
	var outer := []
	var mid := []
	for i in arm.fx.size():
		if arm.alive[i] == 0 or arm.fy[i] < top - 1:
			continue
		if arm.fx[i] <= 1:
			inner.append(i)
		elif arm.fx[i] >= arm.grid.x - 2:
			outer.append(i)
		else:
			mid.append(i)
	t.check(inner.size() > 3 and outer.size() > 3 and mid.size() > 0, "the top of his arm: the side by his trunk, the far side, and between (%d, %d, %d voxels)" % [inner.size(), outer.size(), mid.size()])
	t.eq(arm.stump_loose(inner + mid + outer).size(), 0, "whole, the top of his arm is on him")
	var loose: Array = arm.stump_loose(inner + outer)
	t.check(loose.size() == 1 and (loose[0] as Array).size() == outer.size(), "with nothing of it between, its far side touches nothing of him (%d groups)" % loose.size())
	t.eq(arm.stump_loose(inner).size(), 0, "the side by his trunk does")
	# Cut off below them with the middle gone: the far side falls, the near side is his stump.
	arm.remove_voxels(mid, false)
	var keep := PackedInt32Array()
	for i in arm.fx.size():
		if arm.alive[i] == 1 and arm.fy[i] < top - 1:
			keep.append(i)
	arm.freeze = false
	var res := {"removed": [], "severed": []}
	f.sever(arm, res, keep)
	var fell := 0
	var left := 0
	for r in res.removed:
		var idx: Array = Array(r.indices)
		if idx.size() == outer.size() and outer.has(idx[0]):
			fell += 1
			t.check(r.get("chunk", false), "its far side falls as a piece of its own")
		elif idx.size() == inner.size() and inner.has(idx[0]):
			left += 1
			t.check(not r.get("chunk", false), "the side by his trunk stays on him as the stump")
	t.check(fell == 1 and left == 1 and arm.severed, "the arm cut off: what touched nothing of him fell, what touched him stayed (%d, %d)" % [fell, left])

## The fine voxels `a` draws out of its own part's box (its skin run on over a joint: the neck, the
## slopes of his shoulders, his hips) that are drawn now.
func _skin_over(a: VoxelPart) -> Array:
	var out := []
	var fine: Dictionary = a.fine
	if fine.is_empty() or not fine.has("body"):
		return out
	var par: PackedInt32Array = fine.par
	var gone: Dictionary = fine.get("gone", {})
	for s: int in fine.get("over", PackedInt32Array()):
		var j := par[s]
		if j >= 0 and a.alive[j] == 1 and not gone.has(s):
			out.append(s)
	return out

func test_the_skin_over_a_joint_goes_with_the_flesh_under_it() -> void:
	# (User: the trapezius and the neck were not destroyed any more; every part of every figure can
	# be destroyed, from every side and at every point.) A man's trunk draws his neck up into the foot
	# of his head, the slopes of his shoulders, the caps of his shoulders over the tops of his arms, his
	# hips over the tops of his thighs: where the flesh under that skin is hacked away, it goes with it.
	var w := _world()
	var f := _man(w, "human")
	var torso: VoxelPart = f.torso
	var head: VoxelPart = f.head
	var whole := _skin_over(torso).size()
	t.check(whole > 1000, "his trunk draws skin out of its own box, over the parts beside it (%d fine voxels)" % whole)
	var hosts: Dictionary = FineBody._hosts(torso)
	for pn in ["head", "upperArmL", "upperArmR", "thighL", "thighR"]:
		t.check(hosts.has(pn) and not (hosts[pn] as Dictionary).is_empty(), "%s: some of it is drawn on his trunk's skin" % pn)
	# The foot of his head hacked away (the three layers by his neck): the neck drawn over it goes.
	var foot := []
	for i in head.fx.size():
		if head.alive[i] == 1 and head.fy[i] < 3:
			foot.append(i)
	var expect := 0
	for i: int in foot:
		expect += ((hosts.head as Dictionary).get(i, []) as Array).size()
	t.check(foot.size() > 20 and expect > 20, "the head's foot has a neck drawn over it (%d voxels, %d fine voxels)" % [foot.size(), expect])
	head.remove_voxels(foot, false)
	t.eq(whole - _skin_over(torso).size(), expect, "the neck over those voxels is gone with them, and no other skin of his trunk")
	head.restore_voxels(foot)
	t.eq(_skin_over(torso).size(), whole, "put back, it is drawn again")
	# The slope of his shoulder (the trunk's own top layers) and the cap of his shoulder (the top of
	# his arm): voxels of the arm taken from the top, the trunk's skin over them with them.
	var arm: VoxelPart = f.by_name["upperArmL"]
	var top := []
	for i in arm.fx.size():
		if arm.alive[i] == 1 and arm.fy[i] >= arm.grid.y - 3:
			top.append(i)
	var cap := 0
	for i: int in top:
		cap += ((hosts.upperArmL as Dictionary).get(i, []) as Array).size()
	t.check(cap > 20, "the top of his arm has his shoulder's cap drawn over it (%d fine voxels)" % cap)
	arm.remove_voxels(top, false)
	t.eq(whole - _skin_over(torso).size(), cap, "taken from the top of his arm, the cap of his shoulder goes")
	arm.restore_voxels(top)
	t.eq(_skin_over(torso).size(), whole, "put back, it is drawn again")
	# And what the arm draws over his trunk goes with the trunk's flesh there.
	var arm_over := _skin_over(arm).size()
	var under := Array(torso.voxels_within(arm.pa, 5.0 * torso.vf * torso.part_scale))
	torso.remove_voxels(under, false)
	t.check(_skin_over(arm).size() < arm_over, "the skin the arm draws into his trunk goes where the trunk is hacked away (%d -> %d)" % [arm_over, _skin_over(arm).size()])

## For each part, each fine voxel it draws out of its own box and how near the nearest flesh of the
## parts beside it (and its own) is, in voxels: {part name: {fine voxel: how near}}.
func _flesh_base(f: Fighter) -> Dictionary:
	var out := {}
	for a: VoxelPart in f.parts:
		var fine: Dictionary = a.fine
		if fine.is_empty() or not fine.has("body"):
			continue
		var va := a.vf * a.part_scale
		var half := Vector3(a.grid) * va * 0.5
		var xf: Array = fine.get("xf0", fine.xf)
		var rs := {}
		var every := 0
		for s in xf.size():
			var o: Vector3 = (xf[s] as Transform3D).origin
			if absf(o.x) <= half.x and absf(o.y) <= half.y and absf(o.z) <= half.z:
				continue   # (in its own part's box: its own voxels are under it)
			every += 1
			if every % 3 != 0:
				continue   # (every third: enough to read it by)
			rs[s] = _flesh_near(a.global_transform * o, a, false, va)
		out[String(a.part_name)] = rs
	return out

const _FLESH_LADDER := [0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 9.0, 13.0]
## How near, in voxels of `a`, the nearest flesh of a and the parts jointed to it that are his (`piece`
## false) or that were cut off with it (true) lies to `at`; 99 if none within thirteen.
func _flesh_near(at: Vector3, a: VoxelPart, piece: bool, va: float) -> float:
	var parts := [a]
	if a.parent_part != null and is_instance_valid(a.parent_part):
		parts.append(a.parent_part)
	for c in a.child_parts:
		if c != null and is_instance_valid(c):
			parts.append(c)
	parts = parts.filter(func(q): return (q as VoxelPart).severed == piece and not (q as VoxelPart).missing)
	for k: float in _FLESH_LADDER:
		for q: VoxelPart in parts:
			if not q.voxels_within(q.global_transform.affine_inverse() * at, k * va, 1).is_empty():
				return k
	return 99.0

## How many fine voxels the parts of `f` (his, or what was cut off him) draw out of their boxes that
## are drawn now, with no flesh nearer than it was when he was whole (and a voxel's width more).
func _hanging(f: Fighter, base: Dictionary, piece: bool) -> Array:
	var checked := 0
	var bad := 0
	for a: VoxelPart in f.parts:
		if a.severed != piece or a.missing or not base.has(String(a.part_name)):
			continue
		var va := a.vf * a.part_scale
		var xf: Array = a.fine.get("xf0", a.fine.xf)
		var par: PackedInt32Array = a.fine.par
		var gone: Dictionary = a.fine.get("gone", {})
		for s: int in (base[String(a.part_name)] as Dictionary):
			if par[s] < 0 or a.alive[par[s]] == 0 or gone.has(s):
				continue
			checked += 1
			var at: Vector3 = a.global_transform * (xf[s] as Transform3D).origin
			if _flesh_near(at, a, piece, va) > float(base[String(a.part_name)][s]) + 1.0:
				bad += 1
	return [checked, bad]

func test_nothing_of_him_hangs_in_the_air_where_a_limb_was_cut_off() -> void:
	# (User: voxels of a gladiator hung in the air where a hand was cut off; none may, for any
	# gladiator and any part cut off.) Each joint of a man, cut through: on him and on the piece,
	# no fine voxel of the skin run on over the joint is left drawn with no flesh under it.
	var w := _world()
	var base := _flesh_base(_man(w, "human", Vector3(-6, 1.2, 0)))
	var joints := []
	for p: VoxelPart in _man(w, "human", Vector3(-12, 1.2, 0)).parts:
		if p.parent_part != null and p.joint != null:
			joints.append(String(p.part_name))
	t.check(joints.size() == 9, "nine joints to cut at (%d)" % joints.size())
	var seen := 0
	for jn: String in joints:
		var f := _man(w, "human", Vector3(0, 1.2, 0))
		var c: VoxelPart = f.by_name[jn]
		var keep := PackedInt32Array()
		for i in c.fx.size():
			if c.alive[i] == 1:
				keep.append(i)
		f.sever(c, {"removed": [], "severed": []}, keep)
		var on_him := _hanging(f, base, false)
		var on_it := _hanging(f, base, true)
		seen += int(on_him[0]) + int(on_it[0])
		t.eq(int(on_him[1]) + int(on_it[1]), 0, "%s cut off at its joint: no skin left hanging (%d of his, %d of the piece's drawn out of their boxes)" % [jn, on_him[0], on_it[0]])
		f.queue_free()
		await get_tree().physics_frame
	t.check(seen > 3000, "the audit looked at the skin of every joint (%d fine voxels)" % seen)

## How many of the fine voxels part `parent_name` of `f` draws over part `child_name` are not drawn
## now: [how many lie there, how many of them are gone].
func _hosted_gone(f: Fighter, parent_name: String, child_name: String) -> Array:
	var q: VoxelPart = f.by_name[parent_name]
	var hosts: Dictionary = FineBody._hosts(q).get(child_name, {})
	var gone: Dictionary = q.fine.get("gone", {})
	var n := 0
	var off := 0
	for j in hosts:
		for s: int in hosts[j]:
			n += 1
			if gone.has(s):
				off += 1
	return [n, off]

func _cut_at_joint(f: Fighter, part_name: String) -> void:
	var c: VoxelPart = f.by_name[part_name]
	var keep := PackedInt32Array()
	for i in c.fx.size():
		if c.alive[i] == 1:
			keep.append(i)
	f.sever(c, {"removed": [], "severed": []}, keep)

func test_the_skin_over_a_joint_goes_on_a_beast_and_a_giant_too() -> void:
	var w := _world()
	# A lion's body draws its mane up over the foot of its head; its head cut off, that goes.
	var lion := Beast.new()
	w.add_child(lion)
	Physique.forced = "human"
	lion.build_beast("lion", Vector3(0, 0.5, 0), PI, {"seed": 11})
	Physique.forced = ""
	for p in lion.parts:
		p.freeze = true
	var on_lion := _hosted_gone(lion, "beastBody", "beastHead")
	t.check(int(on_lion[0]) > 10 and int(on_lion[1]) == 0, "a lion's body draws skin over its head, all drawn while the head is on (%s)" % str(on_lion))
	_cut_at_joint(lion, "beastHead")
	on_lion = _hosted_gone(lion, "beastBody", "beastHead")
	t.eq(int(on_lion[1]), int(on_lion[0]), "its head cut off, the skin its body drew over it goes with it")
	# A giant's trunk draws his neck and the slopes of his shoulders; his arm cut off at the shoulder.
	for look in ["troll", "minotaur"]:
		var g := w.fighter(Vector3(6, 1.2, 0), 0.0, {}, {"skin": 0x6f8458, "mods": {"look": look}})
		for p in g.parts:
			p.freeze = true
		t.eq(Physique.giant_of(g), look, "%s: drawn as his own build" % look)
		var on_arm := _hosted_gone(g, "torso", "upperArmL")
		t.check(int(on_arm[0]) > 20 and int(on_arm[1]) == 0, "%s: his trunk draws skin over the top of his arm (%s)" % [look, str(on_arm)])
		_cut_at_joint(g, "upperArmL")
		on_arm = _hosted_gone(g, "torso", "upperArmL")
		t.eq(int(on_arm[1]), int(on_arm[0]), "%s: his arm cut off at the shoulder, the skin his trunk drew over it goes" % look)
		var head_foot := _hosted_gone(g, "head", "torso") if g.head.fine.has("hosts") or not FineBody._hosts(g.head).is_empty() else [0, 0]
		if int(head_foot[0]) > 0:
			t.eq(int(head_foot[1]), 0, "%s: the skin his head draws down over his trunk stays while the trunk is whole" % look)
