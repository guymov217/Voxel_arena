class_name MovePredictor
extends RefCounted
## A guest's own man, a round trip ahead of what the host shows of him (DOM-free, like the rest of the game's logic).
##
## The host walks every man, the guest's too: the keys go to it, it works out where he gets to, and the snapshot comes back
## the same way. His man started to move on his own screen a round trip after he pressed the key, and stopped a round trip
## after he let go (115 ms with both windows on one machine, a good deal more with a friend across the sea). So the guest
## walks him as well, on a model of the host's own walking, and shows him where the model has him.
##
## What keeps the model honest: every input goes out with a number (`sent`), and every snapshot of his man comes back with the
## number the host had got to, how many of its steps it had walked by that input, and where his torso then was and how fast it
## went (`reconcile`). The model is put there, as the host says, and walks on through the keys pressed since (the log of what was
## sent), up to now. A host that agrees with the model changes nothing; one that does not (he walked into a wall, a blow threw
## him) takes him from where the model was to where the host says, over SMOOTH_T, not in a jump.
##
## The walk: his velocity closes on what the keys ask (the host's speed factor for him, the walk's 2.1 m/s or the run's 3.8, the
## way he goes: Fighter.control), at K a second. Measured on the host's own physics (tests/walkresp.gd): from rest the torso is at
## 63 % of its pace in 25-33 ms and the model's 40 a second is the same curve to within a few per cent.

const DT := 1.0 / 120.0        # a step of the model: a physics step of the host's
const K := 40.0                # how fast his velocity closes on the one the keys ask (a second)
const SMOOTH_T := 0.06         # s: what the host's word moves the picture by is taken in this time
const SEQ_N := 128             # the numbers an input goes by wrap here (7 bits of the packet: PlayerInput.pack)
const KEEP := 1.5              # s of what was sent that is kept
const MAX_STEPS := 240         # the most steps taken at once
const LEAD_MAX := 1.2          # m: farther than this from the host's picture of him, the model is not believed
const EFF_AFTER := 0.1         # s the keys have been held before the host's pace is taken for what they ask (a walk is at 98 % by then)

## Where the model has his torso (x, z), how fast it goes, the way the body faces. `pace`: the host's speed factor for him
## (0: he is not walking on his own legs: down, held, in the air: nothing is predicted).
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var yaw := 0.0
var pace := 0.0
var stamina_ok := true         # he has the breath to run (Fighter.control asks for more than 5)
var air := false               # he is in the air: nothing steers him, his velocity stays what it was
var live := false              # the host has said where he is: the model walks
var smooth := Vector2.ZERO     # what the picture is still to take up of the last correction
var seq := 0                   # the number of the last input sent
var time := 0.0                # the model's clock: the match's, to a step

var _eff := 1.0                # how much of the way the keys ask the host has been seen to let him go (a wall in front of him: 0)
var _eff_dir := Vector2.ZERO   # and along which way that was seen
var _t: Array = []             # when each input was sent
var _n: Array = []             # its number
var _u: Array = []             # what it asked: [mx, mz, the way the eyes face (NAN: not said), run]

## The body turns after the eyes (Match.ease_yaw: the same, a copy so this stays a module of its own; a test holds them to it).
static func ease_yaw(cur: float, to: float, dt: float) -> float:
	var d := wrapf(to - cur, -PI, PI)
	return cur + clampf(d * minf(1.0, dt * 16.0), -11.0 * dt, 11.0 * dt)

func reset() -> void:
	pos = Vector2.ZERO
	vel = Vector2.ZERO
	smooth = Vector2.ZERO
	pace = 0.0
	live = false
	_eff = 1.0
	_t.clear()
	_n.clear()
	_u.clear()

## An input goes to the host at `now`: noted, with the number it goes by (which goes in the packet).
func sent(now: float, inp: Dictionary) -> int:
	seq = (seq + 1) % SEQ_N
	var lk = inp.get("look")
	var yw := NAN
	if lk is Dictionary and (lk.get("yaw") is float or lk.get("yaw") is int):
		yw = snappedf(float(lk.yaw), 0.001)
	_t.append(now)
	_n.append(seq)
	_u.append([snappedf(clampf(float(inp.get("mx", 0.0)), -1.0, 1.0), 0.01), snappedf(clampf(float(inp.get("mz", 0.0)), -1.0, 1.0), 0.01), yw, 1.0 if inp.get("sprint", false) else 0.0])
	# (No more than SEQ_N - 8 of them, so a number is never in the log twice.)
	while _t.size() > 2 and (now - float(_t[1]) > KEEP or _t.size() > SEQ_N - 8):
		_t.pop_front()
		_n.pop_front()
		_u.pop_front()
	return seq

## The velocity the keys of one input ask for, the body facing `yw` (Fighter.control: the walk's 2.1 m/s or the run's 3.8, by his
## pace, slower backwards and sideways).
func _target(u: Array, yw: float) -> Vector2:
	var ml := Vector3(float(u[0]), 0.0, float(u[1]))
	if ml.length_squared() > 1.0:
		ml = ml.normalized()
	var run: bool = float(u[3]) > 0.5 and stamina_ok and ml.z > 0.3
	var dir_f := (1.0 + 0.35 * ml.z if ml.z < 0.0 else 1.0) * (1.0 - 0.15 * absf(ml.x))
	var w: Vector3 = Quaternion(Vector3.UP, yw) * ml * ((3.8 if run else 2.1) * pace * dir_f)
	return Vector2(w.x, w.z)

## One step of the model by one input.
func _step(u: Array) -> void:
	var ey: float = u[2]
	if not is_nan(ey):
		yaw = ease_yaw(yaw, ey, DT)
	var tv := _target(u, yaw)
	# Held back along the way the host was seen to hold him back (a wall, another man): the keys are asked for that much less.
	if _eff < 1.0:
		var tl := tv.length()
		if tl > 1e-4 and tv.dot(_eff_dir) > 0.9 * tl:
			tv *= _eff
	if not air:
		vel += (tv - vel) * (1.0 - exp(-K * DT))
	pos += vel * DT

## The model goes on to `now` with the last input sent (the steps of a physics tick, one at a time).
func advance(now: float) -> void:
	if not live:
		time = now
		return
	var n := clampi(int(floor((now - time) / DT + 1e-4)), 0, MAX_STEPS)
	var u: Array = _u[_u.size() - 1] if not _u.is_empty() else [0.0, 0.0, NAN, 0.0]
	for i in n:
		_step(u)
	time += n * DT
	if now - time > 0.25:
		time = now   # (a stall: the model does not owe the time lost)
	smooth *= exp(-n * DT / SMOOTH_T)

## The host's word of him, in the snapshot of `now`: it had got to input number `ack` and walked `ticks` of its steps by it, and
## his torso was at `p` (x, z), going at `v`, the body facing `yw`, his pace factor `pc`, in the air or not. He is put there, the keys
## sent since walked.
## Returns whether the word was taken (an input it names that the log no longer has, or never had, is not).
func reconcile(now: float, ack: int, ticks: int, p: Vector2, v: Vector2, yw: float, pc: float, in_air := false) -> bool:
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(v.x) and is_finite(v.y) and is_finite(yw) and is_finite(pc)):
		return false
	pace = clampf(pc, 0.0, 4.0)
	air = in_air
	var i := -1
	for k in range(_n.size() - 1, -1, -1):
		if int(_n[k]) == ack:
			i = k
			break
	if i < 0:
		if not live:
			# The first word, before any input of his is known to it: he stands where it says.
			pos = p
			vel = v
			yaw = yw
			time = now
			live = true
			return true
		return false
	var before := pos + smooth
	var t0 := float(_t[i]) + maxi(0, ticks) * DT
	pos = p
	vel = v
	yaw = yw
	# How far the host let him go the way the keys he has held a tenth of a second asked: a man who pushes on a wall is let go
	# nowhere, and the model must not walk him through it (the host's picture would be a wall, the guest's a man a hand's breadth
	# into it for as long as he pushed).
	_eff = 1.0
	var k := i
	var ui: Array = _u[i]
	while k > 0 and absf(float((_u[k - 1] as Array)[0]) - float(ui[0])) < 0.05 and absf(float((_u[k - 1] as Array)[1]) - float(ui[1])) < 0.05 and float((_u[k - 1] as Array)[3]) == float(ui[3]):
		k -= 1
	var held := float(_t[i]) - float(_t[k]) + maxi(0, ticks) * DT
	if held >= EFF_AFTER:
		var tg := _target(ui, yw)
		var tl := tg.length()
		if tl > 0.3:
			_eff_dir = tg / tl
			_eff = clampf(v.dot(_eff_dir) / tl, 0.0, 1.2)
	var steps := clampi(int(round((now - t0) / DT)), 0, MAX_STEPS)
	var j := i
	var tt := t0
	for s in steps:
		while j + 1 < _t.size() and float(_t[j + 1]) <= tt + 1e-9:
			j += 1
		_step(_u[j])
		tt += DT
	time = now
	live = true
	# The picture does not jump to where the host's word has him: it takes the difference up over SMOOTH_T (a jump too far is a
	# fresh start: a spawn, a throw across the arena).
	var gap := before - pos
	smooth = gap if gap.length() < 1.0 else Vector2.ZERO
	return true

## Where he is shown (x, z).
func shown() -> Vector2:
	return pos + smooth
