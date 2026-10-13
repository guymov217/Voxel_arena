extends Node
## The organs inside (Anatomy): voxels of their own in the trunk and the head, and what losing
## each does: a torn heart kills in seconds, torn lungs cap the breath, a cut spinal cord takes
## the legs, a broken brain fells him; a stab reaches what is under the skin, a hard blunt blow
## bruises it.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _victim() -> Array:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true, "seed": 5})
	m.me.f.teleport(Vector3(0, 0, -8))
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	return [m, e.f]

## The voxels of `organ` in `part`, a share of them (nearest the front first).
func _of(part: VoxelPart, organ: int, share := 1.0) -> Array:
	var out := []
	for i in part.organ.size():
		if part.organ[i] == organ and part.alive[i]:
			out.append(i)
	out.sort_custom(func(a, b): return part.fz[a] > part.fz[b])
	return out.slice(0, ceili(out.size() * share))

func test_the_organs_lie_inside_the_skin() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	var names := []
	for o in [Anatomy.HEART, Anatomy.LUNG_R, Anatomy.LUNG_L, Anatomy.LIVER, Anatomy.STOMACH, Anatomy.GUTS, Anatomy.SPINE]:
		t.check(_of(v.torso, o).size() >= 8, "the trunk has its %s (%d voxels)" % [Anatomy.organ_name(o), _of(v.torso, o).size()])
	t.check(_of(v.head, Anatomy.BRAIN).size() >= 40, "the head has its brain (%d)" % _of(v.head, Anatomy.BRAIN).size())
	var on_skin := 0
	for p in [v.torso, v.head]:
		for i in p.organ.size():
			if p.organ[i] != Anatomy.NONE and (p.fx[i] == 0 or p.fy[i] == 0 or p.fz[i] == 0 or p.fx[i] == p.grid.x - 1 or p.fy[i] == p.grid.y - 1 or p.fz[i] == p.grid.z - 1):
				on_skin += 1
	t.check(on_skin == 0, "no organ on the skin (%d)" % on_skin)
	t.check(v.torso.kinds[_of(v.torso, Anatomy.HEART)[0]] == 9 and v.torso.bone[_of(v.torso, Anatomy.SPINE)[0]] == 1, "organs drawn as wet flesh, the spine as bone")
	m.queue_free()

func test_a_torn_heart_kills_in_seconds() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	var why := []
	v.died.connect(func(_f, cause): why.append(cause))
	await _steps(30)
	v.torso.remove_voxels(_of(v.torso, Anatomy.HEART, 0.5))
	await _steps(60)
	t.check(v.alive, "a heartbeat later he still stands")
	await _steps(120 * 4)
	t.check(not v.alive and why == ["heart"], "a few seconds later the heart has stopped (%s)" % [why])
	m.queue_free()

func test_torn_lungs_cap_the_breath() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	v.torso.remove_voxels(_of(v.torso, Anatomy.LUNG_R, 0.7) + _of(v.torso, Anatomy.LUNG_L, 0.7))
	v.torso.bleed = 0.0
	await _steps(120 * 3)
	t.check(v.alive and v.breath_cap() < 60.0 and v.stamina <= v.breath_cap() + 0.5, "the breath fills no higher than the lungs allow (%.0f of %.0f)" % [v.stamina, v.breath_cap()])
	m.queue_free()

func test_a_cut_spinal_cord_takes_the_legs() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(60)
	t.check(v.state == "stand", "he stands to begin with")
	var level := []
	for i in _of(v.torso, Anatomy.SPINE):
		if v.torso.fy[i] == 8:
			level.append(i)
	v.torso.remove_voxels(level)
	v.torso.bleed = 0.0
	await _steps(120 * 2)
	t.check(v.cord_legs == 0.0 and not v.can_stand() and v.state != "stand", "the legs fail him (cord %.1f, %s)" % [v.cord_legs, v.state])
	t.check(v.cord_arms == 1.0 and v.arm_func("R") > 0.5, "the arms still work below a low cut (%.2f)" % v.arm_func("R"))
	m.queue_free()

func test_a_broken_brain_fells_him() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	var why := []
	v.died.connect(func(_f, cause): why.append(cause))
	await _steps(30)
	v.head.remove_voxels(_of(v.head, Anatomy.BRAIN, 0.2))
	await _steps(30)
	t.check(v.alive and v.concussion > 0.5, "a bit of it: he is badly rung (%.2f)" % v.concussion)
	v.head.remove_voxels(_of(v.head, Anatomy.BRAIN, 0.4))
	await _steps(30)
	t.check(not v.alive and why == ["brain"], "half of it: he is dead (%s)" % [why])
	m.queue_free()

func test_a_stab_in_the_chest_reaches_the_heart() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var tor := v.torso
	# The heart's middle, and a thrust at it from in front.
	var c := Vector3.ZERO
	var hv := _of(tor, Anatomy.HEART)
	for i in hv:
		c += tor.local_of(i)
	c /= float(hv.size())
	var gt := tor.global_transform
	var fwd := gt.basis.orthonormalized() * Vector3(0, 0, 1)
	var got := []
	var k := 0
	while not got.has("heart") and k < 8:
		tor.hp = 1000.0
		var res: Dictionary = v.apply_hit(tor, {"impulse": 40.0, "type": "point", "hardness": 0.9, "sharpness": 0.9, "point": gt * Vector3(c.x, c.y, tor.half_ext.z), "dir": -fwd, "axis": -fwd})
		got += res.get("organs", [])
		k += 1
		await _steps(4)
	t.check(got.has("heart"), "thrusts at the heart reach it (%d, %s)" % [k, got])
	m.queue_free()

func test_a_hard_blow_to_the_belly_bruises_inside() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var tor := v.torso
	var gt := tor.global_transform
	var fwd := gt.basis.orthonormalized() * Vector3(0, 0, 1)
	var bleed0 := tor.bleed
	var res: Dictionary = v.apply_hit(tor, {"impulse": 35.0, "type": "blunt", "hardness": 0.8, "point": gt * Vector3(-0.05, -0.12, tor.half_ext.z), "dir": -fwd})
	var inside: Array = res.get("organs", [])
	t.check(inside.any(func(o): return o in ["liver", "guts", "stomach"]), "a hammer to the belly bruises what is under it (%s)" % [inside])
	t.check(tor.bleed > bleed0 and v.organ_bruise.values().any(func(b): return b > 0.0), "and it bleeds inside (%.2f)" % (tor.bleed - bleed0))
	m.queue_free()

# ---------- Bones ----------

func test_the_trunk_and_the_head_have_a_skeleton() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	var ribs := _of(v.torso, Anatomy.RIBS)
	t.check(ribs.size() >= 150 and _of(v.torso, Anatomy.PELVIS).size() >= 30 and _of(v.head, Anatomy.SKULL).size() >= 100, "ribs %d, pelvis %d, skull %d" % [ribs.size(), _of(v.torso, Anatomy.PELVIS).size(), _of(v.head, Anatomy.SKULL).size()])
	t.check(ribs.all(func(i): return v.torso.bone[i] == 1 and v.torso.kinds[i] == 6), "bone, drawn as bone")
	t.check(_of(v.torso, Anatomy.SPINE).size() == 80, "the spine whole under the back ribs (%d)" % _of(v.torso, Anatomy.SPINE).size())
	m.queue_free()

## A cut at the forearm from the side, as hard as `J`; returns how many voxels it took.
func _arm_cut(v: Fighter, side: String, J: float) -> Dictionary:
	var fa: VoxelPart = v.arm[side].fore
	fa.hp = 1000.0
	var gt := fa.global_transform
	var bx := gt.basis.orthonormalized()
	return v.apply_hit(fa, {"impulse": J, "type": "edge", "hardness": 0.9, "sharpness": 0.9, "point": gt * Vector3(fa.half_ext.x, 0.0, 0.0), "dir": -bx.x, "axis": bx.z, "edge": -bx.x})

func test_a_light_cut_stops_at_the_bone_a_hard_one_chops_it() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var light := 0
	var hard := 0
	var stopped := false
	for k in 4:
		var res := _arm_cut(v, "R", 7.0)
		stopped = stopped or res.get("bone", false)
		await _steps(4)
	for k in 4:
		_arm_cut(v, "L", 60.0)
		await _steps(4)
	light = _bone_lost(v.arm.R.fore)
	hard = _bone_lost(v.arm.L.fore)
	t.check(stopped and light <= 10, "light cuts reach the bone and only notch it (%d gone)" % light)
	t.check(hard >= 12 and hard >= light * 2, "hard ones chop through it (%d gone)" % hard)
	m.queue_free()

func _bone_lost(p: VoxelPart) -> int:
	var n := 0
	for i in p.fx.size():
		if p.bone[i] and not p.alive[i]:
			n += 1
	return n

func test_a_hammer_breaks_a_shin_and_the_knee_gives() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var sh: VoxelPart = v.by_name.shinR
	var lim: float = sh.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)
	var k := 0
	var res := {}
	while not sh.fractured and k < 6:
		sh.hp = 1000.0
		var gt := sh.global_transform
		var bz := gt.basis.orthonormalized() * Vector3(0, 0, 1)
		res = v.apply_hit(sh, {"impulse": 45.0, "type": "blunt", "hardness": 0.9, "heavy": 1.0, "point": gt * Vector3(0, 0, sh.half_ext.z), "dir": -bz})
		k += 1
		await _steps(4)
	t.check(sh.fractured and sh.function() < 0.2, "the shin is broken (%d blows)" % k)
	t.check(sh.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT) > lim + 0.5, "and the knee bends sideways now")
	t.check(sh.has_meta("open_break"), "a blow that hard opens the skin to the bone")
	m.queue_free()

func test_cracked_ribs_take_the_breath_a_cracked_skull_rings_worse() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var tor := v.torso
	var cap0 := v.breath_cap()
	var k := 0
	while v.ribs_broken == 0 and k < 6:
		tor.hp = 1000.0
		var gt := tor.global_transform
		var bz := gt.basis.orthonormalized() * Vector3(0, 0, 1)
		v.apply_hit(tor, {"impulse": 40.0, "type": "blunt", "hardness": 0.9, "point": gt * Vector3(0.1, tor.half_ext.y * 0.4, tor.half_ext.z), "dir": -bz})
		k += 1
		await _steps(4)
	t.check(v.ribs_broken > 0 and v.breath_cap() < cap0 - 4.0, "ribs cracked (%d), breath %.0f -> %.0f" % [v.ribs_broken, cap0, v.breath_cap()])
	k = 0
	while not v.skull_cracked and k < 8:
		v.head.hp = 1000.0
		v.concussion = 0.0
		var gh := v.head.global_transform
		v.apply_hit(v.head, {"impulse": 45.0, "type": "blunt", "hardness": 0.9, "point": gh * Vector3(v.head.half_ext.x, 0.05, 0), "dir": -(gh.basis.orthonormalized() * Vector3(1, 0, 0))})
		k += 1
		await _steps(4)
	t.check(v.skull_cracked, "a skull cracks (%d)" % k)
	v.concussion = 0.0
	var gh2 := v.head.global_transform
	v.apply_hit(v.head, {"impulse": 15.0, "type": "blunt", "hardness": 0.5, "point": gh2 * Vector3(v.head.half_ext.x, 0.05, 0), "dir": -(gh2.basis.orthonormalized() * Vector3(1, 0, 0))})
	t.check(v.concussion > 15.0 * 0.8 * 0.015 * 1.5, "and the same blow rings it worse now (%.2f)" % v.concussion)
	m.queue_free()

# ---------- Guts ----------

## Slashes across the belly, low and in front, until the guts come out (or 10 blows).
func _open_belly(v: Fighter) -> Dictionary:
	var tor := v.torso
	var res := {}
	var k := 0
	while not v.guts_out and k < 10:
		tor.hp = 1000.0
		v.heart_t = -1.0
		var gt := tor.global_transform
		var bx := gt.basis.orthonormalized()
		var fwd := bx * Vector3(0, 0, 1)
		res = v.apply_hit(tor, {"impulse": 45.0, "type": "edge", "hardness": 0.9, "sharpness": 0.9, "point": gt * Vector3(0.0, -tor.half_ext.y * 0.4, tor.half_ext.z), "dir": -fwd, "axis": bx * Vector3(1, 0, 0), "edge": -fwd})
		k += 1
		await _steps(4)
	return res

func test_an_opened_belly_spills_the_guts_as_a_hanging_chain() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var spilled := []
	v.guts_spilled.connect(func(_f, g, _a, _o): spilled.append(g.size()))
	var res: Dictionary = await _open_belly(v)
	t.check(v.guts_out and spilled.size() == 1, "slashes across the belly open it and the guts come out (%s)" % [spilled])
	var rope: GutRope = GutRope.ropes.back() if not GutRope.ropes.is_empty() else null
	t.check(rope != null and rope.segs.size() >= 4, "as a chain of links (%d)" % (rope.segs.size() if rope else 0))
	if rope == null:
		m.queue_free()
		return
	t.check(rope.segs.all(func(c): return c is Chunk and not c.freeze), "each a free body of its own")
	await _steps(120 * 2)
	var first: Chunk = rope.segs[0]
	var last: Chunk = rope.segs.back()
	t.check(is_instance_valid(first) and first.flap_of == v.torso and first.global_position.distance_to(v.torso.global_position) < 0.6, "two seconds on they still hang from him")
	t.check(last.global_position.y < first.global_position.y, "hanging down (%.2f under %.2f)" % [last.global_position.y, first.global_position.y])
	# A blade swung through a link cuts the chain there.
	var mid: Chunk = rope.segs[rope.segs.size() / 2]
	var w: Weapon = m.spawn_loose_weapon(Data.preset("gladius"), mid.global_position + Vector3(0.4, 0, 0))
	var blade := Vector3.ZERO
	for vv in w.vox:
		blade += Vector3(vv[0], vv[1], vv[2]) * w.vs
	blade /= float(w.vox.size())
	var cut := false
	for i in 40:
		# Swept through the link, blade first, faster than a cut needs.
		w.global_position = mid.global_position + Vector3(0.3 - i * 0.03, 0, 0) - w.global_transform.basis * blade
		w.thrown_t = 1.0
		w.linear_velocity = Vector3(-8, 0, 0)
		await get_tree().physics_frame
		if rope.segs.any(func(c): return is_instance_valid(c) and c.flap_of == null):
			cut = true
			break
	t.check(cut, "a blade through the chain cuts it")
	m.queue_free()

func test_reduced_gore_spills_nothing_but_hurts_the_same() -> void:
	var st: Dictionary = Save.get_value("settings", {}).duplicate()
	var keep = st.get("gore", null)
	st["gore"] = "reduced"
	Save.set_value("settings", st)
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var ropes := GutRope.ropes.size()
	t.check(v.torso.colors[_of(v.torso, Anatomy.HEART)[0]].r > 0.45, "the insides plain flesh")
	await _open_belly(v)
	t.check(v.guts_out and GutRope.ropes.size() == ropes and v.organ_health(Anatomy.GUTS) < 1.0, "the guts are lost, nothing hangs (%.2f)" % v.organ_health(Anatomy.GUTS))
	if keep == null:
		st.erase("gore")
	else:
		st["gore"] = keep
	Save.set_value("settings", st)
	m.queue_free()
