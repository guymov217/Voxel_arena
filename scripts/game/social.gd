class_name Social
extends RefCounted
## Things fighters do to each other besides cutting (social.js): taking hold of a man (one hand
## or both), pinning his arm, hurling or slamming him, a limb picked up off the sand and used as a
## club, the shove, the taunt, playing dead and the emotes. Host side; `m` is the Match.

const TAUNTS := ["Is that all Rome has?", "My grandmother hits harder!", "Come here, I have a surprise for you!", "Your mother was a hamster!", "I am right here, you cowards!", "Boo! Over here!"]
const EMOTES := [
	{"name": "salutes the Emperor", "favor": 3},
	{"name": "does a little dance", "favor": 4},
	{"name": "takes a bow", "favor": 3},
]

var m: Node

func _init(match_: Node) -> void:
	m = match_

static func _ratio(a: Fighter, b: Fighter) -> float:
	return (pow(a.S, 2.5) * float(a.mods.strength)) / pow(b.S, 2.5)

## How far a point is from the surface of a body part's box (0 inside).
static func box_distance(part: VoxelPart, p: Vector3) -> float:
	var l: Vector3 = part.global_transform.affine_inverse() * p
	var he: Vector3 = part.half_ext
	return Vector3(maxf(0.0, absf(l.x) - he.x), maxf(0.0, absf(l.y) - he.y), maxf(0.0, absf(l.z) - he.z)).length()

static func hand_free(c: Fighter, s: String) -> bool:
	var fore: VoxelPart = c.arm[s].fore
	return not c.weapons[s] and not fore.severed and not fore.hanging and not (s == "L" and c.two_handed) and not (c.holding != null and c.holding.get("extra") != null and c.holding.extra.side == s)

func _hint(e: Dictionary, text: String) -> void:
	if e.kind == "local":
		m.feed.emit(text)

## Which hands go for the grab: the one whose mouse button is held with G (both buttons, both
## hands), or the first free one.
func grab_hands(e: Dictionary, inp: Dictionary) -> Array:
	var c: Fighter = e.f
	var want = inp.get("grabHands")
	if want == "both":
		var sides := ["R", "L"].filter(func(s): return hand_free(c, s))
		if sides.size() < 2:
			_hint(e, ("Only your %s hand is free" % ("right" if sides[0] == "R" else "left")) if sides.size() else "Both hands are full")
		return sides
	if want == "R" or want == "L":
		if hand_free(c, want):
			return [want]
		_hint(e, "Your %s hand is full" % ("right" if want == "R" else "left"))
		return []
	if hand_free(c, "R"):
		return ["R"]
	if hand_free(c, "L"):
		return ["L"]
	return []

## The nearest part of any of `targets` to `side`'s hand, within reach (a giant's hand must
## actually touch the body: `touch`).
func nearest_part(c: Fighter, side: String, targets: Array, touch: bool):
	var hand := c.hand_world(side)
	var best = null
	var bd := 0.14 * c.S if touch else 0.7 * maxf(1.0, c.S * 0.85)
	for o in targets:
		for part in o.f.parts:
			if part.severed or part.missing:
				continue
			var d: float = box_distance(part, hand) if touch else part.global_position.distance_to(hand)
			if d < bd:
				bd = d
				best = {"e": o, "part": part}
	return best

func hand_joint(c: Fighter, side: String, part: VoxelPart) -> Joint3D:
	return c._joint_at(c.arm[side].fore, part, c.hand_world(side), false)

func _free_joint(j) -> void:
	if j and is_instance_valid(j):
		j.queue_free()

func grab_person(e: Dictionary, inp: Dictionary):
	var c: Fighter = e.f
	if not c.alive or c.holding != null:
		return null
	var sides := grab_hands(e, inp)
	if sides.is_empty():
		return null
	var side: String = sides[0]
	var touch: bool = c.mods.get("grabby", false)
	var others: Array = m.entities.filter(func(o): return o != e and o.f.alive)
	var best = nearest_part(c, side, others, touch)
	if best == null:
		return null
	c.holding = {"side": side, "target": best.e, "part": best.part, "joint": hand_joint(c, side, best.part), "t": 0.0, "extra": null, "limb": null}
	if sides.size() > 1:
		var second = nearest_part(c, sides[1], [best.e], touch)
		if second:
			c.holding.extra = {"side": sides[1], "part": second.part, "joint": hand_joint(c, sides[1], second.part)}
	var friend: bool = best.e.team == e.team
	var t: Fighter = best.e.f
	var lbl := String(best.part.label).to_lower()
	var two := " with both hands" if c.holding.extra else ""
	m.feed.emit(("%s grabbed %s by the %s%s" % [c.display_name, t.display_name, lbl, two]) if friend else ("%s grabbed %s's %s%s!" % [c.display_name, t.display_name, lbl, two]))
	m.sfx("slap", c.hand_world(side))
	if not friend:
		t.stagger = minf(1.0, t.stagger + 0.3)
		t.grabbed_by = c
		if t.get("arm") != null and t.kind != "beast":
			for s in ["R", "L"]:
				if best.part == t.arm[s].fore or best.part == t.arm[s].upper:
					t.pinned_arm = s
					m.feed.emit("%s pins %s's %s arm!" % [c.display_name, t.display_name, "sword" if s == "R" else "shield"])
	return t

## The other hand takes hold too, of the same man, wherever it reaches him.
func add_second_hand(e: Dictionary) -> bool:
	var c: Fighter = e.f
	var h = c.holding
	if h == null or h.limb != null or h.extra != null:
		return false
	var side := "L" if h.side == "R" else "R"
	if not hand_free(c, side):
		_hint(e, "Your %s hand is full" % ("right" if side == "R" else "left"))
		return false
	var best = nearest_part(c, side, [h.target], c.mods.get("grabby", false))
	if best == null:
		_hint(e, "Your %s hand cannot reach him" % ("right" if side == "R" else "left"))
		return false
	h.extra = {"side": side, "part": best.part, "joint": hand_joint(c, side, best.part)}
	m.feed.emit("%s gets both hands on %s" % [c.display_name, h.target.f.display_name])
	m.sfx("slap", c.hand_world(side))
	return true

## G near a limb lying on the sand: pick it up and fight with it.
func grab_limb(e: Dictionary):
	var c: Fighter = e.f
	if not c.alive or c.holding != null:
		return null
	var side := ""
	if not c.weapons.R and not c.arm.R.fore.severed:
		side = "R"
	elif not c.weapons.L and not c.arm.L.fore.severed and not c.two_handed:
		side = "L"
	if side == "":
		return null
	var hand := c.hand_world(side)
	var best = null
	var bd := 0.75
	for o in m.entities:
		for part in o.f.parts:
			if not part.severed or part.missing or part.wielder != null or part.part_name == "torso" or part.alive_count == 0:
				continue
			var d: float = part.global_position.distance_to(hand)
			if d < bd:
				bd = d
				best = {"e": o, "part": part}
	if best == null:
		return null
	var part: VoxelPart = best.part
	var j := c._joint_at(c.arm[side].fore, part, c.hand_world(side), false)
	c.holding = {"side": side, "target": best.e, "part": part, "joint": j, "t": 0.0, "extra": null, "limb": part}
	part.wielder = c
	for p in c.parts:
		part.add_collision_exception_with(p)
	var own: bool = best.e.f == c
	m.feed.emit("%s picked up %s %s and is going to hit people with it" % [c.display_name, "their own" if own else best.e.f.display_name + "'s", String(part.label).to_lower()])
	m.crowd_add(c, 12 if own else 8, "armed with your own arm" if own else "improvised weapon")
	return part

func _throw_limb(e: Dictionary, inp: Dictionary) -> void:
	var c: Fighter = e.f
	var h: Dictionary = c.holding
	var part: VoxelPart = h.limb
	let_go(c)
	part.thrown_t = 2.0
	part.thrown_by = c
	var from := part.global_position
	var tgt = m.nearest_enemy(e)
	var aim: Vector3 = tgt.f.torso.global_position if tgt else from + Vector3(sin(c.yaw), 0, cos(c.yaw)) * 8.0
	var look = inp.get("look")
	if look != null and (e.kind == "local" or e.kind == "remote"):
		aim = from + Vector3(sin(look.yaw) * cos(look.pitch), sin(look.pitch), cos(look.yaw) * cos(look.pitch)) * 8.0
	part.linear_velocity = c.launch_velocity(from, aim, part.mass / c.MS, maxf(0.3, float(inp.get("throwPower", 0.8))), false, 0.02, c.arm_func(h.side))
	part.angular_velocity = Vector3(8, 0, 0)
	m.feed.emit("%s threw a %s!" % [c.display_name, String(part.label).to_lower()])
	m.sfx("whoosh", from)

func let_go(c: Fighter) -> void:
	var h = c.holding
	if h == null:
		return
	_free_joint(h.joint)
	if h.extra != null:
		_free_joint(h.extra.joint)
	if h.limb != null:
		var part: VoxelPart = h.limb
		part.wielder = null
		if is_instance_valid(part):
			for p in c.parts:
				part.remove_collision_exception_with(p)
	elif h.target and is_instance_valid(h.target.f) and h.target.f.grabbed_by == c:
		h.target.f.grabbed_by = null
		h.target.f.pinned_arm = ""
	if h.limb == null and h.target:
		h.target.struggle = 0.0
		h.target.struggle_hint = false
	c.holding = null

## The giant's other move: the arm comes down and smashes the man he holds into the sand.
func slam_person(e: Dictionary) -> bool:
	var c: Fighter = e.f
	var h = c.holding
	if h == null or h.limb != null:
		return false
	var t: Fighter = h.target.f
	let_go(c)
	var J := minf(45.0, 13.0 * minf(3.0, _ratio(c, t)))
	for p in t.parts:
		if p.severed:
			continue
		var v: Vector3 = p.linear_velocity
		p.linear_velocity = Vector3(v.x * 0.1, -6.0, v.z * 0.1)
		p.angular_velocity = Vector3.ZERO
	t.torso.continuous_cd = true
	t.fall(3.5)
	var was_alive := t.alive
	for pk in [[t.torso, 1.0], [t.head, 0.4]]:
		var part: VoxelPart = pk[0]
		if part == null or part.severed:
			continue
		var point := part.global_position
		var res: Dictionary = t.apply_hit(part, {"impulse": J * pk[1], "type": "blunt", "hardness": 0.6, "sharpness": 0.0, "point": point, "dir": Vector3.DOWN})
		m.report_hit({"kind": "hit", "p": point, "dir": Vector3.DOWN, "J": J * pk[1], "type": "blunt", "char": t, "part": part, "attacker": c, "res": res, "killed": was_alive and not t.alive})
	t.last_attacker = c
	t.concussion = minf(1.0, t.concussion + 0.3)
	t.stamina = maxf(0.0, t.stamina - 30.0)
	c.stamina = maxf(0.0, c.stamina - 20.0)
	m.feed.emit("%s SLAMS %s into the sand!" % [c.display_name, t.display_name])
	m.sfx("thud", t.torso.global_position)
	return true

## F holding a man: throw him (where the player looks, or at the next enemy for a bot). Mass
## matters: a giant hurls a man across the sand; a man can barely shift a giant.
func throw_person(e: Dictionary, inp: Dictionary) -> bool:
	var c: Fighter = e.f
	var h = c.holding
	if h == null:
		return false
	var t: Fighter = h.target.f
	var two: bool = h.extra != null
	let_go(c)
	var strong: bool = m.has_gadget(e, "catapult")
	var fwd := Vector3(sin(c.yaw), 0, cos(c.yaw))
	var aim := fwd
	var look = inp.get("look")
	var player: bool = e.kind == "local" or e.kind == "remote"
	if player and look != null:
		aim = Vector3(sin(look.yaw) * cos(look.pitch), maxf(0.0, sin(look.pitch)) * 0.6, cos(look.yaw) * cos(look.pitch)).normalized()
	else:
		var o = m.nearest_enemy(e)
		if o and o.f != t:
			var d: Vector3 = o.f.torso.global_position - c.torso.global_position
			aim = Vector3(d.x, 0, d.z).normalized()
	var ratio := _ratio(c, t)
	var wind := (0.55 + 0.6 * float(inp.get("throwPower", 0.8))) * (1.3 if two else 1.0)
	var power := (900.0 if strong else 260.0) * pow(t.S, 2.5) * minf(2.4, ratio) * wind
	var vmax := 20.0 if strong else (8.0 if c.mods.get("grabby", false) else 6.0) + 5.0 * minf(1.0, ratio / 2.4)
	var live := t.parts.filter(func(p): return not p.severed)
	var mass_all := 0.0
	for p in live:
		mass_all += p.mass
	power = minf(power, vmax * maxf(1.0, mass_all) / (1.0 + 0.08 * (live.size() - 1)))
	for p in live:
		var v: Vector3 = p.linear_velocity
		if v.length() > 4.0:
			p.linear_velocity = v * (4.0 / v.length())
		p.angular_velocity = Vector3.ZERO
	t.torso.continuous_cd = true
	if ratio < 0.5:
		c.stagger = minf(1.0, c.stagger + 0.5)
		m.feed.emit("%s strains against %s's weight" % [c.display_name, t.display_name])
	t.fall(2.5 if strong else 1.2 + minf(1.5, ratio * 0.4), true)
	t.torso.apply_central_impulse(Vector3(aim.x * power, power * (0.75 if strong else 0.35 + maxf(0.0, aim.y)), aim.z * power))
	for p in live:
		if p != t.torso:
			p.apply_central_impulse(Vector3(aim.x * power * 0.08, power * 0.03, aim.z * power * 0.08))
	t.thrown_by = c
	t.thrown_t = 1.5
	c.stamina = maxf(0.0, c.stamina - 25.0)
	m.feed.emit(("%s CATAPULTED %s!" % [c.display_name, t.display_name]) if strong else ("%s tossed %s" % [c.display_name, t.display_name]))
	m.sfx("whoosh" if strong else "thud", t.torso.global_position)
	m.say(c, "grunt", 0.9)
	if strong:
		m.crowd_add(c, 12, "human catapult")
	return true

## A thrown man is a projectile: landing on someone hurts them (and him).
func flying_hits(dt: float) -> void:
	for e in m.entities:
		var c = e.f
		if not (c.thrown_t > 0.0):
			continue
		c.thrown_t -= dt
		var vel: Vector3 = c.torso.linear_velocity
		var speed := vel.length()
		if speed < 3.5:
			continue
		for o in m.entities:
			if o == e or not o.f.alive or o.f == c.thrown_by:
				continue
			if o.f.torso.global_position.distance_to(c.torso.global_position) > 0.7:
				continue
			var J := minf(40.0, speed * 4.0)
			var dir := vel.normalized()
			var p: Vector3 = o.f.torso.global_position
			var was_alive: bool = o.f.alive
			var res: Dictionary = o.f.apply_hit(o.f.torso, {"impulse": J, "type": "blunt", "hardness": 0.5, "sharpness": 0.0, "point": p, "dir": dir})
			var by = c.thrown_by if c.thrown_by and is_instance_valid(c.thrown_by) else c
			o.f.last_attacker = by
			o.f.torso.apply_central_impulse(Vector3(dir.x * 150.0, 40.0, dir.z * 150.0))
			if o.f.state == "stand":
				o.f.fall(1.5, true)
			m.report_hit({"kind": "hit", "p": p, "dir": dir, "J": J, "type": "blunt", "char": o.f, "part": o.f.torso, "attacker": by, "res": res, "killed": was_alive and not o.f.alive})
			m.feed.emit("%s landed on %s!" % [c.display_name, o.f.display_name])
			m.crowd_add(by, 8, "human cannonball")
			c.thrown_t = 0.0
			break

## Q: a two-handed shove at whoever stands in front. It moves a man back a step; one already
## off balance, winded or still getting up goes down.
func shove(e: Dictionary) -> bool:
	var c: Fighter = e.f
	if not c.alive or c.state != "stand" or c.stamina < 10.0 or c.shove_cool > m.time:
		return false
	var fwd := Vector3(sin(c.yaw), 0, cos(c.yaw))
	var best = null
	var bd := 0.9 * c.S + 0.55
	for o in m.entities:
		var t = o.f
		if o == e or not t.alive:
			continue
		var d: Vector3 = t.torso.global_position - c.torso.global_position
		d.y = 0.0
		var dist := d.length()
		if dist < bd and d.normalized().dot(fwd) > 0.45:
			bd = dist
			best = o
	c.shove_cool = m.time + 0.8
	c.shove_t = 0.3
	c.stamina = maxf(0.0, c.stamina - 10.0)
	if best == null:
		return true
	var t: Fighter = best.f
	if e == m.me and t.team != c.team and m.has_method("mission_event"):
		m.mission_event("shove")
	var dir: Vector3 = t.torso.global_position - c.torso.global_position
	dir.y = 0.0
	dir = dir.normalized()
	var ratio := _ratio(c, t)
	var dv := 2.6 * minf(2.5, ratio) * (0.55 + 0.45 * c.stamina / 100.0)
	for p in t.parts:
		if p.severed:
			continue
		p.apply_central_impulse(Vector3(dir.x * dv, dv * 0.1, dir.z * dv) * p.mass)
	for side in t.feet:
		if t.feet[side]:
			t.feet[side].swing = true
	t.stagger = minf(1.0, t.stagger + 0.3 * minf(1.5, ratio) + (0.25 if t.stamina < 30.0 else 0.0))
	t.last_attacker = c
	var goes_down: bool = t.state == "rising" or t.stagger > 0.75 or t.stamina < 20.0
	if goes_down and t.state != "down" and ratio > 0.5:
		t.fall(1.1)
		m.feed.emit("%s shoved %s to the sand" % [c.display_name, t.display_name])
	m.sfx("slap", t.torso.global_position)
	return true

## T: taunt. The nearest enemies come for you (all of them with a megaphone); the crowd likes it.
func taunt(e: Dictionary) -> bool:
	var c: Fighter = e.f
	if not c.alive or c.taunt_t > 0.0:
		return false
	var loud: bool = m.has_gadget(e, "megaphone")
	c.taunt_t = 10.0 if loud else 5.0
	c.taunt_pose = 1.2
	var line: String = TAUNTS[randi() % TAUNTS.size()]
	m.feed.emit('%s: "%s"' % [c.display_name, line])
	m.crowd_add(c, 10 if loud else 4, "taunt")
	m.sfx("honk" if loud else "boo", c.head.global_position)
	var enemies: Array = m.entities.filter(func(o): return o.team != e.team and o.f.alive and (o.kind == "bot" or o.kind == "beast"))
	var at: Vector3 = c.torso.global_position
	enemies.sort_custom(func(a, b): return a.f.torso.global_position.distance_squared_to(at) < b.f.torso.global_position.distance_squared_to(at))
	for o in (enemies if loud else enemies.slice(0, 2)):
		o.taunted_by = e
		o.taunt_t = c.taunt_t
	return true

func start_emote(e: Dictionary) -> bool:
	var c: Fighter = e.f
	if not c.alive or c.emote_t > 0.0:
		return false
	c.emote_kind = (c.emote_kind + 1) % EMOTES.size()
	c.emote_t = 1.6
	var em: Dictionary = EMOTES[c.emote_kind]
	m.feed.emit("%s %s" % [c.display_name, em.name])
	m.crowd_add(c, em.favor, "showmanship")
	return true

static func emote_pose(kind: int, t: float) -> Dictionary:
	match kind:
		0: return {"main": {"x": 0.25, "y": 1.0}, "off": {"x": -0.6, "y": 0.1}}
		1: return {"main": {"x": sin(t * 10.0) * 0.8, "y": 0.8}, "off": {"x": -sin(t * 10.0) * 0.8, "y": 0.8}, "mx": sin(t * 6.0) * 0.6}
		_: return {"main": {"x": 0.3, "y": -0.6}, "off": {"x": -0.3, "y": -0.6}, "crouch": true}

## The input a fighter acts on this step, after the poses (taunt, emote) and the one-shot
## actions (grab, throw, shove, taunt...). Called for every entity before it moves.
func before(e: Dictionary, inp: Dictionary, dt: float) -> Dictionary:
	var c = e.f
	if not (c is Fighter) or c.kind == "beast":
		return inp
	if c.taunt_t > 0.0:
		c.taunt_t -= dt
	if e.get("taunt_t", 0.0) > 0.0:
		e.taunt_t -= dt
	if c.taunt_pose > 0.0:
		c.taunt_pose -= dt
		inp = inp.duplicate()
		inp.main = {"x": 0.6, "y": 1.0}
		inp.off = {"x": -0.6, "y": 1.0}
		inp.power = false
		inp.thrust = 0.0
	if inp.get("emote", false):
		start_emote(e)
	if c.emote_t > 0.0:
		c.emote_t -= dt
		inp = inp.duplicate()
		inp.merge(emote_pose(c.emote_kind, m.time), true)
		inp.power = false
		inp.thrust = 0.0
		inp.mz = 0.0
	# Playing dead.
	var limp: bool = inp.get("limp", false) and c.alive
	if limp != c.limp:
		c.limp = limp
		if limp:
			c.played_dead = 2.0
			m.feed.emit("%s plays dead. Very convincing." % c.display_name)
			m.crowd_add(c, 2, "drama")
	if c.played_dead > 0.0 and not c.limp:
		c.played_dead -= dt
	if c.holding != null:
		inp = _holding(e, inp, dt)
	else:
		c.carrying = 0.0
		if inp.get("grab", false) and c.alive:
			# G: a weapon in reach, else a loose limb, else a person (G with a mouse button held
			# is only ever for taking hold of people).
			var took = null
			var gh = inp.get("grabHands")
			if gh == null:
				took = c.grab_nearest(m.combat.loose_weapons)
			else:
				took = grab_person(e, inp)
				# Nobody in that hand's reach: it takes a weapon lying there instead (G with the
				# button down near a sword once did nothing at all).
				if took == null and gh != "both":
					took = c.grab_nearest(m.combat.loose_weapons, gh)
			if took is Weapon:
				m.feed.emit("%s picks up a %s" % [c.display_name, String(took.design.get("name", "weapon")).to_lower()])
				m.sfx("pickup", c.hand_world("R" if c.weapons.R == took else "L"))
			if took == null:
				took = grab_limb(e)
			if took == null and gh == null:
				took = grab_person(e, inp)
		# A throw is a movement, not a teleport: the arm (already drawn back while F was held, or
		# drawn back now for a bot) whips forward and the thing leaves the hand partway through.
		if inp.get("throw", false) and c.alive and not e.has("throw_q"):
			var side: String = ("L" if not c.weapons.L else "R") if c.held_item != null else throw_side(c, inp)
			if c.held_item != null or c.weapons.get(side):
				var player: bool = e.kind == "local" or e.kind == "remote"
				e.throw_q = {"inp": inp.duplicate(), "t": 0.09 if player else 0.45, "side": side}
				c.throw_anim = {"side": side, "phase": "follow" if player else "wind", "t": 0.4 if player else 0.45}
		if e.has("throw_q"):
			e.throw_q.t -= dt
			if e.throw_q.t <= 0.0:
				var q: Dictionary = e.throw_q
				e.erase("throw_q")
				if c.alive:
					_throw(e, q.inp, q.side)
					c.throw_anim = {"side": q.side, "phase": "follow", "t": 0.35}
	if inp.get("taunt", false):
		taunt(e)
	if inp.get("shove", false):
		shove(e)
	return inp

## Lets go of whatever is in the throwing hand: players at the crosshair (the point their
## camera looks at), bots at their enemy.
func _throw(e: Dictionary, inp: Dictionary, side := "") -> void:
	var c = e.f
	if c.held_item != null:
		m.throwables.throw_held(e, inp)
		return
	if side == "" or not c.weapons.get(side):
		side = throw_side(c, inp)
	var player: bool = e.kind == "local" or e.kind == "remote"
	var look = inp.get("look")
	var dir = null
	var tgt = null
	if player and inp.get("aimAt") is Vector3:
		tgt = aim_ahead(c, inp.aimAt, look)
	elif player and look != null:
		dir = Vector3(sin(look.yaw) * cos(look.pitch), sin(look.pitch), cos(look.yaw) * cos(look.pitch))
	else:
		var o = m.nearest_enemy(e)
		tgt = o.f.torso.global_position + Vector3(0, 0.25, 0) if o else null
	if c.throw_weapon(side, tgt, clampf(float(inp.get("throwPower", 0.8)), 0.3, 1.0), dir):
		m.sfx("whoosh", c.hand_world(side))

## Which hand throws: the main weapon first; the shield once the main hand is empty, or at
## once with the off hand's button held.
static func throw_side(c, inp: Dictionary) -> String:
	if inp.get("throwOff", false) and c.weapons.L:
		return "L"
	return "R" if c.weapons.R else "L"

## A mark behind the thrower (the wall at his back) is never thrown at: it is moved to a few
## strides ahead where he looks.
static func aim_ahead(c, at: Vector3, look) -> Vector3:
	if look == null:
		return at
	var fwd := Vector3(sin(look.yaw), 0, cos(look.yaw))
	var hp: Vector3 = c.head.global_position
	if (at - hp).dot(fwd) < -0.3:
		var d := Vector3(sin(look.yaw) * cos(look.pitch), sin(look.pitch), cos(look.yaw) * cos(look.pitch))
		var p := hp + d * 4.0
		p.y = maxf(0.05, minf(at.y, hp.y))
		return p
	return at

func _holding(e: Dictionary, inp: Dictionary, dt: float) -> Dictionary:
	var c: Fighter = e.f
	var h: Dictionary = c.holding
	var t = h.target.f if h.target else null
	c.carrying = pow(t.S, 2.5) / (pow(c.S, 2.5) * float(c.mods.strength)) if h.limb == null and t else 0.2
	h.t += dt
	# A holder who goes down lets go.
	var part: VoxelPart = h.part
	var gone: bool = not c.alive or c.state != "stand" or c.arm[h.side].fore.severed or not is_instance_valid(part)
	if not gone:
		gone = part.missing if h.limb != null else (not t.alive or part.severed)
	if not gone and h.limb == null:
		# Carried, not flung: the man in the fist moves at most as fast as a giant's arm.
		var vmax := 9.0 + 3.0 * c.S
		for p in t.parts:
			if p.severed:
				continue
			var v: Vector3 = p.linear_velocity
			if v.length() > vmax:
				p.linear_velocity = v * (vmax / v.length())
		# A player held fights it: every press of Space is a heave against the grip.
		var te: Dictionary = h.target
		if te.kind == "local" or te.kind == "remote":
			te.struggle = maxf(0.0, te.get("struggle", 0.0) - dt * 0.35)
			var jump: bool = te.get("input", {}).get("jump", false)
			if jump and not te.get("struggle_jump", false):
				var grip := pow(clampf(_ratio(c, t) / float(t.mods.strength), 0.6, 2.2), 0.2) * (1.6 if h.extra != null else 1.0)
				te.struggle += 0.36 * (0.4 + 0.6 * t.stamina / 100.0) / grip
				t.stamina = maxf(0.0, t.stamina - 2.0)
				c.stagger = minf(1.0, c.stagger + 0.04)
			te.struggle_jump = jump
			if te.struggle >= 1.0:
				te.struggle = 0.0
				let_go(c)
				m.feed.emit("%s tore free of %s's grip!" % [t.display_name, c.display_name])
				return inp
			if te.kind == "local" and not te.get("struggle_hint", false):
				te.struggle_hint = true
				m.feed.emit("Grabbed! Mash SPACE or hit his arm")
	# The second hand loses its hold if that arm is cut or what it held comes off.
	if not gone and h.extra != null:
		var xf: VoxelPart = c.arm[h.extra.side].fore
		if xf.severed or xf.hanging or h.extra.part.severed:
			_free_joint(h.extra.joint)
			h.extra = null
	if gone:
		let_go(c)
		return inp
	var gh = inp.get("grabHands")
	if inp.get("grab", false) and gh != null and h.limb == null and h.extra == null and h.t > 0.2 and (gh == "both" or gh != h.side):
		add_second_hand(e)
	elif inp.get("throw", false):
		if h.limb != null:
			_throw_limb(e, inp)
		else:
			throw_person(e, inp)
	elif inp.get("slam", false) and h.limb == null:
		slam_person(e)
	elif inp.get("grab", false) and h.t > 0.3:
		let_go(c)
		m.feed.emit("%s let go" % c.display_name)
	elif h.limb == null and h.target.team != e.team and t.alive:
		# Wrestling: the grabbed enemy struggles and both tire.
		c.stamina = maxf(0.0, c.stamina - dt * 6.0)
		t.stamina = maxf(0.0, t.stamina - dt * 8.0)
		var odds: float = 0.25 * (pow(t.S, 2.5) * float(t.mods.strength)) / (pow(c.S, 2.5) * float(c.mods.strength)) * (0.4 + 0.8 * t.stamina / 100.0) / (0.4 + 0.8 * c.stamina / 100.0) / (1.8 if h.extra != null else 1.0)
		if h.target.kind != "local" and h.target.kind != "remote" and randf() < dt * minf(2.0, odds):
			let_go(c)
			m.feed.emit("%s wriggled free" % t.display_name)
	return inp

## After everyone moved: thrown men landing on people, thrown limbs settling.
func after(dt: float) -> void:
	for e in m.entities:
		for p in e.f.parts:
			if p.thrown_t > 0.0:
				p.thrown_t -= dt
	flying_hits(dt)

## Bots: a taunt pulls them onto the taunter; nobody bothers a man playing dead while someone
## else is awake.
func target_for(e: Dictionary, candidates: Array):
	if e.get("taunted_by") != null and e.get("taunt_t", 0.0) > 0.0 and e.taunted_by.f.alive:
		return e.taunted_by
	if e.kind != "local" and e.kind != "remote":
		var awake := candidates.filter(func(o): return not o.f.get("limp") and not (float(o.f.get("played_dead") if o.f.get("played_dead") != null else 0.0) > 0.0))
		if not awake.is_empty() and awake.size() < candidates.size():
			return {"only": awake}
	return null

func clear() -> void:
	for e in m.entities:
		if e.f is Fighter and e.f.holding != null:
			let_go(e.f)
