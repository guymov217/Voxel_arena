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
	# (Right over and more: how many turns before the limb gives varies a little with what ran
	# before it in the suite; one and a half and up is a roll, not a shake.)
	t.check(turn[0] > TAU * 1.5, "it rolled right over, more than one and a half turns (%.0f deg)" % rad_to_deg(turn[0]))
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
	await _run(s[0], s[1], b, 24.0, func(i):
		# Whether the ape's own stride brings him to the hold in time hangs on the physics'
		# chaos: past eight seconds without one, a hand is put on the man (as his own would
		# be, at line "a hand on him"), and the tearing is what is tested.
		if b.hug == null and i == 8 * 120 and b.alive and s[1].alive and not hugged[0] and b.torso.global_position.distance_to(s[1].torso.global_position) < 2.2 * b.S:
			b.hug = {"target": s[1], "t": 3.0, "tick": 0.3, "stagger0": b.stagger}
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

func test_every_blow_on_the_gorilla_cows_it() -> void:
	seed(4)
	var s = await _setup("gorilla", 3.0)
	var b: Beast = s[2]
	var man: Fighter = s[1]
	await get_tree().physics_frame
	var blow := {"type": "blunt", "hardness": 0.5, "sharpness": 0.0, "point": b.torso.global_position, "dir": Vector3.FORWARD}
	var hit := func(J: float) -> void:
		b.ai.dent_at = -9.0
		var h := blow.duplicate()
		h.impulse = J
		b.apply_hit(b.torso, h)
	t.eq(b.nerve, 1.0, "fresh, it has all its nerve")
	hit.call(25.0)
	var one: float = b.nerve
	t.check(one < 0.95, "a solid blow takes some of the fight out of it (%.2f)" % one)
	hit.call(5.0)
	t.check(b.nerve < one and one - b.nerve < 1.0 - one, "a light one a little less (%.2f)" % b.nerve)
	var n0: float = b.nerve
	b.ai.dent_at = -9.0
	var h2 := blow.duplicate()
	h2.impulse = 25.0
	b.apply_hit(b.torso, h2)
	b.apply_hit(b.head, h2)
	t.check(absf((n0 - b.nerve) - (1.0 - one)) < 0.001, "a blow landing on two parts at once is one dent (%.3f)" % (n0 - b.nerve))
	# Struck as it winds up a blow: the blow is broken off and it gives ground.
	var arm: VoxelPart = b.by_name.legFR
	arm.set_meta("ape", "jab")
	b.strike_cool.erase(arm)
	b._strike(arm, 0.5, 1.0, [], 0.3)
	t.check(b.wind.has(arm), "it winds up a blow")
	hit.call(20.0)
	t.check(not b.wind.has(arm), "a solid blow as it winds up breaks the blow off")
	t.eq(b.ai.mode, "recover", "and it gives ground")
	await get_tree().physics_frame
	t.check(not b.strikes.has(arm), "the blow never goes")
	# Cowed, it swings less often (the same chances, rolled as often, at full nerve and at least).
	var reach: float = b.torso.half_ext.z + 1.6 * b.S
	var count := func(nv: float) -> int:
		var n := 0
		b.ai.bite_cool = 99.0
		b.ai.mode = "stalk"
		b.ai.rear = 0.0
		for i in 6000:
			b.nerve = nv
			b.strikes.clear()
			b.wind.clear()
			b.strike_cool.clear()
			b._ape_blows(0.01, man, Vector3.FORWARD, reach * 1.05, 1.0)
			if not b.strikes.is_empty():
				n += 1
		b.strikes.clear()
		b.wind.clear()
		b.strike_cool.clear()
		b.pending.clear()
		for nm in ["legFL", "legFR"]:
			b.by_name[nm].set_meta("ape", "")
		return n
	var bold: int = count.call(1.0)
	var cowed: int = count.call(Beast.NERVE_MIN)
	t.check(bold > 60 and cowed < bold * 0.75, "a cowed ape swings less often (%d blows to %d)" % [cowed, bold])
	# Let be, it gathers itself again.
	b.nerve = 0.5
	man.teleport(Vector3(0, 0, -25))
	await _run(s[0], man, b, 2.0, func(_i): pass)
	t.check(b.nerve > 0.51, "let be, its nerve comes back (%.3f)" % b.nerve)
	s[0].queue_free()

## The health plate says how near the end it is, whatever the end would be: a broken neck, a
## torn brain, a torn heart's last seconds, not only the head, the trunk and the blood.
func test_the_health_plate_counts_every_way_to_die() -> void:
	var s = await _setup("ostrich", 6.0)
	var b: Beast = s[2]
	var man: Fighter = s[1]
	await get_tree().physics_frame
	t.check(b.vitality() > 0.95, "unhurt, it is full (%.2f)" % b.vitality())
	var neck: VoxelPart = null
	for p in b.parts:
		if String(p.part_name).begins_with("neck"):
			neck = p
	t.check(neck != null, "an ostrich has a neck")
	if neck:
		neck.hp = 30.0
		t.check(b.vitality() <= 0.31, "its neck all but broken, the plate is all but empty (%.2f)" % b.vitality())
		neck.hp = 100.0
	var nb: int = man.organ_total.get(Anatomy.BRAIN, 0)
	t.check(nb > 0, "he has a brain")
	man.organ_lost[Anatomy.BRAIN] = int(nb * 0.5)
	t.check(man.vitality() < 0.35, "half his brain gone, he is near the end (%.2f)" % man.vitality())
	man.organ_lost[Anatomy.BRAIN] = 0
	man.heart_t = 1.0
	t.check(man.vitality() < 0.1, "his heart torn, seconds to live (%.2f)" % man.vitality())
	man.heart_t = -1.0
	b.die("test")
	t.eq(b.vitality(), 0.0, "dead, it is empty")
	s[0].queue_free()

func test_a_beasts_one_head_never_hangs_from_a_thin_root() -> void:
	var s = await _setup("griffin", 6.0)
	var b: Beast = s[2]
	t.check(not b.may_hang(b.head), "a griffin's head is held up, however thin its root is cut")
	t.check(b.may_hang(b.by_name.legFL), "its legs still hang broken")
	t.check(s[1].may_hang(s[1].head), "a man's head is his own matter")
	s[0].queue_free()
	var h = await _setup("hydra", 6.0)
	var hy: Beast = h[2]
	t.check(hy.may_hang(hy.heads[0]), "one of a hydra's heads may hang")
	h[0].queue_free()

## The manticore, out of reach of its claws, raises its tail with a roar and flings poisoned
## spikes; a man beside its flank gets the sting.
func test_the_manticore_flings_its_spikes() -> void:
	seed(9)
	var s = await _setup("manticore", 9.0)
	var b: Beast = s[2]
	var man: Fighter = s[1]
	var said := []
	s[0].feed.connect(func(t_): said.append(t_))
	var spikes := [0]
	var poisoned := [false]
	var raised := [false]
	b.ai.volley_cool = 0.0
	await _run(s[0], man, b, 6.0, func(_i):
		if float(b.ai.get("volley", 0.0)) > 0.0:
			raised[0] = true
		for it in s[0].items.list:
			if it.type == "pot_arrow_poison" and it.owner == b:
				spikes[0] = maxi(spikes[0], 1)
		if man.parts.any(func(p): return p.spots.any(func(x): return x.kind == "acid")):
			poisoned[0] = true)
	t.check(raised[0], "it raised its tail to fling them")
	t.check(said.any(func(x): return String(x).contains("tail")), "and the crowd is told it is coming (%s)" % [said])
	t.check(spikes[0] > 0, "the spikes flew")
	t.check(poisoned[0], "and the man is poisoned by them")
	s[0].queue_free()

## The dragon left be is alive, not a statue: its head glances about, it huffs smoke, and now
## and then it rouses and spreads its wings.
func test_the_dragon_is_alive_at_rest() -> void:
	var s = await _setup("dragon", 30.0)
	var b: Beast = s[2]
	s[1].teleport(Vector3(0, 0, -30))
	var huffs := [0]
	b.on_huff = func(_bb): huffs[0] += 1
	var lo := INF
	var hi := -INF
	var roused := false
	for i in 120 * 14:
		b.target = null
		await get_tree().physics_frame
		if i < 120:
			continue
		var rel := PD.quat_of(b.torso).inverse() * PD.quat_of(b.head)
		var f := rel * Vector3(0, 0, 1)
		var yaw := atan2(f.x, f.z)
		lo = minf(lo, yaw)
		hi = maxf(hi, yaw)
		if float(b.ai.get("rouse", 0.0)) > 0.0:
			roused = true
	t.check(hi - lo > 0.2, "its head turns about on its own (%.2f rad)" % (hi - lo))
	t.check(huffs[0] >= 2, "it huffs smoke (%d)" % huffs[0])
	t.check(roused, "and rouses its wings now and then")
	s[0].queue_free()
