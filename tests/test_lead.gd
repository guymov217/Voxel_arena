extends Node
## What a guest draws the others ahead of the host's picture by (Lead): a man walking is drawn on by his pace over the time his blows are
## behind his picture, a man standing or fallen is not, and it comes and goes by easing, never by a jump.

var t

const DT := 1.0 / 60.0

## Rows of a man walking along x at `speed` for `secs`, one every DT; returns the added distance after the last (and the largest change
## between two rows, in `worst`).
func _walk(l: Lead, speed: float, secs: float, ahead := 0.08, standing := true, t0 := 0.0, x0 := 0.0, worst: Array = []) -> Vector3:
	var out := Vector3.ZERO
	var prev := l.cur
	var n := int(secs / DT)
	for i in n:
		var now := t0 + (i + 1) * DT
		out = l.step(Vector3(x0 + speed * (now - t0), 1.0, 0.0), now, standing, ahead)
		if not worst.is_empty():
			worst[0] = maxf(float(worst[0]), (out - prev).length())
		prev = out
	return out

func test_a_man_walking_is_drawn_on_by_his_pace() -> void:
	var l := Lead.new()
	var c := _walk(l, 2.0, 1.0)
	var want := 2.0 * 0.08 * Lead.GAIN
	t.check(absf(c.x - want) < 0.002 and absf(c.z) < 1e-6 and c.y == 0.0, "walking at 2 m/s with 80 ms behind him he is drawn %.1f cm on, along his way (%.1f cm)" % [want * 100.0, c.x * 100.0])
	var l2 := Lead.new()
	var back := _walk(l2, -1.5, 1.0, 0.1)
	t.check(absf(back.x + 1.5 * 0.1 * Lead.GAIN) < 0.002, "and the other way when he goes the other way (%.1f cm)" % (back.x * 100.0))

func test_along_the_sand_only() -> void:
	var l := Lead.new()
	var c := Vector3.ZERO
	for i in 60:
		var now := (i + 1) * DT
		c = l.step(Vector3(0.0, 5.0 + 3.0 * now, 1.5 * now), now, true, 0.08)   # (rising as he walks: a jump, a throw)
	t.check(absf(c.y) < 1e-9 and c.z > 0.05 and absf(c.x) < 1e-6, "what is added is along the sand: his height is the host's (%s)" % str(c))

func test_a_man_standing_is_not_moved() -> void:
	var l := Lead.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	for i in 300:
		var now := (i + 1) * DT
		# (rows are 2 mm steps and a man at rest sways a few of them)
		var c := l.step(Vector3(3.0 + rng.randf_range(-0.004, 0.004), 1.0, -2.0 + rng.randf_range(-0.004, 0.004)), now, true, 0.1)
		worst = maxf(worst, c.length())
	t.check(worst < 0.01, "a man at rest, his rows jittering by a few mm, is drawn no more than %.1f mm from where the host has him" % (worst * 1000.0))

func test_a_fast_man_is_drawn_on_no_more_than_the_most() -> void:
	var l := Lead.new()
	var c := _walk(l, 8.0, 1.0, 0.2)
	t.check(absf(c.length() - Lead.MAX) < 1e-6, "a beast at 8 m/s is drawn on %.0f cm, no more (%.1f)" % [Lead.MAX * 100.0, c.length() * 100.0])
	t.check(c.x > 0.0, "the way he goes")

func test_it_comes_and_goes_by_easing() -> void:
	var l := Lead.new()
	var worst := [0.0]
	_walk(l, 6.0, 0.6, 0.12, true, 0.0, 0.0, worst)
	t.check(l.cur.length() > 0.25, "at a run he is well on (%.1f cm)" % (l.cur.length() * 100.0))
	var step_max := Lead.SLEW * DT + 1e-6
	t.check(float(worst[0]) <= step_max, "and it came by no more than %.1f cm a row (%.2f)" % [step_max * 100.0, float(worst[0]) * 100.0])
	# He stops dead: the rows are the same place from here on.
	var stop := 0.6 * 6.0
	var worst2 := [0.0]
	var n := int(0.4 / DT)
	var prev := l.cur
	var c := Vector3.ZERO
	var after_100ms := Vector3.ZERO
	for i in n:
		var now := 0.6 + (i + 1) * DT
		c = l.step(Vector3(stop, 1.0, 0.0), now, true, 0.12)
		worst2[0] = maxf(float(worst2[0]), (c - prev).length())
		prev = c
		if i == int(0.1 / DT):
			after_100ms = c
	t.check(float(worst2[0]) <= step_max, "he stopped and it goes by no more than %.1f cm a row (%.2f)" % [step_max * 100.0, float(worst2[0]) * 100.0])
	t.check(c.length() < 0.005, "and is gone four tenths of a second on (%.1f cm)" % (c.length() * 100.0))
	t.check(after_100ms.length() > 0.02, "not at once (%.1f cm left a tenth of a second on)" % (after_100ms.length() * 100.0))

func test_a_man_down_or_dead_is_not_walked_on() -> void:
	var l := Lead.new()
	_walk(l, 2.0, 1.0)
	t.check(l.cur.length() > 0.1, "a man walking is drawn on")
	var c := _walk(l, 2.0, 0.5, 0.08, false, 1.0, 2.0)
	t.check(c.length() < 1e-6, "and when he is down (flung, rising, dead) he is drawn where the host has him (%.2f cm)" % (c.length() * 100.0))
	var c2 := _walk(l, 2.0, 1.0, 0.08, true, 1.5, 3.0)
	t.check(c2.length() > 0.1, "on his feet again, he is drawn on again")

func test_a_jump_is_no_pace() -> void:
	var l := Lead.new()
	_walk(l, 2.0, 1.0)
	var c := l.step(Vector3(40.0, 1.0, 40.0), 1.0 + DT, true, 0.08)
	t.check(l.vel.length() == 0.0, "a row far across the sand (a spawn, a throw) tells nothing of his pace")
	t.check(c.length() <= Lead.SLEW * DT + 0.13, "nor does it throw him %.1f cm off" % (c.length() * 100.0))
	var c2 := _walk(l, 2.0, 0.2, 0.08, true, 1.0 + DT, 40.0)
	t.check(c2.length() > 0.0, "and the pace is learnt again from the rows that follow")

func test_a_late_row_tells_nothing() -> void:
	var l := Lead.new()
	_walk(l, 2.0, 1.0)
	l.step(Vector3(5.0, 1.0, 0.0), 2.0, true, 0.08)   # (a second late: the host's game hitched, a packet was lost)
	t.check(l.vel.length() == 0.0, "a row a second late is no pace")

func test_two_rows_in_one_moment() -> void:
	var l := Lead.new()
	_walk(l, 2.0, 1.0)
	var v0 := l.vel
	l.step(Vector3(2.0 + 0.001, 1.0, 0.0), 1.0 + 0.0001, true, 0.08)
	t.check((l.vel - v0).length() < 1e-6, "a row in the very moment of the last is not measured from it")

## A line that stalls and lets its packets go at once: twelve rows in one moment, a stall's worth of his way between the first and the last. The row
## after them is measured from the last of them, and he is not shown running on 12 times as fast for it.
func test_a_burst_after_a_stall_does_not_throw_him_ahead() -> void:
	var l := Lead.new()
	var steady := _walk(l, 2.0, 1.0)
	var worst := 0.0
	var now := 1.0
	var x := 2.0
	# a stall of 200 ms: rows 1/60 s apart are sent all the while, and come together
	for i in 12:
		x += 2.0 * DT
		var c := l.step(Vector3(x, 1.0, 0.0), now + 0.2, true, 0.08)
		worst = maxf(worst, c.length())
	now += 0.2
	for i in 60:
		now += DT
		x += 2.0 * DT
		var c2 := l.step(Vector3(x, 1.0, 0.0), now, true, 0.08)
		worst = maxf(worst, c2.length())
	t.check(worst < steady.length() * 1.25, "after the burst he is drawn on no more than %.1f cm, as he was before the stall (%.1f cm); the most was %.1f cm" % [steady.length() * 125.0, steady.length() * 100.0, worst * 100.0])
	t.check(absf(l.cur.length() - steady.length()) < 0.01, "and he is back at it a second on (%.1f cm)" % (l.cur.length() * 100.0))

## A row a long while after the last (the host's game hitched): no measure of his pace, which stays as it was.
func test_a_late_row_leaves_the_pace_as_it_was() -> void:
	var l := Lead.new()
	_walk(l, 2.0, 1.0)
	var v0 := l.vel
	l.step(Vector3(2.0 + 2.0 * 0.12, 1.0, 0.0), 1.0 + 0.12, true, 0.08)   # (120 ms late: his way over it, 24 cm)
	t.check((l.vel - v0).length() < 1e-6, "a row 120 ms after the last tells nothing: his pace is as it was")
	var c := _walk(l, 2.0, 0.5, 0.08, true, 1.12, 2.0 + 2.0 * 0.12)
	t.check(absf(c.x - 2.0 * 0.08 * Lead.GAIN) < 0.01, "and the rows that follow are measured from it (%.1f cm)" % (c.x * 100.0))

## The rows of a line with a jitter: the pace is kept from arrival times that are not the host's, and what is added must not tremble.
func test_a_jittering_line_does_not_tremble() -> void:
	var l := Lead.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var speed := 2.0
	var lo := 1e9
	var hi := -1e9
	for i in 240:
		var sim := (i + 1) * DT                       # (the host's time)
		var arrive := sim + rng.randf_range(-0.004, 0.004)   # (when it came)
		var c := l.step(Vector3(speed * sim, 1.0, 0.0), arrive, true, 0.08)
		if i > 60:
			lo = minf(lo, c.x)
			hi = maxf(hi, c.x)
	var want := speed * 0.08 * Lead.GAIN
	t.check(lo > want * 0.6 and hi < want * 1.4, "his drawing keeps within 40%% of %.1f cm on a line jittering by 4 ms (%.1f to %.1f cm)" % [want * 100.0, lo * 100.0, hi * 100.0])
