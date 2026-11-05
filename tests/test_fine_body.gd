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

func test_old_wounds_are_scars() -> void:
	var w := _world()
	var b := Body.empty()
	var dent := []
	for x in range(6, 10):
		for y in range(13, 16):
			dent.append((x * 22 + y) * 10 + 9)
	b.scars = {"torso": dent}
	var f := _man(w, "human", Vector3(0, 1.2, 0), "", b)
	var p: VoxelPart = f.torso
	var wound: Dictionary = p.fine.wound
	t.check(wound.size() > 0, "the old wound's dent drawn (%d voxels)" % wound.size())
	var pink := 0
	for i in wound:
		if p.scarred.has(i):
			var c := FineBody.wound_color(p, i, 0, 3)
			if c.is_equal_approx(p.colors[i]) or c.r > c.g:
				pink += 1
	t.check(pink > 0, "its rim in the pink of the scar, no flesh open in it (%d)" % pink)

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
