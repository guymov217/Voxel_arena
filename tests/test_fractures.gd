extends Node
## Broken bones (Fighter._fracture): a blow cracks a bone or breaks it through, under the skin or
## out of it, as hard as it was; a bone broken through leaves the limb no use, not driven, held
## by its muscle only and drawn bent at the break, and it still never passes through the body;
## the skull and the ribs break by degrees too. The campaign keeps them (Body) until the
## physician sets them, no elixir needed, and a guest sees them as the host has them.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _victim(loadout := {}) -> Array:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true, "seed": 5})
	m.me.f.teleport(Vector3(0, 0, -8))
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": loadout, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	return [m, e.f]

## Blunt blows of `J` on the front of `p` until its bone gives (at most `n`).
func _club(v: Fighter, p: VoxelPart, J: float, n := 12) -> int:
	var k := 0
	while p.fracture == 0 and k < n:
		p.hp = 1000.0
		var gt := p.global_transform
		var bz := gt.basis.orthonormalized() * Vector3(0, 0, 1)
		v.apply_hit(p, {"impulse": J, "type": "blunt", "hardness": 0.9, "heavy": 0.0, "point": gt * Vector3(0, 0, p.half_ext.z), "dir": -bz})
		k += 1
		await _steps(3)
	return k

## One blunt blow of `J` on the front of `p`.
func _blow(v: Fighter, p: VoxelPart, J: float) -> void:
	p.hp = 1000.0
	var gt := p.global_transform
	var bz := gt.basis.orthonormalized() * Vector3(0, 0, 1)
	v.apply_hit(p, {"impulse": J, "type": "blunt", "hardness": 0.9, "heavy": 0.0, "point": gt * Vector3(0, 0, p.half_ext.z), "dir": -bz})
	await _steps(3)

func test_a_blow_cracks_or_breaks_as_hard_as_it_was() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var fo: VoxelPart = v.arm.R.fore
	var f0: float = fo.function()
	var k: int = await _club(v, fo, 19.0, 30)
	t.check(fo.fracture == 1 and not fo.fractured, "a fair knock cracks the forearm, no more (level %d after %d blows)" % [fo.fracture, k])
	t.check(fo.function() > 0.3 and fo.function() < f0, "cracked, it still works, less well (%.2f, was %.2f)" % [fo.function(), f0])
	t.check(fo.kink.is_empty(), "and it is not bent")
	var sh: VoxelPart = v.by_name.shinL
	k = await _club(v, sh, 27.0)
	t.check(sh.fracture == 2 and sh.fractured, "a hard blow breaks the shin through, under the skin (level %d)" % sh.fracture)
	t.check(not sh.has_meta("open_break"), "the skin over it whole")
	var th: VoxelPart = v.by_name.thighR
	k = await _club(v, th, 48.0)
	t.check(th.fracture == 2 and not th.has_meta("open_break"), "a heavy one breaks the thigh, but under the skin (level %d)" % th.fracture)
	var ua: VoxelPart = v.arm.L.upper
	k = await _club(v, ua, 80.0)
	t.check(ua.fracture == 2 and not ua.has_meta("open_break"), "a crushing one on a sound upper arm breaks it through, but under the skin: it was not beaten on first (level %d)" % ua.fracture)
	m.queue_free()

## An open break as it happens (user): the work of many blunt blows on the one limb, the bone
## cracked and broken under them, ended by a very hard one that drives the broken ends out through
## the flesh. One crushing blow on a sound limb breaks it under the skin; a broken limb beaten on
## with fair blows stays shut; and the limb is of no use at all after.
func test_an_open_break_takes_a_beating_and_then_a_crushing_blow() -> void:
	var r := _victim({"main": "gladius", "off": "gladius"})
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var sh: VoxelPart = v.by_name.shinR
	await _club(v, sh, 30.0)
	t.check(sh.fracture == 2, "a hard blow breaks the shin under the skin (level %d)" % sh.fracture)
	for i in 12:
		await _blow(v, sh, 30.0)
	t.check(sh.fracture == 2 and not sh.has_meta("open_break"), "beaten on with fair blows, a dozen more, it stays under the skin (level %d)" % sh.fracture)
	await _blow(v, sh, Fighter.OPEN_J + 15.0)
	t.check(sh.fracture == 3 and sh.has_meta("open_break"), "then a very hard blow drives the broken ends out through the skin (level %d)" % sh.fracture)
	t.check(v.leg_broken("R") and v.leg_func("R") < 0.1, "and the leg is of no use at all (%.2f)" % v.leg_func("R"))
	# Nor is a kick: not with it, nor standing on it.
	v.control(1.0 / 120.0, {"kick": true})
	t.check(v.kick_timer <= 0.0, "he cannot kick on a broken leg")
	# A crushing first blow on a sound thigh: broken through, under the skin.
	var th: VoxelPart = v.by_name.thighL
	await _blow(v, th, Fighter.OPEN_J + 15.0)
	t.check(th.fracture == 2 and not th.has_meta("open_break"), "a crushing first blow on a sound thigh breaks it under the skin, not out (level %d)" % th.fracture)
	# A forearm beaten on again and again (cracked, then broken), then struck very hard: open,
	# and what was in its hand falls; the hand takes nothing up again.
	var fo: VoxelPart = v.arm.L.fore
	for i in Fighter.OPEN_AFTER:
		await _blow(v, fo, 16.0)
	t.check(not fo.has_meta("open_break"), "%d fair blows on the forearm do not break it open" % Fighter.OPEN_AFTER)
	await _blow(v, fo, Fighter.OPEN_J + 15.0)
	t.check(fo.fracture == 3 and fo.has_meta("open_break"), "beaten on and then struck very hard, the forearm breaks open (level %d)" % fo.fracture)
	t.check(v.weapons.L == null and not v.hand_works("L") and not v._hand_can_take("L"), "its hand drops what it held and can take nothing up")
	# A blade into the bone: a deep notch breaks it under the cut.
	var fr: VoxelPart = v.arm.R.fore
	var bones := []
	for i in fr.fx.size():
		if fr.alive[i] and fr.bone[i]:
			bones.append(i)
	v._edge_on_bone(fr, bones.slice(0, int(bones.size() * 0.4)), Vector3.ZERO, Vector3(0, 0, -1), 20.0, {})
	t.check(fr.fracture == 2, "a deep notch in the bone breaks it under the skin (level %d)" % fr.fracture)
	m.queue_free()

## Every bone can break, the ribs too, and by an edge as by a club.
func test_a_blade_into_the_ribs_breaks_them() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var tor := v.torso
	var k := 0
	while v.ribs_broken == 0 and k < 20:
		tor.hp = 1000.0
		var gt := tor.global_transform
		var bz := gt.basis.orthonormalized() * Vector3(0, 0, 1)
		v.apply_hit(tor, {"impulse": 30.0, "type": "edge", "sharpness": 1.0, "hardness": 0.9, "point": gt * Vector3(0.1, tor.half_ext.y * 0.4, tor.half_ext.z), "dir": -bz, "axis": gt.basis.orthonormalized() * Vector3(1, 0, 0), "edge": -bz})
		k += 1
		await _steps(3)
	t.check(v.ribs_broken > 0, "a blade cutting into the chest breaks ribs (%d after %d cuts)" % [v.ribs_broken, k])
	m.queue_free()

func test_a_cracked_bone_gives_way_to_less() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var up: VoxelPart = v.arm.L.upper
	up.fracture = 1
	var k := 0
	while not up.fractured and k < 30:
		up.hp = 1000.0
		var gt := up.global_transform
		v.apply_hit(up, {"impulse": 16.0, "type": "blunt", "hardness": 0.9, "heavy": 0.0, "point": gt * Vector3(0, 0, up.half_ext.z), "dir": -(gt.basis.orthonormalized() * Vector3(0, 0, 1))})
		k += 1
		await _steps(3)
	t.check(up.fractured, "cracked, the upper arm breaks through under blows that only crack a whole one (%d blows)" % k)
	m.queue_free()

## Broken through: not driven, flopping from the joint, drawn bent; and still never through him.
func test_a_broken_arm_flops_bent_and_stays_out_of_the_body() -> void:
	var r := _victim({"main": "gladius", "off": ""})
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var fo: VoxelPart = v.arm.R.fore
	var up: VoxelPart = v.arm.R.upper
	var res := {}
	v._fracture(fo, Vector3(0, 0, fo.half_ext.z), 30.0, res, 2, Vector3(0, 0, -1))
	t.check(fo.fractured and v.weapons.R == null, "the forearm broken, the sword falls")
	t.check(not fo.kink.is_empty(), "the forearm is drawn bent at the break")
	var moved := 0
	for i in fo.fx.size():
		if fo.drawn_xf(i).origin.distance_to(fo.local_of(i)) > 0.01:
			moved += 1
	t.check(moved > fo.fx.size() / 5 and moved < fo.fx.size() * 4 / 5, "its far end only (%d of %d voxels drawn turned)" % [moved, fo.fx.size()])
	# He asks the arm for a high guard: a whole arm goes there, a broken one does not.
	var e = m.entity_of(v)
	var hi := {"main": {"x": 0.2, "y": 0.9}, "power": true}
	e.drive = func(_e): return hi
	await _steps(120)
	var hand_y := v.hand_world("R").y - v.torso.global_position.y
	t.check(hand_y < 0.0, "asked up, the broken arm's hand still hangs below the chest (%.2f m)" % hand_y)
	# Turned and shaken hard for a while: the limp arm swings, and never sinks into him.
	e.drive = func(_e): return {}
	var deepest := 0.0
	var swing := 0.0
	for i in 360:
		v.torso.apply_torque_impulse(Vector3(0, 9.0 if (i / 40) % 2 == 0 else -9.0, 0) * v.MS)
		await get_tree().physics_frame
		swing = maxf(swing, (fo.angular_velocity - up.angular_velocity).length())
		for pt in [v.hand_world("R"), fo.global_position, up.global_transform * Vector3(0, -up.half_ext.y, 0)]:
			for body in [v.torso, v.head]:
				var l: Vector3 = body.global_transform.affine_inverse() * pt
				deepest = maxf(deepest, minf(body.half_ext.x - absf(l.x), minf(body.half_ext.y - absf(l.y), body.half_ext.z - absf(l.z))))
	t.check(swing > 1.0, "the forearm flops about on its own (%.1f rad/s against the upper arm)" % swing)
	t.check(deepest < 0.04, "and the arm never sinks into him (deepest %.3f m)" % deepest)
	m.queue_free()

func test_a_broken_leg_is_not_driven_and_he_hops() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var sh: VoxelPart = v.by_name.shinR
	v._fracture(sh, Vector3.ZERO, 30.0, {}, 2)
	t.check(v.leg_func("R") < 0.1, "a broken shin: no leg to stand on (%.2f)" % v.leg_func("R"))
	t.check(v.leg_func("L") > 0.5, "the other leg whole")
	m.queue_free()

func test_the_skull_and_the_ribs_break_by_degrees() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var k := 0
	var lv := []
	while k < 20:
		v.head.hp = 1000.0
		v.concussion = 0.0
		var gh := v.head.global_transform
		v.apply_hit(v.head, {"impulse": 60.0, "type": "blunt", "hardness": 0.9, "point": gh * Vector3(v.head.half_ext.x, 0.05, 0), "dir": -(gh.basis.orthonormalized() * Vector3(1, 0, 0))})
		if lv.is_empty() or lv[-1] != v.skull_fracture:
			lv.append(v.skull_fracture)
		k += 1
		await _steps(3)
	t.check(v.skull_fracture == 2, "hammered, the skull is driven in (levels %s)" % [lv])
	t.check(not v.head.has_meta("open_break") and (v.head.bone_out == null or not v.head.bone_out.visible), "but never broken open: only an arm or a leg breaks out through the skin")
	var tor := v.torso
	var lung0: float = v.lungs()
	k = 0
	while v.ribs_broken < 4 and k < 30:
		tor.hp = 1000.0
		var gt := tor.global_transform
		v.apply_hit(tor, {"impulse": 40.0, "type": "blunt", "hardness": 0.9, "point": gt * Vector3(0.1, tor.half_ext.y * 0.4, tor.half_ext.z), "dir": -(gt.basis.orthonormalized() * Vector3(0, 0, 1))})
		k += 1
		await _steps(3)
	t.check(v.ribs_broken >= 4, "ribs broken one blow after another (%d)" % v.ribs_broken)
	t.check(v.lungs() < lung0, "and broken in, they hurt the lung under them (%.2f -> %.2f)" % [lung0, v.lungs()])
	t.check(not tor.has_meta("open_break"), "never out through the chest")
	m.queue_free()

## Out through the skin only in an arm or a leg (user): a man's upper arms, forearms, thighs and
## shins, a beast's legs; never his head or trunk, nor a beast's neck or tail.
func test_only_an_arm_or_a_leg_breaks_open() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(10)
	var open := []
	var shut := []
	for p in v.parts:
		(open if v.can_break_open(p) else shut).append(String(p.part_name))
	open.sort()
	t.check(open == ["forearmL", "forearmR", "shinL", "shinR", "thighL", "thighR", "upperArmL", "upperArmR"], "a man: his arms and legs (%s)" % [open])
	t.check(shut.has("head") and shut.has("torso"), "not his head or trunk")
	var b = m.spawn_beast({"beast": "lion", "team": 1, "pos": Vector3(3, 0.1, 3), "yaw": 0.0})
	await _steps(5)
	var lion: Beast = b.f
	var legs_open := true
	var rest_shut := true
	for p in lion.parts:
		if bool(p.def.get("leg", false)):
			legs_open = legs_open and lion.can_break_open(p)
		else:
			rest_shut = rest_shut and not lion.can_break_open(p)
	t.check(legs_open, "a beast: its legs")
	t.check(rest_shut, "and nothing else of it")
	var tail = null
	for p in lion.parts:
		if not bool(p.def.get("leg", false)) and p != lion.torso and p != lion.head and p.bone.has(1):
			tail = p
			break
	if tail:
		lion._fracture(tail, Vector3.ZERO, 200.0, {}, 3)
		t.check(tail.fracture == 2 and not tail.has_meta("open_break"), "a blow that would break a leg open breaks its %s under the skin (level %d)" % [tail.part_name, tail.fracture])
	m.queue_free()

## Out through the skin where it makes sense on a leg (user): the thigh and the shin, in the
## middle of the shaft (user: only mid-limb), nearest where the blow fell along the bone and on the
## side it came from; never by the knee, the hip or the ankle, a beast's the same.
func test_a_leg_breaks_open_where_it_was_struck() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(10)
	# [part, how far up it the blow fell (of its half length), the side it came from]
	var cases := [["thighL", 0.4, Vector3(0, 0, 1)], ["thighR", -0.35, Vector3(1, 0, 0)],
		["shinL", 0.0, Vector3(-1, 0, 0)], ["shinR", -0.4, Vector3(0, 0, 1)]]
	for c in cases:
		var p: VoxelPart = v.by_name[c[0]]
		var ax: int = p._root_axis()[0]
		var d: Vector3 = c[2]
		var lp: Vector3 = d * p.half_ext
		lp[ax] = float(c[1]) * p.half_ext[ax]
		v._fracture(p, lp, 200.0, {}, 3, -d)
		var ex := p.break_exit()
		t.check(p.fracture == 3 and p.has_meta("open_break") and not ex.is_empty(), "%s struck %+.2f up it breaks open" % [c[0], c[1]])
		if ex.is_empty():
			continue
		var br := p.break_range()
		var want := clampf(float(c[1]) * p.half_ext[ax], br.x, br.y)
		t.check(absf((ex[0] as Vector3)[ax] - want) < 0.01, "%s: out nearest where it was struck along the bone, in the middle of the shaft (%.3f, struck at %.3f)" % [c[0], (ex[0] as Vector3)[ax], float(c[1]) * p.half_ext[ax]])
		t.check((ex[1] as Vector3).dot(d) > 0.9, "%s: on the side the blow came from (%.2f)" % [c[0], (ex[1] as Vector3).dot(d)])
	# Struck at the very end of the shin, by the knee: it breaks open in the shaft below it, not
	# in the joint.
	var r2 := _victim()
	var v2: Fighter = r2[1]
	await _steps(10)
	var sh: VoxelPart = v2.by_name.shinR
	var ax2: int = sh._root_axis()[0]
	var lp2: Vector3 = Vector3(0, 0, 1) * sh.half_ext
	lp2[ax2] = 0.97 * sh.half_ext[ax2]
	v2._fracture(sh, lp2, 200.0, {}, 3, Vector3(0, 0, -1))
	var ex2 := sh.break_exit()
	var br2 := sh.break_range()
	t.check(not ex2.is_empty() and (ex2[0] as Vector3)[ax2] >= br2.x - 0.005 and (ex2[0] as Vector3)[ax2] <= br2.y + 0.005, "struck by the knee, it breaks open in the middle of the shaft below it (%.3f, the middle %.3f..%.3f)" % [(ex2[0] as Vector3)[ax2] if not ex2.is_empty() else INF, br2.x, br2.y])
	# Struck from between the legs, the inside of the thigh: out the outside of it, never toward
	# the body.
	var th2: VoxelPart = v2.by_name.thighL
	var ax4: int = th2._root_axis()[0]
	var along4: Vector3 = th2._across()[2]
	var med: Vector3 = th2.global_transform.affine_inverse() * v2.torso.global_position
	med -= along4 * med.dot(along4)
	med = med.normalized()
	var lp4: Vector3 = med * th2.half_ext
	lp4[ax4] = 0.1 * th2.half_ext[ax4]
	v2._fracture(th2, lp4, 200.0, {}, 3, -med)
	var outw := th2.bone_dir - along4 * th2.bone_dir.dot(along4)
	t.check(th2.has_meta("open_break") and outw.length() > 0.1 and outw.normalized().dot(med) < 0.25, "struck on the inside of the thigh, the bone comes out away from the body (%.2f)" % (outw.normalized().dot(med) if outw.length() > 0.1 else 9.0))
	# A beast's leg, struck high: open in the shaft, as near there as the middle of it goes.
	var b = m.spawn_beast({"beast": "lion", "team": 1, "pos": Vector3(3, 0.1, 3), "yaw": 0.0})
	await _steps(5)
	var lion: Beast = b.f
	var leg: VoxelPart = null
	for p in lion.parts:
		if bool(p.def.get("leg", false)) and p.bone.has(1):
			leg = p
			break
	if leg:
		var ax3: int = leg._root_axis()[0]
		var side := (ax3 + 1) % 3
		var d3 := Vector3.ZERO
		d3[side] = 1.0
		var lp3: Vector3 = d3 * leg.half_ext
		lp3[ax3] = 0.4 * leg.half_ext[ax3]
		lion._fracture(leg, lp3, 400.0, {}, 3, -d3)
		var ex3 := leg.break_exit()
		var br3 := leg.break_range()
		t.check(leg.has_meta("open_break") and not ex3.is_empty() and absf((ex3[0] as Vector3)[ax3] - clampf(0.4 * leg.half_ext[ax3], br3.x, br3.y)) < 0.01, "a lion's %s breaks open nearest where it was struck, in the middle of the shaft" % leg.part_name)
	else:
		t.check(false, "the lion has a leg with a bone")
	m.queue_free()
	r2[0].queue_free()

## Open only from blunt blows (user): a sword through a limb's bone breaks it, the limb of no use
## after, but under the skin, however heavy the chop; a broken limb cut at again and again stays
## shut.
func test_a_blade_through_the_bone_breaks_it_without_opening_it() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(20)
	var fo: VoxelPart = v.arm.R.fore
	var bones := []
	for i in fo.fx.size():
		if fo.alive[i] and fo.bone[i]:
			bones.append(i)
	var f0: float = fo.function()
	v._edge_on_bone(fo, bones.slice(0, int(bones.size() * 0.75)), Vector3.ZERO, Vector3(0, 0, -1), 30.0, {})
	t.check(fo.fracture == 2 and fo.fractured and not fo.has_meta("open_break"), "a sword through most of the forearm's bone breaks it, under the skin (level %d)" % fo.fracture)
	t.check(fo.function() < 0.1 and f0 > 0.5, "and the arm is of no use after (%.2f, was %.2f)" % [fo.function(), f0])
	var fl: VoxelPart = v.arm.L.fore
	bones = []
	for i in fl.fx.size():
		if fl.alive[i] and fl.bone[i]:
			bones.append(i)
	v._edge_on_bone(fl, bones.slice(0, int(bones.size() * 0.75)), Vector3.ZERO, Vector3(0, 0, -1), Fighter.OPEN_J + 5.0, {})
	t.check(fl.fracture == 2 and not fl.has_meta("open_break"), "a chop as heavy as the hardest blows breaks it through, under the skin: a blade does not drive the bone out (level %d)" % fl.fracture)
	var sh: VoxelPart = v.by_name.shinR
	await _club(v, sh, 30.0)
	t.check(sh.fracture == 2, "a hard blow breaks the shin under the skin (level %d)" % sh.fracture)
	for k in 12:
		sh.hp = 1000.0
		var gt := sh.global_transform
		var bs := gt.basis.orthonormalized()
		v.apply_hit(sh, {"impulse": 30.0, "type": "edge", "hardness": 0.9, "sharpness": 0.05, "heavy": 0.0, "point": gt * Vector3(0, 0, sh.half_ext.z), "dir": bs * Vector3(0, 0, -1), "axis": bs * Vector3(1, 0, 0)})
		await _steps(3)
	t.check(sh.fracture == 2 and not sh.has_meta("open_break"), "cut at twelve times more, it stays under the skin (level %d)" % sh.fracture)
	m.queue_free()

## Everything is voxels and everything breaks, the open break too (user): the bone standing out
## of it is cubes of bone, solid to a blow, and a blow that meets it knocks them off; a hard one
## through the shaft snaps its end off, and what is left of it breaks away blow by blow.
func test_the_bone_out_of_an_open_break_breaks_too() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(20)
	var sh: VoxelPart = v.by_name.shinR
	var ax: int = sh._root_axis()[0]
	var lp: Vector3 = Vector3(0, 0, 1) * sh.half_ext
	v._fracture(sh, lp, 200.0, {}, 3, Vector3(0, 0, -1))
	var n0 := sh.bone_out_left()
	t.check(sh.has_meta("open_break") and n0 > 40, "the bone stands out of the open break as cubes of bone (%d)" % n0)
	t.check(sh.bone_shape != null and not sh.bone_shape.disabled, "solid to a blow, like the rest of him")
	var len0: float = (sh.bone_shape.shape as BoxShape3D).size.y if sh.bone_shape else 0.0
	# A club across the middle of what stands out: it snaps there, the end flies off.
	var mid: Vector3 = sh.bo_origin + sh.bone_dir * (sh.bo_skin + (sh.bo_top - sh.bo_skin) * 0.4)
	var across: Vector3 = sh.bo_basis.x
	var gt := sh.global_transform
	var bs := gt.basis.orthonormalized()
	var res: Dictionary = v.apply_hit(sh, {"impulse": 40.0, "type": "blunt", "hardness": 0.9, "heavy": 0.3, "point": gt * mid, "dir": bs * -across})
	var n1 := sh.bone_out_left()
	t.check(int(res.get("bone_bits", 0)) > 0 and n1 < n0 * 0.75, "a club across it knocks its cubes off and snaps the end off (%d of %d left)" % [n1, n0])
	t.check(sh.bone_shape == null or (sh.bone_shape.shape as BoxShape3D).size.y < len0 - 0.01, "and less of it stands out to be struck (%.3f, was %.3f)" % [(sh.bone_shape.shape as BoxShape3D).size.y if sh.bone_shape else 0.0, len0])
	# Beaten on at the skin, the stump breaks away too.
	for k in 6:
		if sh.bone_out_left() == 0:
			break
		var low: Vector3 = sh.bo_origin + sh.bone_dir * (sh.bo_skin + sh.bo_s * 1.5)
		v.apply_hit(sh, {"impulse": 45.0, "type": "blunt", "hardness": 0.9, "heavy": 0.5, "point": gt * low, "dir": bs * -across})
		await _steps(2)
	t.check(sh.bone_out_left() < n1 * 0.4, "beaten on, what was left breaks away (%d left)" % sh.bone_out_left())
	m.queue_free()

## The campaign: broken bones are carried to the next fight until the physician sets them.
func test_the_physician_sets_bones_without_the_elixir() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	v._fracture(v.arm.L.fore, Vector3.ZERO, 30.0, {}, 3)
	v._fracture(v.by_name.shinR, Vector3.ZERO, 30.0, {}, 1)
	v.ribs_broken = 2
	v.skull_fracture = 2
	v.skull_cracked = true
	var mg := Body.merge(Body.empty(), Body.snapshot(v))
	var b: Dictionary = mg.body
	t.eq(int(b.fractures.get("forearmL", 0)), 3, "the open break of the left forearm is kept")
	t.eq(int(b.fractures.get("shinR", 0)), 1, "the cracked shin too")
	t.eq(int(b.fractures.get("ribs", 0)), 2, "two broken ribs")
	t.eq(int(b.fractures.get("skull", 0)), 2, "and the skull driven in")
	t.check(mg.doctor, "a bone broken through sends him to the physician")
	t.check(str(mg.news).contains("forearm"), "the news says so (%s)" % [mg.news])
	var saved := Body.sanitize(JSON.parse_string(JSON.stringify(b)))
	t.eq(saved.fractures.size(), 4, "they survive a save")
	# The next fight: as broken as he left the last.
	var e2 = m.spawn_fighter({"kind": "bot", "name": "W", "loadout": {}, "team": 1, "pos": Vector3(3, 0.1, 0), "yaw": PI, "body": saved})
	var w: Fighter = e2.f
	await _steps(5)
	t.check(w.arm.L.fore.fractured and w.arm.L.fore.fracture == 3 and not w.arm.L.fore.kink.is_empty(), "the forearm is still broken (and bent) in the next fight")
	t.check(w.by_name.shinR.fracture == 1 and not w.by_name.shinR.fractured, "the shin still cracked")
	t.check(w.ribs_broken == 2 and w.skull_cracked, "the ribs and the skull as they were")
	var offers := Body.offers(saved, 5)
	var sets := offers.filter(func(o): return String(o.id).begins_with("set:"))
	t.eq(sets.size(), 4, "the physician offers to set each of them")
	for o in sets:
		t.check(int(o.price) > 0 and int(o.price) < Body.elixir_price(5), "%s for %d, less than the elixir" % [o.name, o.price])
		t.eq(Body.price_of(String(o.id), saved, 5), int(o.price), "the price is the same asked again")
	var open_p: int = sets.filter(func(o): return o.id == "set:forearmL")[0].price
	var crack_p: int = sets.filter(func(o): return o.id == "set:shinR")[0].price
	t.check(open_p > crack_p, "an open break costs more to set than a crack (%d, %d)" % [open_p, crack_p])
	var healed := saved
	for o in sets:
		healed = Body.apply(healed, String(o.id))
	t.check(healed.fractures.is_empty(), "set, every bone is whole")
	t.check(Body.summary(saved).contains("open break") and not Body.summary(healed).contains("broken") and not Body.summary(healed).contains("break"), "the summary says so (%s / %s)" % [Body.summary(saved), Body.summary(healed)])
	var e3 = m.spawn_fighter({"kind": "bot", "name": "X", "loadout": {}, "team": 1, "pos": Vector3(-3, 0.1, 0), "yaw": PI, "body": healed})
	await _steps(5)
	t.check(not e3.f.arm.L.fore.fractured and e3.f.arm.L.fore.kink.is_empty(), "and in the next fight the forearm is straight and works")
	m.queue_free()

## A guest sees the bones as the host has them: broken, and bent the same way.
func test_a_guest_sees_the_break() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	v._fracture(v.by_name.thighL, Vector3(0, -0.05, 0), 30.0, {}, 2, Vector3(1, 0, 0))
	var e2 = m.spawn_fighter({"kind": "bot", "name": "G", "loadout": {}, "team": 1, "pos": Vector3(3, 0.1, 0), "yaw": PI})
	var g: Fighter = e2.f
	await _steps(3)
	g.apply_status(v.status_packed())
	var a: VoxelPart = v.by_name.thighL
	var b: VoxelPart = g.by_name.thighL
	t.check(b.fractured and b.fracture == 2, "the guest's copy is broken")
	t.check(not b.kink.is_empty() and int(b.kink[4]) == int(a.kink[4]) and absf(float(b.kink[1]) - float(a.kink[1])) < 0.01, "bent at the same place, the same way")
	m.queue_free()

## A break follows the blow that made it (user: from any angle, as the blow fell and as hard as
## it was): bent where it landed along the limb, the far end driven the way the blow went (at any
## angle round the bone, not one of four), further the harder it was; an open one comes out at
## the break on the outside of the bend, the side the blow came from.
func test_a_break_follows_the_blow() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(20)
	var p: VoxelPart = v.by_name.shinR
	var ac := p._across()
	var seen := []
	for k in 6:
		var th := TAU * k / 6.0 + 0.3
		var ld: Vector3 = ((ac[0] as Vector3) * cos(th) + (ac[1] as Vector3) * sin(th)).normalized()
		var code := p.kink_code(Vector3.ZERO, ld, 0.5)
		var push := p.kink_push(code)
		t.check(push.dot(ld) > 0.98, "a blow from %d degrees drives the far end its own way (%.3f)" % [roundi(rad_to_deg(th)), push.dot(ld)])
		seen.append(code)
	t.check(seen.size() == 6 and seen.all(func(c): return seen.count(c) == 1), "six blows, six ways (%s)" % [seen])
	# Where along it, and how far, as the blow was.
	var ax: int = p._root_axis()[0]
	var at := Vector3.ZERO
	at[ax] = p.half_ext[ax] * 0.3
	var ld2: Vector3 = ac[0]
	v._fracture(p, at + ld2 * -p.half_ext[(ax + 1) % 3], 26.0, {}, 2, ld2)
	var brk := p.break_range()
	t.check(absf(float(p.kink[1]) - clampf(at[ax], brk.x, brk.y)) < 0.01, "bent where the blow landed along the shin, in the middle of its bone (%.3f, struck at %.3f)" % [float(p.kink[1]), at[ax]])
	var soft := float(p.kink[5])
	var q: VoxelPart = v.by_name.shinL
	v._fracture(q, at, 60.0, {}, 2, ld2)
	t.check(float(q.kink[5]) > soft + 0.1, "a harder blow bends it further (%.2f against %.2f)" % [q.kink[5], soft])
	# Open: out at the break, on the side the blow came from.
	var fo: VoxelPart = v.arm.R.fore
	var ld3: Vector3 = fo._across()[1]
	v._fracture(fo, Vector3.ZERO, 52.0, {}, 3, ld3)
	var ex := fo.break_exit()
	t.check(not ex.is_empty() and (ex[1] as Vector3).dot(-ld3) > 0.98, "an open break comes out on the side the blow came from")
	t.check(absf((ex[0] as Vector3)[fo._root_axis()[0]] - float(fo.kink[1])) < 0.01, "and at the break itself")
	m.queue_free()

## Where nothing is drawn nothing swings: a break is drawn at once as it always was, no piece of it
## waiting on a frame to be set swinging (VoxelPart.start_due, a screen's); and what changes of a
## part while its own boxes are out of sight (under a finer look that draws it) is not written to
## them, and is when they are drawn again (boxes_back).
func test_a_break_without_a_screen_and_boxes_out_of_sight() -> void:
	var mv := _victim()
	var m: Match = mv[0]
	var v: Fighter = mv[1]
	await _steps(10)
	var p: VoxelPart = v.by_name["forearmR"]
	var ax: int = p._root_axis()[0]
	var at := Vector3.ZERO
	at[ax] = p.half_ext[ax] * 0.1
	p.set_kink(at, 0.4, 40)
	t.check(not p.kink.is_empty() and not p._dangle_due and not p.bent_drawn(), "broken, drawn at once: nothing waits to be set swinging")
	p.start_due()
	t.check(p.dangle_mm == null and not p.kink.is_empty(), "and nothing is")
	p.set_kink(Vector3.ZERO, 0.0, 0)
	t.check(p.kink.is_empty(), "set straight again")
	var q: VoxelPart = v.by_name["thighL"]
	t.check(q.mmi != null and q._boxes() and not q._boxes_stale, "drawn, a part's own boxes are written")
	q.mmi.visible = false
	var left0 := q.alive_count
	q.wound(Vector3(0, 0, q.half_ext.z), 0.08, "bruise")
	q.remove_voxels(q.voxels_within(Vector3(q.half_ext.x, 0, 0), 0.05))
	t.check(not q._boxes() and q._boxes_stale, "out of sight they are not (%d voxels gone)" % (left0 - q.alive_count))
	q.mmi.visible = true
	q.boxes_back()
	t.check(q._boxes() and not q._boxes_stale, "and are written whole when they are drawn again")
	m.queue_free()
