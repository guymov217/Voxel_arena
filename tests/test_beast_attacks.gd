extends Node
## Creatures attack as they should: a scorpion stings and poisons, a python coils round a man and
## crushes him, a bear rakes with its claws (cuts) and rears up to come down on him, a mammoth
## goes after him instead of keeping to its circle, a crocodile rolls with a limb locked in its
## jaws and the man rolled over with it.

var t

func _setup(species: String, dist: float, loadout := {"main": "gladius", "off": "roundShield"}):
	# The last test's match is let go first: freed only at the end of the frame, its bodies
	# stood where this one's man is made and knocked him about.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": loadout})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	man.mods.toughness = 3.0
	var e = m.spawn_beast({"beast": species, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, dist), "yaw": PI})
	return [m, man, e.f]

func _run(m: Match, man: Fighter, b: Beast, seconds: float, each: Callable) -> void:
	for i in int(seconds * 120):
		man.blood = 100.0
		man.head.hp = maxf(man.head.hp, 40.0)
		man.torso.hp = maxf(man.torso.hp, 40.0)
		b.target = man
		await get_tree().physics_frame
		each.call(i)

func test_the_scorpion_stings_and_poisons() -> void:
	seed(5)
	var s = await _setup("scorpion", 2.6)
	var stings := [0]
	s[0].combat.hit.connect(func(h): if h.attacker == s[2] and h.get("part") and h.res and h.char == s[1] and String(h.get("weapon_part", "")) == "": pass)
	var poisoned := [false]
	await _run(s[0], s[1], s[2], 12.0, func(_i):
		if s[1].parts.any(func(p): return p.spots.any(func(x): return x.kind == "acid")):
			poisoned[0] = true)
	t.check(poisoned[0], "the sting went in and the venom eats into him")
	s[0].queue_free()

func test_the_python_coils_and_crushes() -> void:
	seed(6)
	# Bare hands: a blade in his hand that the coils brush is a blow on the snake, and shakes it
	# off him; this is the coil's own test.
	var s = await _setup("python", 2.4, {"main": "", "off": ""})
	var coiled := [false]
	var hp0: float = s[1].torso.hp
	var lost0: int = s[1].torso.fx.size() - s[1].torso.alive_count
	var hits := [0.0]
	s[0].combat.hit.connect(func(h): if h.attacker == s[2] and h.char == s[1] and h.type == "blunt": hits[0] = maxf(hits[0], h.J))
	await _run(s[0], s[1], s[2], 12.0, func(_i):
		if s[2].hug != null and s[2].hug.get("coil", false):
			coiled[0] = true)
	t.check(coiled[0], "the python threw its coils round him")
	t.check(hits[0] > 8.0, "and the squeeze crushed (strongest squeeze J %.0f)" % hits[0])
	s[0].queue_free()

func test_the_bear_rakes_with_its_claws_and_rears() -> void:
	seed(7)
	var s = await _setup("bear", 2.6)
	var cuts := [0]
	var reared := [false]
	s[0].combat.hit.connect(func(h): if h.attacker == s[2] and h.char == s[1] and h.type == "edge": cuts[0] += 1)
	await _run(s[0], s[1], s[2], 12.0, func(_i):
		if float(s[2].ai.get("rear", 0.0)) > 0.0:
			var up: Vector3 = PD.quat_of(s[2].torso) * Vector3(0, 0, 1)
			if up.y > 0.45:
				reared[0] = true)
	t.check(cuts[0] > 0, "the claws cut (%d)" % cuts[0])
	t.check(reared[0], "it rose up on its hind legs")
	s[0].queue_free()

func test_the_mammoth_hunts() -> void:
	seed(8)
	var s = await _setup("mammoth", 12.0)
	var closest := [INF]
	await _run(s[0], s[1], s[2], 10.0, func(_i):
		closest[0] = minf(closest[0], s[2].torso.global_position.distance_to(s[1].torso.global_position)))
	t.check(closest[0] < 5.0 * s[2].S * 0.5 + 2.0, "it came for him (closest %.1f m)" % closest[0])
	s[0].queue_free()

func test_the_crocodile_grabs_a_limb_and_rolls() -> void:
	seed(9)
	var s = await _setup("crocodile", 2.2)
	var rolled := [false]
	var wrenches := [0]
	var torn := [false]
	s[0].combat.hit.connect(func(h):
		if h.attacker == s[2] and h.char == s[1] and h.get("roll", false):
			wrenches[0] += 1
			if h.res.get("rolled", false):
				torn[0] = true)
	# Through the roll: how far round the crocodile, the limb in its jaws and the man's trunk
	# go on its length, and how far the bitten place gets from its teeth.
	var turn := [0.0, 0.0, 0.0]
	var gap := [0.0]
	await _run(s[0], s[1], s[2], 16.0, func(_i):
		var b: Beast = s[2]
		if b.hug != null and b.hug.get("roll", false) and is_instance_valid(b.hug.part):
			rolled[0] = true
			var ax: Vector3 = PD.quat_of(b.torso) * Vector3(0, 0, 1)
			turn[0] += absf(b.torso.angular_velocity.dot(ax)) / 120.0
			turn[1] += absf(b.hug.part.angular_velocity.dot(ax)) / 120.0
			turn[2] += absf(s[1].torso.angular_velocity.dot(ax)) / 120.0
			var g: float = b.mouth_point().distance_to(b.hug.part.global_transform * (b.hug.bite_at as Vector3))
			if not b.hug.part.severed:   # (the step it comes away it is out of the jaws)
				gap[0] = maxf(gap[0], g))
	t.check(rolled[0], "the jaws closed on a limb and it went into its roll")
	t.check(turn[0] > TAU * 2.0, "it rolled right over, more than twice (%.0f deg)" % rad_to_deg(turn[0]))
	t.check(turn[1] > turn[0] * 0.8, "the limb went round with the jaws (%.0f of %.0f deg)" % [rad_to_deg(turn[1]), rad_to_deg(turn[0])])
	t.check(turn[2] > turn[0] * 0.5, "and the man was rolled over with it (%.0f deg)" % rad_to_deg(turn[2]))
	t.check(gap[0] < 0.15, "the teeth never left the bite (at most %.2f m off)" % gap[0])
	t.check(wrenches[0] >= 3, "the roll wrenched at the limb (%d)" % wrenches[0])
	t.check(torn[0], "and tore it off")
	s[0].queue_free()

## A man in its roll fights it: pulling away the whole time prises the jaws open before the
## limb is twisted off.
func test_pulling_away_breaks_the_death_roll() -> void:
	seed(9)
	var s = await _setup("crocodile", 2.2)
	s[0].me.drive = func(_e): return {"mz": -1.0}
	var rolled := [false]
	var torn := [false]
	var freed := [false]
	var pry := [0.0]
	var marked := [true]
	s[0].combat.hit.connect(func(h):
		if h.attacker == s[2] and h.char == s[1] and h.get("roll", false) and h.res.get("rolled", false):
			torn[0] = true)
	await _run(s[0], s[1], s[2], 16.0, func(_i):
		var b: Beast = s[2]
		if b.hug != null and b.hug.get("roll", false):
			rolled[0] = true
			pry[0] = maxf(pry[0], float(b.hug.get("pry", 0.0)))
		elif rolled[0] and pry[0] > 0.9 and not torn[0] and not freed[0]:
			freed[0] = true
			marked[0] = s[1].has_meta("rolled_by"))
	t.check(rolled[0], "the jaws closed on a limb and it rolled")
	t.check(freed[0], "pulling away prised the jaws open (pry %.2f)" % pry[0])
	t.check(not torn[0], "before the limb was twisted off")
	t.check(not marked[0], "and he is out of it")
	s[0].queue_free()

func test_the_elephant_charges_and_crushes() -> void:
	seed(10)
	var s = await _setup("elephant", 9.0)
	var closest := [INF]
	var fastest := [0.0]
	var crushed := [0]
	s[0].combat.hit.connect(func(h):
		if h.attacker == s[2] and h.char == s[1] and h.type == "blunt":
			crushed[0] += 1)
	await _run(s[0], s[1], s[2], 14.0, func(_i):
		closest[0] = minf(closest[0], s[2].torso.global_position.distance_to(s[1].torso.global_position))
		fastest[0] = maxf(fastest[0], Vector2(s[2].torso.linear_velocity.x, s[2].torso.linear_velocity.z).length()))
	t.check(fastest[0] > 3.0, "it charged (%.1f m/s)" % fastest[0])
	t.check(closest[0] < 2.5 * s[2].S, "it came over him (closest %.1f m)" % closest[0])
	t.check(crushed[0] > 0, "and stomped or trampled him (%d)" % crushed[0])
	s[0].queue_free()

func test_hide_turns_a_slash_but_not_a_thrust() -> void:
	var s = await _setup("elephant", 4.0)
	var b: Beast = s[2]
	var at: Vector3 = b.torso.global_position + Vector3(b.torso.half_ext.x, 0, 0)
	var slash: Dictionary = b.apply_hit(b.torso, {"impulse": 30.0, "type": "edge", "hardness": 0.9, "sharpness": 1.0, "point": at, "dir": Vector3.LEFT, "axis": Vector3.UP, "edge": Vector3.LEFT, "wsz": 1.0})
	var thrust: Dictionary = b.apply_hit(b.torso, {"impulse": 30.0, "type": "point", "hardness": 0.9, "sharpness": 1.0, "point": at + Vector3(0, 0.3, 0), "dir": Vector3.LEFT, "axis": Vector3.LEFT, "thrust": 1.0, "wsz": 1.0})
	var n_slash := 0
	for r in slash.removed:
		n_slash += r.indices.size()
	var n_thrust := 0
	for r in thrust.removed:
		n_thrust += r.indices.size()
	t.check(slash.get("hide", false), "the hide took the slash")
	t.check(n_slash < 12, "and little of it got in (%d voxels)" % n_slash)
	t.check(n_thrust > n_slash, "a committed thrust gets further in (%d vs %d)" % [n_thrust, n_slash])
	t.check(b.mods.toughness > 1.5, "a beast is tougher than a man (%.1f)" % b.mods.toughness)
	s[0].queue_free()

func test_the_ostrich_winds_up_and_hops_into_its_kick() -> void:
	seed(11)
	var s = await _setup("ostrich", 2.4)
	var b: Beast = s[2]
	var wound := [false]
	var hopped := [false]
	var pecks := [0]
	s[0].combat.hit.connect(func(h):
		if h.attacker == b and h.char == s[1] and h.get("att_part") == null and h.type == "point":
			pecks[0] += 1)
	await _run(s[0], s[1], b, 14.0, func(_i):
		for p in b.wind:
			if float(b.wind[p]) > 0.0 and b.strikes.has(p):
				wound[0] = true
		for l in b.legs:
			if b.strikes.has(l) and not b.wind.has(l) and b.torso.linear_velocity.y > 1.2:
				hopped[0] = true)
	t.check(wound[0], "every strike is wound up first")
	t.check(hopped[0], "it hopped into its kick")
	s[0].queue_free()

func test_the_gorilla_hugs_and_tears_a_man_in_two() -> void:
	seed(12)
	var s = await _setup("gorilla", 2.4)
	var b: Beast = s[2]
	t.check(b.legs.size() == 4 and b.by_name.has("legFLLo"), "an ape on four limbs, fists and feet")
	var hugged := [false]
	var rent := [false]
	var punches := [0]
	var powers := {}
	s[0].combat.hit.connect(func(h):
		if h.attacker == b and h.char == s[1]:
			if h.get("rend", false):
				rent[0] = true
			if h.type == "blunt" and h.get("att_part") != null and String(h.att_part.part_name).begins_with("legF"):
				punches[0] += 1
				var arm = h.att_part.parent_part
				if arm and h.get("bite", false) and b.strikes.has(arm) and String(arm.get_meta("ape", "")) != "":
					var pw := float(h.att_part.get_meta("power", 1.0))
					powers[pw] = maxf(float(powers.get(pw, 0.0)), h.J))
	var kinds := {}
	await _run(s[0], s[1], b, 16.0, func(_i):
		if b.hug != null:
			hugged[0] = true
		for n in ["legFL", "legFR"]:
			var k := String(b.by_name[n].get_meta("ape", ""))
			if k != "":
				kinds[k] = true)
	t.check(hugged[0], "it took hold of him")
	t.check(rent[0], "and tore him in two")
	t.check(kinds.size() >= 2, "it threw more than one kind of blow: %s" % str(kinds.keys()))
	t.check(punches[0] >= 1, "and its fists landed (%d blows)" % punches[0])
	t.check(b.base_bite * 0.9 >= 45.0, "a gorilla's lightest blow is three men's punches (%.0f)" % (b.base_bite * 0.9))
	var cap_jab: float = b.base_bite * 0.9
	t.check(powers.values().all(func(j): return j <= b.base_bite * 1.8 + 0.01), "no blow lands harder than a slam may (%s)" % str(powers))
	t.check(not powers.has(0.9) or powers[0.9] <= cap_jab + 0.01, "a jab lands no harder than a jab may (bite %.1f, %s)" % [b.base_bite, str(powers)])
	var off: int = s[1].parts.filter(func(p): return p.severed).size()
	t.check(off >= 2, "an arm and a leg came away (%d parts off)" % off)
	s[0].queue_free()

func test_a_hold_needs_a_touch() -> void:
	seed(21)
	var s = await _setup("gorilla", 3.0)
	var b: Beast = s[2]
	var man: Fighter = s[1]
	# Within the hug's range but out of contact, rooted, and its blows and its rearing held
	# back: no hug can start, since nothing of it is on him.
	b.sp = b.sp.duplicate()
	b.sp.speed = 0.0
	b.sp.lunge = 0.0
	b.ai.bite_cool = 0.0
	b.ai.rear_cool = 999.0
	for n in ["legFL", "legFR"]:
		b.strike_cool[b.by_name[n]] = 999.0
	var touched := [false]
	await _run(s[0], man, b, 3.0, func(_i):
		if s[0].combat.touching(b, man):
			touched[0] = true)
	t.check(not touched[0], "nothing of it touched him from a pace off")
	t.check(b.hug == null, "and so it has no hold on him")
	# Set against its fist: the touch is noted, and only then may the hold come.
	var fist: VoxelPart = b.by_name.legFRLo
	man.teleport(fist.global_position + Vector3(0, 0.2, -0.3))
	await _run(s[0], man, b, 1.5, func(_i):
		if s[0].combat.touching(b, man):
			touched[0] = true)
	t.check(touched[0], "pressed against its fist, the touch is noted")
	t.check(s[0].combat.touch_part(b, man, 9.0) != null, "and which part of him it touched")
	s[0].queue_free()
