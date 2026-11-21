extends Node
## The wait put on every man's hands in a fight of people against each other (InputDelay): the input of so many ticks ago comes out,
## a press is acted on once however the wait changes, and the wait is the slowest friend's trip for the host and what is left of it
## for each guest.

var t

func _inp(n: int, jump := false) -> Dictionary:
	return {"mx": float(n), "jump": jump, "useItem": -1}

func test_no_wait_is_no_change() -> void:
	var d := InputDelay.new()
	for n in 5:
		var out := d.step(_inp(n), 0)
		t.eq(out.mx, float(n), "with no wait this tick's input is what comes out")
	t.check(d.idle(), "and nothing is kept")

func test_a_wait_of_three_ticks() -> void:
	var d := InputDelay.new()
	var got := []
	for n in 10:
		got.append(int(d.step(_inp(n), 3).mx))
	t.eq(got, [0, 0, 0, 0, 1, 2, 3, 4, 5, 6], "the input of three ticks ago comes out (the first there is, till there are so many)")

func test_a_press_comes_out_once_and_in_its_place() -> void:
	var d := InputDelay.new()
	var jumps := []
	for n in 14:
		var out := d.step(_inp(n, n == 5), 3)
		if out.jump:
			jumps.append(n)
	t.eq(jumps, [8], "a press made on tick 5 is acted on on tick 8, and once")

func test_a_shorter_wait_loses_no_press() -> void:
	var d := InputDelay.new()
	var jumps := []
	var kicks := 0
	for n in 20:
		var inp := _inp(n, n == 6)
		inp["kick"] = n == 7
		# the wait is 6 ticks until tick 10, then 1: the ticks passed over are 5..8
		var out := d.step(inp, 6 if n < 10 else 1)
		if out.jump:
			jumps.append(n)
		if out.get("kick", false):
			kicks += 1
	t.eq(jumps.size(), 1, "a press that falls in the ticks a shorter wait passes over is not lost, nor repeated")
	t.eq(kicks, 1, "nor the next one's")

func test_a_longer_wait_repeats_the_state_not_the_press() -> void:
	var d := InputDelay.new()
	var jumps := 0
	var xs := []
	for n in 16:
		var out := d.step(_inp(n, n == 3), 2 if n < 8 else 5)
		if out.jump:
			jumps += 1
		xs.append(int(out.mx))
	t.eq(jumps, 1, "a wait made longer does not act on a press again")
	t.check(xs[10] <= xs[9] + 1 and xs[15] == 10, "and the hands go on from where they were (%s)" % str(xs))

func test_an_item_used_is_not_lost() -> void:
	var d := InputDelay.new()
	var used := []
	for n in 14:
		var inp := {"mx": 0.0, "useItem": 2 if n == 4 else -1}
		var out := d.step(inp, 4 if n < 8 else 0)
		if int(out.useItem) >= 0:
			used.append(int(out.useItem))
	t.eq(used, [2], "an item used on a tick passed over by a shorter wait is used once")

## The wait of the host and of each guest.
func test_the_waits_of_the_room() -> void:
	var h := InputDelay.holds({2: 60.0, 3: 20.0})
	t.check(absf(float(h[1]) - 0.034) < 1e-6, "the host waits the slowest friend's trip (30 ms) and a margin (%.3f s)" % float(h[1]))
	t.check(absf(float(h[2]) - 0.004) < 1e-6, "the slowest has only the margin to wait (%.3f s)" % float(h[2]))
	t.check(absf(float(h[3]) - 0.024) < 1e-6, "a quicker friend what is left of it (%.3f s)" % float(h[3]))
	t.eq(float(InputDelay.holds({})[1]), 0.0, "no friend, no wait")
	t.eq(float(InputDelay.holds({2: -1.0})[1]), 0.0, "a friend not measured yet is not waited for")
	var far := InputDelay.holds({2: 400.0, 3: 40.0})
	t.check(absf(float(far[1]) - 0.09) < 1e-6 and float(far[2]) == 0.0 and absf(float(far[3]) - 0.07) < 1e-6, "a very slow line is waited for no more than the cap (%s)" % str(far))
