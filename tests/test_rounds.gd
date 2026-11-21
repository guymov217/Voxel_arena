extends Node
## The rounds of a fight: each fight's own setting (Series.kind), the match of several rounds that the menu keeps between
## bouts, and what the guests are told.

var t

func _match(mode: String, opts := {}) -> Match:
	var m := Match.new()
	add_child(m)
	var o := {"mode": mode, "headless": true, "seed": 3, "decrees": [], "hazards": []}
	o.merge(opts, true)
	m.setup(o)
	return m

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _menu() -> Node:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	menu.series_look_ms = 100
	menu.series_score_ms = 100
	add_child(menu)
	return menu

func _no_killcam() -> void:
	var st: Dictionary = Save.get_value("settings", {})
	st["killcam"] = false
	Save.set_value("settings", st)

# ---------- Who a round is for ----------

func test_a_round_of_free_for_all_is_the_last_mans() -> void:
	var m := _match("ffa", {"rounds": 3, "series": Series.new(3).to_dict()})
	var result := []
	m.finished.connect(func(r): result.append(r))
	for e in m.entities:
		if e != m.me:
			e.f.die("wounds")
	await _steps(2)
	t.check(not result.is_empty(), "the round is over")
	if not result.is_empty():
		t.eq(String(result[0].round_key), Series.human_key(1), "the player's (he plays here: peer 1)")
		t.eq(String(result[0].round_name), String(m.me.f.display_name), "by name")
	m.queue_free()

func test_a_round_a_bot_wins_is_the_bots() -> void:
	var m := _match("ffa")
	var result := []
	m.finished.connect(func(r): result.append(r))
	var last = m.entities.filter(func(e): return e != m.me)[0]
	for e in m.entities:
		if e != last:
			e.f.die("wounds")
	await _steps(2)
	t.check(not result.is_empty(), "the round is over")
	if not result.is_empty():
		t.eq(String(result[0].round_key), Series.bot_key(String(last.f.display_name)), "the last bot's, by name")
	m.queue_free()

func test_a_team_fights_round_is_the_teams() -> void:
	var m := _match("teams")
	var result := []
	m.finished.connect(func(r): result.append(r))
	var mine: int = m.me.team
	for e in m.entities:
		if e.team != mine:
			e.f.die("wounds")
	await _steps(2)
	t.check(not result.is_empty(), "the round is over")
	if not result.is_empty():
		t.eq(String(result[0].round_key), Series.team_key(mine), "the player's team's")
		t.eq(String(result[0].round_name), Series.team_name(mine), "Red or Blue by name")
	m.queue_free()

func test_a_hill_round_is_the_man_who_held_it() -> void:
	var m := _match("hill")
	var result := []
	m.finished.connect(func(r): result.append(r))
	m.modes.hill.score[m.me.id] = 20.5
	await _steps(2)
	t.check(not result.is_empty(), "the round is over")
	if not result.is_empty():
		t.eq(String(result[0].round_key), Series.human_key(1), "the one who held it")
	m.queue_free()

# ---------- The fights with a count of their own ----------

func test_best_of_n_follows_the_setting() -> void:
	for n in [3, 5, 7]:
		var m := _match("bo3", {"rounds": n})
		t.eq(int(m.modes.bo3.max), n, "best of %d" % n)
		m.queue_free()
	var d := _match("bo3")
	t.eq(int(d.modes.bo3.max), 3, "three unless told otherwise")
	d.queue_free()

func test_best_of_five_is_not_over_at_two_wins() -> void:
	var m := _match("bo3", {"rounds": 5})
	var foe = m.entities[1]
	var result := []
	m.finished.connect(func(r): result.append(r))
	m.modes.bo3.wins = {m.me.id: 1}
	m.modes.bo3.round = 2
	await _steps(260)
	foe.f.blood = 10.0
	await _steps(2)
	t.eq(int(m.modes.bo3.wins.get(m.me.id, 0)), 2, "two rounds to the player")
	t.check(result.is_empty() and float(m.modes.bo3.pause) > 0.0, "and the match goes on: three are needed")
	m.queue_free()

func test_the_reign_is_as_long_as_the_setting() -> void:
	var m := _match("king", {"rounds": 3})
	t.eq(int(m.modes.king.max), 3, "a reign of three")
	var result := []
	m.finished.connect(func(r): result.append(r))
	m.modes.king.streak = 2
	for e in m.entities:
		if e != m.me:
			e.f.die("wounds")
	await _steps(2)
	t.check(m.over and not result.is_empty() and result[0].won, "the third bout held: king of the arena")
	m.queue_free()
	var d := _match("king")
	t.eq(int(d.modes.king.max), 7, "seven unless told otherwise")
	d.queue_free()

func test_the_hunt_ends_at_the_waves_asked_for() -> void:
	var m := _match("hunt", {"rounds": 3})
	t.eq(m.modes.goal_waves, 3, "three waves to clear")
	var result := []
	m.finished.connect(func(r): result.append(r))
	m.modes.wave = 3
	for b in m.entities.filter(func(e): return e.kind == "beast"):
		b.f.die("wounds")
	await _steps(2)
	t.check(m.over and not result.is_empty() and result[0].won, "the third wave cleared wins")
	m.queue_free()
	var d := _match("hunt")
	t.eq(d.modes.goal_waves, 0, "no end to it unless told")
	d.queue_free()

func test_what_the_hud_says_of_the_match() -> void:
	var s := Series.new(5)
	s.record("p1", "Aulus")
	s.record("p2", "Brutus")
	var m := _match("ffa", {"rounds": 5, "series": s.to_dict()})
	t.check(m.fight_status().contains("Round 3 of 5") and m.fight_status().contains("Aulus 1 : 1 Brutus"), "the round and the score (%s)" % m.fight_status())
	m.queue_free()
	var one := _match("ffa")
	t.check(not one.fight_status().contains("Round"), "a fight of one round says nothing of rounds")
	one.queue_free()

# ---------- The match the menu keeps ----------

func test_a_fight_of_three_rounds_starts_a_match_and_one_of_one_does_not() -> void:
	var menu := _menu()
	await get_tree().process_frame
	menu.start({"mode": "ffa", "rounds": 3})
	var m: Match = menu.match_
	t.eq(int(m.series.get("n", 0)), 3, "a match of three rounds")
	t.eq(int(menu.last_start.get("rounds", 0)), 3, "and R plays it with the same")
	menu._end_match()
	menu.start({"mode": "ffa", "rounds": 1})
	t.check(menu.match_.series.is_empty(), "one round: no match to keep")
	menu.start({"mode": "ffa", "rounds": 4})
	t.check(menu.match_.series.is_empty(), "a number the fight does not offer: its own")
	menu.start({"mode": "endless", "rounds": 5})
	t.check(menu.match_.series.is_empty(), "a fight without the setting: none")
	menu._end_match()
	menu.queue_free()
	await get_tree().process_frame

func test_a_round_won_brings_the_next() -> void:
	_no_killcam()
	var menu := _menu()
	await get_tree().process_frame
	menu.start({"mode": "ffa", "rounds": 3})
	var first: Match = menu.match_
	for e in first.entities:
		if e != first.me:
			e.f.die("wounds")
	var t0 := Time.get_ticks_msec()
	while menu.match_ == first and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	t.check(menu.match_ != first and is_instance_valid(menu.match_), "the next round began")
	if menu.match_ != first:
		var s := Series.from_dict(menu.match_.series)
		t.eq(s.played, 1, "one round played")
		t.eq(s.wins.get(Series.human_key(1), 0), 1, "to the player")
		t.eq(s.round_now(), 2, "round two")
		t.check(menu.match_.fight_status().contains("Round 2 of 3"), "on the HUD (%s)" % menu.match_.fight_status())
		t.eq(menu.match_.entities.size(), 4, "and a fresh arena: the player and three bots")
	menu._end_match()
	menu.queue_free()
	await get_tree().process_frame

func test_the_match_is_decided_when_nobody_can_catch_the_leader() -> void:
	_no_killcam()
	var menu := _menu()
	await get_tree().process_frame
	menu.start({"mode": "ffa", "rounds": 3})
	var m: Match = menu.match_
	# Round one went to the player; he wins round two as well: two of three, no third to play.
	var s := Series.from_dict(menu.last_start.get("series"))
	s.record(Series.human_key(1), "Me")
	menu.last_start.series = s.to_dict()
	var out := [-1]
	var go := func():
		out[0] = 1 if await menu._series_after({"round_key": Series.human_key(1), "round_name": "Me"}, m) else 0
	go.call()
	var t0 := Time.get_ticks_msec()
	while out[0] < 0 and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	t.eq(out[0], 0, "the match is over: the flow after a bout takes him on")
	t.check(menu.match_ == m, "no next round")
	t.check(m.series_text.contains("Me 2"), "the score he is shown (%s)" % m.series_text)
	menu._end_match()
	menu.queue_free()
	await get_tree().process_frame
