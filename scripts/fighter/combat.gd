class_name Combat
extends Node
## Turns contacts into blows (combat.js): a weapon on a body part, a fist, a kick or a bite on
## someone, weapon on weapon (a clang that chips edges). Bodies report their contacts during the
## physics step; they are judged on the next one against the velocities going into the step
## that made them, since by then the solver has already stopped the blade.

signal hit(info: Dictionary)
signal clang(info: Dictionary)
signal chip(info: Dictionary)

const TYPE_RANK := {"point": 3, "edge": 2, "blunt": 1, "grip": 0}
const STRIKING := ["forearmR", "forearmL", "shinR", "shinL", "head"]
## An elephant's or a mammoth's tusk (_tusk): the weight behind it, and the most a blow of it is.
const TUSK_M := 10.0
const TUSK_CAP := 85.0

static var current: Combat = null

var fighters: Array = []      # Fighter and Beast nodes in the match
## The beasts among them, picked out once a step (and again whenever the list's length changes): each man asks every step whether a beast has hold of
## him (Fighter._beast_has_me_now), and looked through the whole list for the beasts to ask: sixteen men, sixteen times sixteen, in a fight with no
## beast in it at all. Which of them is alive and what it holds is still asked of each at the moment, as before.
## (One list for every man: where the men's controls run on worker threads (Match._run_jobs, an experiment) it is picked out on the main thread before
## they start, and they only read it. Picked out by the first of them to ask, several at once made and let go of the list under one another.)
var _beasts: Array = []
var _beasts_key := -1
func beasts() -> Array:
	var key := Engine.get_physics_frames() * 4096 + fighters.size()
	if key != _beasts_key:
		var found := []
		for o in fighters:
			if is_instance_valid(o) and o.get("kind") == "beast":
				found.append(o)
		_beasts = found
		_beasts_key = key
	return _beasts
var loose_weapons: Array = [] # weapons nobody holds (thrown, dropped)
var pending: Array = []          # the step's contacts that may be a blow, each [a, b, a's shape, b's shape, where, the impulse] (report; a list each, not a table of six names: 140 a step in a melee)
var touch_q: Array = []          # [part, part, impulse] reported this step, noted at the next (see _settle)
## Contacts handled in an order of their own (see _in_order), not the physics' (off in play: the
## game is tuned to it; the trailer's recorder turns it on, its two passes then go the same way).
static var canonical := false
var vel := {}
var cool := {}
var time := 0.0
var enabled := true
var chip_mult := 1.0             # Glass Weapons: every hit breaks something
const TWO_HAND_BLOW := 1.2       # a blow with both hands on the haft, over one
## A push kick (Fighter.kick_push 1: a long press of the kick's key, one strength) against a plain kick: how much more of the foot's speed is the blow (x), how much higher the blow may go (the
## cap), the least it lands with (the weight of the man is behind it, whatever the foot's own speed when it meets him), how much more of an impulse is put on his trunk (N s) and how fast the
## whole of him is sent back over it (m/s, by a man's own weight against his: sent back, not launched), and how likely he is to be felled by it.
const PUSH_BLOW := 0.9
const PUSH_CAP := 8.0     # (user, "really strong": its harm was J 40, which took 62 voxels off a belly, 5% of his blood and an organ, now J 28: about a third of that; the shove is not the blow's)
const PUSH_JMIN := 28.0
const PUSH_SHOVE := 40.0
const PUSH_DV := 1.0
const PUSH_FELL := 0.8
static var LODGE_K := 1.0        # how readily held blades stay in the wound (tests set it to 0 or 1e3)
var touches := {}                # a beast's (a man's) id -> {the other's id -> [t, a: the toucher's part, b: the touched part, J, Jmax]}: whose body is on whom
var touches_p := {}              # a part's id -> {the other man's id -> the same}: what one part is on (a forearm, a beast's part)
# (A note is a list of five, not a table of five names: it is written over a hundred times a step in a melee, and a list's places are a fifth of a table's keys to write.)
# (By the two ids, one table in another: they were one table by a key spelt out of the two ("12:34", "p12:34"), and the spelling was most of what a note cost.)

## The last touch of any part of `a` on any part of `b` within `within` seconds: the victim's
## part touched, or null. A grapple, a squeeze, a roll or a trample is only real while the body
## doing it is in contact with the body it is done to.
func touch_part(a, b, within := 0.25) -> VoxelPart:
	if a == null or b == null:
		return null
	var row = touches.get(a.get_instance_id())
	var r = row.get(b.get_instance_id()) if row != null else null
	if r == null or time - float(r[0]) > within:
		return null
	return r[2] if is_instance_valid(r[2]) else null

func touching(a, b, within := 0.25) -> bool:
	return touch_part(a, b, within) != null

## Whether this one part of `a` touched `b` (any part) lately: the victim's part, or null.
func touch_by(part: VoxelPart, b, within := 0.25) -> VoxelPart:
	if part == null or b == null:
		return null
	var row = touches_p.get(part.get_instance_id())
	var r = row.get(b.get_instance_id()) if row != null else null
	if r == null or time - float(r[0]) > within:
		return null
	return r[2] if is_instance_valid(r[2]) else null

## The impulse the physics put through the touch of `a` on `b` this step (N·s, summed over
## their contacts): the weight and the drive actually bearing on him, for what a squeeze, a
## trample or a stomp does to him. Zero without a touch within `within` seconds.
func touch_impulse(a, b, within := 0.25) -> float:
	if a == null or b == null:
		return 0.0
	var row = touches.get(a.get_instance_id())
	var r = row.get(b.get_instance_id()) if row != null else null
	if r == null or time - float(r[0]) > within:
		return 0.0
	return float(r[3])

## Whether anyone ever asks what this part touched. touch_part, touching and touch_impulse are asked of a beast (its hug, its coil, its stomp, what it gripped), touch_by of a
## beast's part or of a forearm (the hand that grabs is on its forearm: Social.nearest_part). Of a man's thigh on another man's shin nobody asks, and those are nearly all of a
## melee's touches: with ten men pressed on one another 440 notes a step were written, two keys spelt out and a table looked up for each, and never read (the second
## diagnostic report: a room's step cost the same with eight alive as with twelve).
static func _asked(p: VoxelPart) -> bool:
	var v: int = p.touch_asked
	if v < 0:
		v = 1 if (p.fighter is Beast or String(p.part_name).begins_with("forearm")) else 0
		p.touch_asked = v
	return v == 1

## Whether this part can ever be the one that lands a blow on another's part (process_contacts lets go of a touch of two parts neither of which can): cut off (a club, perhaps),
## a striking part, a jaw, a point, a tusk.
static func _may_strike(p: VoxelPart) -> bool:
	if p.severed:
		return true
	var k: int = p.strike_ok
	if k < 0:
		k = _strike_static(p)
	return k == 1

## What of _may_strike does not change as a man is hurt (a striking part, a jaw, a point, a tusk), told of a part once: its `strike_ok`, let go again where a beast gives a part a bite.
## (Asked of every touch of every part, a dozen reads of other objects each: a tenth of a melee's step.)
static func _strike_static(p: VoxelPart) -> int:
	var k := 1 if (STRIKING.has(p.part_name) or p.def.get("bite", false) or p.def.get("point", false) or _tusk(p)) else 0
	p.strike_ok = k
	return k

func _note_touch(a: VoxelPart, b: VoxelPart, J: float) -> void:
	var fa = a.fighter
	var fb = b.fighter
	if fa == null or fb == null or fa == fb:
		return
	if not _asked(a):
		return
	var fbid: int = fb.get_instance_id()
	if fa is Beast:
		_note(touches, fa.get_instance_id(), fbid, a, b, J)
	_note(touches_p, a.get_instance_id(), fbid, a, b, J)

## _note_touch of two parts whose men are known to be two different men, and the first part one somebody asks about (report knows all of that).
func _note_on(a: VoxelPart, b: VoxelPart, fa, fb, J: float) -> void:
	var fbo: Object = fb   # (the ids asked of them as the objects they are: at a sixth of the cost)
	var fbid := fbo.get_instance_id()
	if fa is Beast:
		var fao: Object = fa
		_note(touches, fao.get_instance_id(), fbid, a, b, J)
	# (_note's lines for the table a melee writes a hundred times a step, here and not a call away.)
	var ao: Object = a
	var pid := ao.get_instance_id()
	var row = touches_p.get(pid)
	if row == null:
		row = {}
		touches_p[pid] = row
	var r = row.get(fbid)
	if r == null:
		row[fbid] = [time, a, b, J, J]
	elif float(r[0]) == time:
		r[3] += J
		if J > float(r[4]):
			r[4] = J; r[1] = a; r[2] = b
	else:
		r[0] = time; r[1] = a; r[2] = b; r[3] = J; r[4] = J

func _note(tab: Dictionary, ka: int, kb: int, a: VoxelPart, b: VoxelPart, J: float) -> void:
	var row = tab.get(ka)
	if row == null:
		row = {}
		tab[ka] = row
	var r = row.get(kb)
	if r == null:
		row[kb] = [time, a, b, J, J]
	elif float(r[0]) == time:
		r[3] += J   # another contact of the same step: the impulses add up
		if J > float(r[4]):
			r[4] = J; r[1] = a; r[2] = b   # the hardest contact names the parts
	else:
		# (The pair's first contact of this step: its record is written over, not made afresh.)
		r[0] = time; r[1] = a; r[2] = b; r[3] = J; r[4] = J

## Every note there is, as [of one part (true) or of a whole body (false), the note {t, a, b, J, Jmax}]: for the tests that look at what was noted.
func touch_notes() -> Array:
	var out := []
	for row in touches.values():
		for r in row.values():
			out.append([false, {"t": r[0], "a": r[1], "b": r[2], "J": r[3], "Jmax": r[4]}])
	for row in touches_p.values():
		for r in row.values():
			out.append([true, {"t": r[0], "a": r[1], "b": r[2], "J": r[3], "Jmax": r[4]}])
	return out

func _enter_tree() -> void:
	current = self
	process_physics_priority = -100

func _exit_tree() -> void:
	if current == self:
		current = null

## Pressed on by someone else's weapon this step, or by a giant's body or a beast's, a man is told of it
## (Fighter._no_fling caps what that adds to his speed: a man's shins caught in a giant's striding legs
## were flung at 25 m/s and sent him into the sky, user). This is that look, alone, for when the combat
## is off (report tells him in the same pass over the contacts that it makes of them).
func _struck_only(f, state: PhysicsDirectBodyState3D) -> void:
	for i in state.get_contact_count():
		var o = state.get_contact_collider_object(i)
		if o is Weapon:
			if o.holder != null and o.holder != f:
				f.struck_frame = Engine.get_physics_frames()
				break
		elif o is VoxelPart and o.fighter != null and o.fighter != f:
			if Fighter.is_giant_over(o, f):
				f.struck_frame = Engine.get_physics_frames()
				break
			if Fighter.is_beast_on(o, f):
				f.beast_frame = Engine.get_physics_frames()

## Called from a body's _integrate_forces with its contacts.
func report(body: RigidBody3D, state: PhysicsDirectBodyState3D) -> void:
	# The body is looked at once, and each contact let go at the first thing that rules it out:
	# most are a foot on the sand, or a body's own parts against each other, every step.
	var bw := body is Weapon
	var bp := not bw and body is VoxelPart
	if not (bw or bp):
		return
	var bf = body.fighter if bp else null
	# (A part's man is told what presses on him in this same pass, the combat on or not: `told` while he still may be. A man is a Fighter, a beast one too: the only ones with a struck_frame.)
	var told: bool = bp and bf != null and is_instance_valid(bf) and bf is Fighter
	if not enabled:
		if told:
			_struck_only(bf, state)
		return
	var bobj: Object = body   # (the ids asked of the bodies as the objects they are: at a sixth of the cost)
	var bid := bobj.get_instance_id()
	var holder = body.holder if bw else null
	# (What is read of the body is read once, not at every touch: whether it is cut off, whether its man is dead, how big he is. Whether anybody may ask who touched this part, and
	# whether it may land a blow, is asked of it only by a touch that gets as far as needing to know, -1 until then. Most bodies with a contact have the sand under them and their own
	# man's parts beside them, every step.)
	var b_sev: bool = body.severed if bp else false
	var b_dead := -1
	var giant_s := -1.0
	var b_asked := -1
	var b_strikes := -1
	for i in state.get_contact_count():
		var other = state.get_contact_collider_object(i)
		if other == null:
			continue
		var op := other is VoxelPart
		var ow := not op and other is Weapon
		if not (op or ow):
			continue
		var of = other.fighter if op else null   # (the other part's man, read once of the five times it was)
		if told:
			if ow:
				if other.holder != null and other.holder != bf:
					bf.struck_frame = Engine.get_physics_frames()
					told = false
			elif of != null and of != bf:
				# (Fighter.is_giant_over, else is_beast_on, in their own lines: the two were called for every touch of another man's part, and of two men neither is so.)
				if of is Beast:
					if not (bf is Beast) and not (of.hug != null and of.hug.get("target") == bf) and not (bf.has_meta("beast_hold") and bf.get_meta("beast_hold") == of):
						bf.beast_frame = Engine.get_physics_frames()
				else:
					if giant_s < 0.0:
						giant_s = float(bf.S) * Fighter.GIANT_OVER
					if float(of.S) > giant_s:
						bf.struck_frame = Engine.get_physics_frames()
						told = false
		if bp:
			if ow:
				# A trap does not move under physics, so the part it meets reports the contact
				# (any other weapon reports its own).
				if other.is_hazard:
					pending.append([other, body, state.get_contact_collider_shape(i), state.get_contact_local_shape(i), state.get_contact_local_position(i), state.get_contact_impulse(i).length()])
				continue
			# (A limb cut off is a club, even in the hands of the man it came off.)
			if bf != null and of == bf and not b_sev and not other.severed:
				continue
			# The parts of two fallen men against each other (a heap of the dead is a hundred such contacts a step, each
			# seen from both sides): nobody asks who touched whom among the dead (a hold, a squeeze or a stomp is the
			# living's), and a blow wants a living hand (process_contacts lets go of it): nothing to note, let go at once.
			if bf != null and of != null:
				if b_dead < 0:
					b_dead = 0 if bf.alive else 1
				if b_dead == 1 and not of.alive and not b_sev and not other.severed:
					continue
			# (Noted only where somebody may ask (_asked), kept only where one of the two may land a blow (_may_strike): the rest, which is most of a melee, is let go here.)
			if b_asked < 0:
				b_asked = 1 if bf != null and _asked(body) else 0
			var noted: bool = b_asked == 1
			var oa := -1   # (whether the other part is one somebody asks about: read at most once)
			if not noted and of != null:
				oa = other.touch_asked
				if oa < 0:
					oa = 1 if _asked(other) else 0
				noted = oa == 1
			var kept := false
			var oobj: Object = other
			if bid <= oobj.get_instance_id():
				if b_strikes < 0:
					b_strikes = 1 if _may_strike(body) else 0
				if b_strikes == 1:
					kept = true
				else:
					var ks: int = other.strike_ok
					if ks < 0:
						ks = _strike_static(other)
					kept = ks == 1 or other.severed
			if not (noted or kept):
				continue
			var cj := state.get_contact_impulse(i).length()
			if noted:
				if canonical:
					touch_q.append([body, other, cj])
				else:
					# (Each way only where the part is one somebody asks about: _note_touch lets go of the other at once, and was called to do it.)
					if b_asked == 1 and of != null and of != bf:
						_note_on(body, other, bf, of, cj)
					if oa < 0:
						oa = other.touch_asked
						if oa < 0 and of != null:
							oa = 1 if _asked(other) else 0
					if oa == 1 and of != null and bf != null and of != bf:
						_note_on(other, body, of, bf, cj)
			if not kept:
				continue
			pending.append([body, other, state.get_contact_local_shape(i), state.get_contact_collider_shape(i), state.get_contact_local_position(i), cj])
		else:
			if op and holder != null and of == holder:
				continue   # a weapon on the man holding it
			if ow:
				var oobj: Object = other
				if bid > oobj.get_instance_id():
					continue
			pending.append([body, other, state.get_contact_local_shape(i), state.get_contact_collider_shape(i), state.get_contact_local_position(i), state.get_contact_impulse(i).length()])

## A weapon lying loose (dropped, thrown, left by the dead) that has lain still a spell is put to sleep, and again each step it is
## still, as a corpse at rest is (Match._at_rest): one never let sleep kept every body it touched awake, the heap of the dead it lay
## on with them. The physics wakes it the moment anything touches or pushes it; pushed harder than a nudge it moves, and has to lie
## still a spell again; picking it up (Fighter.pick_up) makes it awake and sleepless. Not one on a chain, a trap, one burning,
## impaled or in flight.
const WEAPON_REST_AFTER := 1.5   # s
func _rest_weapons(dt: float) -> void:
	for w in loose_weapons:
		if not is_instance_valid(w) or w.sleeping:
			continue
		if w.holder != null or w.freeze or w.is_hazard or w.chain_head != null or not w.chain_links.is_empty() \
				or w.stuck != null or w.lodge_pending != null or w.thrown_t > 0.0 or not w._flames.is_empty():
			continue
		if w.linear_velocity.length_squared() < 0.04 and w.angular_velocity.length_squared() < 0.09:
			w.rest_t += dt
			if w.rest_t > WEAPON_REST_AFTER:
				w.can_sleep = true
				w.sleeping = true
		else:
			w.rest_t = 0.0

func _physics_process(dt: float) -> void:
	if canonical:
		_settle()
	time += dt
	var hits := process_contacts(dt)
	for h in hits:
		if h.kind == "hit":
			hit.emit(h)
		else:
			chip.emit(h)
	_rest_weapons(dt)
	record_velocities()

func record_velocities() -> void:
	vel.clear()
	# (Every body's two velocities in one call of the C++ core, the bodies in the order the lines below take them: the same entries.)
	var nc := Greedy.core()
	if nc != null and Greedy.vel_all_ok:
		# (The list of bodies made and recorded in the core: the same bodies, each fighter's parts, the weapons in his hands and their chain heads, then the loose ones.)
		for w in loose_weapons:
			if not is_instance_valid(w):
				loose_weapons = loose_weapons.filter(func(x): return is_instance_valid(x))
				break
		nc.record_vel_all(fighters, loose_weapons, vel)
		return
	if nc != null and Greedy.bulk_ok:
		var bodies := []
		for f in fighters:
			if not is_instance_valid(f):
				continue
			bodies.append_array(f.parts)
			for w in f.weapons.values():
				if w:
					bodies.append(w)
					if w.chain_head:
						bodies.append(w.chain_head)
		for w in loose_weapons:
			if not is_instance_valid(w):
				loose_weapons = loose_weapons.filter(func(x): return is_instance_valid(x))
				break
		for w in loose_weapons:
			bodies.append(w)
			if w.chain_head:
				bodies.append(w.chain_head)
		nc.record_vel(bodies, vel)
		return
	for f in fighters:
		if not is_instance_valid(f):
			continue
		for p in f.parts:
			vel[p.get_instance_id()] = [p.linear_velocity, p.angular_velocity]
		for w in f.weapons.values():
			if w:
				_record(w)
	for w in loose_weapons:
		if not is_instance_valid(w):
			loose_weapons = loose_weapons.filter(func(x): return is_instance_valid(x))
			break
	for w in loose_weapons:
		_record(w)

func _record(w: Weapon) -> void:
	vel[w.get_instance_id()] = [w.linear_velocity, w.angular_velocity]
	if w.chain_head:
		vel[w.chain_head.get_instance_id()] = [w.chain_head.linear_velocity, w.chain_head.angular_velocity]

func _vel_at(body: RigidBody3D, p: Vector3) -> Vector3:
	if body is Weapon and body.is_hazard:
		return body.hazard_vel + body.hazard_spin.cross(p - body.global_position)
	var v = vel.get(body.get_instance_id())
	var com := body.global_transform * body.center_of_mass
	if v == null:
		return body.linear_velocity + body.angular_velocity.cross(p - com)
	return v[0] + v[1].cross(p - com)

func _lin(body: RigidBody3D) -> Vector3:
	var v = vel.get(body.get_instance_id())
	return v[0] if v != null else body.linear_velocity

func _cooldown(key: String, J: float, t: float) -> bool:
	var c = cool.get(key)
	if c != null and time - c[0] < t and J < c[1] * 1.6:
		return false
	cool[key] = [time, J]
	return true

## The contacts of the last step put in an order of their own (the parts' and weapons' ages, then
## where and how hard), not the order the physics reported them in. That order is not always the
## same from one run of the same fight to the next (the physics engine's threads report as they
## finish), and the blows were dealt, the impulses summed and the dice rolled in it: a run drawn
## with the film camera's depth of field went another way than the same run undrawn.
static func _in_order(rows: Array, key: Callable) -> Array:
	if rows.size() < 2:
		return rows
	var keyed := []
	for i in rows.size():
		keyed.append(key.call(rows[i]) + [i])
	keyed.sort()
	var out := []
	for k in keyed:
		out.append(rows[int(k[-1])])
	return out

static func _id(o) -> int:
	return o.get_instance_id() if is_instance_valid(o) else 0

## The touches the last step reported, noted (in order) at the stamp of the step that made them.
func _settle() -> void:
	if touch_q.is_empty():
		return
	for t in _in_order(touch_q, func(t): return [_id(t[0]), _id(t[1]), t[2]]):
		if is_instance_valid(t[0]) and is_instance_valid(t[1]):
			_note_touch(t[0], t[1], t[2])
			_note_touch(t[1], t[0], t[2])
	touch_q.clear()

## Whether `part` is of an arm that holds a man (`held`: Fighter.holding, the side of its hand and, with the second hand on him, that one's).
## A beast's hold is the whole beast's: nothing of it strikes the man it has.
func _holds_with(af, part, held: Dictionary) -> bool:
	if af is Beast or not (af.get("arm") is Dictionary):
		return true
	for h in [held, held.get("extra")]:
		if h is Dictionary and (af.arm as Dictionary).has(h.get("side", "")):
			var a: Dictionary = af.arm[h.side]
			if part == a.fore or part == a.upper:
				return true
	return false

func process_contacts(_dt: float) -> Array:
	var groups := {}
	if canonical:
		pending = _in_order(pending, func(c): return [_id(c[0]), _id(c[1]), c[2], c[3], c[4].x, c[4].y, c[4].z, c[5]])
	for c in pending:
		var a = c[0]
		var b = c[1]
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		var cj: float = c[5]
		if a is Weapon and b is Weapon:
			if cj <= 1.2:
				continue
			var k := "clang:%d:%d" % [a.get_instance_id(), b.get_instance_id()]
			var g = groups.get(k)
			if g == null or cj > g.J:
				groups[k] = {"clang": true, "a": a, "b": b, "sa": c[2], "sb": c[3], "p": c[4], "J": cj}
			continue
		var att = null
		var vic = null
		var att_shape := -1
		if a is Weapon and b is VoxelPart:
			att = a; vic = b; att_shape = c[2]
		elif a is VoxelPart and b is VoxelPart and (a.severed or b.severed) and (_is_club(a) or _is_club(b)):   # (a club is cut off: two reads before the two calls)
			# A severed limb swung or thrown like a club.
			if _is_club(a) and not _is_club(b):
				att = a; vic = b
			elif _is_club(b) and not _is_club(a):
				att = b; vic = a
			else:
				continue
			if vic.fighter == att.wielder or vic.fighter == att.thrown_by:
				continue
		elif a is VoxelPart and b is VoxelPart:
			# (Each man read once of the many times he was: the two parts' men, then the attacker's and the victim's.)
			var a_man = a.fighter
			var b_man = b.fighter
			if a_man == b_man:
				continue
			var af = a_man
			var vf = b_man
			var sa := _lin(a).length()
			var sb := _lin(b).length()
			if sa >= sb:
				att = a; vic = b
			else:
				att = b; vic = a
				af = b_man; vf = a_man
			# A tusk the head drives in a strike is the blow, whatever moves the faster (a man
			# flung back off it moved faster than it, and the gore was read as him bumping into it).
			if vf is Beast and _tusk(vic) and vf.strikes_with(vic):
				var was = att
				att = vic
				vic = was
				var was_f = af
				af = vf
				vf = was_f
			var bite: bool = att.def.get("bite", false)
			if not (STRIKING.has(att.part_name) or bite or att.def.get("point", false) or (af is Beast and _tusk(att))):
				continue
			# Jaws cut off or hacked away bite nothing (a crocodile's closed on whatever touched
			# them, its jaw gone or not).
			if bite and not att.can_bite():
				continue
			if af.state != "stand" or not af.alive or att.severed:
				continue
			# The man a giant holds is not struck by the arm that holds him: what that arm does to him is the hold, the
			# slam and the throw (Social). (Brought into the fist, the man hung in the swinging arm was
			# beaten by it, forearm and trunk, before he was ever thrown.) The other arm, a foot and a head are his to
			# strike with (user: holding an enemy with one hand, the other hand has to be able to punch him; every
			# strike of the whole man was let go by here, whichever of his parts it was).
			var held = af.holding
			if held != null and held.get("target") != null and held.target.f == vf and _holds_with(af, att, held):
				continue
			# (Nor the man he has just let go of, while the arm is still following through: he leaves the
			# hand with the speed it gave him, and the landing is what hurts him.)
			if vf.thrown_by == af and vf.thrown_t > Social.THROW_CLEAR:
				continue
			# A beast's jaws, claws and horns bite only in a strike (the snap of the jaws, the
			# swipe, the toss: Beast.strikes, telegraphed by the wind-up before it): a head that
			# merely bumps into a man as it mauls or turns is no bite. (Every touch of the jaws
			# at a walk's speed was one, a bite every half second whatever the man did: a bout
			# with a lion was over in ten seconds and nothing he did could change it.)
			# (A crocodile's too. Its jaws closed on whatever touched them, and grown to stand as
			# high as a man's hands they touched his arms all the time: near forty bites in half a
			# minute, both arms gone before he had kicked it five times, user.)
			if af is Beast and not af.strikes_with(att):
				continue
			if af.kind != "beast" and not bite:
				var n: String = att.part_name
				if n.begins_with("shin") and not af.kick_strike():
					continue
				# (How fast the part goes against his trunk: asked of a fist and a head only, not of a kick.)
				if n.begins_with("forearm"):
					# A fist strikes while it is thrown or swung (Fighter.fist_strike), not whenever it
					# moves: drawn in, on its way home, or flung aside by a blow it is a touch.
					var fs: int = af.fist_strike(n.right(1))
					if fs == 0 or (_lin(att) - _lin(af.torso)).length() < (1.5 if fs == 2 else 2.5):
						continue
				# (Nor is a head rocked by the blow it has just taken a butt at the man who dealt it.)
				if n == "head" and ((_lin(att) - _lin(af.torso)).length() < 3.0 or af.daze_t > 0.0):
					continue
		else:
			continue
		# A shell laid over skin that no collider of his reaches (FineBody shells) is a blow on the part whose
		# flesh that skin lies on, which is where it is cut.
		if not vic.skin_shapes.is_empty():
			vic = vic.host_part(int(c[3]) if vic == b else int(c[2]))   # (a part with no shells laid over it is its own host)
		if vic.severed and not vic.fighter.alive and att is VoxelPart:
			continue
		# (The pair as the two ids: it was a string spelt out of them for every contact, eighty a step in a melee. The groups keep the order they were first met in.)
		var att_o: Object = att   # (asked as the objects they are: their ids at a sixth of the cost)
		var vic_o: Object = vic
		var key := [att_o.get_instance_id(), vic_o.get_instance_id()]
		var rank := 0
		var typ := "blunt"
		var mat := ""
		var box := {}
		if att is Weapon:
			box = att.box_for_shape(att_shape)
			typ = box.get("type", "blunt")
			mat = box.get("mat", "wood")
			rank = TYPE_RANK.get(typ, 0)
		var g2 = groups.get(key)
		if g2 == null:
			groups[key] = {"att": att, "vic": vic, "J": cj, "rank": rank, "type": typ, "mat": mat, "box": box, "p": c[4]}
		else:
			g2.J += cj
			if rank > g2.rank:
				g2.rank = rank; g2.type = typ; g2.mat = mat; g2.box = box; g2.p = c[4]
	pending.clear()
	var out := []
	for g in groups.values():
		if g.get("clang", false):
			_clang(g, out)
			continue
		var h := _blow(g)
		if not h.is_empty():
			out.append(h)
	return out

func _clang(g: Dictionary, out: Array) -> void:
	var a: Weapon = g.a
	var b: Weapon = g.b
	var ba := a.box_for_shape(g.sa)
	var bb := b.box_for_shape(g.sb)
	var ha: float = Data.material(ba.get("mat", "wood")).get("hardness", 0.5)
	var hb: float = Data.material(bb.get("mat", "wood")).get("hardness", 0.5)
	# (How fast the two came together there, as the step before the touch had them: what the sparks are judged by.)
	clang.emit({"p": g.p, "J": g.J, "metal": ha + hb, "v": (_vel_at(a, g.p) - _vel_at(b, g.p)).length()})
	if not _cooldown("clang:%d" % a.get_instance_id(), g.J, 0.12):
		return
	for pair in [[a, ba, ha, hb], [b, bb, hb, ha]]:
		var w: Weapon = pair[0]
		if pair[1].is_empty():
			continue
		var idx := w.voxel_near(pair[1], g.p)
		# Steel on steel takes the edge off both blades, the harder the other the more.
		w.wear_edge(minf(0.05, g.J * pair[3] * 0.0007))
		var k := w.knock(idx, Weapon.chip_score(g.J * chip_mult, pair[2], pair[3]))
		if not k.is_empty():
			out.append({"kind": "chip", "weapon": w, "indices": k.indices, "voxels": k.voxels, "p": g.p, "broke": k.broke})

## The speed of a point driven home (m/s, along its blade) that puts all of a thrust behind it.
const THRUST_FULL_V := 3.0
## What a man puts behind a thrust, as a share of the full lunge (user: it went through a man at
## the campaign's start, and a knife to the belly killed him at once): the man's own strength (the
## training's Vis: the stronger, the harder) and the weight of the weapon (a dagger's point has
## little behind it, a spear's more, a gladius's the most; none beyond that). THRUST_BASE is what a
## man untaught drives with a gladius.
const THRUST_BASE := 0.9
const THRUST_MASS_REF := 1.7     # kg: a gladius
const THRUST_MASS_EXP := 0.35
static func thrust_power(mass: float, strength: float) -> float:
	var weight := clampf(pow(maxf(0.05, mass) / THRUST_MASS_REF, THRUST_MASS_EXP), 0.5, 1.1)
	return THRUST_BASE * weight * clampf(strength, 0.5, 2.0)
## How much of the hardest a punch can land (its cap) makes it a punch that has landed, and ends it.
const JAB_SOLID := 0.6

## An elephant's, a mammoth's or a boar's tusk, any length of it: it lands a blow when the head that
## drives it strikes (Beast.strikes_with), a gore or a slash, as a real one's does (user).
static func _tusk(p) -> bool:
	return p is VoxelPart and p.fighter is Beast and Beast.TUSKERS.has(p.fighter.species) and String(p.part_name).begins_with("tusk")

func _blow(g: Dictionary) -> Dictionary:
	var vic: VoxelPart = g.vic
	var vic_char = vic.fighter
	if vic_char != null and bool(vic_char.get("untouchable")):
		return {}   # (a man at a stall of the yard: the blade meets him as it would a wall, and no more)
	var p: Vector3 = g.p
	var att = g.att
	var is_weapon: bool = att is Weapon
	var rel := _vel_at(att, p) - _vel_at(vic, p)
	var speed := rel.length()
	var dir := rel.normalized()
	if is_weapon and att.holder == null and not att.thrown_t > 0.0 and not att.is_hazard:
		return {}
	var club: bool = not is_weapon and _is_club(att)
	var kick: bool = not is_weapon and not club and att.part_name.begins_with("shin") and att.fighter.kick_strike()
	# A push kick (the key held for a long press, Fighter.kick_push: 0 a plain kick, 1 a push kick) lands harder and shoves farther.
	var kpush: float = float(att.fighter.kick_push) if kick else 0.0
	# A giant's foot is not slowed by the small man it comes down on: the blow's speed is the foot's own
	# (read after the step, with the man already carried along under it, there was hardly a speed
	# between the two, and a stamp that threw a man to the sand hurt him not at all).
	if kick and float(att.fighter.S) > 1.8 * float(vic_char.get("S") if vic_char.get("S") != null else 1.0):
		rel = _vel_at(att, p)
		speed = rel.length()
		dir = rel.normalized()
	var tusk: bool = not is_weapon and not club and _tusk(att)
	var bite: bool = not is_weapon and not club and (att.def.get("bite", false) or att.def.get("point", false) or tusk)
	var punch: bool = not is_weapon and not club and not bite and not kick
	if speed < (2.2 if is_weapon else (1.5 if kick else 2.0)):
		return {}
	# A beast's foot or knuckle walking into a man is a shove, not a blow: its blows are its
	# strikes (a bite, a claw, a fist swung), which mark the part for the length of the swing.
	if punch and att.fighter is Beast:
		return {}
	# A fist lands as hard as it is swung: the ape's weight leaning on him is no punch.
	var fist: bool = bite and att.def.get("fist", false)
	if fist and speed < 3.0:
		return {}
	var jabbing: bool = punch and att.fighter.fist_strike(att.part_name.right(1)) == 2
	var m_eff: float
	if is_weapon or club:
		# The bigger the weapon, the harder it lands: its weight is most of the blow (a stick or
		# a dagger a little over half a gladius's, a hammer twice), the arm's share small.
		m_eff = 0.3 + 1.15 * pow(maxf(0.05, att.mass), 0.6)
	else:
		m_eff = 5.0 if bite else (3.6 if kick else (4.0 if jabbing else 3.0))
		# A big man's fist or foot has his weight behind it (a giant's fist landed no harder than
		# a man's at the same speed).
		if punch or kick:
			m_eff *= clampf(float(att.fighter.S), 1.0, 2.5)
		if kpush > 0.0:
			m_eff *= 1.0 + PUSH_BLOW * kpush
	var cap: float
	if is_weapon:
		cap = 70.0
	elif club:
		cap = 40.0
	elif bite:
		cap = float(att.fighter.get("bite_power")) if att.fighter.get("bite_power") != null else 45.0
		if att.def.get("claw", false):
			cap *= 1.4   # a swipe has the whole foreleg and shoulder behind it
		if att.def.get("fist", false):
			cap *= float(att.get_meta("power", 1.0))   # a jab, a hook or a slam: each as hard as its swing
	else:
		# (A kick shoves more than it harms: three of them felled a man in a row.)
		# A fist that lands is felt (user: every punch, given or taken, must really be felt): a
		# jab up to 30, a swung fist 24, a giant's fist with a giant's weight behind it.
		cap = (20.0 + PUSH_CAP * kpush) if kick else (30.0 if jabbing else 24.0)
		if punch:
			cap *= clampf(float(att.fighter.S), 1.0, 2.5)
		# A colossus's stamp or punt comes down with the whole weight of him (his foot is no man's kick that shoves).
		if kick and bool(att.fighter.mods.get("colossus", false)) and (att.fighter.stomp_at != null or att.fighter.punt_at != null):
			cap *= clampf(float(att.fighter.S), 1.0, 2.5)
	if tusk:
		# A tusk is no bite (an elephant's bite is nil, and every gore landed at nothing): its blow
		# is the weight of the head behind it, driven or swung into him (user: the blow is
		# physical): an elephant's or a mammoth's a tonne, a boar's as heavy as its bite.
		var huge: bool = att.fighter.species == "elephant" or att.fighter.species == "mammoth"
		m_eff = TUSK_M if huge else 5.0
		cap = TUSK_CAP if huge else maxf(20.0, float(att.fighter.get("bite_power")))
	var J := minf(cap, m_eff * speed) if fist else minf(cap, maxf(g.J, m_eff * speed))
	if kpush > 0.0:
		J = maxf(J, minf(cap, lerpf(20.0, PUSH_JMIN, kpush)))
	if bite and att.fighter is Beast:
		# A beast's blow lands as hard as it is struck, as a weapon's does: what the contact reads
		# off a great weight leaning into a man (a paw resting on his arm, jaws closing slowly) is
		# not a blow, a touch at most (user: every touch of a monster wrecked his arm, even one with
		# nothing behind it). (Still a touch: one dropped as no blow at all, a beast at a man's side
		# struck nothing for seconds on end.)
		J = minf(J, maxf(4.0, m_eff * speed * 1.4))
	var heavy := 0.0
	var tpow := 1.0   # (what a man and his weapon put behind a thrust: THRUST_BASE and what comes of strength and weight)
	if is_weapon and att.is_hazard:
		J = minf(40.0, maxf(J, 6.0 * speed))
	if is_weapon and att.holder:
		var hv: Vector3 = _lin(att.holder.torso)
		var sv := _vel_at(att, p) - hv
		var swing := sv.length()
		var vt: Vector3 = _lin(vic_char.torso) if vic_char.get("torso") else hv
		var closing := rel.normalized()
		var vic_into := maxf(0.0, -(_vel_at(vic, p) - vt).dot(closing))
		var w_into := maxf(0.0, sv.dot(closing))
		if vic_into > w_into:
			J *= maxf(0.25, w_into / vic_into)
		# A man down swings nothing, but one fighting on from the ground with his legs gone swings
		# with what his arm and his back have in them (Fighter.fights_down).
		if att.holder.state != "stand":
			swing = swing * 0.75 if att.holder.has_method("fights_down") and att.holder.fights_down() else 0.0
		if swing < 1.5:
			J = minf(J, m_eff * speed * 0.5)
		J = minf(J, m_eff * speed * 1.4)
		J *= 0.15 + 0.85 * minf(1.0, swing / 3.5)
		J *= 0.75 + 0.25 * minf(2.4, swing / 4.0)
		heavy = clampf((swing - 4.0) / 6.0, 0.0, 1.0)
		# A thrust is the whole body behind the point, not a hand's speed: driven home along the
		# blade it lands far harder than its speed says (the web game's lunge).
		var t_side: String = "R" if att.holder.weapons.R == att else "L"
		var th: float = float(att.holder.thrust_amt.get(t_side, 0.0)) if "thrust_amt" in att.holder else 0.0
		if th > 0.3 and (g.type == "point" or g.type == "edge"):
			var bax: Vector3 = PD.quat_of(att) * Vector3.UP
			if bax.dot(closing) < 0.0:
				bax = -bax
			var along := bax.dot(closing)
			# Driven home along the blade: a point, or an edge's tip coming in point first. The
			# wound runs along the blade too, whichever way the bodies happened to be moving
			# as it went in (measured off that, a stab read as a glancing poke).
			if along > (0.4 if g.type == "point" else 0.75):
				dir = bax
				along = 1.0
				# As hard as the point is driven: its own speed along the blade into him, the arm's
				# drive and the body's lunge in it (user: a blow's harm is its momentum). A point
				# only held out, or pushed in slowly, is no stab (it landed at half a full stab's
				# weight, still or not, and took a man's arm out of his own stroke).
				var drive := minf(1.0, maxf(0.0, _vel_at(att, p).dot(bax)) / THRUST_FULL_V)
				# (As much of it as this man, with this weapon, can put behind the point.)
				var push := thrust_power(att.mass, float(att.holder.mods.get("strength", 1.0)) if "mods" in att.holder else 1.0)
				tpow = push
				drive *= push
				J = maxf(J, minf(75.0, (18.0 + 16.0 * th) * drive)) * (1.0 + 0.8 * th * drive)
				heavy = maxf(heavy, 0.45 * th * drive)
				if g.type == "edge":
					g = g.duplicate()
					g.type = "point"
	elif is_weapon and att.thrown_t > 0.0 and not att.is_hazard:
		# Thrown: the blow is its momentum, in proportion to how hard it was thrown (the speed
		# it lands at) and to how heavy it is; a dagger stings, a hammer flattens.
		J = minf(90.0, (0.5 + att.mass) * speed * 0.95)
		if att.is_shield:
			J *= 0.5   # a flat board spinning in: it knocks a man about more than it breaks him
		heavy = clampf((att.mass * speed - 20.0) / 40.0, 0.0, 1.0)
	if is_weapon:
		# The same rules for every weapon, whoever made it (user: any weapon a man can build, and
		# the cleverest wins): nothing is scaled for being a named preset (each carried a hidden
		# multiplier of its own, and a weapon reshaped at the forge kept it).
		# Size counts on top: a small weapon lands lighter than a sword, a great one heavier,
		# whatever speed it comes in at. A crushing blow is all weight; an edge puts its force on
		# a line, and there weight matters less: half the say a blunt blow gives it. A point puts
		# it on a spot, driven by the arm and the body behind it: a dagger's goes in as a spear's.
		var m_rel := maxf(0.05, att.mass) / 1.7
		if g.type == "edge":
			J *= clampf(pow(m_rel, 0.15), 0.7, 1.2)
		elif g.type != "point":
			J *= clampf(pow(m_rel, 0.3), 0.55, 1.35)
	if J < (4.0 if is_weapon else 3.0):
		return {}
	var key := "%d:%d" % [att.get_instance_id(), vic.get_instance_id()]
	if not _cooldown(key, J, 0.14):
		return {}
	var blow_key := "blow:%d:%d" % [att.get_instance_id(), vic_char.get_instance_id()]
	var before = cool.get(blow_key)
	if not bite and not _cooldown(blow_key, J, 0.32):
		return {}
	# One strike of a fist or a foot lands once on a man. A harder contact of the same strike (the
	# fist through his guard and on to his head, a touch that grows into the blow as the arm
	# drives on) lands with what the first left of it, not whole on top of it: one punch was two
	# and three blows, 8 and 14 on the forearm and 30 on the head.
	var j_whole := J
	if (punch or kick) and before != null and time - float(before[0]) < 0.32:
		J -= float(before[1])
	if bite and not _cooldown("bite:%d" % att.get_instance_id(), J, 0.45):
		return {}
	var typ := "blunt"
	var hardness := 0.3
	var sharpness := 0.0
	var axis := dir
	var edge := Vector3.ZERO
	var blade := Vector3.ZERO   # (the blade a cut is made with, where it touched: Weapon.blade_at)
	var attacker = null
	var thrown := false
	if is_weapon:
		attacker = att.holder if att.holder else att.thrower
		thrown = att.holder == null and att.thrown_t > 0.0
		typ = "blunt" if g.type == "grip" else g.type
		hardness = Data.material(g.mat).get("hardness", 0.5)
		# (A soft weapon hits as soft as it is, not as hard as the bronze band that touched him.)
		hardness = minf(hardness, 2.0 * att.mean_hardness)
		sharpness = float(att.design.get("sharpness", 0.0)) * att.keenness()
		var q := PD.quat_of(att)
		axis = q * Vector3.UP
		edge = q * Vector3.RIGHT
		if typ == "point" and dir.dot(axis) < 0.0:
			axis = -axis
		if typ == "edge" and not g.box.is_empty():
			blade = att.blade_at(att.voxel_near(g.box, p), p)
	elif club:
		hardness = 0.4
		attacker = att.wielder if att.wielder else att.thrown_by
		thrown = att.wielder == null
	elif bite and att.def.get("fist", false):
		# A gorilla's fist: a club of bone and muscle, blunt and heavy.
		typ = "blunt"
		hardness = 0.5
		heavy = maxf(heavy, 0.5)
		attacker = att.fighter
	elif tusk and not att.def.get("point", false):
		# The length of a tusk driven or swung into him: a club of ivory, as heavy as the head
		# behind it (its tip goes in as a point, below).
		typ = "blunt"
		hardness = 0.8
		heavy = maxf(heavy, 0.5)
		attacker = att.fighter
	elif bite and att.def.get("claw", false):
		# A paw's claws rake like knives: a cut along the swing, as deep as the blow drives it.
		typ = "edge"
		hardness = 0.9
		sharpness = 0.95
		edge = dir
		axis = PD.quat_of(att) * Vector3(0, -1, 0)
		attacker = att.fighter
	elif bite:
		# Teeth, not a blade: they go in, they do not slice (at a blade's keenness a beast's
		# bite took a quarter of a man each time, and a bout with a lion was over in ten seconds).
		typ = "point"
		hardness = 0.8
		sharpness = 0.65
		attacker = att.fighter
	else:
		attacker = att.fighter
	if attacker == vic_char:
		return {}
	var was_alive: bool = vic_char.alive
	# A bite takes a mouthful: the teeth close on a lump the size of the jaws, and tear it out.
	var crush := minf(0.11, (0.035 + J * 0.0012) * sqrt(float(att.fighter.S))) if bite and not tusk and J > 6.0 and not att.def.get("claw", false) and not att.def.get("fist", false) else 0.0
	var thrust_k := 0.0
	if is_weapon and att.holder and "thrust_amt" in att.holder:
		thrust_k = clampf(float(att.holder.thrust_amt.get("R" if att.holder.weapons.R == att else "L", 0.0)), 0.0, 1.0)
	# The studs on a mace's head crush with it, unless it is driven in point first.
	if is_weapon and typ == "point" and thrust_k < 0.5 and att.crusher():
		typ = "blunt"
		sharpness = 0.0
	# A giant's blow (the Cyclops, the Minotaur, a troll) is pulled a little: it still lands
	# heaviest of all, but not every one of them at the most a head can take (the cap on a
	# blow comes down with it: Fighter.apply_hit "pull").
	var pull := 1.0
	if bite and att.fighter is Beast:
		pull = float(Beast.BITE_PULL.get(att.fighter.species, 1.0))
	# The trainer's blow: a man taught to put his weight behind it hits harder; and strength
	# (the arm's drive) puts half of itself behind every blow too.
	if attacker and "mods" in attacker and not bite:
		J *= float(attacker.mods.get("blow", 1.0)) * (1.0 + 0.5 * (float(attacker.mods.get("strength", 1.0)) - 1.0))
	# A foe of a party's bout lands a little harder for each friend (Data.duel), a bite and a kick as a blade (and the cap on what a blow may take with it: "might").
	var foe_k := clampf(float(attacker.foe_dmg), 1.0, 3.0) if attacker != null and "foe_dmg" in attacker else 1.0
	J *= foe_k
	# Both arms behind the haft: a fifth more behind the blow.
	if attacker and "two_handed" in attacker and attacker.two_handed and not bite and att is Weapon:
		J *= TWO_HAND_BLOW
	if attacker and not (attacker is Beast) and "S" in attacker and float(attacker.S) >= 1.8:
		J *= Fighter.GIANT_BLOW
		pull = Fighter.GIANT_BLOW
	var stag0: float = float(vic_char.get("stagger")) if kick and vic_char.get("stagger") != null else 0.0
	var conc0: float = float(vic_char.get("concussion")) if vic_char.get("concussion") != null else 0.0
	var cracked0: bool = bool(vic_char.get("skull_cracked"))
	# One thrust is one blow: a point that touches him and drives on in the same lunge (a spear's long
	# shaft, a touch that grows into the stab) lands with what the first contact left of it, not whole
	# on top of it (a spear's one thrust was two and three blows, 80 of a man's 100).
	var prior := 0.0
	var dealt_key := "dealt:%d:%d" % [att.get_instance_id(), vic.get_instance_id()]
	var dealt = cool.get(dealt_key)
	if is_weapon and typ == "point" and thrust_k > 0.3 and dealt != null and time - float(dealt[0]) < 0.32:
		prior = float(dealt[1])
	var res: Dictionary = vic_char.apply_hit(vic, {"impulse": J, "type": typ, "hardness": hardness, "sharpness": sharpness, "point": p, "dir": dir, "axis": axis, "edge": edge, "blade": blade, "heavy": heavy, "thrown": thrown, "serrated": is_weapon and att.design.get("serrated", false), "crush": crush, "pull": pull, "thrust": thrust_k if typ == "point" else 0.0, "tpower": tpow if typ == "point" else 1.0, "prior": prior, "might": (float(attacker.mods.get("blow", 1.0)) if attacker and "mods" in attacker and not bite else 1.0) * foe_k, "bump": punch and not jabbing, "wsz": att.wscale if is_weapon else minf(1.4, float(attacker.S)) if attacker and "S" in attacker else 1.0, "bite": bite and not tusk and not att.def.get("fist", false), "weapon": is_weapon, "weapon_h": maxf(hardness, att.mean_hardness) if is_weapon else 1.0, "mass": att.mass if is_weapon else 0.0, "unarmed": punch or kick, "speed": speed})
	if is_weapon and typ == "point" and thrust_k > 0.3:
		cool[dealt_key] = [float(dealt[0]) if prior > 0.0 else time, prior + float(res.get("dmg", 0.0))]
	# Skidding off a plate: the blade goes on along it, not into it (its push into the plate
	# is turned aside at the point it struck, so it twists off too).
	if is_weapon and res.has("glance_n"):
		var gn: Vector3 = res.glance_n
		var vn := (_vel_at(att, p) - _vel_at(vic, p)).dot(gn)
		if vn < 0.0:
			att.apply_impulse(gn * (-vn) * 1.1 * float(res.glance) * att.mass, p - att.global_position)
	if bite and not tusk and att.fighter.has_method("bit"):
		att.fighter.bit(att, vic, res, dir)
	if attacker:
		vic_char.last_attacker = attacker
	# A punch that has landed does not go on to the end of its reach: the fist starts home. (One
	# that landed solidly: a touch on the way, his forearm brushed, does not stop it.)
	if jabbing and j_whole >= JAB_SOLID * cap:
		att.fighter.jab_landed(att.part_name.right(1))
	# A thrown blade that lands edge-on, or a point that lands point first, and bites deep
	# enough stays in the wound (combat.js).
	if thrown and is_weapon and not vic.severed and J > 9.0:
		var keen: float = hardness * sharpness
		if keen > 0.4 and not res.has("glance") and not res.get("stopped", false) and (g.type == "point" or (g.type == "edge" and not res.get("slid", false))) and att.has_method("impale") and att.impale(vic_char, vic, p):
			res.impaled = true
	# A heavy blade driven home stays in the wound, in the hand that struck: an axe in a shoulder,
	# a cleaver in a thigh (not every time: the harder it lands and the more weight out at its
	# head, the likelier, more where it met bone). It has to be wrenched out of him, dragging him
	# with it, or let go of.
	if is_weapon and att.holder and not thrown and not vic.severed and res.get("severed", []).is_empty() and not res.has("glance") and not res.get("slid", false) and not res.get("blocked", false) and not res.get("stopped", false):
		var lk := lodge_chance(att, typ, J, thrust_k, res)
		if lk > 0.0 and randf() < lk and att.lodge_in(vic_char, vic, p, 0.6 + clampf((J - 20.0) / 50.0, 0.0, 0.6) + (0.35 if res.get("bone", false) else 0.0)):
			res.lodged = true
	# A giant's blow lands once; then its weapon goes on through the man (Weapon.pass_through).
	if is_weapon and att.holder and not thrown and J > 10.0 and not res.get("lodged", false) and vic_char is Fighter and not (vic_char is Beast) and "S" in att.holder and float(att.holder.S) > float(vic_char.S) * Fighter.GIANT_OVER:
		att.pass_through(vic_char, 0.3)
	if punch and not vic.severed:
		vic.bleed += J * (0.05 if vic == vic_char.head else 0.015)
		if vic == vic_char.head:
			vic_char.concussion = minf(1.0, vic_char.concussion + J * 0.012)
			# (One knock at a time, the fist's ringing and the blow's together: Fighter.CONC_PER_BLOW.)
			if not cracked0:
				vic_char.concussion = minf(vic_char.concussion, maxf(conc0, conc0 + Fighter.CONC_PER_BLOW))
		vic.apply_central_impulse(Vector3(dir.x, dir.y * 0.5, dir.z) * J * 0.7 * vic_char.MS)
		# The man takes it: rocked back half a step, reeling, his hands and feet slow for a moment
		# (a punch moved a man less than a nudge, user: knockback, stun, stagger, all of it). The
		# harder it lands and the bigger the fist against the man, the more.
		if vic_char is Fighter and not (vic_char is Beast) and vic_char.state == "stand":
			var ratio := clampf(float(att.fighter.S) / maxf(0.5, float(vic_char.S)), 0.5, 2.5)
			var k := clampf(J / 20.0, 0.3, 1.5) * ratio
			var flat := Vector3(dir.x, 0.0, dir.z)
			if flat.length() > 0.01:
				vic_char.torso.apply_central_impulse((flat.normalized() * 22.0 + Vector3.UP * 2.0) * minf(k, 2.0) * vic_char.MS)
			vic_char.stagger = minf(1.0, vic_char.stagger + 0.22 * k * (1.4 if vic == vic_char.head else 1.0))
			vic_char.daze(0.18 + 0.2 * minf(k, 1.5))
			vic_char.jolt_t = vic_char.time
	if kick and not vic.severed and vic_char.get("torso"):
		var m := 260.0 if att.fighter.mods.get("superKick", false) else minf(55.0 + PUSH_SHOVE * kpush, J * (3.0 + 2.5 * kpush))
		var sdir := Vector3(dir.x, 0.0, dir.z)
		if kpush > 0.0:
			# A push kick drives him straight back from the kicker, as the foot's own line is whatever way it happened to be going (up, as the knee came out) when it met him.
			var away: Vector3 = vic_char.torso.global_position - att.fighter.torso.global_position
			away.y = 0.0
			sdir = away.normalized() if away.length_squared() > 1e-4 else Vector3(sin(att.fighter.yaw), 0.0, cos(att.fighter.yaw))
		vic_char.torso.apply_central_impulse(Vector3(sdir.x * m, 10.0 + 10.0 * kpush, sdir.z * m))
		if kpush > 0.0 and vic_char is Fighter and not (vic_char is Beast):
			# And the whole of him goes back with it, his feet let off the sand to stumble (as a two-handed shove does it, Social.shove), the bigger and stronger the kicker against him, the farther.
			var kf: Fighter = att.fighter
			var ratio := minf(2.5, pow(kf.S, 2.5) * float(kf.mods.strength) / pow(vic_char.S, 2.5))
			var dv := PUSH_DV * kpush * ratio
			for vp in vic_char.parts:
				if not vp.severed:
					vp.apply_central_impulse(Vector3(sdir.x * dv, dv * 0.1, sdir.z * dv) * vp.mass)
			for side in vic_char.feet:
				if vic_char.feet[side]:
					vic_char.feet[side].swing = true
			vic_char.jolt_t = vic_char.time
		# It rocks him a little, the same however hard it lands: kicks one after another do not
		# pile up into a fall the way they did. (A push kick sends him reeling.)
		vic_char.stagger = minf(1.0, minf(vic_char.stagger, stag0 + 0.06) + 0.04 + 0.5 * kpush)
		if kpush > 0.0 and vic_char is Fighter and not (vic_char is Beast):
			vic_char.daze(0.2 + 0.4 * kpush)
		var lv: Vector3 = vic_char.torso.linear_velocity
		# A kick takes the legs from under a man only now and then: the harder it lands, the
		# more he is on the move, out of breath or reeling, the likelier; never a sure thing.
		var sweep: float = ((0.12 if Vector2(lv.x, lv.z).length() > 0.8 else 0.0) + (0.12 if vic_char.stamina < 30.0 else 0.0) + 0.15 * vic_char.stagger) * clampf(J / 22.0, 0.2, 1.0)
		if kpush > 0.0:
			# (A push kick throws the whole man, wherever it lands on him; the bigger he is against the kicker, the less.)
			sweep += PUSH_FELL * kpush * clampf(float(att.fighter.S) / maxf(0.5, float(vic_char.S)), 0.0, 1.0)
			att.fighter.kick_landed = true
		# One chance a kick (a foot that lands twice in the one kick is still one kick).
		var now := time
		var rolled := now - float(vic_char.get_meta("sweep_roll", -10.0)) < 0.4
		if not rolled:
			vic_char.set_meta("sweep_roll", now)
		if (vic.def.get("leg", false) or kpush > 0.0) and vic_char.state == "stand" and not rolled and randf() < sweep:
			vic_char.fall(1.2)
			res.tripped = true
	var chip := {}
	if is_weapon and not g.box.is_empty():
		# What the blade met: armour, bone, or only flesh (soft: it hardly tires the metal).
		var vh := 0.85 if res.get("armor", false) else (0.55 if res.get("bone", false) else 0.15)
		var idx: int = att.voxel_near(g.box, p)
		var mat_h: float = Data.material(g.mat).get("hardness", 0.5)
		# Every cut and stab blunts the edge a little (bone, armour, the sand of a fall).
		if typ != "blunt":
			att.wear_edge(minf(0.03, J * 0.00028 * (2.0 if res.get("armor", false) else 1.0) * (1.6 if res.get("bone", false) else 1.0)))
		var brittle: float = float(Data.material(g.mat).get("brittle", 0.0))
		# A blow tires the metal where it lands even when nothing gives (a brittle blade more).
		var k: Dictionary = att.knock(idx, Weapon.chip_score(J * maxf(0.25, brittle) * chip_mult, mat_h, vh))
		if not k.is_empty():
			chip = {"indices": k.indices, "voxels": k.voxels, "broke": k.broke}
	return {"kind": "hit", "att_part": att if not is_weapon else null, "p": p, "dir": dir, "J": J, "type": typ, "mat": g.mat, "punch": punch, "kick": kick, "push": kpush, "bite": bite and not tusk, "weapon": att if is_weapon else null, "char": vic_char, "part": vic, "attacker": attacker, "res": res, "killed": was_alive and not vic_char.alive, "chip": chip, "thrown": thrown}

## How likely a held weapon's blow is to stay in the wound: a weapon heavy at the head (an axe,
## a trident: the weight out at the blade drives it in and wedges it), or a long heavy blade
## into bone now and then, the harder the blow the likelier; a sword's or a dagger's cut slides
## out of the wound it made.
static func lodge_chance(w, typ: String, J: float, thrust_k: float, res: Dictionary) -> float:
	if float(w.design.get("sharpness", 0.0)) < 0.3 or w.design.get("chain") != null or w.is_shield or w.design.has("shoots"):
		return 0.0
	# Never a giant's: his blade in a man pinned the man where he stood, the giant's arm too strong
	# ever to strain on it and so ever to wrench it out (user). His blows throw men about instead.
	if w.holder and float(w.holder.S) >= 1.5:
		return 0.0
	var head: float = (w.center_of_mass - w.grip_main).length() / maxf(0.01, float(w.reach))
	var heft := maxf(clampf((head - 0.5) / 0.15, 0.0, 1.0), 0.3 * clampf((w.mass - 2.5) / 2.0, 0.0, 1.0) * (1.0 if res.get("bone", false) else 0.0))
	var k := 0.0
	if typ == "edge":
		k = clampf((J - 20.0) / 35.0, 0.0, 0.55) * heft
	elif typ == "point" and thrust_k > 0.5:
		k = clampf((J - 30.0) / 40.0, 0.0, 0.4) * heft
	if res.get("bone", false):
		k *= 1.6
	return minf(0.7 if LODGE_K <= 1.0 else 1.0, k * LODGE_K)

static func _is_club(p) -> bool:
	return p is VoxelPart and p.severed and (p.wielder != null or p.thrown_t > 0.0)

static func _preset_key(design: Dictionary) -> String:
	for k in Data.presets:
		if Data.presets[k].get("name") == design.get("name"):
			return k
	return ""
