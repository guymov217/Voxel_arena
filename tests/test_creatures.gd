extends Node
## Every creature as a creature: the right number of heads, legs and wings; it moves its own
## joints; it attacks a man in front of it with the parts it has; and what it can still do follows
## what is left of it (a cut-off head, tail, horn or wing takes its attack or its flight with it;
## missing voxels stay missing, except on the hydra, which grows some back).

var t
const DT := 1.0 / 120.0

func _world() -> TestWorld:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	return w

func _beast(w: TestWorld, species: String, pos: Vector3, yaw := PI) -> Beast:
	var b := Beast.new()
	w.add_child(b)
	b.build_beast(species, pos, yaw, {"seed": 11})
	w.combat.fighters.append(b)
	return b

func _run(w: TestWorld, list: Array, seconds: float, man = null) -> void:
	for s in int(seconds / DT):
		if man:
			man.control(DT, {"main": {"x": 0.0, "y": 0.1}})
		for b in list:
			b.control(DT)
		await get_tree().physics_frame

func _cut(b: Beast, n: String) -> void:
	b.detach_limb(b.by_name[n], {"removed": [], "severed": []})

const ANATOMY := {
	"lion": [1, 4, 0], "wolf": [1, 4, 0], "boar": [1, 4, 0], "bear": [1, 4, 0], "goat": [1, 4, 0], "elephant": [1, 4, 0], "gorilla": [1, 4, 0],
	"tiger": [1, 4, 0], "hyena": [1, 4, 0], "rat": [1, 4, 0], "crocodile": [1, 4, 0], "bull": [1, 4, 0], "rhino": [1, 4, 0],
	"python": [1, 0, 0], "ostrich": [1, 2, 2], "mammoth": [1, 4, 0], "scorpion": [1, 8, 0], "spider": [1, 8, 0],
	"cerberus": [3, 4, 0], "hydra": [5, 4, 0], "griffin": [1, 4, 2], "chimera": [3, 4, 0], "manticore": [1, 4, 2],
	"basilisk": [1, 0, 0], "dragon": [1, 4, 2],
}

func test_anatomy_counts() -> void:
	var w := _world()
	var bad := []
	for k in Data.beasts:
		var b := _beast(w, k, Vector3(0, 0.2, 0))
		var want: Array = ANATOMY[k]
		var nw := b.parts.filter(func(p): return String(p.part_name).begins_with("wing")).size()
		if b.heads.size() != want[0] or b.legs.size() != want[1] or nw != want[2]:
			bad.append("%s heads %d legs %d wings %d" % [k, b.heads.size(), b.legs.size(), nw])
		if k == "scorpion" and not (b.by_name.has("clawL") and b.by_name.has("clawR") and b.by_name.has("stinger")):
			bad.append("scorpion pincers/stinger")
		b.queue_free()
		w.combat.fighters.erase(b)
	t.check(bad.is_empty(), ", ".join(bad))
	w.queue_free()

## Each species, alone with a man standing in front of it, moves its animated joints and lands
## blows on him (the decoy goat is harmless and only wanders).
func test_every_creature_animates_and_attacks() -> void:
	var no_hits := []
	var still := []
	for k in Data.beasts:
		seed(hash(k) + 2)   # the game's dice (randf) the same whatever ran before
		var w := _world()
		var man := w.fighter(Vector3(0, 0, 0), PI, {"main": "gladius"}, {"name": "Man", "slot": 0})
		man.mods.toughness = 50.0
		var b: Beast
		if Data.beasts[k].ai == "path":
			# The elephants walk their circle: the man stands on it, a little ahead.
			b = _beast(w, k, Vector3(0, 0.2, 6.0), PI * 0.5)
			man.teleport(Vector3(sin(0.8) * 6.0, 0, cos(0.8) * 6.0))
		else:
			b = _beast(w, k, Vector3(0, 0.2, 2.2 + 0.9 * b_size(k)))
		b.target = man
		b.ai.fly_cool = 999.0
		var hits := [0]
		var stomps := [0]
		b.on_stomp = func(_b): stomps[0] += 1
		b.on_breath = func(_b, _k, _r): stomps[0] += 1
		w.combat.hit.connect(func(h): if h.attacker == b: hits[0] += 1)
		var first := {}
		for a in b.anim:
			first[a.part] = PD.quat_of(a.part.parent_part).inverse() * PD.quat_of(a.part)
		var moved := 0.0
		# Seven seconds to land a blow; a big slow one that starts far off (the hydra) gets up
		# to twelve to close in, the rest stop at seven as before.
		for s in int(12.0 / DT):
			if s >= int(7.0 / DT) and (hits[0] > 0 or stomps[0] > 0):
				break
			man.blood = 100.0
			man.control(DT, {"main": {"x": 0.0, "y": 0.1}})
			b.control(DT)
			if s % 30 == 0:
				for a in b.anim:
					if not a.part.severed:
						var rel: Quaternion = PD.quat_of(a.part.parent_part).inverse() * PD.quat_of(a.part)
						moved = maxf(moved, rel.angle_to(first[a.part]))
			await get_tree().physics_frame
		if not b.anim.is_empty() and moved < 0.03:
			still.append("%s %.3f" % [k, moved])
		if k != "goat" and hits[0] == 0 and stomps[0] == 0:
			no_hits.append(k)
		w.queue_free()
		await get_tree().process_frame
	t.check(still.is_empty(), "joints that never moved: " + ", ".join(still))
	t.check(no_hits.is_empty(), "never landed a blow: " + ", ".join(no_hits))

func b_size(k: String) -> float:
	return float(Data.beasts[k].scale)

func test_damage_takes_abilities_with_it() -> void:
	var w := _world()
	# Cerberus without a head fights on with the other two; it does not grow a new one.
	var c := _beast(w, "cerberus", Vector3(-8, 0.2, 0))
	_cut(c, "headL")
	t.check(c.alive and c.biting_heads().size() == 2 and c.heads_left().size() == 2, "cerberus fights on with two heads")
	# A scorpion without its tail cannot sting.
	var sc := _beast(w, "scorpion", Vector3(-4, 0.2, 0))
	_cut(sc, "tail")
	t.check(sc.by_name.stinger.severed and not sc.part_ok(sc.by_name.stinger), "the stinger went with the tail")
	# A dragon with a wing off cannot fly, and cannot take off.
	var d := _beast(w, "dragon", Vector3(0, 0.2, 0))
	t.check(d.can_fly(), "a whole dragon can fly")
	_cut(d, "wingL")
	t.check(not d.can_fly(), "a one-winged dragon cannot")
	# A chimera without its goat head has no fire; its lion head still bites.
	var ch := _beast(w, "chimera", Vector3(4, 0.2, 0))
	t.check(ch.can_breathe(), "the chimera breathes fire")
	_cut(ch, "goatHead")
	t.check(not ch.can_breathe() and ch.biting_heads().has(ch.head), "no goat head, no fire; the lion still bites")
	# A bull with its horns off charges shorter.
	var bu := _beast(w, "bull", Vector3(8, 0.2, 0))
	var full := bu.horn_fn()
	_cut(bu, "hornL"); _cut(bu, "hornR")
	t.check(full > 0.9 and bu.horn_fn() == 0.0, "horns gone: horn %.2f -> %.2f" % [full, bu.horn_fn()])
	# A lion that lost its head is dead and bites nobody.
	var li := _beast(w, "lion", Vector3(0, 0.2, 8))
	_cut(li, "beastHead")
	t.check(not li.alive and li.biting_heads().is_empty(), "the beheaded lion")
	w.queue_free()

## A lion's hind legs give its pounce: with them cut it rushes in on the ground instead.
func test_hurt_legs_change_the_attack() -> void:
	var w := _world()
	var li := _beast(w, "lion", Vector3(0, 0.2, 0))
	var full := li.hind_fn()
	_cut(li, "legBLLo")
	_cut(li, "legBRLo")
	t.check(full > 0.9 and li.hind_fn() < 0.6, "hind legs %.2f -> %.2f" % [full, li.hind_fn()])
	w.queue_free()

## Voxels knocked off stay off while the creature moves; only the hydra's wounds close a little.
func test_missing_voxels_stay_missing() -> void:
	var w := _world()
	var li := _beast(w, "lion", Vector3(-3, 0.2, 0))
	var hy := _beast(w, "hydra", Vector3(4, 0.2, 0))
	var tail: VoxelPart = li.by_name.tail
	var hh: VoxelPart = hy.by_name.head1
	var idx := []
	for i in 12:
		idx.append(i)
	tail.remove_voxels(idx)
	hh.remove_voxels(range(0, hh.fx.size() / 3))
	var tail_left := tail.alive_count
	var head_left := hh.alive_count
	await _run(w, [li, hy], 6.0)
	t.check(tail.alive_count == tail_left, "the lion's tail stayed chipped (%d -> %d)" % [tail_left, tail.alive_count])
	t.check(hh.alive_count > head_left and hh.alive_count < hh.fx.size(), "the hydra head grew some back (%d -> %d of %d)" % [head_left, hh.alive_count, hh.fx.size()])
	_cut(hy, "head2")
	var n := hy.heads_left().size()
	await _run(w, [hy], 2.0)
	t.check(n == 4 and hy.heads_left().size() == 4 and hy.by_name.head2.severed, "a severed hydra head stays off")
	w.queue_free()

## The blows land like blows: a man attacked by each creature is thrown about and hurt, but
## no joint of his or of the creature's comes apart (the two sides of every joint stay within a
## few centimetres), nothing flies off at absurd speed, he is never launched into the air, and
## every number stays finite.
## (His speed is read at every step, and as a whole: thrown, all of him goes. One limb's own speed
## is let go higher for the step a blow takes: a chimera's forepaw at 14 m/s on his thigh whips
## the shin round the knee at 20 to 27 m/s for one step, and read every sixth step that passed or
## failed by how far off the chimera started: 12.6 m/s where the test stands it, 20.8 and 22.0
## from 18 and 24 cm further back.)
func test_attacks_stay_physical() -> void:
	var bad := []
	for k in Data.beasts:
		if k == "goat":
			continue
		seed(hash(k))
		# The last world is let go first (freed at the end of a frame, its bodies stood where
		# this man is made).
		await get_tree().physics_frame
		await get_tree().physics_frame
		var w := _world()
		var man := w.fighter(Vector3(0, 0, 0), PI, {}, {"name": "Man", "slot": 0})
		var b: Beast
		if Data.beasts[k].ai == "path":
			b = _beast(w, k, Vector3(0, 0.2, 6.0), PI * 0.5)
			man.teleport(Vector3(sin(0.8) * 6.0, 0, cos(0.8) * 6.0))
		else:
			b = _beast(w, k, Vector3(0, 0.2, 2.2 + 0.9 * b_size(k)))
		b.target = man
		b.ai.fly_cool = 999.0
		var vmax := 0.0    # the fastest he goes, all of him
		var vpart := 0.0   # the fastest any one part of him goes
		var ymax := 0.0
		var gap := 0.0
		var gap_at := ""
		var finite := true
		for s in int(6.0 / DT):
			man.control(DT, {})
			b.control(DT)
			await get_tree().physics_frame
			var mom := Vector3.ZERO
			var mass := 0.0
			for p in man.parts:
				if not p.severed:
					vpart = maxf(vpart, p.linear_velocity.length())
					mom += p.linear_velocity * p.mass
					mass += p.mass
			vmax = maxf(vmax, (mom / maxf(mass, 0.001)).length())
			if s % 6 != 0:
				continue
			for f in [man, b]:
				for p in f.parts:
					var pos: Vector3 = p.global_position
					if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
						finite = false
					if p.severed:
						continue
					if f == man:
						ymax = maxf(ymax, pos.y)
					if p.joint and p.parent_part and not p.parent_part.severed and p.def.get("ca") != null:
						gap = maxf(gap, (p.parent_part.global_transform * p.pa).distance_to(p.global_transform * p.ca))
		if not finite or vmax > 20.0 or vpart > 40.0 or ymax > 3.0 or gap > 0.12 * maxf(1.0, b.S):
			bad.append("%s v %.1f (a part %.1f) y %.1f gap %.2f at %s%s" % [k, vmax, vpart, ymax, gap, gap_at, "" if finite else " NaN"])
		w.queue_free()
		await get_tree().process_frame
	t.check(bad.is_empty(), "unphysical: " + ", ".join(bad))

## Every blow a creature lands is a touch: its body on his at that moment, in the physics (a
## bite, a claw, a kick, a ram, a stomp, a squeeze, a sting...). Nothing reaches him through the
## air but what is meant to (fire; none of it is a blow here).
func test_every_blow_is_a_touch() -> void:
	var bad := []
	var landed := 0
	for k in Data.beasts:
		seed(hash(k) + 1)
		var w := _world()
		var man := w.fighter(Vector3(0, 0, 0), PI, {}, {"name": "Man", "slot": 0})
		var b: Beast
		if Data.beasts[k].ai == "path":
			b = _beast(w, k, Vector3(0, 0.2, 6.0), PI * 0.5)
			man.teleport(Vector3(sin(0.8) * 6.0, 0, cos(0.8) * 6.0))
		else:
			b = _beast(w, k, Vector3(0, 0.2, 2.2 + 0.9 * b_size(k)))
		b.target = man
		b.ai.fly_cool = 999.0
		var blows := [0]
		var untouched := []
		w.combat.hit.connect(func(h):
			if h.get("attacker") == b and h.get("char") == man:
				blows[0] += 1
				if not w.combat.touching(b, man, 0.3):
					untouched.append(str(h.keys().filter(func(x): return x in ["bite", "ram", "trample", "rend", "roll", "fall"]))))
		for s in int(6.0 / DT):
			man.blood = 100.0
			man.head.hp = maxf(man.head.hp, 40.0)
			man.torso.hp = maxf(man.torso.hp, 40.0)
			man.control(DT, {})
			b.control(DT)
			await get_tree().physics_frame
		landed += blows[0]
		if not untouched.is_empty():
			bad.append("%s: %d of %d blows without a touch %s" % [k, untouched.size(), blows[0], untouched.slice(0, 3)])
		w.queue_free()
		await get_tree().physics_frame
	# (A sanity floor: bites land only in a strike window now, so six seconds a creature gives
	# 8–12 blows over all of them, by the dice of the round.)
	t.check(landed > 5, "the creatures landed blows (%d)" % landed)
	t.check(bad.is_empty(), "every blow came with the creature's body on his: %s" % [bad])

## A blow on a part from the side: a club (blunt) or a point.
func _blow(b: Beast, p: VoxelPart, kind: String) -> Dictionary:
	var q := PD.quat_of(p)
	var at: Vector3 = p.global_position + q * Vector3(p.half_ext.x * 1.05, 0, 0)
	var dir: Vector3 = (p.global_position - at).normalized()
	return b.apply_hit(p, {"impulse": 30.0 if kind == "blunt" else 20.0, "type": kind, "hardness": 0.85, "sharpness": 0.0 if kind == "blunt" else 0.9, "point": at, "dir": dir, "axis": dir, "edge": dir, "heavy": 0.3})

## A part beaten past what it can take is broken, not off: a club leaves a bull's horn and
## dewlap on him with nothing left in them, a leg run through hangs broken; nothing comes
## away until a blade cuts the last voxels joining it to the body, and then it falls.
func _cut_free(b: Beast, p: VoxelPart) -> int:
	var vfs: float = p.vf * p.part_scale
	var ra: Array = p._root_axis()
	var ax: int = ra[0]
	var cx: int = 0 if ax != 0 else 2
	var la_ax: int = 3 - ax - cx
	var root: float = maxf(0.0, p.half_ext[ax] - 1.6 * vfs) * (1.0 if ra[1] else -1.0)
	var best = null
	var best_d := -INF
	for pass_ in 3:
		for i in p.fx.size():
			if not p.alive[i]:
				continue
			var v: Vector3 = p.local_of(i)
			if (pass_ < 2 and absf(v[ax] - root) > vfs * 0.6) or (pass_ == 0 and absf(v[la_ax]) > vfs * 1.2):
				continue
			if v[cx] > best_d:
				best_d = v[cx]
				best = v
		if best != null:
			break
	var lp: Vector3 = best if best != null else Vector3.ZERO
	lp[cx] += vfs * 0.5 + 0.01
	var ld := Vector3.ZERO
	ld[cx] = -1.0
	var la := Vector3.ZERO
	la[la_ax] = 1.0
	var bs: Basis = p.global_transform.basis.orthonormalized()
	for k in 30:
		if p.severed:
			return k
		b.apply_hit(p, {"impulse": 60.0, "type": "edge", "hardness": 0.9, "sharpness": 1.0, "heavy": 1.0, "wsz": 1.0, "point": p.to_global(lp), "dir": bs * ld, "axis": bs * la, "edge": bs * ld})
		b.blood = 100.0
		b.alive = true
	return -1

func test_every_part_breaks_by_its_harm() -> void:
	var w := _world()
	var b := _beast(w, "bull", Vector3(0, 0.2, 0))
	for i in 30:
		await get_tree().physics_frame
	for n in ["hornL", "dewlap"]:
		var p: VoxelPart = b.by_name[n]
		for k in 12:
			_blow(b, p, "blunt")
		t.check(p.hp <= 0.0 and not p.severed, "a club beats the %s to nothing and it stays on (hp %d, severed %s)" % [n, int(p.hp), str(p.severed)])
		var cut := _cut_free(b, p)
		t.check(cut >= 1, "a blade cuts the %s free (%s blows)" % [n, str(cut) if cut >= 0 else "not in 30"])
	var leg: VoxelPart = b.by_name["legFL"]
	for k2 in 15:
		_blow(b, leg, "point")
	t.check(leg.hanging and not leg.severed, "the leg run through hangs broken and stays on (hanging %s, severed %s, hp %d)" % [str(leg.hanging), str(leg.severed), int(leg.hp)])
	var cut2 := _cut_free(b, leg)
	t.check(cut2 >= 1, "and comes away only cut through (%s blows)" % (str(cut2) if cut2 >= 0 else "not in 30"))
	t.check(not b.torso.severed, "the trunk stays on")
	w.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

## A horn or a tusk is hard through and through (user: one that breaks is not to dangle like a
## limb, it is rigid): beaten with a club it cracks and is chipped away, stiff on him until it is
## broken through and off, never broken under its skin and drawn bent with its end swinging, as a
## leg's bone is, nor hanging by a strip; a blade through it takes it off.
func test_a_horn_and_a_tusk_break_rigid() -> void:
	var w := _world()
	var bull := _beast(w, "bull", Vector3(0, 0.2, 0))
	var jumbo := _beast(w, "elephant", Vector3(8, 0.3, 0))
	for i in 30:
		await get_tree().physics_frame
	seed(11)
	for pair in [[bull, "hornL"], [bull, "hornTipR"], [jumbo, "tuskL"], [jumbo, "tuskTipR"]]:
		var b: Beast = pair[0]
		var p: VoxelPart = b.by_name[pair[1]]
		t.check(b.is_hard(p) and not b.may_hang(p), "the %s's %s is hard" % [b.species, pair[1]])
		for k in 40:
			_blow(b, p, "blunt")
			b.blood = 100.0
			b.alive = true
		var flapped: bool = b.flaps.any(func(fl): return fl.part == p)
		t.check(not p.fractured and p.kink.is_empty() and p.dangle_mm == null and not p.hanging and not flapped,
				"the %s's %s beaten with a club forty times is stiff on him or broken off, never bent or hanging (broken %s, bent %s, swinging %s, hanging %s, a piece of it on a strip %s, off %s, crack %d)" % [b.species, pair[1], str(p.fractured), str(not p.kink.is_empty()), str(p.dangle_mm != null), str(p.hanging), str(flapped), str(p.severed), p.fracture])
	# (A leg under the same club does break and bend: the rule is the horn's, not the club's.)
	var leg: VoxelPart = bull.by_name["legFL"]
	for k in 40:
		_blow(bull, leg, "blunt")
		bull.blood = 100.0
		bull.alive = true
	t.check(leg.fractured or leg.hanging, "his leg under the same club breaks (broken %s, hanging %s)" % [str(leg.fractured), str(leg.hanging)])
	var horn: VoxelPart = bull.by_name["hornR"]
	var cut := _cut_free(bull, horn)
	t.check(cut >= 1 and horn.severed and not horn.hanging, "a blade through the horn takes it off, a stiff piece (%s blows)" % (str(cut) if cut >= 0 else "not in 30"))
	w.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

## A scorpion's tail is curled in toward its foe (user; it stood up behind it like a club, the
## sting at the sky): held, it arches up over the back and forward, the sting forward of the
## tail's root and over the head, its point forward and down. The manticore's the same, its sting
## pointing forward. And a tail that carries a head bears its weight (user: the chimera's serpent
## hung limp, its head at its hocks): the serpent stands reared over the rump, its head well over
## the back.
func test_a_sting_is_held_curled_at_its_foe_and_a_serpent_reared() -> void:
	var w := _world()
	var sc := _beast(w, "scorpion", Vector3(-7, 0.2, 0))
	var mt := _beast(w, "manticore", Vector3(0, 0.3, 0))
	var ch := _beast(w, "chimera", Vector3(8, 0.3, 0))
	await _run(w, [sc, mt, ch], 2.5)
	for b: Beast in [sc, mt]:
		var k: float = b.S / float(b.sp.scale)
		var inv: Transform3D = b.torso.global_transform.affine_inverse()
		var stg: VoxelPart = b.by_name.stinger
		var tail: VoxelPart = b.by_name.tail
		var root: Vector3 = inv * (tail.global_transform * tail.ca)
		var at: Vector3 = inv * stg.global_position
		var way: Vector3 = (inv.basis * (stg.global_transform.basis * Vector3.UP)).normalized()   # from its joint to its point
		t.check(at.z > root.z + 0.6 * k, "the %s's sting hangs forward of its tail's root (%.2f, the root %.2f)" % [b.species, at.z, root.z])
		t.check(way.z > 0.3 and way.y < 0.2, "the %s's sting points forward, not at the sky (its way %s)" % [b.species, str(way.snapped(Vector3.ONE * 0.01))])
		if b == sc:
			var crown: float = (inv * b.head.global_position).y + b.head.half_ext.y
			t.check(at.y > crown + 0.15 * k and way.y < -0.3, "the scorpion's sting hangs over its head, its point down at its foe (%.2f over the body's middle, the head's top %.2f; its way %s)" % [at.y, crown, str(way.snapped(Vector3.ONE * 0.01))])
	var kc: float = ch.S / float(ch.sp.scale)
	var sn: VoxelPart = ch.by_name.snakeHead
	var up_by: float = (ch.torso.global_transform.affine_inverse() * sn.global_position).y - ch.torso.half_ext.y
	t.check(up_by > 0.5 * kc, "the chimera's serpent is reared up, its head over the back (%.2f over it)" % up_by)
	w.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

## A scorpion's shin is drawn with its thigh (user: it has to look like a scorpion, its legs
## spread out to its sides; the parts that carry them are folded under it): as it sits on the
## upper part at rest, lifted about the knee it is drawn at by a share of what its own joint is
## bent, either way; the knee stays where it is and the foot comes up. Hanging broken, folded up.
func test_a_carried_shin_is_drawn_on_its_thigh() -> void:
	var up := Transform3D(Basis(Vector3.UP, 0.4), Vector3(1, 2, 3))
	var rel := Transform3D(Basis(Vector3.BACK, 1.3), Vector3(0.2, -0.3, 0.0))
	var hinge := Vector3(0.5, 0.2, 0.0)
	var foot: Vector3 = rel.affine_inverse() * (hinge + Vector3(0.4, -0.5, 0.0))   # (a point of the shin, in its own frame)
	var knee: Vector3 = rel.affine_inverse() * hinge
	var still := Beast.carried_at(up, up * rel, rel, hinge, Vector3.BACK, 0.55)
	t.check(still.is_equal_approx(up * rel), "its knee as at rest, it is drawn where it sits on the upper part")
	var lifts := []
	for bend in [0.8, -0.8]:
		var low: Transform3D = up * Transform3D(Basis(Vector3.RIGHT, bend), Vector3(0.3, 0.1, -0.2)) * rel   # its own part, turned at its joint
		var drawn := Beast.carried_at(up, low, rel, hinge, Vector3.BACK, 0.55)
		t.check((drawn * knee).is_equal_approx(up * hinge), "the knee it is drawn at stays where it is (bent %.1f)" % bend)
		lifts.append((up.affine_inverse() * (drawn * foot)).y - (up.affine_inverse() * (still * foot)).y)
	t.check(lifts[0] > 0.15 and is_equal_approx(lifts[0], lifts[1]), "its foot comes up as the knee bends, either way alike (%.2f, %.2f)" % [lifts[0], lifts[1]])
	var broken := Beast.carried_at(up, up * rel, rel, hinge, Vector3.BACK, 0.55, true)
	t.check((up.affine_inverse() * (broken * foot)).y - (up.affine_inverse() * (still * foot)).y > lifts[0], "hanging broken it is drawn folded up at the knee")

## A leg cut off lies still on the sand as dead flesh does: the motors of its own joints (its knee)
## let go of it; and a dead beast's legs go slack (user: pieces of a body turned and rolled about
## the arena by themselves).
func test_a_cut_off_leg_lies_still_and_a_dead_beast_goes_slack() -> void:
	var w := _world()
	var b := _beast(w, "lion", Vector3(0, 0.7, 0), 0.0)
	await _run(w, [b], 1.5)
	var leg: VoxelPart = b.legs[0]
	var lo: VoxelPart = b.lower_of(leg)
	var knee := lo.joint as Generic6DOFJoint3D
	t.check(knee != null, "the knee is a joint with a motor")
	_cut(b, leg.part_name)
	t.check(not knee.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR) and not knee.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR), "cut off, its knee's motor lets go")
	await _run(w, [b], 3.0)
	var spin := leg.angular_velocity.length() + lo.angular_velocity.length()
	var drift := Vector2(leg.linear_velocity.x, leg.linear_velocity.z).length()
	t.check(spin < 0.6 and drift < 0.2, "the leg lies still on the sand (turning %.2f rad/s, moving %.2f m/s)" % [spin, drift])
	b.die("test")
	await _run(w, [b], 0.5)
	var on := 0
	for l in b.legs:
		for p in [l, b.lower_of(l)]:
			var j := p.joint as Generic6DOFJoint3D if p else null
			if j and (j.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR) or j.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR)):
				on += 1
	t.eq(on, 0, "dead, none of its legs is driven")
	w.queue_free()
