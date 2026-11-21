extends Node
## A guest's own man walked ahead of the host's word (MovePredictor): the model is the host's walking, an input goes out with a
## number and comes back as the one the host had got to, and what he sees is the model's man, moved to where the host says.

var t

## One run of `secs` seconds of a guest and a host in the same room: the guest presses what `keys.call(time)` says (one input every
## 16.7 ms), the host gets each `d1` seconds late and walks a man by the latest it has (the host's man is a model like the guest's,
## told nothing of the guest, with `host_pace` for his pace and held at `wall` along z if it is a number), sends a snapshot of him
## every 16.7 ms that the guest gets `d2` seconds later. Returns what the guest saw of him and what he would have seen with no delay.
func _run(keys: Callable, secs: float, d1: float, d2: float, host_pace := 1.0, wall := INF) -> Dictionary:
	var g := MovePredictor.new()       # the guest's own
	var host := MovePredictor.new()    # the host's man
	var ideal := MovePredictor.new()   # the same walk with no delay at all
	host.pace = host_pace
	host.live = true
	ideal.pace = host_pace
	ideal.live = true
	g.pace = host_pace
	g.live = true
	var arrivals := []      # [time it reaches the host, the input, its number]
	var snaps := []         # [time it reaches the guest, the word]
	var cur: Array = [0.0, 0.0, 0.0, 0.0]
	var cur_seq := -1
	var cur_ticks := 0
	var shown := []
	var truth := []
	var hosts := []
	var n := int(secs * 120.0)
	for i in n:
		var now := float(i) * MovePredictor.DT
		# guest: a frame is two steps; at its start the keys are read and sent
		if i % 2 == 0:
			var k: Array = keys.call(now)
			var inp := {"mx": k[0], "mz": k[1], "look": {"yaw": 0.0, "pitch": 0.0}, "sprint": k.size() > 2 and k[2]}
			var sq := g.sent(now, inp)
			ideal.sent(now, inp)
			arrivals.append([now + d1, [snappedf(k[0], 0.01), snappedf(k[1], 0.01), 0.0, 1.0 if (k.size() > 2 and k[2]) else 0.0], sq])
		# snapshots that have come
		while not snaps.is_empty() and float(snaps[0][0]) <= now:
			var w: Array = snaps.pop_front()[1]
			g.reconcile(now, w[0], w[1], w[2], w[3], w[4], w[5])
		# the host: the inputs that have come, one step
		while not arrivals.is_empty() and float(arrivals[0][0]) <= now:
			var a: Array = arrivals.pop_front()
			cur = a[1]
			if int(a[2]) != cur_seq:
				cur_seq = int(a[2])
				cur_ticks = 0
		var before := host.pos
		host._step(cur)
		if host.pos.y > wall:
			host.pos.y = wall
			host.vel.y = 0.0
		cur_ticks += 1
		if i % 2 == 1:
			snaps.append([now + d2, [cur_seq, cur_ticks, host.pos, host.vel, host.yaw, host_pace]])
		# the guest and the ideal one step on
		g.advance(now + MovePredictor.DT)
		ideal.advance(now + MovePredictor.DT)
		shown.append(g.shown())
		truth.append(ideal.pos)
		hosts.append(before)
	return {"shown": shown, "truth": truth, "host": hosts}

func _worst(a: Array, b: Array, from: int, to: int) -> float:
	var w := 0.0
	for i in range(from, mini(to, a.size())):
		w = maxf(w, ((a[i] as Vector2) - (b[i] as Vector2)).length())
	return w

## The model's easing of the body is the host's (Match.ease_yaw), or the two would walk different ways round a turn.
func test_the_body_turns_the_hosts_way() -> void:
	var worst := 0.0
	for i in 200:
		var cur := randf_range(-8.0, 8.0)
		var to := randf_range(-8.0, 8.0)
		var dt := randf_range(0.002, 0.02)
		worst = maxf(worst, absf(MovePredictor.ease_yaw(cur, to, dt) - Match.ease_yaw(cur, to, dt)))
	t.check(worst < 1e-9, "the same turn as the host's (%.9f off at worst)" % worst)

## An input's number goes in the packet (7 bits above the flags) and comes back out whole, whatever else is set.
func test_an_inputs_number_goes_out_and_comes_back() -> void:
	var inp := {"mx": 1.0, "mz": -1.0, "sprint": true, "crouch": true, "jump": true, "kick": true, "grabHands": "both", "grip": true, "revive": true, "depthOn": true, "depth": 0.5, "aimAt": Vector3(1, 2, 3), "aimFrom": Vector3(0, 1, 0), "look": {"yaw": 1.5, "pitch": 0.2}}
	for sq in [0, 1, 5, 64, 127]:
		inp.seq = sq
		var back := PlayerInput.unpack(PlayerInput.pack(inp))
		t.eq(int(back.get("seq", -1)), sq, "number %d comes back" % sq)
		t.check(back.sprint and back.crouch and back.jump and back.kick and back.grip and back.revive and back.depthOn and back.aimAt is Vector3 and back.grabHands == "both", "and every flag with it (%d)" % sq)
	inp.erase("seq")
	t.eq(int(PlayerInput.unpack(PlayerInput.pack(inp)).get("seq", -1)), 0, "an input with none is number 0")
	var wire: Array = PlayerInput.pack({"seq": 127, "look": {"yaw": 0.0, "pitch": 0.0}})
	t.check(int(wire[11]) < 2147483647, "and the flag word stays a 32-bit number on the wire (%d)" % int(wire[11]))

## The numbers wrap at 128; the log never holds one twice, and a word naming a number it has no longer is not taken.
func test_the_numbers_wrap_and_the_log_has_each_once() -> void:
	var g := MovePredictor.new()
	var seen := {}
	var last := 0
	var ok := true
	for i in 400:
		var sq := g.sent(float(i) * 0.009, {"mz": 1.0})
		ok = ok and sq == (last + 1) % MovePredictor.SEQ_N
		last = sq
		seen = {}
		for k in g._n:
			ok = ok and not seen.has(int(k))
			seen[int(k)] = true
	t.check(ok, "numbers go up by one and wrap at %d, and none is in the log twice" % MovePredictor.SEQ_N)
	t.check(g._n.size() <= MovePredictor.SEQ_N - 8, "the log holds at most %d" % (MovePredictor.SEQ_N - 8))
	g.live = true
	g.pace = 1.0
	var p0 := g.pos
	var taken := g.reconcile(10.0, 999, 1, Vector2(5, 5), Vector2.ZERO, 0.0, 1.0)
	t.check(not taken and g.pos == p0, "a word that names an input it does not have is left alone")

## He presses forward and his man walks at once, with not a word from the host yet.
func test_a_press_is_walked_before_the_host_has_said_anything() -> void:
	var g := MovePredictor.new()
	g.reconcile(0.0, 0, 0, Vector2.ZERO, Vector2.ZERO, 0.0, 1.0)   # (the host's first word: he stands here)
	g.sent(0.0, {"mz": 1.0, "look": {"yaw": 0.0, "pitch": 0.0}})
	var at_2cm := -1.0
	for i in 60:
		g.advance(float(i + 1) * MovePredictor.DT)
		if at_2cm < 0.0 and g.shown().y >= 0.02:
			at_2cm = float(i + 1) * MovePredictor.DT
	t.check(at_2cm > 0.0 and at_2cm < 0.035, "2 cm on in %.0f ms of the press (the host's own man: 25)" % (at_2cm * 1000.0))
	t.check(g.vel.y > 1.4 and g.vel.y < 2.1, "and at %.2f m/s half a second on, the walk's pace" % g.vel.y)

## A host that walks him as the model does changes nothing: the guest shows him where he would be with no delay, to a millimetre,
## where his own snapshots alone were 20 cm behind the keys.
func test_a_host_that_agrees_is_followed_to_the_millimetre() -> void:
	var keys := func(tm: float) -> Array:
		# forward 0.5 s, still 0.4 s, strafe 0.5 s, back while running left, stop
		if tm < 0.5: return [0.0, 1.0, true]
		if tm < 0.9: return [0.0, 0.0]
		if tm < 1.4: return [1.0, 0.0]
		if tm < 1.8: return [-0.7, -0.7]
		return [0.0, 0.0]
	var r := _run(keys, 2.4, 0.04, 0.04)
	var worst := _worst(r.shown, r.truth, 60, 288)
	var behind := _worst(r.host, r.truth, 60, 288)
	t.check(worst < 0.005, "what he sees is within %.1f mm of the walk with no delay at all" % (worst * 1000.0))
	t.check(behind > 0.12, "where the host's own picture of him was %.0f cm behind it" % (behind * 100.0))

## And with a far longer way (a friend across the sea: 120 ms each way) it is the same, since the model has the keys he pressed.
func test_a_long_round_trip_is_the_same() -> void:
	var keys := func(tm: float) -> Array:
		return [0.0, 1.0] if fmod(tm, 1.2) < 0.6 else [0.0, 0.0]
	var r := _run(keys, 3.6, 0.12, 0.12)
	var worst := _worst(r.shown, r.truth, 120, 432)
	var behind := _worst(r.host, r.truth, 120, 432)
	t.check(worst < 0.005, "within %.1f mm of the walk with no delay at 240 ms round trip" % (worst * 1000.0))
	t.check(behind > 0.2, "where the host's picture was %.0f cm behind" % (behind * 100.0))

## A host that does not walk as the model does (a wall in the way): the picture does not jump to it, it comes there within a
## breath, and does not go on through it.
func test_a_wall_the_model_does_not_know_is_come_to_without_a_jump() -> void:
	var keys := func(_tm: float) -> Array:
		return [0.0, 1.0]
	var r := _run(keys, 3.0, 0.04, 0.04, 1.0, 0.8)
	var shown: Array = r.shown
	var biggest_step := 0.0
	var worst_in := 0.0
	for i in range(1, shown.size()):
		biggest_step = maxf(biggest_step, ((shown[i] as Vector2) - (shown[i - 1] as Vector2)).length())
		if i > 240:
			worst_in = maxf(worst_in, (shown[i] as Vector2).y - 0.8)
	t.check(biggest_step < 0.03, "a step of him is never more than %.1f cm (a walk is 1.8 cm a step)" % (biggest_step * 100.0))
	t.check(worst_in < 0.15, "and held at the wall for a second he is never more than %.0f cm into it" % (worst_in * 100.0))
	# and let go there: the picture settles to the host's
	var keys2 := func(tm: float) -> Array:
		return [0.0, 1.0] if tm < 1.0 else [0.0, 0.0]
	var r2 := _run(keys2, 2.0, 0.04, 0.04, 1.0, 0.8)
	var last_shown: Vector2 = r2.shown[r2.shown.size() - 1]
	var last_host: Vector2 = r2.host[r2.host.size() - 1]
	t.check((last_shown - last_host).length() < 0.01, "he is where the host has him when the keys are let go (%.1f mm)" % ((last_shown - last_host).length() * 1000.0))
	# and turn from the wall: his man walks off the moment the key is down, not a tenth of a second on (the wall's hold is
	# only on the way into it)
	var keys3 := func(tm: float) -> Array:
		if tm < 1.0: return [0.0, 1.0]
		return [0.0, -1.0]
	var r3 := _run(keys3, 1.4, 0.04, 0.04, 1.0, 0.8)
	var at_wall := 0.8
	var back_2cm := -1.0
	for i in range(120, r3.shown.size()):
		if (r3.shown[i] as Vector2).y <= at_wall - 0.02:
			back_2cm = float(i - 120) / 120.0
			break
	t.check(back_2cm >= 0.0 and back_2cm < 0.06, "turning from the wall he is 2 cm off it in %.0f ms" % (back_2cm * 1000.0))

## The pace the host names is the one he walks at (a man weighed down, a man slowed), and a pace of 0 (he is down, or held)
## is nothing predicted: the model stands.
func test_the_host_names_the_pace() -> void:
	var g := MovePredictor.new()
	g.reconcile(0.0, 0, 0, Vector2.ZERO, Vector2.ZERO, 0.0, 0.5)
	g.sent(0.0, {"mz": 1.0, "look": {"yaw": 0.0, "pitch": 0.0}})
	for i in 120:
		g.advance(float(i + 1) * MovePredictor.DT)
	t.check(absf(g.vel.y - 1.05) < 0.1, "at half the pace he goes at %.2f m/s, not 2.1" % g.vel.y)
	g.reconcile(1.0, g.seq, 2, g.pos, g.vel, 0.0, 0.0)
	t.eq(g.pace, 0.0, "a word of pace 0 is taken")

## Where he looks decides where his keys take him: with the eyes turned a quarter round, forward is that way.
func test_forward_is_where_the_body_faces() -> void:
	var g := MovePredictor.new()
	g.reconcile(0.0, 0, 0, Vector2.ZERO, Vector2.ZERO, 0.0, 1.0)
	g.sent(0.0, {"mz": 1.0, "look": {"yaw": PI / 2.0, "pitch": 0.0}})
	for i in 240:
		g.advance(float(i + 1) * MovePredictor.DT)
	t.check(g.pos.x > 1.5 and absf(g.pos.y) < 0.9, "turned a quarter round he walks along x (%.2f, %.2f)" % [g.pos.x, g.pos.y])

## In the air nothing steers him: the model keeps the velocity he had, whatever keys are held, and takes the keys again on landing.
func test_in_the_air_he_goes_on_as_he_was_going() -> void:
	var g := MovePredictor.new()
	g.reconcile(0.0, 0, 0, Vector2.ZERO, Vector2(0, 2.0), 0.0, 1.0, true)
	g.sent(0.0, {"mx": -1.0, "mz": 0.0, "look": {"yaw": 0.0, "pitch": 0.0}})   # (the keys ask him to go off sideways: no use in the air)
	for i in 60:
		g.advance(float(i + 1) * MovePredictor.DT)
	t.check(absf(g.vel.y - 2.0) < 1e-6 and absf(g.vel.x) < 1e-6, "his velocity is as it was (%.2f, %.2f m/s)" % [g.vel.x, g.vel.y])
	t.check(absf(g.pos.y - 1.0) < 0.01, "and he has gone a metre in half a second (%.2f m)" % g.pos.y)
	g.reconcile(0.5, g.seq, 1, g.pos, g.vel, 0.0, 1.0, false)
	for i in 60:
		g.advance(0.5 + float(i + 1) * MovePredictor.DT)
	t.check(g.vel.x < -1.0, "on the sand again the keys take him (%.2f m/s sideways)" % g.vel.x)
