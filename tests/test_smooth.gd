extends Node
## The men's smooth skin (FineSmooth; drawing only, user: only the outer layer smooth, the voxel
## look kept): a part's skin meets the skin of the part jointed onto it, a knee and an elbow are
## one skin bent round the joint, and nothing that is not his skin is drawn on him: no plain
## block on a joint, no plate of his head's own voxels under his chin.

const FineSmooth := preload("res://scripts/fighter/fine_smooth.gd")

var t

func _at(part: String) -> PackedInt32Array:
	return FineBody._fine_at(FineBody.part_data("hero", part).cells)

func _corners(at: PackedInt32Array, own: Dictionary, sol: Dictionary) -> PackedFloat32Array:
	return FineSmooth.corners(at, sol, FineSmooth.blurred(sol, FineSmooth.GEO_REACH), FineSmooth.blurred(sol, FineSmooth.REACH),
		own, FineSmooth.blurred(own, FineSmooth.GEO_REACH), FineSmooth.blurred(own, FineSmooth.REACH))

func test_the_skin_meets_at_a_knee() -> void:
	# The thigh's lowest layer of fine voxels stands on the shin's top one (the leg is cut level at
	# the knee, tools/gen_fine_body.py), and each of the two is made smooth with the other joined on:
	# the corners they share are drawn in the same place by both, so no slit opens along the knee.
	if Greedy.core() == null:
		t.check(true, "no native core built: the men are drawn as cubes")
		return
	var th := _at("thighR")
	var sh := _at("shinR")
	var a: Dictionary = FineSmooth.solid(th, PackedInt32Array(), 2, true, true)
	var b: Dictionary = FineSmooth.solid(sh, PackedInt32Array(), 2, false, true)
	# (The shin's grid lies 32 fine voxels under the thigh's; the knee at the foot of the thigh.)
	var ja: Dictionary = FineSmooth.joined(a, [[b, Vector3i(0, -32, 0), Vector3(8.0, 0.0, 8.0), 13.0]])
	var ca := _corners(th, a, ja)
	var cb := _corners(sh, b, FineSmooth.joined(b, [[a, Vector3i(0, 32, 0), Vector3(8.0, 32.0, 8.0), 13.0]]))
	var top := {}
	for s in sh.size() / 3:
		var q := Vector3i(sh[s * 3], sh[s * 3 + 1], sh[s * 3 + 2])
		if q.y != 31:
			continue
		for c in [2, 3, 6, 7]:
			var o: int = (s * 8 + c) * 4
			top[Vector2i(q.x + (c & 1), q.z + ((c >> 2) & 1))] = Vector3(cb[o], cb[o + 1], cb[o + 2])
	var n := 0
	var moved := 0
	var worst := 0.0
	for s in th.size() / 3:
		var q := Vector3i(th[s * 3], th[s * 3 + 1], th[s * 3 + 2])
		if q.y != 0:
			continue
		for c in [0, 1, 4, 5]:
			var key := Vector2i(q.x + (c & 1), q.z + ((c >> 2) & 1))
			if not top.has(key):
				continue
			# (On his skin: a corner with nothing of the leg on some side of it. Those inside the leg,
			# where the one part's end lies under the other, are never seen.)
			if not _on_skin(ja, key.x, 0, key.y):
				continue
			var o: int = (s * 8 + c) * 4
			var d := Vector3(ca[o], ca[o + 1], ca[o + 2])
			n += 1
			moved += 1 if d != Vector3.ZERO else 0
			worst = maxf(worst, d.distance_to(top[key]))
	t.check(n > 30 and moved > 20, "the thigh and the shin share the corners of his skin round the knee (%d, %d of them moved)" % [n, moved])
	t.check(worst < 0.08, "and both draw each of them in the same place (%.3f of a fine voxel apart at worst)" % worst)

## Whether the corner (x, y, z) of the fine grid lies on the skin of `sol`: one of the eight fine
## voxels that meet at it is not him.
func _on_skin(sol: Dictionary, x: int, y: int, z: int) -> bool:
	var f: PackedFloat32Array = sol.f
	var lo: Vector3i = sol.lo
	var pad: int = sol.pad
	for dx in [-1, 0]:
		for dy in [-1, 0]:
			for dz in [-1, 0]:
				if f[((x + dx - lo.x + pad) * int(sol.sy) + (y + dy - lo.y + pad)) * int(sol.sz) + (z + dz - lo.z + pad)] <= 0.5:
					return true
	return false

## voxel_body.gdshader's bend, on a point of the world drawn with a part whose length lies along `along`.
func _bent(x: Vector3, along: Vector3, at: Vector4, turn: Vector4) -> Vector3:
	var c := Vector3(at.x, at.y, at.z)
	var rel := x - c
	var k := clampf(rel.dot(along.normalized()) / at.w * 0.5 + 0.5, 0.0, 1.0)
	var w := k * k * (3.0 - 2.0 * k)
	return c + rel.rotated(Vector3(turn.x, turn.y, turn.z), turn.w * w) if w > 0.0 else x

func test_a_bent_knee_is_one_skin() -> void:
	# The two parts that meet at a knee or an elbow are drawn as one skin bent round the joint
	# (Fighter.bend_of, the shader's bend_at and bend_turn): a point of the limb is drawn in the same
	# place whichever of the two it is drawn with, at any bend; away from the joint each part is
	# drawn where it is.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst := 0.0
	var stray := 0.0
	var h := 0.085
	for k in 60:
		var up := Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(-PI, PI))
		var low := Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 2.4)) * up
		var pivot := Vector3(rng.randf_range(-3, 3), rng.randf_range(0, 2), rng.randf_range(-3, 3))
		var b: Array = Fighter.bend_of(up, low, pivot, h)
		for j in 20:
			# (A point of the limb where it is at rest, from the joint: the same in both parts' frames.)
			var r := Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.08, 0.08))
			var by_up := _bent(pivot + up * r, up.y, b[0], b[1])
			var by_low := _bent(pivot + low * r, low.y, b[2], b[3])
			worst = maxf(worst, by_up.distance_to(by_low))
		var far_up := pivot + up * Vector3(0.03, 2.0 * h, -0.02)
		var far_low := pivot + low * Vector3(0.03, -2.0 * h, -0.02)
		stray = maxf(stray, maxf(_bent(far_up, up.y, b[0], b[1]).distance_to(far_up), _bent(far_low, low.y, b[2], b[3]).distance_to(far_low)))
	t.check(worst < 1e-4, "a point of a bent limb is drawn in one place by both its parts (%.2f mm apart at worst)" % (worst * 1000.0))
	t.check(stray < 1e-6, "and away from the joint each part is drawn where it is")
	var straight: Array = Fighter.bend_of(Basis(), Basis(), Vector3.ZERO, h)
	t.check(is_zero_approx((straight[1] as Vector4).w), "a straight limb is not bent")

## voxel_body.gdshader's level foot, on a point of the world drawn with a shin whose length lies along `along`.
func _levelled(x: Vector3, along: Vector3, at: Vector4, turn: Vector4) -> Vector3:
	var c := Vector3(at.x, at.y, at.z)
	var rel := x - c
	var k := clampf(0.5 - rel.dot(along.normalized()) / at.w * 0.5, 0.0, 1.0)
	var w := k * k * (3.0 - 2.0 * k)
	if w <= 0.0:
		return x
	var rot := Vector3(turn.x, turn.y, turn.z)
	var d := Vector3(0.0, turn.w * w, 0.0)
	if rot.length() > 0.00001:
		d += rel.rotated(rot.normalized(), rot.length() * w) - rel
	return x + d

func test_a_foot_is_level_on_the_sand() -> void:
	# (User: better feet.) A man's foot is drawn with his shin, and a shin leans at every step and
	# in his guard: the foot is drawn turned level about the ankle (Fighter.foot_level, the shader's
	# foot_at and foot_turn), its sole where the shin's own foot stands. Drawing only.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var worst := 0.0
	var stray := 0.0
	for k in 40:
		var b := Basis(Vector3.UP, rng.randf_range(-PI, PI)) * Basis(Vector3(cos(float(k)), 0.0, sin(float(k))), rng.randf_range(0.05, 0.7))
		var at := Transform3D(b, Vector3(rng.randf_range(-3, 3), 0.0, rng.randf_range(-3, 3)))
		at.origin.y -= (at * Vector3(0.0, -4.0 * Fighter.V, 0.0)).y   # (the foot of the shin on the sand)
		var lv: Array = Fighter.foot_level(at, Vector3.ZERO, 1.0, 0.0)
		if not t.check((lv[0] as Vector4).w > 0.0, "a leaning shin's foot is levelled"):
			return
		for j in 12:
			# (A point of his sole, in the shin's frame: from the heel to the toes.)
			var q := Vector3(rng.randf_range(-0.05, 0.05), -4.0 * Fighter.V, rng.randf_range(-0.08, 0.17))
			worst = maxf(worst, absf(_levelled(at * q, b.y, lv[0], lv[1]).y))
		var shin := at * Vector3(0.02, -0.06, 0.01)
		stray = maxf(stray, _levelled(shin, b.y, lv[0], lv[1]).distance_to(shin))
	t.check(worst < 0.001, "his sole lies on the sand from heel to toe, however the shin leans (%.2f mm off it at worst)" % (worst * 1000.0))
	t.check(stray < 1e-6, "and the shin over the ankle is drawn where it is")
	var none := [Vector4.ZERO, Vector4.ZERO]
	t.check(Fighter.foot_level(Transform3D(Basis(), Vector3(0, 4.0 * Fighter.V, 0)), Vector3.ZERO, 1.0, 0.0) == none, "an upright shin's foot is as it is")
	t.check(Fighter.foot_level(Transform3D(Basis(Vector3.RIGHT, 1.3), Vector3(0, 0.1, 0)), Vector3.ZERO, 1.0, 0.0) == none, "a shin that lies keeps its foot (a man down)")
	t.check(Fighter.foot_level(Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(0, 0.7, 0)), Vector3.ZERO, 1.0, 0.0) == none, "and a foot in the air goes with its shin (a kick)")

func test_the_fight_reads_his_broad_forms() -> void:
	# (User: a little more muscle on his arms and legs, and the game not hurt.) What his arms are
	# kept out of is read off his sculpt (Fighter._outline): his trunk's and his arms' outlines as
	# they were before the bellies of his muscles were put on them are kept beside the drawn ones
	# (tools/gen_fine_body.py "keep"), and those are what the fight reads.
	var tpl := FineBody.template()
	for bn in FineBody.BUILDS:
		var parts: Dictionary = tpl.builds[bn].parts
		var kept := 0
		for pn in ["torso", "upperArmR", "upperArmL", "forearmR", "forearmL"]:
			kept += 1 if parts[pn].get("keep") is Array and (parts[pn].keep as Array).size() == (parts[pn].prof as Array).size() and parts[pn].get("keep_rows") is Array else 0
		t.eq(kept, 5, "the %s's trunk and arms keep the outline the fight reads" % bn)
		# (The drawn arm is the fuller: its muscles' bellies stand out of the kept one.)
		var fuller := 0.0
		var rows: Array = parts.upperArmR.keep_rows
		for r in range(int(rows[0]) + 10 + 8, int(rows[1]) + 10 - 8):
			for a in (parts.upperArmR.prof[r] as Array).size():
				fuller += float(parts.upperArmR.prof[r][a]) - float(parts.upperArmR.keep[r][a])
		t.check(fuller > 0.0, "the %s's arm is drawn the fuller of the two" % bn)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	for i in 10:
		await get_tree().physics_frame
	var f: Fighter = m.me.f
	var pd: Dictionary = tpl.builds[Physique.build_of(f)].parts.upperArmR
	var o = f._outline(f.by_name.upperArmR)
	if t.check(o is Dictionary, "a man's arm has its outline"):
		var k: float = f.by_name.upperArmR.vf * f.by_name.upperArmR.part_scale / 0.0275
		var off := 0.0
		var na: int = o.na
		for r in (pd.keep as Array).size():
			for a in na:
				off = maxf(off, absf(float((o.prof as PackedFloat32Array)[r * na + a]) - float(pd.keep[r][a]) * k))
		t.check(off < 1e-5, "the outline the fight reads is the kept one (%.4f mm off it)" % (off * 1000.0))
		t.eq(int(o.r0), int(pd.keep_rows[0]) + int(tpl.margin), "over the rows he is in there")
	m.queue_free()
	await get_tree().process_frame

func test_his_feet_are_bare_in_their_sandals() -> void:
	# (User: better feet.) The game's own voxels at his foot are a boot's; the fine body paints his
	# foot on them (tools/gen_fine_body.py _paint): his own skin, the straps, and the sole under it.
	var tpl := FineBody.template()
	for bn in FineBody.BUILDS:
		var b: Dictionary = tpl.builds[bn]
		var cells: Array = b.parts.shinR.cells
		var n := [0, 0, 0, 0]
		var sole_ok := true
		var high := 0
		for c in range(0, cells.size(), FineBody.CELL):
			var paint := int(cells[c + 8])
			n[clampi(paint, 0, 3)] += 1
			if int(cells[c + 1]) == 0 and paint != 3:
				sole_ok = false
			if paint != 0 and int(cells[c + 1]) > 7:
				high += 1
		t.check((b.get("palette", []) as Array).size() >= 3 and n[1] > 60 and n[2] > 30 and n[3] > 20, "the %s's foot: his skin, the straps and the sole (%d, %d, %d fine voxels)" % [bn, n[1], n[2], n[3]])
		t.check(sole_ok and high == 0, "its lowest layer all sole, and nothing painted over his ankle")

func test_nothing_of_his_trunk_hangs_under_his_armpit() -> void:
	# (User: strange spiky lumps under his armpits; and then: bits there still, as if he were
	# melting.) His trunk and his arm are each drawn of their own flesh alone and are one only in the
	# round of the shoulder, which both draw (tools/gen_fine_body.py _own_cells). Under that round
	# nothing of his trunk lies out past his flank: there a share of the fold of skin between the two
	# was drawn with his trunk, and stood out of his side when the arm came up.
	var tpl := FineBody.template()
	var body = JSON.parse_string(FileAccess.get_file_as_string("res://data/body.json"))
	var grid := Vector3.ZERO
	var at := Vector3.ZERO
	for p in body.parts:
		if p.name == "torso":
			grid = Vector3(p.grid[0], p.grid[1], p.grid[2])
		elif p.name == "upperArmR":
			at = Vector3(p.pa[0], p.pa[1], p.pa[2])   # (his shoulder, in his trunk's frame)
	var vox := 0.0275
	var cell := vox / float(tpl.res)
	var round := 0.075
	for bn in FineBody.BUILDS:
		var cells: Array = tpl.builds[bn].parts.torso.cells
		var widest := 0.0
		var seen := 0
		for c in range(0, cells.size(), FineBody.CELL):
			var q := Vector3(int(cells[c]) + 0.5, int(cells[c + 1]) + 0.5, int(cells[c + 2]) + 0.5) * cell - grid * vox * 0.5
			if q.y > at.y - 0.085 or q.y < at.y - 0.26:
				continue
			if Vector3(absf(q.x) - absf(at.x), q.y - at.y, q.z).length() < round + cell:
				continue
			seen += 1
			widest = maxf(widest, absf(q.x))
		t.check(seen > 200 and widest < 0.235, "under the %s's shoulders his trunk goes no further out than his flank (%.3f m from his middle, of %d fine voxels there)" % [bn, widest, seen])

func test_nothing_but_his_skin_is_drawn_on_a_man() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	# (A brute: a foe drawn in that build.)
	var e = m.spawn_fighter({"kind": "bot", "name": "Brutus", "build": "brute", "loadout": {"main": "warhammer", "off": "", "armor": []}, "team": 1, "pos": Vector3(4, 0.1, 4), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {}
	for i in 30:
		await get_tree().physics_frame
	for f: Fighter in [m.me.f, e.f]:
		var bn := Physique.build_of(f)
		# The fine head ends at the jaw: none of the head's own lowest layer is drawn under it (a
		# brute's, its head drawn nearly full size, kept the whole layer: a plate under his chin, user).
		var head: VoxelPart = f.head
		var hid: PackedByteArray = head.fine.get("hid", PackedByteArray())
		var low := 0
		for i in head.fx.size():
			if head.fy[i] == 0 and hid.size() == head.fx.size() and hid[i] == 0 and (head.shape_xf[i] as Transform3D).basis.get_scale().length() > 0.001:
				low += 1
		t.check(hid.size() == head.fx.size() and low == 0, "none of the %s's head's lowest layer is drawn under his chin (%d)" % [bn, low])
		# His skin closes over his joints itself: no plain block is drawn on any of them (the block
		# on the neck stood out under his chin, user).
		f.draw_now()
		var caps := 0
		for p: VoxelPart in f.parts:
			var cap: MeshInstance3D = f.joint_caps.get(p)
			if cap != null and cap.visible:
				caps += 1
		t.eq(caps, 0, "no plain block is drawn on a joint of the %s" % bn)
		# His skin is smooth where the C++ core is there to work it out, cubes without it.
		var smooth := 0
		for p: VoxelPart in f.parts:
			if p != head and p.fine.get("smooth", false):
				smooth += 1
		t.eq(smooth, 9 if Greedy.core() != null else 0, "the %s's nine parts are drawn in his smooth skin" % bn)
	t.eq(Physique.build_of(e.f), "brute", "a foe is drawn in the build he is given")
	m.queue_free()
	await get_tree().process_frame

func test_every_player_is_the_one_build() -> void:
	# (User: one character for every player, so that none of them looks, or seems, the heavier man.
	# The three builds were only ever how a man is drawn: now a player's is not his to choose, his
	# own in his save or one a guest sends.)
	var menu = load("res://scripts/ui/menu.gd").new()
	var was = Save.get_value("look", {})
	Save.set_value("look", {"build": 2, "v": menu.LOOK_V})
	t.eq(int(menu.look().build), 0, "a save's build of another day is the hero's")
	Save.set_value("look", was)
	t.eq(String(menu.peer_look({"build": "brute"}).build), "", "a guest's build is not his to send")
	menu.free()
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "warhammer", "off": ""}})
	t.eq(Physique.build_of(m.me.f), "hero", "a player is the hero, whatever he carries")
	m.queue_free()
	await get_tree().process_frame

