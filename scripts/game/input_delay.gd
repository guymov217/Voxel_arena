class_name InputDelay
extends RefCounted
## A wait put on one man's hands (DOM-free). In a fight of people against each other the host's own hands reach the physics at once and a
## guest's a trip of the line later, so the host's blade starts before a guest's by that trip (user: the host must have no advantage).
## Here every man's hands, the host's and each guest's, are held until the slowest friend's trip has been made: Match feeds each
## tick's input in and acts on what comes out, the input of `ticks` ticks ago. Presses (a jump, a kick, a grab) ride with their tick:
## none is lost when the wait is made shorter, none is repeated when it is made longer.

const KEEP := 40            # ticks of inputs kept (a third of a second at 120 a second)

var _ring: Array = []       # inputs of the ticks, oldest first
var _base := 0              # the number of the oldest tick in the ring
var _out := -1              # the number of the tick last handed out

func reset() -> void:
	_ring.clear()
	_base = 0
	_out = -1

## Nothing held back and nothing waiting: the caller may drop it.
func idle() -> bool:
	return _ring.size() <= 1

## This tick's input in; what to act on out: the input `ticks` ticks ago (the oldest there is, while there are not so many yet).
func step(inp: Dictionary, ticks: int) -> Dictionary:
	_ring.append(inp)
	var newest := _base + _ring.size() - 1
	while _ring.size() > KEEP:
		_ring.pop_front()
		_base += 1
	var want := maxi(_base, newest - clampi(ticks, 0, KEEP - 1))
	var out: Dictionary = _ring[want - _base]
	if want > _out:
		# The ticks passed over (the wait made shorter) leave their presses in the one acted on.
		var first := maxi(_out + 1, _base)
		if want - first > 0:
			out = out.duplicate()
			for n in range(first, want):
				_carry(out, _ring[n - _base])
	elif not out.is_empty():
		# The same tick again (the wait made longer): its presses were acted on the first time.
		out = _spent(out)
	_out = maxi(_out, want)
	if ticks <= 0:
		# No wait: nothing is kept.
		_ring = [_ring[_ring.size() - 1]]
		_base = newest
	return out

static func _carry(into: Dictionary, from: Dictionary) -> void:
	for k in PlayerInput.ONE_SHOT:
		if from.get(k, false):
			into[k] = true
	if int(from.get("useItem", -1)) >= 0 and int(into.get("useItem", -1)) < 0:
		into.useItem = from.useItem

static func _spent(inp: Dictionary) -> Dictionary:
	var out := inp.duplicate()
	for k in PlayerInput.ONE_SHOT:
		if out.has(k):
			out[k] = false
	if out.has("useItem"):
		out.useItem = -1
	return out

## What the wait is, for the host (index 1) and for each guest (by id): the slowest guest's trip one way (half his round trip, the
## round trip a guest measures and tells), and for each guest what is left of it after his own trip. `pings`: id -> round trip in ms
## (a guest not measured yet is not waited for); `margin`: ms more than the slowest (the line wobbles), `cap`: ms at most.
## Returns {id: seconds}, 1 being the host.
static func holds(pings: Dictionary, margin := 4.0, cap := 90.0) -> Dictionary:
	var worst := 0.0
	for id in pings:
		worst = maxf(worst, maxf(0.0, float(pings[id])) * 0.5)
	var d := minf(cap, worst + (margin if worst > 0.0 else 0.0))
	var out := {1: d / 1000.0}
	for id in pings:
		var trip := maxf(0.0, float(pings[id])) * 0.5
		out[int(id)] = maxf(0.0, d - trip) / 1000.0
	return out
