extends Node
## A room keeps time (Net.steps_cap, Net._pace): a frame of a room may run more physics steps than the engine's four
## when they are cheap, so a slow picture (two windows on one computer, a first-time shader build, a window behind
## another) does not slow the game down for everyone; and not when they are dear, where more of them would only
## make the picture slower.

var t

func test_the_cap_follows_what_a_step_costs() -> void:
	t.eq(Net.steps_cap(0.0, 4), 4, "no measure yet: the engine's cap")
	t.eq(Net.steps_cap(1.8, 4), Net.ROOM_STEPS_MAX, "a guest's cheap step: as far as a room goes")
	t.eq(Net.steps_cap(3.6, 4), Net.ROOM_STEPS_MAX, "the yard with a guest in it")
	t.eq(Net.steps_cap(6.0, 4), 8, "a step of 6 ms: eight to a frame (50 ms of physics)")
	t.eq(Net.steps_cap(8.0, 4), 6, "at the edge of the 8.3 ms there are: six")
	t.eq(Net.steps_cap(12.0, 4), 4, "a room too dear for the computer: the engine's cap, no more")
	t.eq(Net.steps_cap(30.0, 4), 4, "far too dear: still not below it")
	t.eq(Net.steps_cap(2.0, 16), 16, "a cap of the player's own above the room's stays")

func test_a_room_raises_the_cap_and_gives_it_back() -> void:
	var orig: int = Engine.max_physics_steps_per_frame
	var cost: float = Net.step_ms
	var room: String = Net.transport
	var over: bool = Net.overloaded
	var hot: int = Net._hot_looks
	var alone: int = Net._steps_alone
	var on: bool = Net.overload_on
	Net.overload_on = true
	# (A heavy test before this one may have left the game over its budget with two steps to a frame, as it does while it is:
	# this one starts from a host that keeps up, with the engine's own cap.)
	Net.overloaded = false
	Net._hot_looks = 0
	Net._steps_alone = -1
	Engine.max_physics_steps_per_frame = int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 4))
	var was: int = Engine.max_physics_steps_per_frame
	Net.step_ms = 3.0
	Net.transport = "enet"
	Net._pace()
	t.eq(Engine.max_physics_steps_per_frame, Net.ROOM_STEPS_MAX, "in a room: raised")
	Net.step_ms = 12.0
	Net._pace()
	t.eq(Engine.max_physics_steps_per_frame, was, "a room whose steps cost too much: the engine's own")
	Net.step_ms = 3.0
	Net._pace()
	t.eq(Engine.max_physics_steps_per_frame, Net.ROOM_STEPS_MAX, "raised again when they cost less")
	Net.transport = ""
	Net._pace()
	t.eq(Engine.max_physics_steps_per_frame, was, "out of the room: the cap it was")
	Net.step_ms = cost
	Net.transport = room
	Net.overloaded = over
	Net._hot_looks = hot
	Net._steps_alone = alone
	Net.overload_on = on
	Engine.max_physics_steps_per_frame = orig

func test_the_game_reads_its_own_step_cost() -> void:
	# (The suite runs one step to a frame: Net's own clock of a frame's steps comes out as the cost of one.)
	var before: float = Net.step_ms
	for i in 30:
		await get_tree().physics_frame
	t.check(Net.step_ms > 0.0 and Net.step_ms < 1000.0, "a step has a cost (%.2f ms)" % Net.step_ms)
	Net.step_ms = before
