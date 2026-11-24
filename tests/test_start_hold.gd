extends Node
## A game's start in a room waits for everyone (Match.hold, StartVeil): the men are built, the host's and every guest's, before the game begins, and it begins for all at once.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Physics frames until `cond` holds (or `most` of them): how many it took, -1 if it never did.
func _until(cond: Callable, most := 1500) -> int:
	for i in most:
		if cond.call():
			return i
		await get_tree().physics_frame
	return 0 if cond.call() else -1

func _peers(n: int) -> Array:
	var peers := []
	for i in n:
		peers.append({"id": 2 + i, "name": ["Bob", "Cat", "Dan"][i], "loadout": {"main": "axe", "off": ""}, "kit": {"nailPot": 1 + i}})
	return peers

## The yard's own people: its dummies and the keepers of its stalls.
func _people() -> int:
	var n: int = Yard.DUMMIES.size()
	for id in Yard.stations():
		if Yard.STATIONS[id].has("npc"):
			n += 1
	return n

func _host(seed_: int, friends: int, banners: Array = []) -> Match:
	var m := Match.new()
	m.stage_always = true
	m.hold_always = true
	add_child(m)
	m.banner.connect(func(text, _sub): banners.append(text))
	m.setup({"mode": "yard", "role": "host", "headless": true, "name": "Ann", "seed": seed_, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": _peers(friends)})
	return m

## The yard of a host with friends is held from its first frame: the world asleep, no time passing, its banner kept back; and when the last man is in the game begins at once.
func test_the_world_waits_for_every_friend_and_then_begins() -> void:
	var banners := []
	var m := _host(1, 3, banners)
	t.check(m.hold, "the start is held")
	t.check(Net.sim_held, "and the room's step is not read while it is")
	t.eq(m.start_coming, 3 + _people(), "the three friends and the yard's own people to wait for")
	t.eq(Physique.budget_us, Match.HOLD_BUILD_US, "the men are built a good share of every frame while the veil hides it")
	t.check(get_viewport().disable_3d, "and the picture is not drawn")
	var held := 0
	var quiet := true
	while m.hold and held < 4000:
		quiet = quiet and m.tick == 0 and m.time == 0.0 and banners.is_empty()
		held += 1
		await get_tree().physics_frame
	t.check(held > 2, "the game begins when the last of them is in, not before (%d frames)" % held)
	t.check(quiet, "and until then no step of the game is taken, no time passes and the start's banner is kept back")
	t.eq(m.humans().size(), 4, "all four are in at that moment")
	t.eq(m.coming, 0, "nobody on his way")
	t.check(not Net.sim_held and not get_viewport().disable_3d and Physique.budget_us == 0, "the world is awake, drawn and built at the old pace again")
	t.eq(banners.size(), 1, "the banner is said then (%s)" % [banners])
	await _steps(10)
	t.check(m.tick > 0 and m.time > 0.0, "and the game runs from then (tick %d)" % m.tick)
	m.queue_free()
	await get_tree().physics_frame

## No room, no friends to wait for (or no screen): nothing is held, as it was.
func test_a_start_with_nobody_to_wait_for_is_not_held() -> void:
	var m := Match.new()
	m.stage_always = true
	add_child(m)
	m.setup({"mode": "yard", "role": "host", "headless": true, "name": "Ann", "seed": 2, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": _peers(2)})
	t.check(not m.hold and not Net.sim_held, "friends staged, but not in a room: not held")
	m.queue_free()
	await get_tree().physics_frame
	t.check(not Match.start_hold_expected({"role": "local", "peers": _peers(1)}), "a lone player's start is not told to be held")
	t.check(not Match.start_hold_expected({"role": "host", "headless": true, "peers": _peers(1)}), "nor a game without a screen")
	t.check(not Match.start_hold_expected({"role": "host", "peers": []}), "nor a room with nobody in it")

## In a room the host waits for every guest to say he has built the men, and begins when the last has: and a guest who leaves is not waited for.
func test_the_host_waits_for_the_guests_to_say_they_are_ready() -> void:
	var dt: bool = Net.dtls
	Net.dtls = false
	var err: int = Net.host_enet(28630)
	Net.dtls = dt
	if err != OK:
		t.check(false, "a room could not be opened for the test (%d)" % err)
		return
	Net.peers[2] = {"name": "Bob", "loadout": {"main": "axe"}}
	Net.peers[3] = {"name": "Cat", "loadout": {"main": "axe"}}
	Net.peers[4] = {"name": "Dan", "loadout": {"main": "axe"}}
	var m := Match.new()
	m.stage_always = true
	add_child(m)
	m.setup({"mode": "yard", "role": "host", "headless": true, "name": "Ann", "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": _peers(3)})
	t.check(m.hold, "a room's start is held")
	var built := await _until(func(): return m._assembled, 4000)
	t.check(built >= 0, "the host has every man of the start in")
	t.check(m.hold, "but the game does not begin: the guests have not said they have built them too")
	t.eq(m._hold_waiting.keys().size(), 3, "three guests to hear from")
	m.hold_ready(2)
	m.hold_ready(2)
	t.check(m.hold, "one of three is not everyone (and his word twice is one)")
	Net.peers.erase(4)
	m.drop_peer(4)
	t.check(m.hold, "one who left is no longer waited for: one of two is still not everyone")
	m.hold_ready(3)
	t.check(not m.hold, "the last to say it begins the game")
	t.check(not Net.sim_held, "the world wakes")
	m.queue_free()
	await get_tree().physics_frame
	Net.leave()

## A guest who never answers is waited for a while, not for ever.
func test_a_guest_who_does_not_answer_is_waited_for_a_while() -> void:
	var m := _host(4, 1)
	await _until(func(): return m.start_coming == 0, 4000)
	m._hold_waiting = {2: true}
	m._assembled = true
	m.hold = true
	m._guests_timeout()
	t.check(not m.hold, "the time he is given is up: the game begins")
	m.queue_free()
	await get_tree().physics_frame

## A game left before it began wakes the world it put to sleep (or the menu's own, and every match after, would be frozen).
func test_a_game_left_while_held_wakes_the_world() -> void:
	var m := _host(5, 2)
	t.check(m.hold and Net.sim_held, "held")
	m.queue_free()
	await _steps(3)
	t.check(not Net.sim_held and not get_viewport().disable_3d and Physique.budget_us == 0, "the match gone, the world is awake and drawn again")
	var n := _host(6, 2)
	t.check(n.hold, "another is held")
	n.let_go()
	await _steps(3)
	t.check(not Net.sim_held and not get_viewport().disable_3d, "let go of while held: the same")

## A guest holds from the host's word until the host says go; he says he is ready only when he has built all the men he was told of.
func test_a_guest_holds_until_the_host_says_go() -> void:
	var m := Match.new()
	add_child(m)
	var began := [0]
	m.released.connect(func(): began[0] += 1)
	m.setup({"mode": "yard", "role": "guest", "headless": true, "decrees": [], "hazards": [], "hold": true})
	t.check(m.hold and Net.sim_held, "a guest told that the start is held holds")
	await _steps(10)
	t.eq(m.time, 0.0, "and takes no step of the game")
	m.guest_pending[7] = {"id": 7}
	m.guest_message("assembled", {})
	t.check(m._assembled_seen and not m._ready_sent, "told that every man is in, he has one still to build: he does not say he is ready")
	m.guest_pending.erase(7)
	m._guest_ready_check()
	t.check(m._ready_sent, "he says it when the last is built")
	t.check(m.hold, "and holds until he is told to go")
	m.guest_message("go", {})
	t.check(not m.hold and began[0] == 1 and not Net.sim_held, "told to go, the game begins for him (once)")
	m.guest_message("go", {})
	t.eq(began[0], 1, "a second word changes nothing")
	m.queue_free()
	await get_tree().physics_frame

## The guest who is not told to hold (the host's start holds nothing) is not held.
func test_a_guest_not_told_to_hold_does_not() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "role": "guest", "headless": true, "decrees": [], "hazards": []})
	t.check(not m.hold and not Net.sim_held, "not held")
	m.queue_free()
	await get_tree().physics_frame

## While the start is held the room's step is not read (the steps are empty ones: read, the host would think itself fast and let every foe in at once), nor the pace changed.
func test_the_steps_are_not_read_while_held() -> void:
	var was_ms: float = Net.step_ms
	var was_over: bool = Net.overloaded
	Net.step_ms = 7.0
	Net.sim_held = true
	Net._frame_steps = 3
	Net._frame_t0 = Time.get_ticks_usec() - 1000
	Net._time_steps()
	t.eq(Net.step_ms, 7.0, "what a step costs is left as it was")
	t.eq(Net._frame_steps, 0, "and the frame's count is let go")
	Net.overloaded = true
	Net._pace()
	t.check(Net.overloaded, "nor is the pace looked at")
	Net.sim_held = false
	Net.overloaded = was_over
	Net.step_ms = was_ms

## What the veil says.
func test_the_veil_says_how_far_the_start_is() -> void:
	t.eq(StartVeil.line_for(Vector2i(3, 8), false), "3 of 8 in", "the host: how many of the men are in")
	t.eq(StartVeil.line_for(Vector2i(2, 5), true), "3 to build", "a guest: how many he has still to build")
	t.eq(StartVeil.line_for(Vector2i(5, 5), true), "Waiting for the others", "and when he has built them all, that he waits")

## The veil stays while the game is held and fades away when it begins.
func test_the_veil_goes_when_the_game_begins() -> void:
	var m := _host(8, 1)
	var veil := StartVeil.new(m)
	add_child(veil)
	var vid := veil.get_instance_id()
	var gone := func():
		var v = instance_from_id(vid)
		return v == null or v.is_queued_for_deletion()
	await _steps(2)
	t.check(not gone.call(), "up while the game is held")
	await _until(func(): return not m.hold, 4000)
	await _until(gone, 600)
	t.check(gone.call(), "gone, faded, after it begins")
	m.queue_free()
	await get_tree().physics_frame

## Whether every one of the yard's own people (its dummies and the keepers of its stalls) is in.
func _people_in(m: Match) -> bool:
	var keepers := 0
	for id in Yard.stations():
		if Yard.STATIONS[id].has("npc"):
			keepers += 1
	return m.yard.dummies.size() == Yard.DUMMIES.size() and m.yard.keepers.size() == keepers

## The yard's own people (dummies, keepers) are built after the friends: a held start waits for them too, and the yard is whole when it begins.
func test_a_held_yard_is_whole_when_it_begins() -> void:
	var m := _host(9, 2)
	t.eq(m.start_coming, 2 + _people(), "the friends and the yard's own people are counted from the first frame")
	var friends_in := await _until(func(): return m.coming == 0, 4000)
	t.check(friends_in >= 0 and m.hold, "the friends are in, and the start is still held for the dummies and the keepers")
	await _until(func(): return not m.hold, 4000)
	t.check(_people_in(m), "when it begins the dummies and the keepers are in")
	t.eq(m.start_coming, 0, "nobody left to wait for")
	t.eq(String(m.hold_stats.get("why", "")), "everyone is in", "said so (nobody in a room to be waited for)")
	t.check(int(m.hold_stats.get("men", 0)) >= 3 + _people(), "with all the men in (%s)" % [m.hold_stats])
	m.queue_free()
	await get_tree().physics_frame

## A match is held once, at its start: a bout's first round called again does not freeze the game in the middle of it.
func test_a_match_is_held_once() -> void:
	var m := _host(10, 1)
	await _until(func(): return not m.hold, 4000)
	t.check(not m.hold, "begun")
	m.bring_in([{"kind": "bot", "name": "Late", "loadout": {"main": "gladius", "off": ""}, "team": 1, "pos": Vector3(3, 0, -6), "yaw": 0.0}], Callable(), true)
	t.check(not m.hold and not Net.sim_held, "a second start-time batch does not hold the game again")
	await _until(func(): return m.coming == 0, 4000)
	m.queue_free()
	await get_tree().physics_frame
