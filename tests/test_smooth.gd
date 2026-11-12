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

