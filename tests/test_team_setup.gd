extends Node
## The teams of a team fight, chosen in the yard (TeamSetup, YardPlay): a circle for each team, each player walks into his, the
## host begins when all stand in one, the bots fill the sides.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _yard(role := "local") -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "headless": true, "seed": 1, "decrees": [], "hazards": [], "role": role, "loadout": {"main": "gladius", "off": "roundShield"}})
	return m

func test_the_circles_are_on_the_sand_apart() -> void:
	var a: Vector3 = TeamSetup.CENTRES[0]
	var b: Vector3 = TeamSetup.CENTRES[1]
	t.check(a.x < 0.0 and b.x > 0.0, "Red to the left, Blue to the right")
	t.check(a.distance_to(b) > 2.0 * TeamSetup.RADIUS + 1.0, "with room between")
	t.eq(TeamSetup.ring_at(a.x, a.z), 0, "the middle of Red's")
	t.eq(TeamSetup.ring_at(b.x + 1.0, b.z), 1, "inside Blue's")
	t.eq(TeamSetup.ring_at(0.0, 0.0), -1, "between them: none")
	t.eq(TeamSetup.ring_at(a.x + TeamSetup.RADIUS + 0.1, a.z), -1, "just outside: none")

func test_who_stands_where() -> void:
	var s := TeamSetup.new("teams", {"rounds": 3})
	t.check(not s.ready(), "nobody here: not ready")
	s.set_place(1, "Aulus", TeamSetup.CENTRES[0].x, TeamSetup.CENTRES[0].z)
	s.set_place(7, "Brutus", 0.0, 0.0)
	t.eq(s.team_of(1), 0, "Aulus in Red's")
	t.eq(s.team_of(7), -1, "Brutus in none")
	t.eq(s.members(0), ["Aulus"], "who is in Red's")
	t.eq(s.waiting(), ["Brutus"], "who is out")
	t.check(not s.ready() and s.why_not().contains("Brutus"), "not ready, and why (%s)" % s.why_not())
	s.set_place(7, "Brutus", TeamSetup.CENTRES[1].x, TeamSetup.CENTRES[1].z)
	t.check(s.ready() and s.why_not() == "", "everyone in a circle: ready")
	t.eq(s.assignment(), {1: 0, 7: 1}, "the teams of each")
	s.forget(7)
	t.eq(s.assignment(), {1: 0}, "one who left is out of it")

func test_what_everyone_is_told() -> void:
	var s := TeamSetup.new("teams", {"rounds": 5})
	s.set_place(1, "Aulus", TeamSetup.CENTRES[0].x, TeamSetup.CENTRES[0].z)
	s.set_place(2, "Brutus", 0.0, 0.0)
	var st := s.state()
	t.eq(st.t, [["Aulus"], []], "who is in each circle")
	t.eq(st.w, ["Brutus"], "who is out")
	t.check(not bool(st.ok), "not ready")
	t.check(s.line(true).contains("Brutus"), "the host's line says who is awaited (%s)" % s.line(true))
	var back := TeamSetup.clean_state(st)
	t.eq(back.t, st.t, "a guest reads it back")
	s.set_place(2, "Brutus", TeamSetup.CENTRES[1].x, TeamSetup.CENTRES[1].z)
	t.check(s.line(true).contains("E"), "ready: the host is told to begin")
	t.check(not s.line(false).contains("E:"), "the guests are not")
	t.eq(TeamSetup.clean_state({}), {}, "no word: none")
	t.eq(TeamSetup.clean_state({"t": "x"}), {}, "not teams")
	var bad := TeamSetup.clean_state({"t": [["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"], 5], "w": 3, "r": INF})
	t.check((bad.t[0] as Array).size() <= TeamSetup.MOST_NAMES and bad.t[1] is Array and bad.w is Array, "made safe")
	t.eq(TeamSetup.sign_text(0, ["Aulus"]), "%s\nAulus" % TeamSetup.team_name(0).to_upper(), "the sign over a circle")

func test_the_bots_fill_the_sides() -> void:
	t.eq(TeamSetup.fill_plan([3, 1]), [1, 1], "three and one: two more for the second")
	t.eq(TeamSetup.fill_plan([0, 0]), [0, 0, 1, 1], "nobody: two a side")
	t.eq(TeamSetup.fill_plan([1, 0]), [0, 1, 1], "one and none: to two each")
	t.eq(TeamSetup.balance_plan([3, 1], 2), [1, 1], "n bots to the smaller side")
	t.eq(TeamSetup.balance_plan([0, 0], 3), [0, 1, 0], "level: alternately")
	t.eq(TeamSetup.balance_plan([2, 2], 0), [], "none asked: none")

func test_each_side_starts_on_its_half_facing_the_other() -> void:
	for n in [1, 2, 3]:
		for k in n:
			t.check(TeamSetup.spawn_pos(0, k, n).x < 0.0 and TeamSetup.spawn_pos(1, k, n).x > 0.0, "Red left, Blue right (%d of %d)" % [k, n])
	t.check(TeamSetup.spawn_pos(0, 0, 3).z != TeamSetup.spawn_pos(0, 1, 3).z, "each in his own place")

func test_the_fight_takes_the_teams_chosen() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "teams", "headless": true, "seed": 3, "decrees": [], "hazards": [], "teams": {1: 1, 77: 1, 78: 0},
		"peers": [{"id": 77, "name": "B", "loadout": {}}, {"id": 78, "name": "C", "loadout": {}}]})
	var by := {}
	for e in m.entities:
		by[e.team] = int(by.get(e.team, 0)) + 1
	t.eq(m.me.team, 1, "the host on the team he chose")
	t.eq(m.entities.filter(func(e): return e.kind == "remote" and e.team == 1).size(), 1, "his friend beside him")
	t.eq(m.entities.filter(func(e): return e.kind == "remote" and e.team == 0).size(), 1, "the other on the other")
	t.eq(by.get(0, 0), by.get(1, 0), "the sides are made even (%s)" % str(by))
	t.check(m.entities.filter(func(e): return e.team == 1).all(func(e): return e.f.torso.global_position.x > 0.0), "Blue starts on the right")
	t.check(m.entities.filter(func(e): return e.team == 0).all(func(e): return e.f.torso.global_position.x < 0.0), "Red on the left")
	m.queue_free()

func test_the_yard_reads_who_stands_in_a_circle() -> void:
	var m := _yard()
	var went := []
	m.station.connect(func(id): went.append(id))
	m.yard.begin_teams("teams", {"rounds": 3})
	t.check(m.yard.teams_on(), "the teams are being chosen")
	m.me.f.teleport(Vector3(0, 0, 0))
	await _steps(3)
	m.yard.update(0.2, {})
	t.eq(m.yard.team_setup.team_of(1), -1, "standing between: in none")
	t.check(not m.yard.team_setup.ready() and m.yard.team_line().contains("circle"), "not ready (%s)" % m.yard.team_line())
	m.yard.update(0.2, {"talk": true})
	t.check(not went.has("team_go"), "E does not begin it")
	m.me.f.teleport(Vector3(TeamSetup.CENTRES[1].x, 0, TeamSetup.CENTRES[1].z))
	await _steps(3)
	m.yard.update(0.2, {})
	t.eq(m.yard.team_setup.team_of(1), 1, "in Blue's")
	t.check(m.yard.team_setup.ready(), "all in a circle: ready")
	m.yard.update(0.2, {"talk": true})
	t.check(went.has("team_go"), "E begins it")
	m.yard.end_teams()
	t.check(not m.yard.teams_on(), "and the circles are taken up")
	m.queue_free()

func test_a_friend_in_the_room_must_be_in_a_circle_too() -> void:
	var m := _yard("host")
	m.add_peer(101, {"name": "Friend", "loadout": {"main": "gladius"}})
	await _steps(4)
	m.yard.begin_teams("teams", {})
	m.me.f.teleport(Vector3(TeamSetup.CENTRES[0].x, 0, TeamSetup.CENTRES[0].z))
	await _steps(3)
	m.yard.update(0.2, {})
	t.eq(m.humans().size(), 2, "two of them in the yard")
	t.check(not m.yard.team_setup.ready() and m.yard.team_setup.waiting().size() == 1, "the host alone in a circle: not ready")
	var friend = m.humans().filter(func(e): return e.kind == "remote")[0]
	friend.f.teleport(Vector3(TeamSetup.CENTRES[1].x, 0, TeamSetup.CENTRES[1].z))
	await _steps(3)
	m.yard.update(0.2, {})
	t.check(m.yard.team_setup.ready(), "both in a circle: ready")
	t.eq(m.yard.team_setup.assignment(), {1: 0, 101: 1}, "each on his own side")
	m.queue_free()

func test_a_guest_sees_what_the_host_says_of_the_teams() -> void:
	var host := _yard()
	host.yard.begin_teams("teams", {})
	host.me.f.teleport(Vector3(TeamSetup.CENTRES[0].x, 0, TeamSetup.CENTRES[0].z))
	await _steps(3)
	host.yard.update(0.2, {})
	var guest := Match.new()
	add_child(guest)
	guest.setup({"mode": "yard", "headless": true, "seed": 1, "decrees": [], "hazards": [], "role": "guest"})
	guest.guest_message("teams", host.yard.team_setup.state())
	t.check(guest.yard.teams_on(), "the circles are on his sand")
	t.check(guest.yard.team_line() != "", "and he reads the line (%s)" % guest.yard.team_line())
	guest.guest_message("teams", {})
	t.check(not guest.yard.teams_on(), "the host's word that it is over takes them up")
	host.queue_free()
	guest.queue_free()
