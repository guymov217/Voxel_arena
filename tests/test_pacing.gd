extends Node
## What the engine may do in a frame while the host cannot keep up (Net.steps_cap, Net.overload_after, Net._pace): two physics steps a frame
## once its steps keep costing more than the 8.3 ms there is for each (a room's, and a game alone), never on a spike or for a host that
## keeps up, and the engine's own cap (or the room's) back when it is over. The steps themselves are the same whatever the cap.

var t
var _saved := {}

func _save() -> void:
	_saved = {"cap": Engine.max_physics_steps_per_frame, "step_ms": Net.step_ms, "over": Net.overloaded, "hot": Net._hot_looks, "alone": Net._steps_alone, "transport": Net.transport, "on": Net.overload_on}
	Net.overload_on = true
	Net.overloaded = false
	Net._hot_looks = 0
	Net._steps_alone = -1
	Net.transport = ""
	Engine.max_physics_steps_per_frame = int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 4))

func _restore() -> void:
	Engine.max_physics_steps_per_frame = _saved.cap
	Net.step_ms = _saved.step_ms
	Net.overloaded = _saved.over
	Net._hot_looks = _saved.hot
	Net._steps_alone = _saved.alone
	Net.transport = _saved.transport
	Net.overload_on = _saved.on

func _cap() -> int:
	return Engine.max_physics_steps_per_frame

func test_the_room_caps_are_as_they_were_and_an_overloaded_host_gets_two() -> void:
	t.eq(Net.steps_cap(0.0, 4), 4, "no cost known yet: the engine's cap")
	t.eq(Net.steps_cap(4.0, 4), 12, "a light step: as many as fit in the budget, 12 at most")
	t.eq(Net.steps_cap(8.0, 4), 6, "8 ms a step: 6")
	t.eq(Net.steps_cap(10.0, 4), 5, "10 ms a step: 5")
	t.eq(Net.steps_cap(20.0, 4), 4, "a step dearer than a quarter of the budget: not under the engine's cap")
	t.eq(Net.steps_cap(20.0, 4, true), 2, "over its budget for good: two a frame")
	t.eq(Net.steps_cap(3.0, 4, true), 2, "(over is over, whatever the number given)")
	t.eq(Net.steps_cap(20.0, 1, true), 1, "an engine cap of one is not raised to two")
	t.eq(Net.steps_cap(20.0, 8, true), 2, "an engine cap of eight is brought down to two")

func test_it_takes_two_looks_to_be_over_and_a_cost_under_7_8_to_be_clear() -> void:
	var r := Net.overload_after(false, 0, 20.0)
	t.eq(r, [false, 1], "one look at a dear step is not enough")
	r = Net.overload_after(r[0], r[1], 20.0)
	t.eq(r, [true, 2], "two in a row are")
	r = Net.overload_after(r[0], r[1], 8.2)
	t.check(r[0], "between the two limits (8.2 ms) it stays over")
	r = Net.overload_after(r[0], r[1], 7.9)
	t.check(r[0], "7.9 ms: still over")
	r = Net.overload_after(r[0], r[1], 7.7)
	t.check(not r[0], "7.7 ms: clear")
	# A spike (a first-time shader, one heavy step: the smoothed cost jumps for a look and is back at the next).
	r = Net.overload_after(false, 0, 30.0)
	r = Net.overload_after(r[0], r[1], 5.0)
	t.eq(r, [false, 0], "a spike of one look is forgotten")
	r = Net.overload_after(r[0], r[1], 30.0)
	t.eq(r, [false, 1], "and starts the count again")
	# A host a hair over its budget never is (8.33 ms): the line is 8.6.
	var q := [false, 0]
	for i in 20:
		q = Net.overload_after(q[0], q[1], 8.5)
	t.check(not q[0], "8.5 ms a step, for as long as you like, is not over")
	for i in 2:
		q = Net.overload_after(q[0], q[1], 8.6)
	t.check(q[0], "8.6 is")

func test_a_game_alone_whose_steps_cost_too_much_gets_two_steps_and_then_the_engines_cap_back() -> void:
	_save()
	Net.step_ms = 14.0
	Net._pace()
	t.eq(_cap(), 4, "the first look: not yet")
	Net._pace()
	t.eq(_cap(), 2, "the second: two steps a frame")
	t.check(Net.overloaded, "and it says so")
	Net.step_ms = 8.2
	Net._pace()
	t.eq(_cap(), 2, "between the limits it stays so")
	Net.step_ms = 6.0
	Net._pace()
	t.eq(_cap(), 4, "the engine's own cap is back when the steps are cheap again")
	t.eq(Net._steps_alone, -1, "with nothing left to put back")
	t.check(not Net.overloaded, "and it is not over")
	_restore()

func test_a_spike_does_not_touch_the_cap() -> void:
	_save()
	Net.step_ms = 30.0
	Net._pace()
	Net.step_ms = 5.0
	Net._pace()
	Net._pace()
	t.eq(_cap(), 4, "one look at a dear step, then cheap ones: the cap never moved")
	t.eq(Net._steps_alone, -1, "and nothing was kept to put back")
	_restore()

func test_a_host_that_keeps_up_is_not_touched() -> void:
	_save()
	for cost in [0.4, 3.0, 6.0, 7.8, 8.0, 8.4, 8.5]:
		Net.step_ms = cost
		for i in 6:
			Net._pace()
		t.eq(_cap(), 4, "a step of %.1f ms: the engine's cap, as it was" % cost)
		t.check(not Net.overloaded, "%.1f ms is not over" % cost)
	_restore()

func test_a_room_that_is_over_gets_two_and_one_that_is_not_its_own_catch_up() -> void:
	_save()
	Net.transport = "test"
	Net.step_ms = 4.0
	Net._pace()
	t.eq(_cap(), 12, "a light room catches up as far as the physics allows")
	Net.step_ms = 14.0
	Net._pace()
	t.eq(_cap(), 4, "a dear step, once: the engine's cap, as it was")
	Net._pace()
	t.eq(_cap(), 2, "twice: two")
	Net.step_ms = 8.2
	Net._pace()
	t.eq(_cap(), 2, "between the limits it stays two")
	Net.step_ms = 4.0
	Net._pace()
	t.eq(_cap(), 12, "and a light room again is a light room")
	Net.transport = ""
	Net._pace()
	t.eq(_cap(), 4, "the room closes: the engine's own cap")
	t.eq(Net._steps_alone, -1, "with nothing left to put back")
	_restore()

func test_the_switch_turns_it_off() -> void:
	_save()
	Net.overload_on = false
	Net.step_ms = 20.0
	for i in 5:
		Net._pace()
	t.eq(_cap(), 4, "off: a dear step changes nothing")
	t.check(not Net.overloaded, "and it is not over")
	t.eq(Net._steps_alone, -1, "with nothing kept to put back")
	Net.overload_on = true
	Net._pace()
	Net._pace()
	t.eq(_cap(), 2, "on again: two")
	Net.overload_on = false
	Net._pace()
	t.eq(_cap(), 4, "and off again: the engine's cap, at once")
	_restore()

func test_a_step_is_a_120th_of_a_second_whatever_the_cap() -> void:
	var was := Engine.max_physics_steps_per_frame
	for cap in [1, 2, 4, 12]:
		Engine.max_physics_steps_per_frame = cap
		await get_tree().physics_frame
		await get_tree().physics_frame
		t.check(is_equal_approx(get_physics_process_delta_time(), 1.0 / 120.0), "a step is 1/120 s with the cap at %d (%.6f)" % [cap, get_physics_process_delta_time()])
	t.eq(Engine.physics_ticks_per_second, 120, "and 120 of them a second")
	Engine.max_physics_steps_per_frame = was
