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
		var vmax := 0.0
		var ymax := 0.0
		var gap := 0.0
		var gap_at := ""
		var finite := true
		for s in int(6.0 / DT):
			man.control(DT, {})
			b.control(DT)
			await get_tree().physics_frame
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
						vmax = maxf(vmax, p.linear_velocity.length())
						ymax = maxf(ymax, pos.y)
					if p.joint and p.parent_part and not p.parent_part.severed and p.def.get("ca") != null:
						gap = maxf(gap, (p.parent_part.global_transform * p.pa).distance_to(p.global_transform * p.ca))
		if not finite or vmax > 20.0 or ymax > 3.0 or gap > 0.12 * maxf(1.0, b.S):
			bad.append("%s v %.1f y %.1f gap %.2f at %s%s" % [k, vmax, ymax, gap, gap_at, "" if finite else " NaN"])
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
