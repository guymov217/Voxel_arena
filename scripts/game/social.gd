class_name Social
extends RefCounted
## Things fighters do to each other besides cutting (social.js): taking hold of a man (one hand
## or both), pinning his arm, hurling or slamming him, a limb picked up off the sand and used as a
## club, the shove, the taunt, playing dead and the emotes. Host side; `m` is the Match.

const TAUNTS := ["Is that all Rome has?", "My grandmother hits harder!", "Come here, I have a surprise for you!", "Your mother was a hamster!", "I am right here, you cowards!", "Boo! Over here!"]
const EMOTES := [
	{"name": "salutes the Emperor", "feed": "%s salutes the Emperor", "favor": 3},
	{"name": "does a little dance", "feed": "%s does a little dance", "favor": 4},
	{"name": "takes a bow", "feed": "%s takes a bow", "favor": 3},
]

var m: Node

# ---------- The Hand of Jupiter ----------
## A man seized in an unseen grip (the "telekinesis" charge from the market): for MIND_T seconds
## he hangs MIND_DIST ahead of where his captor looks, off his feet, free to swing his arms; F
## hurls him the way the captor looks, and the ground, a wall or a man he lands on hurts him
## by how hard he came down. No giants (MIND_S, MIND_MASS); any other foe, a beast or a boss too.
const MIND_T := 3.0
const MIND_REACH := 12.0
const MIND_S := 1.45
const MIND_DIST := 2.8
const MIND_NEAR := 1.3
const MIND_FAR := 6.0
const MIND_HURL := 14.0
const MIND_COOL := 1.5   # a grip that closed on nothing: a moment before the next
const MIND_USES := 2     # grips a man gets in one bout, whatever charges he carries
const MIND_REST := 8.0   # seconds after a grip before the next
var minds := []   # {e: captor entity, t: the held Fighter, left, flung, prev_v, watch, fx_t}

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
	return not c.weapons[s] and not fore.severed and not fore.hanging and not (s == c.two_off() and c.two_handed) and not (c.holding != null and c.holding.get("extra") != null and c.holding.extra.side == s)

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
			_hint(e, Loc.t("Only your right hand is free" if sides[0] == "R" else "Only your left hand is free") if sides.size() else Loc.t("Both hands are full"))
		return sides
	if want == "R" or want == "L":
		if hand_free(c, want):
			return [want]
		_hint(e, Loc.t("Your right hand is full" if want == "R" else "Your left hand is full"))
		return []
	if hand_free(c, "R"):
		return ["R"]
	if hand_free(c, "L"):
		return ["L"]
	return []

## A giant's hand is on a man only where the fist has touched him (user: the giant took hold of a man
## from half a metre off, and he was drawn across to the fist). With the physics' touch of the forearm on
## that part on record the fist has to be at it, FIST_REACH (x the giant's size, a forearm's half-width
## and a little: lying flat on a man the hand is that far off his surface); with none on record (the
## contacts come and go between steps) only a fist at the surface, TOUCH_GAP (m: the few centimetres the
## physics keeps a fist off a body, whatever the giant's size). Tests may set TOUCH_GAP.
static var TOUCH_GAP := 0.06
const FIST_REACH := 0.12
const MAN_REACH := 0.09   # a man's hand, sent to him (grab_go): this near the part it touches (m: a forearm's half-width and the little the physics keeps two bodies apart)

## The nearest part of any of `targets` to `side`'s hand, within reach (a giant's hand must
## actually touch the body: `touch`).
func nearest_part(c: Fighter, side: String, targets: Array, touch: bool, on_gap := -1.0):
	var hand := c.hand_world(side)
	var best = null
	var bd := INF if touch else 0.7 * maxf(1.0, c.S * 0.85)
	if on_gap < 0.0:
		on_gap = FIST_REACH * c.S
	for o in targets:
		# A giant's hand takes only what it is on: the part his forearm touches (the physics'
		# contact), at the hand, or one whose surface is at the hand (a touch's width off).
		var on: VoxelPart = m.combat.touch_by(c.arm[side].fore, o.f, 0.3) if touch else null
		for part in o.f.parts:
			if part.severed or part.missing:
				continue
			var d: float = box_distance(part, hand) if touch else part.global_position.distance_to(hand)
			if touch and d >= (on_gap if part == on else TOUCH_GAP):
				continue
			if d < bd:
				bd = d
				best = {"e": o, "part": part}
	return best

func hand_joint(c: Fighter, side: String, part: VoxelPart) -> Joint3D:
	return c._joint_at(c.arm[side].fore, part, c.hand_world(side), false)

## A man's hand closes on what it has taken (user: no physical contact; held as the reach left
## the two, the fist stood a finger's breadth off the arm it held, daylight between them, for as
## long as it held it). The joint that holds the part is the hand's own point pinned to a point
## of the part: that point is moved, over GRIP_CLOSE_T, from where the hand touched him to the
## point of the part nearest it that is well inside it, and the hand comes onto him with it. A
## limb (a part much longer than it is thick, whose box is half again as thick as the limb drawn
## in it) is clasped round its middle line, GRIP_END in from its end: a wrist is held, not a
## fist met with a fist. The trunk or the head: GRIP_IN under whichever of its faces the hand is
## at. As a giant's fist has its man (_close_in), without the man being moved.
const GRIP_IN := 0.06
const GRIP_END := 0.1
const GRIP_CLOSE_T := 0.12
func _grip_onto(c: Fighter, side: String, part: VoxelPart) -> Dictionary:
	var l: Vector3 = part.global_transform.affine_inverse() * c.hand_world(side)
	var he: Vector3 = part.half_ext
	var g := Vector3.ONE * GRIP_IN * c.S
	var long := he.max_axis_index()
	var thick := 0.0
	for i in 3:
		if i != long:
			thick = maxf(thick, he[i])
	if he[long] > 1.6 * thick:
		g = he
		g[long] = GRIP_END * c.S
	var to := l
	for i in 3:
		var lim := maxf(0.0, he[i] - g[i])
		to[i] = clampf(l[i], -lim, lim)
	return {"t": 0.0, "from": l, "to": to}

func _grip_close(hold: Dictionary, dt: float) -> void:
	var cl = hold.get("close")
	if cl == null:
		return
	cl.t += dt
	var k := clampf(float(cl.t) / GRIP_CLOSE_T, 0.0, 1.0)
	var j = hold.get("joint")
	if j != null and is_instance_valid(j):
		PhysicsServer3D.pin_joint_set_local_b((j as Joint3D).get_rid(), (cl.from as Vector3).lerp(cl.to, k * k * (3.0 - 2.0 * k)))
	if k >= 1.0:
		hold.erase("close")

## The point of `part`'s box nearest `p`.
static func box_point(part: VoxelPart, p: Vector3) -> Vector3:
	var xf := part.global_transform
	var l: Vector3 = xf.affine_inverse() * p
	var he: Vector3 = part.half_ext
	return xf * Vector3(clampf(l.x, -he.x, he.x), clampf(l.y, -he.y, he.y), clampf(l.z, -he.z, he.z))

## How far into the giant's fist (x S) the part he has taken hold of is drawn: the pin joint lets the
## two overlap (it keeps them from colliding), and a man held with a hand's breadth of daylight
## between his head and the fist, however near, did not look held.
const GRIP_SINK := 0.03
const THROW_CLEAR := 1.2   # a man thrown (thrown_t counts down from 1.5 s) is clear of his thrower's blows after 0.3 s

## A giant's hand closes on what it is on, and the man is brought the last of the way into the fist:
## the pin joint holds the two as they stand, so a man taken from a hand's breadth off (the hand
## only has to be near the part it touched) hung that far under the fist, from nothing (user: no
## physical contact to be seen when the giant lifts him). The whole of him goes, as one, till the
## part held lies in the fist's end (GRIP_SINK).
func _close_in(c: Fighter, side: String, t: Fighter, part: VoxelPart) -> void:
	var hand := c.hand_world(side)
	var inward: Vector3 = c.arm[side].fore.global_transform.basis.y.normalized()   # (the hand point is the forearm's -y end: the fist lies back along +y)
	var shift := hand + inward * GRIP_SINK * c.S - box_point(part, hand)
	if shift.length() < 0.01 * c.S:
		return
	var bodies: Array = t.parts.duplicate()
	for w in t.weapons.values():
		if w:
			bodies.append(w)
	for b in bodies:
		if is_instance_valid(b) and not (b is VoxelPart and (b as VoxelPart).severed):
			b.global_position += shift
			b.snap_drawing()

func _free_joint(j) -> void:
	if j and is_instance_valid(j):
		j.queue_free()

## Whose hand takes only what it is on, of its own accord: a giant's, and any big bot's (its bot
## holds the button down through its reach). A man's hand is sent to him first: grab_go.
static func big_hands(c: Fighter, e: Dictionary) -> bool:
	return c.mods.get("grabby", false) or (c.S >= 1.8 and e.has("bot"))

func grab_person(e: Dictionary, inp: Dictionary, on_him := false, whom = null, gap := MAN_REACH):
	var c: Fighter = e.f
	if not c.alive or c.holding != null:
		return null
	var sides := grab_hands(e, inp)
	if sides.is_empty():
		return null
	var side: String = sides[0]
	# A hand takes only what it is on: a hold from a stride off read as the man pulled up by
	# nothing (user: the giant's; then every man's, there was no touch at all when a player took
	# hold of a foe). A giant's hand (and any big bot's) by itself; a man's when his reach has
	# brought it onto him (`on_him`: grab_go).
	var big := big_hands(c, e)
	var touch: bool = big or on_him
	var others: Array = [whom] if whom != null else m.entities.filter(func(o): return o != e and o.f.alive)
	var best = nearest_part(c, side, others, touch, -1.0 if big else gap)
	if best == null:
		return null
	if big:
		_close_in(c, side, best.e.f, best.part)
	var onto: bool = on_him and not big
	c.holding = {"side": side, "target": best.e, "part": best.part, "joint": hand_joint(c, side, best.part), "t": 0.0, "extra": null, "limb": null}
	if onto:
		c.holding["close"] = _grip_onto(c, side, best.part)
	if sides.size() > 1:
		var second = nearest_part(c, sides[1], [best.e], touch, -1.0 if big else gap)
		if second:
			c.holding.extra = {"side": sides[1], "part": second.part, "joint": hand_joint(c, sides[1], second.part)}
			if onto:
				c.holding.extra["close"] = _grip_onto(c, sides[1], second.part)
	var friend: bool = best.e.team == e.team
	var t: Fighter = best.e.f
	var lbl := Loc.lower(String(best.part.label))
	var line: String
	if friend:
		line = "%s grabbed %s by the %s with both hands" if c.holding.extra else "%s grabbed %s by the %s"
	else:
		line = "%s grabbed %s's %s with both hands!" if c.holding.extra else "%s grabbed %s's %s!"
	m.feed.emit(Loc.t(line) % [c.display_name, t.display_name, lbl])
	m.sfx("slap", c.hand_world(side))
	if not friend:
		t.stagger = minf(1.0, t.stagger + 0.3)
		t.grabbed_by = c
		if t.get("arm") != null and t.kind != "beast":
			for s in ["R", "L"]:
				if best.part == t.arm[s].fore or best.part == t.arm[s].upper:
					t.pinned_arm = s
					m.feed.emit(Loc.t("%s pins %s's sword arm!" if s == "R" else "%s pins %s's shield arm!") % [c.display_name, t.display_name])
	return t

## The other hand takes hold too, of the same man, wherever it reaches him.
func add_second_hand(e: Dictionary, on_him := false, gap := MAN_REACH) -> bool:
	var c: Fighter = e.f
	var h = c.holding
	if h == null or h.limb != null or h.extra != null:
		return false
	var side := "L" if h.side == "R" else "R"
	if not hand_free(c, side):
		if not on_him:
			_hint(e, Loc.t("Your right hand is full" if side == "R" else "Your left hand is full"))
		return false
	var best = nearest_part(c, side, [h.target], big_hands(c, e) or on_him, -1.0 if big_hands(c, e) else gap)
	if best == null:
		if not on_him:
			_hint(e, Loc.t("Your right hand cannot reach him" if side == "R" else "Your left hand cannot reach him"))
		return false
	h.extra = {"side": side, "part": best.part, "joint": hand_joint(c, side, best.part)}
	if on_him and not big_hands(c, e):
		h.extra["close"] = _grip_onto(c, side, best.part)
	m.feed.emit(Loc.t("%s gets both hands on %s") % [c.display_name, h.target.f.display_name])
	m.sfx("slap", c.hand_world(side))
	return true

## G at a man: a man's hand goes out to him, and closes on him where it touches him (user: there
## was no physical contact at all when a player pressed the grab button on a foe; the hand took
## whatever part of him had its middle within 70 cm of it, from where it hung, and he was held on
## nothing). The nearest of him within the arm's reach of that shoulder is reached for, for
## GRAB_TRY_T at most, the hand sent to the spot on him nearest it (Fighter's `grabAt`: he stoops
## to a man on the sand), and the hold is taken the moment the hand is on him (grab_person's
## touch, the giants' own: the hand MAN_REACH from the part its forearm touches; in the last
## third of the reach a fist's width, GRAB_LAST, when the forearm lies along him and its end cannot
## come nearer). Nobody in reach: no reach (G is then for what lies on the sand). A giant's hand
## needs none of this (big_hands).
const GRAB_TRY_T := 0.6
const GRAB_TRY_DOWN := 2.0   # for a man on the sand: he has to stoop to him first
const GRAB_LAST := 0.12
const GRAB_ARM := 1.1      # how far from the shoulder the spot on him may be (x the arm's length), and
const GRAB_LEAN := 0.25    # a lean more (m x S)
const GRAB_INTO := 0.05    # the hand is sent this far into him (m), so that it comes onto him
const GRAB_STOOP := 0.4    # to a man below him, near along the sand, he stoops (Fighter's grabAt): his shoulder comes this much lower (x S)
func grab_go(e: Dictionary, inp: Dictionary):
	var c: Fighter = e.f
	if big_hands(c, e):
		return grab_person(e, inp)
	if not c.alive or c.holding != null or c.state != "stand":
		return null
	var sides := grab_hands(e, inp)
	if sides.is_empty():
		return null
	var spot = _spot_on(c, sides[0], m.entities.filter(func(o): return o != e and o.f.alive))
	if spot == null:
		return null
	var secs := GRAB_TRY_T if String(spot.e.f.get("state")) == "stand" else GRAB_TRY_DOWN
	e.grab_try = {"t": secs, "all": secs, "side": sides[0], "target": spot.e, "both": sides.size() > 1, "second": false}
	return spot.e.f

## The nearest of `targets` to `side`'s hand that the arm can reach: {e, part, at (the spot on it)}.
func _spot_on(c: Fighter, side: String, targets: Array):
	var hand := c.hand_world(side)
	var up: VoxelPart = c.arm[side].upper
	var sh: Vector3 = up.global_transform * up.ca   # (its shoulder)
	var far := (Fighter.UPPER_LEN + Fighter.FORE_LEN) * c.S * GRAB_ARM + GRAB_LEAN * c.S
	var mid: Vector3 = c.torso.global_position
	var best = null
	var bd := INF
	for o in targets:
		if not is_instance_valid(o.f):
			continue
		for part in o.f.parts:
			if part.severed or part.missing:
				continue
			var at := box_point(part, hand)
			var from := sh
			if Vector2(at.x - mid.x, at.z - mid.z).length() < Fighter.GRAB_BEND_NEAR * c.S:
				from.y = clampf(at.y, sh.y - GRAB_STOOP * c.S, sh.y)
			if at.distance_to(from) > far:
				continue
			var d := at.distance_to(hand)
			if d < bd:
				bd = d
				best = {"e": o, "part": part, "at": at}
	return best

## A reach under way (grab_go, or the other hand's): the hand sent to him, and the hold taken
## when it is on him. Returns the input he acts on this step.
func _grab_reach(e: Dictionary, inp: Dictionary, dt: float) -> Dictionary:
	var tr: Dictionary = e.grab_try
	var c: Fighter = e.f
	var side: String = tr.side
	tr.t -= dt
	var te = tr.target
	var holds: bool = c.holding != null
	if tr.t <= 0.0 or not c.alive or c.state != "stand" or te == null or not is_instance_valid(te.f) or not hand_free(c, side) or holds != bool(tr.second) or (holds and c.holding.target != te):
		e.erase("grab_try")
		return inp
	var spot = _spot_on(c, side, [te])
	if spot == null:
		e.erase("grab_try")
		return inp
	var out := inp.duplicate()
	var hand := c.hand_world(side)
	var to: Vector3 = (spot.at as Vector3) - hand
	out.grab = true
	out.grabHands = side
	out.grabAt = (spot.at as Vector3) + (to.normalized() * GRAB_INTO if to.length() > 0.01 else Vector3.ZERO)
	var gap := GRAB_LAST * c.S if float(tr.t) < float(tr.all) / 3.0 else MAN_REACH * c.S
	if tr.second:
		if add_second_hand(e, true, gap):
			e.erase("grab_try")
	elif grab_person(e, out, true, te, gap) != null:
		e.erase("grab_try")
		# (Both buttons held: the other hand goes to him next.)
		if tr.both and c.holding != null and c.holding.extra == null:
			var other := "L" if side == "R" else "R"
			if hand_free(c, other):
				e.grab_try = {"t": GRAB_TRY_T, "all": GRAB_TRY_T, "side": other, "target": te, "both": false, "second": true}
	return out

## G near a limb lying on the sand: pick it up and fight with it.
func grab_limb(e: Dictionary):
	var c: Fighter = e.f
	if not c.alive or c.holding != null:
		return null
	var side := ""
	if not c.weapons.R and not c.arm.R.fore.severed and not (c.two_handed and c.two_off() == "R"):
		side = "R"
	elif not c.weapons.L and not c.arm.L.fore.severed and not (c.two_handed and c.two_off() == "L"):
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
	m.feed.emit(Loc.t("%s picked up their own %s and is going to hit people with it") % [c.display_name, Loc.lower(String(part.label))] if own else Loc.t("%s picked up %s's %s and is going to hit people with it") % [c.display_name, best.e.f.display_name, Loc.lower(String(part.label))])
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
	m.feed.emit(Loc.t("%s threw a %s!") % [c.display_name, Loc.lower(String(part.label))])
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
	m.feed.emit(Loc.t("%s SLAMS %s into the sand!") % [c.display_name, t.display_name])
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
		m.feed.emit(Loc.t("%s strains against %s's weight") % [c.display_name, t.display_name])
	t.fall(2.5 if strong else 1.2 + minf(1.5, ratio * 0.4), true)
	t.torso.apply_central_impulse(Vector3(aim.x * power, power * (0.75 if strong else 0.35 + maxf(0.0, aim.y)), aim.z * power))
	for p in live:
		if p != t.torso:
			p.apply_central_impulse(Vector3(aim.x * power * 0.08, power * 0.03, aim.z * power * 0.08))
	t.thrown_by = c
	t.thrown_t = 1.5
	flights[t] = {"peak": 0.0, "v": Vector3.ZERO}   # (followed to where he lands: flying_hits)
	c.stamina = maxf(0.0, c.stamina - 25.0)
	m.feed.emit((Loc.t("%s CATAPULTED %s!") % [c.display_name, t.display_name]) if strong else (Loc.t("%s tossed %s") % [c.display_name, t.display_name]))
	m.sfx("whoosh" if strong else "thud", t.torso.global_position)
	m.say(c, "grunt", 0.9, "effort")
	if strong:
		m.crowd_add(c, 12, "human catapult")
	return true

## A thrown man is a projectile: landing on someone hurts them (and him). And whatever stops him,
## the sand, the wall, another man, hurts him by how hard it stopped him (user: the giant holds a
## man in one hand and really throws him, and it does him harm; tossed across the arena he got up
## from the sand untouched unless he came down on his feet from high up).
var flights := {}   # Fighter -> {peak, v}: a man thrown by another, followed to his landing
func flying_hits(dt: float) -> void:
	for f in flights.keys():
		if not is_instance_valid(f) or not (f.thrown_t > 0.0) or not f.alive:
			flights.erase(f)
	for e in m.entities:
		var c = e.f
		if not (c.thrown_t > 0.0):
			continue
		c.thrown_t -= dt
		var vel: Vector3 = c.torso.linear_velocity
		var speed := vel.length()
		var fl = flights.get(c)
		if fl != null:
			fl.peak = maxf(float(fl.peak), speed)
			if float(fl.peak) > 6.0 and speed < float(fl.peak) * 0.5:
				_throw_land(c, float(fl.peak) - speed, fl.v)
				flights.erase(c)
			elif speed > 1.0:
				fl.v = vel
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
			m.feed.emit(Loc.t("%s landed on %s!") % [c.display_name, o.f.display_name])
			m.crowd_add(by, 8, "human cannonball")
			c.thrown_t = 0.0
			break

## What stopping a man does to him, the sand's blow or a wall's: by the speed it took off him (m/s).
## One law for a man thrown and for a man an ape beats on the sand (Beast._rag_land).
static func landing_blow(drop: float) -> float:
	return clampf(drop * 2.6, 8.0, 52.0)

## The landing of a man thrown: a blunt blow on the trunk and the skull by how hard he was
## stopped (as the Hand of Jupiter's, _mind_land), charged to whoever threw him.
func _throw_land(t: Fighter, drop: float, pv: Vector3) -> void:
	var by = t.thrown_by if t.thrown_by != null and is_instance_valid(t.thrown_by) else null
	var J := landing_blow(drop)
	var dir: Vector3 = -pv.normalized() if pv.length_squared() > 1e-4 else Vector3.DOWN
	var was_alive := t.alive
	for pk in [[t.torso, 1.0], [t.head, 0.45]]:
		var part: VoxelPart = pk[0]
		if part == null or part.severed or not t.alive:
			continue
		var point := part.global_position
		var res: Dictionary = t.apply_hit(part, {"impulse": J * pk[1], "type": "blunt", "hardness": 0.6, "sharpness": 0.0, "point": point, "dir": dir})
		m.report_hit({"kind": "hit", "p": point, "dir": dir, "J": J * pk[1], "type": "blunt", "char": t, "part": part, "attacker": by, "res": res, "killed": was_alive and not t.alive, "landing": true})
	if by != null:
		t.last_attacker = by
	t.concussion = minf(1.0, t.concussion + 0.25 * J / 52.0)
	t.stamina = maxf(0.0, t.stamina - J * 0.5)
	if J > 20.0:
		m.feed.emit(Loc.t("%s lands hard!") % t.display_name)
	m.sfx("thud", t.torso.global_position, clampf(J / 40.0, 0.4, 1.0))

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
	t.jolt_t = t.time
	t.last_attacker = c
	var goes_down: bool = t.state == "rising" or t.stagger > 0.75 or t.stamina < 20.0
	if goes_down and t.state != "down" and ratio > 0.5:
		t.fall(1.1)
		m.feed.emit(Loc.t("%s shoved %s to the sand") % [c.display_name, t.display_name])
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
	m.feed.emit('%s: "%s"' % [c.display_name, Loc.t(line)])
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
	m.feed.emit(Loc.t(String(em.feed)) % c.display_name)
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
	# A man in his grip: F hurls him, not the sword in hand.
	var mnd = mind_of(e)
	if mnd != null and inp.get("throw", false):
		_mind_hurl(mnd, _aim_dir(e, inp, _aim_from(e, inp)))
		inp = inp.duplicate()
		inp.throw = false
		inp.charging = 0.0
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
			m.feed.emit(Loc.t("%s plays dead. Very convincing.") % c.display_name)
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
			# A weapon of his stuck fast in a body: G lets go of it (it stays in him).
			if c.lodged_side() != "" and c.let_go_lodged():
				took = true
			elif tear_out(c):
				took = true
			elif e.has("grab_try"):
				took = true   # (his hand is on its way to a man already)
			elif gh == null:
				took = c.grab_nearest(m.combat.loose_weapons)
			else:
				took = grab_go(e, inp)
				# Nobody in that hand's reach: it takes a weapon lying there instead (G with the
				# button down near a sword once did nothing at all).
				if took == null and gh != "both":
					took = c.grab_nearest(m.combat.loose_weapons, gh)
			# (The word and the sound come when the hand has it: Match._on_took_up.)
			if took == null:
				took = grab_limb(e)
			if took == null and gh == null:
				took = grab_go(e, inp)
		# A throw is a movement, not a teleport: the arm (already drawn back while F was held, or
		# drawn back now for a bot) whips forward and the thing leaves the hand partway through.
		if inp.get("throw", false) and c.alive and not e.has("throw_q"):
			var side: String = c.item_hand() if c.held_item != null else throw_side(c, inp)
			if c.held_item != null or c.weapons.get(side):
				var player: bool = e.kind == "local" or e.kind == "remote"
				# A spear leaves the hand over the shoulder, at the top of the hand's speed. A bot's
				# too: it left the bot's drawn-back hand before the arm had moved, so its wind-up is
				# that much shorter and the spear leaves as long after the bot chose to throw as ever.
				var go: float = SPEAR_GO if c.held_item == null and c.weapons[side].point_first() else 0.0
				e.throw_q = {"inp": inp.duplicate(), "t": (go if go > 0.0 else 0.09) if player else 0.45 - go, "side": side, "go": 0.0 if player else go}
				c.throw_anim = {"side": side, "phase": "follow" if player else "wind", "t": 0.4 if player else 0.45 - go}
		if e.has("throw_q"):
			e.throw_q.t -= dt
			if e.throw_q.t <= 0.0:
				var q: Dictionary = e.throw_q
				if float(q.get("go", 0.0)) > 0.0 and c.alive:
					# (A bot's spear, drawn back: now the arm drives, and it leaves the hand on the way.)
					q.t = q.go
					q.go = 0.0
					c.throw_anim = {"side": q.side, "phase": "follow", "t": 0.4}
				else:
					e.erase("throw_q")
					if c.alive:
						_throw(e, q.inp, q.side)
						c.throw_anim = {"side": q.side, "phase": "follow", "t": 0.35}
	if inp.get("taunt", false):
		taunt(e)
	if inp.get("shove", false):
		shove(e)
	# (After all that G did this step: the reach's own G is not a press.)
	if e.has("grab_try"):
		inp = _grab_reach(e, inp, dt)
	return inp

## G with someone's blade stuck in him: he tears it out of himself (it comes out on its next step,
## as if wrenched, and the wound bleeds for it). Nobody is left on the end of another's weapon.
func tear_out(c) -> bool:
	for o in m.entities:
		if not is_instance_valid(o.f) or o.f == c:
			continue
		for w in o.f.weapons.values():
			if w and w.stuck != null and w.stuck.has("need") and w.stuck.char == c:
				w.stuck.age = Weapon.LODGE_HOLD
				return true
	return false

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
		tgt = aim_ahead(c, inp.aimAt, look, inp.get("aimFrom"))
	elif player and look != null:
		dir = Vector3(sin(look.yaw) * cos(look.pitch), sin(look.pitch), cos(look.yaw) * cos(look.pitch))
	else:
		var o = m.nearest_enemy(e)
		tgt = o.f.torso.global_position + Vector3(0, 0.25, 0) if o else null
	if c.throw_weapon(side, tgt, clampf(float(inp.get("throwPower", 0.8)), 0.3, 1.0), dir):
		m.sfx("whoosh", c.hand_world(side))

## Which hand throws: the main weapon first, the shield once the main hand is empty; or the
## other hand when the player picked it (a tap of the left button while winding up), if it
## holds anything.
static func throw_side(c, inp: Dictionary) -> String:
	var side := "R" if c.weapons.R else "L"
	if inp.get("throwOther", false):
		var other := "L" if side == "R" else "R"
		if c.weapons.get(other):
			return other
	return side

## A mark behind the thrower (the wall at his back) is never thrown at: it is moved to a few
## strides ahead where he looks. Nor one farther along the crosshair's line than a throw reaches
## without a lob (THROW_MARK, less looking up): past that the arc that lands on it jumped from a
## flat throw to a high lob and back as the crosshair went over the far sand, the wall and the
## sky (user: each throw at another angle). It is drawn in along the line it is seen along
## (`from`, the crosshair's eye), so it stays under the crosshair.
const THROW_MARK := 18.0
const SPEAR_GO := 0.07   # s from the arm's drive forward to a spear leaving the hand
static func aim_ahead(c, at: Vector3, look, from = null) -> Vector3:
	if look == null:
		return at
	var fwd := Vector3(sin(look.yaw), 0, cos(look.yaw))
	var hp: Vector3 = c.head.global_position
	if (at - hp).dot(fwd) < -0.3:
		var d := Vector3(sin(look.yaw) * cos(look.pitch), sin(look.pitch), cos(look.yaw) * cos(look.pitch))
		var p := hp + d * 4.0
		p.y = maxf(0.05, minf(at.y, hp.y))
		return p
	var o: Vector3 = from if from is Vector3 else hp
	var line := at - o
	var dist := line.length()
	var most := THROW_MARK / (1.0 + maxf(0.0, line.y / maxf(1e-3, dist)))
	if dist > most:
		at = o + line / dist * most
	return at

const HEAVE_T := 0.34      # s from F to the man leaving the hands
const HEAVE_BACK := 0.38   # of it drawing him back
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
				m.feed.emit(Loc.t("%s tore free of %s's grip!") % [t.display_name, c.display_name])
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
	_grip_close(h, dt)
	if h.extra != null:
		_grip_close(h.extra, dt)
	var gh = inp.get("grabHands")
	var man: bool = not big_hands(c, e)
	# A man thrown is heaved: the arms that hold him draw him back and drive him out the way he
	# goes, and he leaves them at the end of the drive (he flew from still arms the step F was
	# pressed: user, the throws). A giant's hoist and hurl are his bot's own.
	if h.has("heave"):
		var hv: Dictionary = h.heave
		hv.t += dt
		var k := float(hv.t) / HEAVE_T
		var out := inp.duplicate()
		var back := k < HEAVE_BACK
		for sd in ([h.side, h.extra.side] if h.extra != null else [h.side]):
			var pose := {"x": (0.55 if sd == "R" else -0.55), "y": 0.25} if back else {"x": (0.1 if sd == "R" else -0.1), "y": 0.75}
			if sd == "R":
				out.main = pose
				out.thrust = -0.9 if back else 1.4
			else:
				out.off = pose
				out.offThrust = -0.9 if back else 1.4
		out.power = true
		if k >= 1.0:
			throw_person(e, hv.inp)
		return out
	if inp.get("grab", false) and gh != null and h.limb == null and h.extra == null and h.t > 0.2 and (gh == "both" or gh != h.side):
		if man:
			var other := "L" if h.side == "R" else "R"
			if not hand_free(c, other):
				_hint(e, Loc.t("Your right hand is full" if other == "R" else "Your left hand is full"))
			elif _spot_on(c, other, [h.target]) == null:
				_hint(e, Loc.t("Your right hand cannot reach him" if other == "R" else "Your left hand cannot reach him"))
			elif not e.has("grab_try"):
				e.grab_try = {"t": GRAB_TRY_T, "all": GRAB_TRY_T, "side": other, "target": h.target, "both": false, "second": true}
		else:
			add_second_hand(e)
	elif inp.get("throw", false):
		if h.limb != null:
			_throw_limb(e, inp)
		elif man:
			h["heave"] = {"t": 0.0, "inp": inp.duplicate()}
		else:
			throw_person(e, inp)
	elif inp.get("slam", false) and h.limb == null:
		slam_person(e)
	elif inp.get("grab", false) and h.t > 0.3:
		let_go(c)
		m.feed.emit(Loc.t("%s let go") % c.display_name)
	elif h.limb == null and h.target.team != e.team and t.alive:
		# Wrestling: the grabbed enemy struggles and both tire.
		c.stamina = maxf(0.0, c.stamina - dt * 6.0)
		t.stamina = maxf(0.0, t.stamina - dt * 8.0)
		var odds: float = 0.25 * (pow(t.S, 2.5) * float(t.mods.strength)) / (pow(c.S, 2.5) * float(c.mods.strength)) * (0.4 + 0.8 * t.stamina / 100.0) / (0.4 + 0.8 * c.stamina / 100.0) / (1.8 if h.extra != null else 1.0)
		if h.target.kind != "local" and h.target.kind != "remote" and randf() < dt * minf(2.0, odds):
			let_go(c)
			m.feed.emit(Loc.t("%s wriggled free") % t.display_name)
	return inp

## After everyone moved: thrown men landing on people, thrown limbs settling.
func after(dt: float) -> void:
	for e in m.entities:
		for p in e.f.parts:
			if p.thrown_t > 0.0:
				p.thrown_t -= dt
	flying_hits(dt)
	minds_tick(dt)

# ---------- The Hand of Jupiter ----------

## The grip `e` holds now (not one he has already let fly), or null.
func mind_of(e: Dictionary):
	for mnd in minds:
		if mnd.e == e and not mnd.flung:
			return mnd
	return null

static func _aim_from(e: Dictionary, inp: Dictionary) -> Vector3:
	var af = inp.get("aimFrom", e.get("last_aim_from"))
	if af is Vector3:
		return af
	var c: Fighter = e.f
	return c.head.global_position if not c.head.severed else c.torso.global_position + Vector3.UP * 0.5

static func _aim_dir(e: Dictionary, inp: Dictionary, from: Vector3) -> Vector3:
	var at = inp.get("aimAt", e.get("last_aim"))
	if at is Vector3 and (at as Vector3).distance_to(from) > 0.2:
		return ((at as Vector3) - from).normalized()
	var lk = inp.get("look")
	if lk is Dictionary:
		return Vector3(sin(float(lk.yaw)) * cos(float(lk.pitch)), sin(float(lk.pitch)), cos(float(lk.yaw)) * cos(float(lk.pitch))).normalized()
	var c: Fighter = e.f
	return Vector3(sin(c.yaw), 0.1, cos(c.yaw)).normalized()

## Seizes the foe in the crosshair (the nearest one close by when nothing is): true if a man
## is held. Whoever is too big, or a boss, is beyond the grip.
func mind_hold(e: Dictionary) -> bool:
	var c = e.f
	if not (c is Fighter) or not c.alive or mind_of(e) != null:
		return false
	if int(e.get("mind_uses", 0)) >= MIND_USES:
		_hint(e, "The Hand of Jupiter is spent for this bout")
		return false
	if float(e.get("mind_cool", -1.0)) > m.time:
		_hint(e, Loc.t("The grip needs a moment (%d s)") % ceili(float(e.mind_cool) - m.time))
		return false
	var inp: Dictionary = e.get("input", {})
	var from := _aim_from(e, inp)
	var dir := _aim_dir(e, inp, from)
	var best = null
	var bd := INF
	for o in m.entities:
		if o == e or o.team == e.team or not o.f.alive or o.get("harmless", false) or not (o.f is Fighter):
			continue
		var t: Fighter = o.f
		if _is_giant(t):
			continue
		var to: Vector3 = t.torso.global_position - from
		var along := to.dot(dir)
		if along < 0.3 or along > MIND_REACH:
			continue
		var off := (to - dir * along).length()
		if off > 0.9 * float(t.S) + 0.15 * along:
			continue
		if off < bd:
			bd = off
			best = o
	if best == null:
		# Closed on nothing: nobody is seized, and the grip needs a moment before the next try.
		e.mind_cool = m.time + MIND_COOL
		_hint(e, "The grip closes on nothing: look at a foe (no giants)")
		return false
	var t: Fighter = best.f
	for p in t.parts:
		if not p.severed:
			p.angular_velocity *= 0.3
	t.fall(0.5, true)
	t.last_attacker = c
	e.mind_uses = int(e.get("mind_uses", 0)) + 1
	e.mind_cool = m.time + MIND_REST
	minds.append({"e": e, "t": t, "left": MIND_T, "dist": MIND_DIST, "flung": false, "prev_v": Vector3.ZERO, "peak": 0.0, "watch": 0.0, "fx_t": 0.0})
	var seize := "%s seizes %s in an unseen grip! He hangs where you look: F hurls him." if e.kind == "local" else "%s seizes %s in an unseen grip!"
	m.feed.emit(Loc.t(seize) % [c.display_name, t.display_name])
	m.sfx("whoosh", t.torso.global_position)
	m.say(t, "grunt", 0.8, "pain")
	m.crowd_add(c, 10, "the hand of Jupiter")
	return true

## Too big for the grip: a giant of a man (a cyclops, a troll, a titan: MIND_S), a beast of
## MIND_MASS and more (a rhino, an elephant, a mammoth) and the monsters of myth that come as
## bosses (MIND_MONSTERS: the dragon, the hydra, Cerberus...). Everything else hangs: men,
## bosses among them, and beasts up to a bull or a gorilla.
const MIND_MASS := 500.0
const MIND_MONSTERS := ["dragon", "hydra", "cerberus", "chimera", "manticore", "basilisk"]
static func _is_giant(t) -> bool:
	if t is Beast:
		return t.live_mass() >= MIND_MASS or MIND_MONSTERS.has(String(t.species))
	return float(t.S) > MIND_S

func minds_tick(dt: float) -> void:
	for mnd in minds.duplicate():
		var t: Fighter = mnd.t
		var c = mnd.e.f
		if not is_instance_valid(t) or not is_instance_valid(c):
			minds.erase(mnd)
			continue
		if mnd.flung:
			# In the air: his landing (the ground, a wall, a man) hurts by how hard it stopped him.
			mnd.watch -= dt
			var v: Vector3 = t.torso.linear_velocity
			var peak: float = maxf(float(mnd.peak), v.length())
			mnd.peak = peak
			if v.length() < peak * 0.5 and peak > 6.0 and t.alive:
				_mind_land(mnd, peak - v.length())
				minds.erase(mnd)
				continue
			if v.length() > 1.0:
				mnd.prev_v = v
			if mnd.watch <= 0.0:
				minds.erase(mnd)
			continue
		if not t.alive or not c.alive:
			minds.erase(mnd)
			continue
		mnd.left -= dt
		var inp: Dictionary = mnd.e.get("input", {})
		var from := _aim_from(mnd.e, inp)
		var dir := _aim_dir(mnd.e, inp, from)
		if mnd.left <= 0.0:
			# The grip fades: he drops where he hangs.
			minds.erase(mnd)
			t.fall(0.8, true)
			m.feed.emit(Loc.t("The grip on %s lets go") % t.display_name)
			continue
		# The wheel draws him in or pushes him off.
		mnd.dist = clampf(float(mnd.dist) + float(inp.get("wheel", 0.0)) * 0.5, MIND_NEAR, MIND_FAR)
		var goal := from + dir * float(mnd.dist)
		goal.y = maxf(goal.y, 1.7 * float(t.S))   # high enough that his feet find no sand
		var pos: Vector3 = t.torso.global_position
		# A spring to where he should hang, damped, with his weight carried: the trunk is held,
		# the rest of him dangles (and swings as he likes).
		var acc := ((goal - pos) * 30.0 - t.torso.linear_velocity * 7.0).limit_length(80.0) + Vector3.UP * 9.8
		t.torso.apply_central_force(acc * t.torso.mass)
		for p in t.parts:
			if p != t.torso and not p.severed:
				p.apply_central_force(Vector3.UP * 9.8 * p.mass * 0.85)
		t.fall(0.5, true)
		mnd.fx_t -= dt
		if mnd.fx_t <= 0.0 and m.fx:
			mnd.fx_t = 0.12
			m.fx.burst("sparks", pos, 3, Vector3.UP, 0.6)

## F lets go: he flies on with the swing he was given (a fast sweep of the mouse and F sends him
## the way the sweep went), and a little the way his captor looks.
func _mind_hurl(mnd: Dictionary, dir: Vector3) -> void:
	var t: Fighter = mnd.t
	var c = mnd.e.f
	var v: Vector3 = t.torso.linear_velocity * 1.25 + dir * MIND_HURL * 0.5
	if v.length() < MIND_HURL * 0.65:
		v = (v.normalized() if v.length() > 0.5 else dir) * MIND_HURL * 0.65
	v = v.limit_length(MIND_HURL * 1.7) + Vector3.UP * 0.8
	for p in t.parts:
		if not p.severed:
			p.linear_velocity = v
			p.angular_velocity = Vector3.ZERO
	t.torso.continuous_cd = true
	t.fall(2.0, true)
	t.thrown_by = c
	t.thrown_t = 1.5
	mnd.flung = true
	mnd.prev_v = v
	mnd.peak = v.length()
	mnd.watch = 2.5
	m.feed.emit(Loc.t("%s HURLS %s!") % [c.display_name, t.display_name])
	m.sfx("whoosh", t.torso.global_position)
	m.crowd_add(c, 8, "hurled")

## The landing: a blunt blow on the trunk and the skull by how hard he was stopped.
func _mind_land(mnd: Dictionary, drop: float) -> void:
	var t: Fighter = mnd.t
	var c = mnd.e.f
	var J := clampf(drop * 2.6, 8.0, 52.0)
	var pv: Vector3 = mnd.prev_v
	var dir: Vector3 = -pv.normalized() if pv.length_squared() > 1e-4 else Vector3.DOWN
	var was_alive := t.alive
	for pk in [[t.torso, 1.0], [t.head, 0.45]]:
		var part: VoxelPart = pk[0]
		if part == null or part.severed:
			continue
		var point := part.global_position
		var res: Dictionary = t.apply_hit(part, {"impulse": J * pk[1], "type": "blunt", "hardness": 0.6, "sharpness": 0.0, "point": point, "dir": dir})
		m.report_hit({"kind": "hit", "p": point, "dir": dir, "J": J * pk[1], "type": "blunt", "char": t, "part": part, "attacker": c, "res": res, "killed": was_alive and not t.alive})
	t.last_attacker = c
	t.concussion = minf(1.0, t.concussion + 0.3 * J / 52.0)
	if J > 20.0:
		m.feed.emit(Loc.t("%s lands hard!") % t.display_name)
		if m.me != null and mnd.e == m.me and not m.headless:
			Achievements.unlock("jupiter_hand")
	m.sfx("thud", t.torso.global_position, clampf(J / 40.0, 0.4, 1.0))

## Bots: a taunt pulls them onto the taunter; nobody bothers a man playing dead while someone
## else is awake.
func target_for(e: Dictionary, candidates: Array):
	if e.get("taunted_by") != null and e.get("taunt_t", 0.0) > 0.0 and e.taunted_by.f.alive:
		return e.taunted_by
	if e.kind != "local" and e.kind != "remote":
		var awake := []
		for o in candidates:
			if o.f.get("limp"):
				continue
			var pd = o.f.get("played_dead")
			if not (float(pd if pd != null else 0.0) > 0.0):
				awake.append(o)
		if not awake.is_empty() and awake.size() < candidates.size():
			return {"only": awake}
	return null

func clear() -> void:
	flights.clear()
	for e in m.entities:
		if e.f is Fighter and e.f.holding != null:
			let_go(e.f)
