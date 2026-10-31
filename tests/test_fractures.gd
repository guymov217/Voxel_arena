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
	t.check(th.fracture == 3 and th.has_meta("open_break"), "a crushing one breaks the thigh out through the skin (level %d)" % th.fracture)
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
	while v.skull_fracture < 3 and k < 20:
		v.head.hp = 1000.0
		v.concussion = 0.0
		var gh := v.head.global_transform
		v.apply_hit(v.head, {"impulse": 60.0, "type": "blunt", "hardness": 0.9, "point": gh * Vector3(v.head.half_ext.x, 0.05, 0), "dir": -(gh.basis.orthonormalized() * Vector3(1, 0, 0))})
		if lv.is_empty() or lv[-1] != v.skull_fracture:
			lv.append(v.skull_fracture)
		k += 1
		await _steps(3)
	t.check(v.skull_fracture == 3 and v.head.has_meta("open_break"), "hammered, the skull breaks open at last (levels %s)" % [lv])
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
