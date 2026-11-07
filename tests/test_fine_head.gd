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

## The man bald, each hairstyle of the arena's day his hair, sitting on his head (user: the base man
## completely bald, every hairstyle fitted to him, of that period): no style, no hair; each style its
## own cells round his scalp, out of his head and close on it; a style no longer offered drawn as the
## nearest; a receding man's temples bare; the hair piece's own blocks not drawn.
func test_bald_and_the_hairstyles_of_the_day() -> void:
	var w := _world()
	var count_hair := func(f: Fighter) -> int:
		var n := 0
		for c in f.head.fine.cells:
			if int(c[3]) == FineHead.HAIR:
				n += 1
		return n
	Physique.forced = "human"
	var bare := w.fighter(Vector3(0, 1.2, 0), 0.0, {}, {"skin": 0xc68e5e})
	Physique.forced = ""
	t.eq(count_hair.call(bare), 0, "no hairstyle: bald, no hair on him")
	var skin: Color = bare.head.fine.look.skin
	var crown_bare := true
	var own: PackedColorArray = bare.head.fine.own
	for s in (bare.head.fine.cells as Array).size():
		var c: Array = bare.head.fine.cells[s]
		if int(c[3]) == FineHead.SKIN and (int(c[4]) & FineHead.CAP) != 0 and absf(own[s].r - own[s].g) < 0.02:
			crown_bare = false   # (a hair's grey or brown, not his skin's warm tone)
	t.check(crown_bare, "his crown his skin")
	var x := 3.0
	var t0: Dictionary = FineHead.template()
	for st in FineHead.STYLES:
		Physique.forced = "human"
		var f := w.fighter(Vector3(x, 1.2, 0), 0.0, {"armor": [st]}, {"skin": 0xc68e5e})
		Physique.forced = ""
		x += 3.0
		var n: int = count_hair.call(f)
		t.check(n > 300, "%s drawn as his hair (%d cells)" % [st, n])
		t.eq(String(f.head.fine.look.style), st, "%s read as the style he wears" % st)
		# Close on his head: every cell of it over his scalp, a voxel of it or two out (but the
		# style's own locks off it: a fall, braids, a knot).
		var far := 0
		var c0: Vector3 = f.head.fine.wc
		for s in (f.head.fine.cells as Array).size():
			var c: Array = f.head.fine.cells[s]
			if int(c[3]) != FineHead.HAIR or (int(c[4]) & FineHead.HAIR_EXTRA) != 0:
				continue
			var v: Vector3 = (f.head.fine.xf[s] as Transform3D).origin - c0
			if v.length() > FineHead.outline(f.head, v.normalized()) + f.head.vf * f.head.part_scale * 1.2:
				far += 1
		t.check(far < n / 50, "%s close on his head (%d of %d off it)" % [st, far, n])
		# The piece's own blocks not drawn (his hair is the fine head's).
		for ad in f.head.get_meta("armor", []):
			if String(ad.id) == st and ad.node != null:
				var shown := 0
				for ci in (ad.cells as Array).size():
					if Physique.plate_xf(f.head, ad.cells[ci], ad.pts[ci] as Vector3, st).basis.get_scale().length() > 0.001:
						shown += 1
				t.eq(shown, 0, "%s: the piece's own blocks not drawn" % st)
	Physique.forced = "human"
	var old := w.fighter(Vector3(x, 1.2, 0), 0.0, {"armor": ["hair_mohawk"]}, {"skin": 0xc68e5e})
	var crop := w.fighter(Vector3(x + 3.0, 1.2, 0), 0.0, {"armor": ["hair_crop"]}, {"skin": 0xc68e5e})
	var rec := w.fighter(Vector3(x + 6.0, 1.2, 0), 0.0, {"armor": ["hair_crop"]}, {"skin": 0xc68e5e})
	Physique.forced = ""
	t.eq(String(old.head.fine.look.style), "hair_crop", "a mohawk (no longer offered) drawn as the Roman crop")
	rec.face_ids = ["hair_receding"]
	Physique.dress(rec, "human")
	t.check(count_hair.call(rec) < count_hair.call(crop), "a receding man's temples bare (%d of %d)" % [count_hair.call(rec), count_hair.call(crop)])
	# A bot: a style of the day by his name, the same each time; now and then none.
	var styles := {}
	for i in 24:
		var b := w.fighter(Vector3(0, 1.2, 6.0 + float(i) * 2.0), 0.0, {}, {"skin": 0xc68e5e})
		b.is_bot = true
		b.display_name = "Bot %d" % i
		Physique.dress(b, "human")
		styles[String(b.head.fine.look.style)] = true
	t.check(styles.size() >= 4 and (styles.has("hair_crop") or styles.has("hair_curls_top")), "the bots' hair of the day, by name (%s)" % ", ".join(styles.keys()))

## Under a helmet his hair is tucked away (the helmet sits on his head, not on his hair); what hangs
## below it shows; a hat over the crown the same.
func test_hair_tucked_under_a_helmet() -> void:
	var w := _world()
	Physique.forced = "human"
	var f := w.fighter(Vector3(0, 1.2, 0), 0.0, {"armor": ["hair_long", "helmet"]}, {"skin": 0xc68e5e})
	Physique.forced = ""
	var tucked: Dictionary = f.head.fine.get("tucked", {})
	var under := 0
	var out := 0
	var extra_out := 0
	for s in (f.head.fine.cells as Array).size():
		var c: Array = f.head.fine.cells[s]
		if int(c[3]) != FineHead.HAIR:
			continue
		if tucked.has(s):
			under += 1
		else:
			out += 1
			if (int(c[4]) & FineHead.HAIR_EXTRA) != 0:
				extra_out += 1
	t.check(under > out, "his hair under the helmet tucked away (%d tucked, %d shown)" % [under, out])
	t.check(extra_out > 0, "what hangs below it shows (%d)" % extra_out)

## An older save's hairstyle (its index into the list as it was) read as the same style, or the
## arena's nearest for one no longer offered, and saved so.
func test_an_old_saves_hairstyle() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	var keep = Save.get_value("look", {})
	for pair in [[6, "hair_crop"], [1, "hair_crop"], [5, "hair_long"], [7, "hair_curls_top"], [11, "hair_curls_top"], [9, "hair_bun"], [10, "hair_suebian"], [0, ""]]:
		Save.set_value("look", {"hair": pair[0], "skin": 1})
		var l: Dictionary = menu.look()
		t.eq(String(menu.LOOK_SLOTS.hair[l.hair]), String(pair[1]), "the old list's hairstyle %d read as %s" % pair)
		t.eq(int((Save.get_value("look", {}) as Dictionary).get("v", 1)), int(menu.LOOK_V), "and saved so")
		t.eq(int(menu.look().hair), int(l.hair), "the same when read again")
	Save.set_value("look", keep)
	menu.free()
