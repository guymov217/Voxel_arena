extends Node
## The fine head (FineHead): the new look draws a man's head in voxels a third the size of his
## own, over them, so his face is a face and not a box (user: the faces looked like the block
## game's; voxels still, but a man's). Drawing only: the head's own voxels are what is hit, cut and
## bled, and the fine ones go with them; the old looks keep their own heads.

var t

func _world() -> TestWorld:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	return w

func _man(w: TestWorld, style: String, at := Vector3(0, 1.2, 0), faces := []) -> Fighter:
	Physique.forced = style
	var f := w.fighter(at, 0.0, {}, {"skin": 0xc68e5e})
	if not faces.is_empty():
		f.face_ids = faces
		Physique.dress(f, style)
	Physique.forced = ""
	for p in f.parts:
		p.freeze = true
	return f

func test_the_new_look_draws_a_fine_head() -> void:
	var w := _world()
	var f := _man(w, "human")
	var h: VoxelPart = f.head
	if not t.check(not h.fine.is_empty(), "the new look's man has a fine head over his own"):
		return
	var cells: Array = h.fine.cells
	t.check(cells.size() > 2000, "a face sculpted in thousands of fine voxels (%d)" % cells.size())
	var par: PackedInt32Array = h.fine.par
	var over := 0
	for s in par.size():
		if par[s] >= 0:
			over += 1
	t.eq(over, cells.size(), "each fine voxel lies over one of the head's own, and goes with it")
	var hid := 0
	var hd: PackedByteArray = h.fine.hid
	for i in hd.size():
		if hd[i] == 1:
			hid += 1
	t.check(hid > 0 and hid < h.fx.size(), "the head's own shell is not drawn under it, the inside and the neck are (%d of %d hidden)" % [hid, h.fx.size()])
	t.eq(h.fx.size(), h.shape_xf.size(), "every voxel of the head still there for every blow")
	Physique.dress(f, "classic")
	t.check(h.fine.is_empty(), "the classic blocks take it off")
	t.eq(h.shape_xf.size(), 0, "and draw the head's own voxels as they were")
	Physique.dress(f, "strong")
	t.check(h.fine.is_empty(), "the strong gladiators keep their own heads")
	Physique.dress(f, "human")
	t.check(not h.fine.is_empty(), "the new look puts it back")

func test_his_choices_are_drawn_fine() -> void:
	var w := _world()
	var f := _man(w, "human", Vector3(0, 1.2, 0), ["eyes_blue", "mouth_grin"])
	var h: VoxelPart = f.head
	if not t.check(not h.fine.is_empty(), "a fine head"):
		return
	t.check((h.fine.look.iris as Color).is_equal_approx(Physique.BLUE), "his blue eyes")
	var own: PackedColorArray = h.fine.own
	var cells: Array = h.fine.cells
	var iris := 0
	var blue := 0
	for s in cells.size():
		if int(cells[s][3]) == FineHead.IRIS:
			iris += 1
			if own[s].is_equal_approx(Physique.BLUE):
				blue += 1
	t.check(iris > 0 and blue == iris, "every iris voxel blue (%d of %d)" % [blue, iris])
	var grin: Dictionary = h.fine.get("paint", {})
	t.check(grin.size() > 0, "his grin drawn on the fine face (%d voxels)" % grin.size())
	# A blink and a grimace drawn there too, and gone again.
	FineHead.mood(h, true, false, 0)
	var shut: Dictionary = h.fine.paint
	t.check(shut.size() > grin.size(), "his eyes shut on it (%d voxels)" % shut.size())
	FineHead.mood(h, false, false, 0)
	t.eq((h.fine.paint as Dictionary).size(), grin.size(), "and open again")

## Your gladiator's face as he likes it, serious or silly (user): the colour of his hair and of his
## eyes, and his face's paint and scars, each drawn on the fine face and in the classic look; and
## the room takes them from a guest.
func test_hair_eyes_and_face_paint_as_he_chose() -> void:
	var w := _world()
	var plain := _man(w, "human", Vector3(0, 1.2, 0), ["none"])
	var base := (plain.head.fine.get("paint", {}) as Dictionary).size()
	var f := _man(w, "human", Vector3(3, 1.2, 0), ["hc_ginger", "iris_green"])
	var h: VoxelPart = f.head
	t.check((h.fine.look.hair as Color).is_equal_approx(Physique.HAIR_DYES.hc_ginger), "his hair the ginger he chose")
	t.check((h.fine.look.iris as Color).is_equal_approx(Physique.IRISES.iris_green), "his eyes the green he chose")
	t.check(not bool(h.fine.look.bald), "a dyed crown is never read as a shaved one")
	var blond := _man(w, "human", Vector3(6, 1.2, 0), ["hc_platinum"])
	t.check(not bool(blond.head.fine.look.bald), "nor a platinum one on a fair skin")
	var x := 9.0
	var silent := []
	for id in Physique.FACES:
		if not String(id).begins_with("face_") or id == "face_stubble":
			continue
		var g := _man(w, "human", Vector3(x, 1.2, 0), [id])
		x += 3.0
		if (g.head.fine.get("paint", {}) as Dictionary).size() <= base:
			silent.append(id)
		t.check(not Physique.face_marks(String(id)).is_empty(), "%s drawn in the classic look too" % id)
	t.check(silent.is_empty(), "every face paint and scar drawn on the fine face (%s)" % ", ".join(silent))
	var st := _man(w, "human", Vector3(x, 1.2, 0), ["face_stubble"])
	t.eq(int(st.head.fine.look.beard), 7, "stubble on his jaw")
	# A guest's look: every slot of it taken, nothing that is not one.
	var menu = load("res://scripts/ui/menu.gd").new()
	var all := []
	for k in menu.LOOK_SLOTS:
		all.append(menu.LOOK_SLOTS[k][1])
	var pk: Dictionary = menu.peer_look({"look": all + ["hc_fake", 7]})
	t.eq((pk.armor as Array).size(), all.size(), "a guest's whole look taken, a slot each, nothing else")
	menu.free()

## The nose he chose (Your gladiator): each of the template's noses drawn on the face in place of
## its own broad one, and nothing but the nose changes (user: the veteran's face for every man, his
## nose his own to pick).
func test_the_nose_he_chose() -> void:
	var w := _world()
	var base: Array = _man(w, "human", Vector3(0, 1.2, 0), ["none"]).head.fine.cells
	var a := {}
	for c in base:
		a[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = true
	var x := 3.0
	for nm in ["straight", "roman", "broken", "small"]:
		var f := _man(w, "human", Vector3(x, 1.2, 0), ["nose_" + nm])
		x += 3.0
		var b := {}
		for c in f.head.fine.cells:
			b[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = true
		var changed := []
		for k in a:
			if not b.has(k):
				changed.append(k)
		for k in b:
			if not a.has(k):
				changed.append(k)
		t.check(not changed.is_empty(), "the %s nose is drawn (%d fine voxels other than the broad one's)" % [nm, changed.size()])
		var elsewhere := changed.filter(func(k): return absf(float(k.x) - 15.0) > 6.0 or float(k.z) < 22.0)
		t.check(elsewhere.is_empty(), "the %s nose: only the nose changes (%d voxels elsewhere)" % [nm, elsewhere.size()])
	w.queue_free()
