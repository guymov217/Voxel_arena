extends Node
## A man's skin has colliders under it (FineBody shells; user: the trapezius is not destroyed by sword
## blows, and it is very important that every voxel a gladiator is made of can be destroyed). The
## sculpt of the new look stands out of the boxes his parts are made of at the shoulders (the slope from
## his neck to them, the deltoids): four to nine centimetres out of every collider he has, so a blade went
## through the skin untouched, and a blow from above landed on the head's box or the arm's, never on what
## was drawn. Skin that far out has shells, boxes of their own on the part that draws it; a blow on one is a
## blow on the part whose flesh the skin lies on; they go with the skin as it is cut away from under them;
## and the classic look, which draws nothing out of the boxes, has none.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(12, 0.02, 12))
	return m

var _men := 0
## A man standing still, drawn in the new look.
func _man(m: Match, style := "human") -> Fighter:
	_men += 1
	Physique.forced = style
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(-12.0 + (_men % 7) * 4.0, 0.1, -9.0 + int(_men / 7) * 5.0), "yaw": 0.0})
	Physique.forced = ""
	e.erase("bot")
	e.drive = func(_e): return {}
	return e.f

## The volume (cm3) of the shells of `p` over skin of `host`'s flesh ("" its own).
func _volume(p: VoxelPart, host: String) -> float:
	var v := 0.0
	for cs: CollisionShape3D in p.skin_shapes:
		if String(cs.get_meta("host")) == host:
			var sz := (cs.shape as BoxShape3D).size
			v += sz.x * sz.y * sz.z * 1.0e6
	return v

## How many of the shells of `p` lie over skin of `host`'s flesh ("" its own).
func _shells(p: VoxelPart, host: String) -> int:
	var n := 0
	for cs: CollisionShape3D in p.skin_shapes:
		if String(cs.get_meta("host")) == host:
			n += 1
	return n

func _shape_index(p: VoxelPart, cs: CollisionShape3D) -> int:
	for oid in p.get_shape_owners():
		if p.shape_owner_get_owner(oid) == cs:
			return p.shape_owner_get_shape_index(oid, 0)
	return -1

## The fine voxels of `a` drawn now that no collider of the man's lies within `r` of: those that
## stand out of him.
func _out_of_reach(m: Match, a: VoxelPart, r: float) -> int:
	var space := m.get_world_3d().direct_space_state
	var sph := SphereShape3D.new()
	sph.radius = r
	var fine: Dictionary = a.fine
	var xf: Array = fine.get("xf0", fine.xf)
	var par: PackedInt32Array = fine.par
	var gone: Dictionary = fine.get("gone", {})
	var n := 0
	for s in xf.size():
		if par[s] < 0 or a.alive[par[s]] == 0 or gone.has(s):
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sph
		q.transform = Transform3D(Basis.IDENTITY, a.global_transform * (xf[s] as Transform3D).origin)
		q.collision_mask = VoxelPart.LAYER_BODY
		q.collide_with_bodies = true
		if space.intersect_shape(q, 1).is_empty():
			n += 1
	return n

func test_the_skin_of_his_shoulders_has_colliders_under_it() -> void:
	var m := _match()
	var f := _man(m)
	await _steps(30)
	var torso: VoxelPart = f.torso
	t.check(torso.skin_shapes.size() > 0 and f.by_name.upperArmL.skin_shapes.size() > 0 and f.by_name.upperArmR.skin_shapes.size() > 0, "his trunk and his arms have shells (%d, %d and %d boxes)" % [torso.skin_shapes.size(), f.by_name.upperArmL.skin_shapes.size(), f.by_name.upperArmR.skin_shapes.size()])
	t.check(f.head.skin_shapes.is_empty(), "his head, drawn inside its box, has none")
	var far := _out_of_reach(m, torso, 0.03)
	t.check(far <= 12, "next to no skin his trunk draws is three centimetres or more from every collider of his (%d fine voxels)" % far)
	# And as it was without them, for the test to say something: the same skin, shells taken off.
	var kept := []
	for p: VoxelPart in f.parts:
		kept.append(p.skin_shapes.map(func(cs): return [cs.position, (cs.shape as BoxShape3D).size, cs.get_meta("host")]))
		for cs: CollisionShape3D in p.skin_shapes:
			cs.disabled = true
	await _steps(2)
	var bare := _out_of_reach(m, torso, 0.03)
	t.check(bare > 150, "without them a good part of it stands out of his colliders (%d fine voxels)" % bare)
	for p: VoxelPart in f.parts:
		for cs: CollisionShape3D in p.skin_shapes:
			cs.disabled = false
	f.state = "dead"
	f.alive = false

func test_a_blade_along_his_shoulder_line_meets_his_skin() -> void:
	var m := _match()
	var f := _man(m)
	await _steps(30)
	var torso: VoxelPart = f.torso
	var space := m.get_world_3d().direct_space_state
	var tx := torso.global_transform
	for y in [0.31, 0.325, 0.34]:
		for sx in [-1.0, 1.0]:
			var from: Vector3 = tx * Vector3(sx * 0.7, y, 0.0)
			var to: Vector3 = tx * Vector3(sx * 0.05, y, 0.0)
			var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, VoxelPart.LAYER_BODY))
			var at: Vector3 = tx.affine_inverse() * (r.position as Vector3) if not r.is_empty() else Vector3.ZERO
			t.check(not r.is_empty() and absf(at.x) > 0.27, "a blade laid along his shoulders at %.0f cm above the middle of his trunk's box, from the %s, meets him out at the shoulder (at %.0f cm across)" % [y * 100.0, "right" if sx < 0.0 else "left", at.x * 100.0])
	f.state = "dead"
	f.alive = false

func test_a_blow_on_a_shell_is_a_blow_on_the_part_whose_flesh_the_skin_lies_on() -> void:
	var m := _match()
	var f := _man(m)
	await _steps(30)
	var torso: VoxelPart = f.torso
	var seen := {}
	for cs: CollisionShape3D in torso.skin_shapes:
		var host := String(cs.get_meta("host"))
		var idx := _shape_index(torso, cs)
		if idx < 0:
			t.check(false, "a shell has a shape of the trunk's body")
			return
		var want: VoxelPart = f.by_name[host] if host != "" else torso
		if torso.host_part(idx) != want:
			t.check(false, "a shell over %s's skin is a blow on %s (got %s)" % [host if host != "" else "his own", want.part_name, torso.host_part(idx).part_name])
			return
		seen[host] = true
	t.check(seen.has("") and seen.has("upperArmL") and seen.has("upperArmR"), "his trunk has shells over his own skin and over each arm's (%s)" % str(seen.keys()))
	t.eq(torso.host_part(0), torso, "the trunk's own box is the trunk")
	f.state = "dead"
	f.alive = false

func test_shells_go_with_the_skin_cut_away_from_under_them() -> void:
	var m := _match()
	var f := _man(m)
	await _steps(30)
	var torso: VoxelPart = f.torso
	var arm: VoxelPart = f.by_name.upperArmL
	var own0 := _shells(torso, "")
	var on_arm0 := _shells(torso, "upperArmL")
	var other0 := _volume(torso, "upperArmR")
	t.check(own0 > 0 and on_arm0 > 0 and other0 > 0.0, "his trunk has shells of each kind (%d, %d, %.0f cm3)" % [own0, on_arm0, other0])
	# The flesh under the skin the trunk's own shells lie over, cut away.
	var mp: Dictionary = torso.fine.shell_map
	var par: PackedInt32Array = torso.fine.par
	var under := {}
	for k in (mp.at as Array).size():
		if String((mp.host as PackedStringArray)[k]) == "":
			for s: int in (mp.cells[k] as Array):
				under[par[s]] = true
	torso.remove_voxels(under.keys(), false)
	await _steps(3)
	t.eq(_shells(torso, ""), 0, "cut away from under them, the trunk's own shells are gone")
	t.check(_shells(torso, "upperArmR") > 0, "(the skin over the other arm that lies on the flesh just cut goes too, the rest stays: %.0f of %.0f cm3 left over it)" % [_volume(torso, "upperArmR"), other0])
	var right_left := _volume(torso, "upperArmR")
	# The whole arm cut off the shoulder: the skin the trunk drew on it with it.
	var all := []
	for i in arm.fx.size():
		if arm.alive[i] == 1:
			all.append(i)
	arm.remove_voxels(all, false)
	await _steps(3)
	t.eq(_shells(torso, "upperArmL"), 0, "the arm gone, the shells over its skin are gone")
	t.eq(arm.skin_shapes.size(), 0, "and the arm's own, with its flesh")
	t.check(absf(_volume(torso, "upperArmR") - right_left) < 0.06 * right_left, "the other arm's are as they were")
	# Put back, they are laid again.
	arm.restore_voxels(all)
	torso.restore_voxels(under.keys())
	await _steps(3)
	t.eq(_shells(torso, "") > 0 and _shells(torso, "upperArmL") > 0, true, "the flesh back, so are the shells")
	f.state = "dead"
	f.alive = false

## One chop of a gladius in at `sx`'s shoulder from outside and above, thrown at 11 m/s: the first blow
## it lands, {part, at (his trunk's frame)}.
func _chop(m: Match, f: Fighter, thrower: Fighter, design: Dictionary, mid: Vector3, sx: float) -> Dictionary:
	var hits := []
	var on := func(h): hits.append(h)
	m.combat.hit.connect(on)
	var tx := f.torso.global_transform
	var tb := tx.basis.orthonormalized()
	var d: Vector3 = (tb * Vector3(-sx * 0.7, -0.7, 0.0)).normalized()
	var a: Vector3 = tb * Vector3(0, 0, 1)
	var basis := Basis(d, a, d.cross(a))
	var target: Vector3 = tx * Vector3(sx * 0.14, 0.29, 0.0)
	var origin := target - d * 0.55 - basis * mid
	var w := m.spawn_loose_weapon(design, origin)
	w.gravity_scale = 0.0
	w.global_transform = Transform3D(basis, origin)
	w.thrower = thrower
	for i in 60:
		if is_instance_valid(w) and hits.is_empty():
			w.linear_velocity = d * 11.0
			w.angular_velocity = Vector3.ZERO
			w.thrown_t = 5.0
		await get_tree().physics_frame
	m.combat.hit.disconnect(on)
	if is_instance_valid(w):
		m.combat.loose_weapons.erase(w)
		w.queue_free()
	if hits.is_empty():
		return {}
	var first: Dictionary = hits[0]
	return {"part": first.part, "at": tx.affine_inverse() * (first.p as Vector3)}

func test_a_chop_in_at_the_shoulder_lands_on_his_trapezius() -> void:
	var m := _match()
	var design: Dictionary = Data.preset("gladius")
	var w0 := Weapon.new()
	add_child(w0)
	w0.setup(design, 1.0)
	var mid := Vector3.ZERO
	var n := 0
	for v in w0.vox:
		if v[4] == "edge":
			mid += Vector3(v[0], v[1], v[2])
			n += 1
	mid = mid / float(n) * w0.vs
	w0.queue_free()
	var thrower := _man(m)
	for sx in [-1.0, 1.0]:
		var f := _man(m)
		await _steps(30)
		var side: String = "right" if sx < 0.0 else "left"
		var cells0 := _trapezius(f)
		var first: Dictionary = await _chop(m, f, thrower, design, mid, sx)
		var at: Vector3 = first.get("at", Vector3.ZERO)
		t.check(not first.is_empty() and at.y > 0.31, "a chop in at the %s shoulder from outside and above lands up in the skin he is drawn with, not in the box under it (%.0f cm above his trunk's middle, his trunk's box ends at 29)" % [side, at.y * 100.0])
		var cells1 := _trapezius(f)
		t.check(cells1 < cells0 - 10, "and takes some of his trapezius with it (%d fine voxels of skin there, %d after)" % [cells0, cells1])
		for k in 3:
			await _chop(m, f, thrower, design, mid, sx)
		var cells4 := _trapezius(f)
		t.check(cells4 < cells0 * 0.75, "and four of them take a good deal more (%d of %d left)" % [cells4, cells0])
		f.state = "dead"
		f.alive = false
	thrower.state = "dead"
	thrower.alive = false

## The skin drawn over the slope of his shoulder to his neck, his trunk's fine voxels drawn there.
func _trapezius(f: Fighter) -> int:
	var torso: VoxelPart = f.torso
	var fine: Dictionary = torso.fine
	var xf: Array = fine.get("xf0", fine.xf)
	var par: PackedInt32Array = fine.par
	var gone: Dictionary = fine.get("gone", {})
	var n := 0
	for s in xf.size():
		var o: Vector3 = (xf[s] as Transform3D).origin
		if absf(o.x) < 0.06 or absf(o.x) > 0.30 or o.y < 0.27 or o.y > 0.37 or absf(o.z) > 0.15:
			continue
		if par[s] < 0 or torso.alive[par[s]] == 0 or gone.has(s):
			continue
		n += 1
	return n

func test_an_arrow_in_the_skin_of_his_shoulder_strikes_him() -> void:
	var m := _match()
	var f := _man(m)
	await _steps(30)
	var torso: VoxelPart = f.torso
	var items := Items.new()
	var seen := {}
	var arm_hits := 0
	for cs: CollisionShape3D in torso.skin_shapes:
		var host := String(cs.get_meta("host"))
		var p: Vector3 = torso.global_transform * cs.position
		var hit = items.hit_char(p, [f], 0.16, null, true)
		if hit == null or hit.char != f:
			t.check(false, "an arrow in the middle of a shell over %s's skin strikes him" % [host if host != "" else "his own"])
			return
		seen[host] = true
		# (Where shells over different flesh overlap it is the nearest that tells which part it is on.)
		if host == "upperArmL" or host == "upperArmR":
			arm_hits += 1 if hit.part == f.by_name[host] else 0
	t.check(seen.size() >= 3, "arrows strike the skin of each kind (%s)" % str(seen.keys()))
	t.check(arm_hits > 0, "and one in the skin that lies on an arm's flesh strikes the arm (%d of them)" % arm_hits)
	# Out in the air past the skin, nothing.
	t.check(items.hit_char(torso.global_transform * Vector3(0.0, 0.7, 0.5), [f], 0.16, null, true) == null, "and the air beside him is empty")
	f.state = "dead"
	f.alive = false

func test_the_classic_look_draws_nothing_out_of_the_boxes() -> void:
	var m := _match()
	var f := _man(m, "classic")
	await _steps(5)
	var all := 0
	for p: VoxelPart in f.parts:
		all += p.skin_shapes.size()
	t.eq(all, 0, "the classic blocks have no shells")
	Physique.dress(f, "human")
	await _steps(5)
	t.check(f.torso.skin_shapes.size() > 0, "dressed in the new look, he has them")
	Physique.dress(f, "classic")
	await _steps(5)
	all = 0
	for p: VoxelPart in f.parts:
		all += p.skin_shapes.size()
	t.eq(all, 0, "and undressed, none again")
	f.state = "dead"
	f.alive = false

## The old Items.hit_char, to the line: what an arrow asks of every part of a man.
func _hit_char_old(items: Items, p: Vector3, chars: Array, r: float, owner_, any_part: bool):
	for c in chars:
		if not is_instance_valid(c) or not c.alive or c == owner_:
			continue
		if c.torso.global_position.distance_squared_to(p) > pow(3.2 * float(c.S) + r, 2.0):
			continue
		var parts: Array = c.parts if any_part else [c.head, c.torso]
		for part in parts:
			if part == null or part.severed:
				continue
			var d := Social.box_distance(part, p)
			if d <= 0.0 or (r > 0.17 and d < r) or (not any_part and part.global_position.distance_to(p) < r + 0.1 * c.S):
				return {"char": c, "part": Social.struck_part(part, p) if any_part else part}
	return null

## What an arrow in the air asks of a man's part (Social.box_reaches: the box's distance and the skin's, the skin's shapes gone over only where the point is near the box that holds
## them all, VoxelPart.skin_box) is what the distance to the box and the skin (Social.box_distance) said, for points inside, at the edge of, near and far from every shape of a man's
## skin; and Items.hit_char names the same man and the same part as it did.
func test_an_arrows_questions_of_a_part_are_what_the_distance_to_the_box_and_the_skin_said() -> void:
	var m := _match()
	var f := _man(m)
	await _steps(30)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var items := Items.new()
	var bad := []
	var asked := 0
	var yes := 0
	var by_skin := 0
	var skinned := 0
	var radii := [0.05, 0.16, 0.17, 0.1701, 0.22, 0.45]
	for part: VoxelPart in f.parts:
		if part.skin_shapes.is_empty():
			continue
		skinned += 1
		for k in 400:
			var local: Vector3
			match k % 5:
				0, 1:
					# in, on and round the edge of a shape of the skin
					var cs: CollisionShape3D = part.skin_shapes[rng.randi() % part.skin_shapes.size()]
					var he := (cs.shape as BoxShape3D).size * 0.5
					local = cs.position + Vector3(rng.randf_range(-1, 1) * (he.x + 0.12), rng.randf_range(-1, 1) * (he.y + 0.12), rng.randf_range(-1, 1) * (he.z + 0.12))
					if k % 5 == 1:
						local = cs.position + Vector3(he.x * float(rng.randi_range(-1, 1)), he.y * float(rng.randi_range(-1, 1)), he.z * float(rng.randi_range(-1, 1))) + Vector3(1e-5, -1e-5, 0.0) * float(rng.randi_range(-1, 1))
				2:
					local = part.half_ext * Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6))
				3:
					local = Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
				_:
					local = Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
			var at: Vector3 = part.global_transform * local
			var r: float = radii[rng.randi() % radii.size()]
			var d := Social.box_distance(part, at)
			var want := d <= 0.0 or (r > 0.17 and d < r)
			var got := Social.box_reaches(part, at, r)
			asked += 1
			if want:
				yes += 1
				# (Where the box alone does not say so: the skin does.)
				var he0 := part.half_ext
				var l0: Vector3 = part.global_transform.affine_inverse() * at
				var db := Vector3(maxf(0.0, absf(l0.x) - he0.x), maxf(0.0, absf(l0.y) - he0.y), maxf(0.0, absf(l0.z) - he0.z)).length()
				if not (db <= 0.0 or (r > 0.17 and db < r)):
					by_skin += 1
			if got != want:
				bad.append("%s k=%d r=%.4f: %s, not %s" % [part.name, k, r, got, want])
			var hit_new = items.hit_char(at, [f], r, null, true)
			var hit_old = _hit_char_old(items, at, [f], r, null, true)
			if (hit_new == null) != (hit_old == null) or (hit_new != null and (hit_new.char != hit_old.char or hit_new.part != hit_old.part)):
				bad.append("hit_char %s k=%d r=%.4f" % [part.name, k, r])
			var hit_new2 = items.hit_char(at, [f], r, null, false)
			var hit_old2 = _hit_char_old(items, at, [f], r, null, false)
			if (hit_new2 == null) != (hit_old2 == null) or (hit_new2 != null and (hit_new2.char != hit_old2.char or hit_new2.part != hit_old2.part)):
				bad.append("hit_char (a dart) %s k=%d r=%.4f" % [part.name, k, r])
	t.check(bad.is_empty(), "the same answers to the two questions and the same man and part struck (%d asked; unlike: %s)" % [asked, str(bad.slice(0, 5))])
	t.check(skinned >= 3 and asked > 1200 and yes > 400 and by_skin > 50 and asked - yes > 400, "what was asked covers the cases (%d parts with a skin, %d points, %d reached, %d of them by the skin alone)" % [skinned, asked, yes, by_skin])
	f.state = "dead"
	f.alive = false

## The box that holds every shape of a part's skin (VoxelPart.skin_box): each shape within it, worked out again when the shapes change, and none for none.
func test_the_box_that_holds_a_parts_skin_follows_its_shapes() -> void:
	var m := _match()
	var f := _man(m)
	await _steps(20)
	var worst := 0.0
	var parts := 0
	for part: VoxelPart in f.parts:
		if part.skin_shapes.is_empty():
			t.eq(part.skin_box(), AABB(), "no shapes, no box (%s)" % part.name)
			continue
		parts += 1
		var sb := part.skin_box()
		var tight := false
		for cs: CollisionShape3D in part.skin_shapes:
			var he := (cs.shape as BoxShape3D).size * 0.5
			var lo := cs.position - he
			var hi := cs.position + he
			worst = maxf(worst, maxf(maxf(sb.position.x - lo.x, sb.position.y - lo.y), maxf(sb.position.z - lo.z, maxf(hi.x - sb.end.x, maxf(hi.y - sb.end.y, hi.z - sb.end.z)))))
			if is_equal_approx(lo.x, sb.position.x) or is_equal_approx(hi.x, sb.end.x):
				tight = true
		t.check(tight, "and the box is no wider than the shapes need (%s)" % part.name)
	t.check(parts >= 3 and worst <= 1e-6, "every shape of %d parts lies within its part's box (worst %.2g m out)" % [parts, worst])
	var p: VoxelPart = f.torso
	p.skin_set([[AABB(Vector3(0.1, 0.2, 0.3), Vector3(0.2, 0.2, 0.2)), ""], [AABB(Vector3(-0.2, 0.0, 0.0), Vector3(0.1, 0.1, 0.1)), ""]])
	t.check(p.skin_box().is_equal_approx(AABB(Vector3(-0.2, 0.0, 0.0), Vector3(0.5, 0.4, 0.5))), "worked out again for new shapes (%s)" % str(p.skin_box()))
	p.skin_set([[AABB(Vector3(0.1, 0.2, 0.3), Vector3(0.2, 0.2, 0.2)), ""]])
	t.check(p.skin_box().is_equal_approx(AABB(Vector3(0.1, 0.2, 0.3), Vector3(0.2, 0.2, 0.2))), "and for fewer")
	p.skin_set([])
	t.eq(p.skin_box(), AABB(), "and none for none")
	f.state = "dead"
	f.alive = false
