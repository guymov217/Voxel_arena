class_name Lead
extends RefCounted
## What a guest draws one fighter of the others moved on by (DOM-free). The host's snapshot of a man is a trip and a snapshot's wait old on
## a guest's screen, and a blow the guest makes lands a trip after he made it: a man walking at 2 m/s has gone 14 cm on from where the
## screen shows him by the time it lands, a beast charging at 6 m/s 40 (user: the host must have no advantage, in a fight with the
## enemies too). Here the pace of the torso is kept from the rows, and the fighter is drawn ahead of the host's picture of him by that
## pace over `ahead` seconds, along the sand, by a share of it (GAIN) and no more than MAX, eased in and out. A man who is down, rising
## or dead is not walked on: nothing is added then.

const GAIN := 0.9            # the share of the way to where the host will have him that he is drawn on
const MAX := 0.3             # m: the most that is added (a long way would show as a man in two places)
const SLEW := 2.5            # m/s: how fast what is added may change (a struck man's pace jumps; his picture must not)
const PACE_LO := 0.25        # m/s: below this he stands (rows of 2 mm steps and a frame's jitter are no walk)
const PACE_HI := 0.7         # m/s: from this the whole is added
const EMA := 0.3             # the share of each row's pace that is taken into the pace kept
const JUMP := 3.0            # m: a row this far from the last is a spawn or a throw across the sand, of which no pace is known
const LATE := 0.25           # s: a row this long after the last tells nothing of his pace
const SLOW := 0.08           # s: a row this long after the last (a stall, a packet lost) is no measure of his pace either: the next is measured from it
const SURE := 0.0167         # s: a pace measured over less than this is taken in by that much less (a sixtieth of a second)

var vel := Vector3.ZERO      # his pace along the sand (m/s)
var cur := Vector3.ZERO      # what is added now (m)
var _p := Vector3.ZERO       # where the last row had his torso (along the sand)
var _t := -1.0               # when

func reset() -> void:
	vel = Vector3.ZERO
	cur = Vector3.ZERO
	_p = Vector3.ZERO
	_t = -1.0

## A row of his: where his torso is in it, `now` (s), whether he is on his feet, how long his picture is behind where his blows will meet
## him (s). Returns what is to be added to every body of his.
func step(pos: Vector3, now: float, standing: bool, ahead: float) -> Vector3:
	var p := Vector3(pos.x, 0.0, pos.z)
	var dt := now - _t
	if _t < 0.0 or dt > LATE or p.distance_to(_p) > JUMP:
		vel = Vector3.ZERO
		_p = p
		_t = now
		dt = 0.0
	elif dt > SLOW:
		_p = p   # (the pace stays as it was; the next row is measured from this one)
		_t = now
		dt = 0.0
	elif dt >= 0.004:
		vel = vel.lerp((p - _p) / dt, EMA * minf(1.0, dt / SURE))
		_p = p
		_t = now
	else:
		# Rows that come together (a line that stalled and let its packets go at once): his place is the last's, and the time is the same
		# moment, so that the next row is measured from the last and not from the first of them, which would show him run a whole stall's way.
		_p = p
		dt = 0.0
	var want := Vector3.ZERO
	if standing:
		want = vel * (maxf(0.0, ahead) * GAIN * smoothstep(PACE_LO, PACE_HI, vel.length()))
		if want.length() > MAX:
			want = want.normalized() * MAX
	cur = cur.move_toward(want, SLEW * maxf(dt, 0.004))
	return cur
