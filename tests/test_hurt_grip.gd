extends Node
## A cut-off hand lets go of what both hands held and takes nothing up again; a stump hangs at
## the side; a long haft is held with the hands apart; a fighter on weak legs stands on the sand,
## not in it (user videos: the crocodile's bite, the cyclops knee-deep, the pole hammer).

var t

func _match(lo := {"main": "gladius", "off": ""}, training := {"enemy": "none"}) -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": training, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": lo})
	return m

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _sole(f: Fighter, sd: String) -> float:
	var sh: VoxelPart = f.by_name["shin" + sd]
	return (sh.global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)).y - f.ground_level

func test_a_cut_off_hand_lets_go_of_the_haft_and_its_stump_hangs_still() -> void:
	var m := _match({"main": "warhammer", "off": ""})
	var f: Fighter = m.me.f
	var k := [0]
	m.me.drive = func(_e):
		k[0] += 1
		return {"main": {"x": sin(k[0] * 0.05) * 2.0, "y": 0.3}, "power": true}
	await _steps(120)
	t.check(f.two_handed, "the hammer starts in both hands")
	f.detach_limb(f.arm.L.fore, {"removed": [], "severed": []})
	await _steps(1)
	t.check(not f.two_handed and f.weapon_joints.L == null, "the hand that is gone holds the haft no longer")
	await _steps(300)
	var spin := 0.0
	for i in 300:
		await get_tree().physics_frame
		spin += (f.arm.L.upper.angular_velocity - f.torso.angular_velocity).length()
	t.check(spin / 300.0 < 3.0, "the stump does not whirl after the hammer (%.1f rad/s)" % (spin / 300.0))
	t.check(f.weapons.R != null, "the good hand keeps the hammer")
	m.queue_free()

func test_a_cut_off_hand_takes_no_part_in_picking_up() -> void:
	var m := _match({"main": "", "off": ""})
	var f: Fighter = m.me.f
	m.me.drive = func(_e): return {}
	await _steps(60)
	f.detach_limb(f.arm.L.fore, {"removed": [], "severed": []})
	await _steps(30)
	var w := m.spawn_loose_weapon(Data.preset("warhammer"), f.hand_world("R"))
	t.check(f.pick_up("R", w), "the good hand takes up a two-handed hammer")
	t.check(not f.two_handed and f.weapon_joints.L == null, "and holds it alone: the stump does not close on it")
	t.eq(f.toggle_grip(), null, "nor can both hands be put to it")
	m.queue_free()

func test_a_long_haft_is_held_with_the_hands_apart() -> void:
	var vox := []
	for y in 56:
		vox.append([0, y, 0, "wood", "grip" if y < 14 else "blunt"])
	var g = ForgeLib.two_hand_points({"voxels": vox, "twoHanded": true, "grips": {"main": [0, 3, 0], "off": [0, 0, 0]}})
	t.check(g != null and (g.main as Vector3).distance_to(g.off) >= 10.0, "two fists left side by side at the butt of a 2.2 m haft go apart (%s)" % [g])
	t.check(g != null and (g.off as Vector3).y < (g.main as Vector3).y, "the off hand stays below the main one")
	for k in ["zweihander", "warhammer", "spear", "longsword"]:
		var d: Dictionary = Data.preset(k)
		var raw = ForgeLib.grip_points(d)
		var got = ForgeLib.two_hand_points(d)
		t.check(got == null or ((got.main as Vector3).is_equal_approx(raw.main) and (got.off as Vector3).distance_to(raw.main) > 0.0), "%s keeps its grips" % k)

func test_weak_legs_stand_on_the_sand_not_in_it() -> void:
	var m := _match({"main": "gladius", "off": ""}, {"enemy": "foe:cyclops", "behaviour": "fights", "difficulty": 0.8})
	var e = null
	for x in m.entities:
		if x != m.me:
			e = x
	var f: Fighter = e.f
	m.me.f.teleport(Vector3(0, 0.1, -30))
	await _steps(60)
	for n in ["shinL", "shinR", "thighL", "thighR"]:
		f.by_name[n].hp = 35.0
	f.fall(1.0, true)
	var under := 0
	var stood := 0
	for i in 1500:
		await get_tree().physics_frame
		if f.state != "stand" and f.state != "rising":
			continue
		stood += 1
		if minf(_sole(f, "L"), _sole(f, "R")) < -0.08 * f.S:
			under += 1
	t.check(stood > 600, "the cyclops gets up on his hacked legs (%d steps up)" % stood)
	t.check(under < 30, "and his feet stay on the sand, not knee-deep in it (%d steps under)" % under)
	m.queue_free()

func test_a_two_hander_with_a_dagger_in_the_other_hand_holds_both() -> void:
	var m := _match({"main": "longsword", "off": "dagger"})
	var f: Fighter = m.me.f
	m.me.drive = func(_e): return {}
	await _steps(30)
	t.check(f.weapons.R != null and f.weapons.L != null and not f.two_handed, "the longsword in one hand, the dagger in the other")
	m.queue_free()
	m = _match({"main": "gladius", "off": "longsword"})
	f = m.me.f
	m.me.drive = func(_e): return {}
	await _steps(30)
	t.check(f.weapons.L != null and str(f.weapons.L.design.name) == "Longsword", "and a longsword goes in the off hand")
	m.queue_free()
	m = _match({"main": "longsword", "off": ""})
	f = m.me.f
	m.me.drive = func(_e): return {}
	await _steps(30)
	t.check(f.two_handed, "with nothing for the other hand, both take the longsword")
	m.queue_free()

func test_a_pot_is_never_readied_in_the_hand_round_the_weapon() -> void:
	var m := _match({"main": "warhammer", "off": ""})
	var f: Fighter = m.me.f
	m.me.drive = func(_e): return {}
	await _steps(60)
	t.check(f.two_handed, "the hammer in both hands")
	m.throwables.hold_item(m.me, "pot_fire", "pot_fire")
	t.eq(f.held_item.side, "L", "the pot goes to the off hand")
	t.check(not f.two_handed and f.weapons.R != null, "which lets go of the haft for it; the hammer stays in the right")
	m.queue_free()
	m = _match({"main": "gladius", "off": "roundShield"})
	f = m.me.f
	m.me.drive = func(_e): return {}
	await _steps(30)
	t.eq(f.item_hand(), "L", "both hands full: the shield hand takes the pot, not the sword hand")
	m.queue_free()

## H with the weapon low across to the far hip, where the haft's other end is behind him: the
## off hand never closes on it there (user: it took hold behind his back), and a hand dragged
## round behind lets go and comes out in front.
func test_the_off_hand_never_takes_the_haft_behind_the_back() -> void:
	for wk in ["mace", "longsword", "warhammer", "spear"]:
		var m := _match({"main": wk, "off": ""})
		var f: Fighter = m.me.f
		var press := [false]
		var k := [0]
		m.me.drive = func(_e):
			k[0] += 1
			var d := {"main": {"x": 1.9 * sin(k[0] / 120.0 * 1.7), "y": -1.2 + 0.4 * sin(k[0] / 120.0)}, "power": true}
			if press[0]:
				d.grip = true
				press[0] = false
			return d
		await _steps(60)
		if f.two_handed:
			f.toggle_grip()
		var worst := 0.0
		var stuck := 0
		for i in 120 * 8:
			if i % 150 == 0:
				press[0] = true
			await get_tree().physics_frame
			var l: Vector3 = f.torso.global_transform.affine_inverse() * f.hand_world("L")
			var e: Vector3 = f.torso.half_ext
			var b := -e.z - l.z
			if absf(l.x) < e.x * 1.3 and l.y > -1.2 * e.y and l.y < 1.3 * e.y and b > 0.0:
				stuck += 1
				if f.two_handed:
					worst = maxf(worst, b)
		t.check(worst < 0.04 * f.S, "%s: on the haft the off hand is not behind the back (%.2f m)" % [wk, worst])
		t.check(stuck < 60, "%s: and a free hand is not left there either (%d steps of 960)" % [wk, stuck])
		m.queue_free()
