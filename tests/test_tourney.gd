extends Node
## The tournament (Tourney, and the menu that plays it out): one on one, single elimination, the winner goes on until one is crowned.

var t

func _e(key: String, name: String, peer := -1, bot := true) -> Dictionary:
	return {"key": key, "name": name, "peer": peer, "bot": bot}

func _four() -> Array:
	return [_e("p1", "Aulus", 1, false), _e("bCrixus", "Crixus"), _e("bCato", "Cato"), _e("bVeles", "Veles")]

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_four_make_two_bouts_and_a_final() -> void:
	var tr := Tourney.make(_four(), 5)
	t.eq(tr.current_round().size(), 2, "two bouts in the first round")
	t.eq(tr.in_round(), 4, "four in it")
	t.eq(tr.round_name(), Loc.t("The semi-final"), "the semi-final")
	t.check(tr.current_round().all(func(m): return String(m.b) != ""), "no byes")
	t.check(not tr.finished() and tr.champion() == "", "nobody crowned")

func test_an_odd_one_out_goes_through() -> void:
	var list := _four()
	list.append(_e("bDruso", "Druso"))
	var tr := Tourney.make(list, 3)
	var byes := tr.current_round().filter(func(m): return String(m.b) == "")
	t.eq(byes.size(), 1, "one bye")
	t.eq(String(byes[0].winner), String(byes[0].a), "he is through already")
	t.eq(tr.in_round(), 5, "five in the round")

func test_the_draw_is_the_seeds() -> void:
	var a := Tourney.make(_four(), 11)
	var b := Tourney.make(_four(), 11)
	t.eq(a.current_round(), b.current_round(), "the same seed, the same pairs")
	var differs := false
	for seed_ in range(1, 12):
		if Tourney.make(_four(), seed_).current_round() != a.current_round():
			differs = true
	t.check(differs, "another seed can draw another")

func test_the_winners_go_on_to_a_crown() -> void:
	var tr := Tourney.make(_four(), 5)
	var first := tr.current_round()
	for m in first:
		tr.report(m, String(m.a))
	t.check(tr.round_done(), "the round is done")
	t.check(tr.advance(), "the winners go on")
	t.eq(tr.in_round(), 2, "two left")
	t.eq(tr.round_name(), Loc.t("The final"), "the final")
	var fin := tr.open_match()
	t.eq([String(fin.a), String(fin.b)], [String(first[0].a), String(first[1].a)], "the winners, in order")
	tr.report(fin, String(fin.b))
	t.check(tr.finished() and tr.champion() == String(first[1].a), "crowned: the one who won the final")
	t.check(not tr.advance(), "nothing more to play")

func test_only_a_winner_of_the_bout_is_taken() -> void:
	var tr := Tourney.make(_four(), 5)
	var m := tr.open_match()
	tr.report(m, "nobody")
	t.eq(String(m.winner), "", "a name that is not in the bout does not win it")
	tr.report(m, String(m.b))
	t.eq(String(m.winner), String(m.b), "one that is does")

func test_bots_settle_their_bouts_unseen() -> void:
	var list := [_e("p1", "Aulus", 1, false), _e("p2", "Brutus", 2, false), _e("bCrixus", "Crixus"), _e("bCato", "Cato")]
	var tr := Tourney.make(list, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	tr.settle_bots(rng)
	var seen := 0
	for m in tr.current_round():
		if String(m.winner) == "":
			seen += 1
			t.check(tr.is_seen(m), "a bout left is one a player is in")
		else:
			t.check(not tr.is_seen(m) or String(m.b) == "", "one settled is bots'")
	t.check(seen >= 1, "the players' bouts are left to be fought (%d)" % seen)
	t.eq(tr.log.size(), 2 - seen, "each bout settled is told (%s)" % str(tr.log))

func test_a_player_who_leaves_forfeits() -> void:
	var tr := Tourney.make(_four(), 2)
	tr.forfeit("p1")
	var m: Dictionary = tr.current_round().filter(func(x): return String(x.a) == "p1" or String(x.b) == "p1")[0]
	t.check(String(m.winner) != "" and String(m.winner) != "p1", "the other goes on")
	t.check(tr.entrant("p1").get("gone", false), "he is marked gone")
	t.eq(tr.humans_left(), 0, "and no player is left in it")

func test_the_bracket_reads() -> void:
	var tr := Tourney.make(_four(), 5)
	var m := tr.open_match()
	tr.report(m, String(m.a))
	var lines := tr.lines()
	t.check(lines.size() >= 3 and String(lines[0]) == Loc.t("Round %d") % 1, "a heading and a line a bout")
	t.check(lines.any(func(l): return String(l).contains("✓")), "the winner is marked")
	t.check(tr.match_text(m).contains(tr.name_of(String(m.a))), "who against whom")

func test_how_big_the_bracket_is() -> void:
	t.eq(Tourney.entrant_count(1, -1), 4, "alone, filled: four")
	t.eq(Tourney.entrant_count(3, -1), 4, "three, filled: four")
	t.eq(Tourney.entrant_count(5, -1), 8, "five, filled: eight")
	t.eq(Tourney.entrant_count(8, -1), 8, "eight: eight")
	t.eq(Tourney.entrant_count(2, 0), 2, "two, no bots: two")
	t.eq(Tourney.entrant_count(1, 3), 4, "one and three bots")
	t.eq(Tourney.entrant_count(6, 7), Tourney.MOST, "never past eight")

func test_what_a_guest_names_is_made_safe() -> void:
	t.eq(Tourney.clean_entrants(null), [], "nothing")
	var c := Tourney.clean_entrants([{"key": "p1", "name": "A", "peer": 1}, {"key": "p1", "name": "Again"}, 5, {"key": 7}, {"key": "b" + "x".repeat(60), "name": "B"}])
	t.eq(c.size(), 2, "one of each key, only the real ones")
	t.check(String(c[1].key).length() <= 24, "keys kept short")

# ---------- A bout in the arena ----------

func _match(opts: Dictionary) -> Match:
	var m := Match.new()
	add_child(m)
	var o := {"mode": "tourney", "headless": true, "seed": 3, "decrees": [], "hazards": []}
	o.merge(opts, true)
	m.setup(o)
	return m

func test_a_bout_is_the_two_of_the_pair() -> void:
	var m := _match({"pair": [_e("p1", "Me", 1, false), _e("bCrixus", "Crixus")], "tourney_line": "The final · Me against Crixus",
		"peers": [{"id": 51, "name": "Watcher", "loadout": {}}]})
	t.eq(m.entities.size(), 2, "two on the sand")
	t.check(m.me != null, "the player is one of them")
	t.eq(m.entities.filter(func(e): return e.kind == "bot")[0].f.display_name, "Crixus", "his foe is the bot of the bracket")
	t.check(m.entities.all(func(e): return e.kind != "remote"), "the friend who is not in it has no fighter: he looks on")
	t.check(m.fight_status().contains("The final"), "the HUD says which bout (%s)" % m.fight_status())
	var result := []
	m.finished.connect(func(r): result.append(r))
	for e in m.entities:
		if e.kind == "bot":
			e.f.die("wounds")
	await _steps(2)
	t.check(not result.is_empty() and String(result[0].round_key) == "p1", "the bout is the player's")
	m.queue_free()

func test_a_host_not_in_the_pair_looks_on() -> void:
	var m := _match({"pair": [_e("p51", "A", 51, false), _e("p52", "B", 52, false)],
		"peers": [{"id": 51, "name": "A", "loadout": {}}, {"id": 52, "name": "B", "loadout": {}}]})
	t.check(m.me == null, "the host has no fighter in it")
	t.eq(m.entities.size(), 2, "the two friends fight")
	m.queue_free()

# ---------- The menu plays it out ----------

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

func test_alone_against_bots_to_the_crown() -> void:
	_no_killcam()
	var menu := _menu()
	await get_tree().process_frame
	menu._tourney_begin({"mode": "tourney", "rounds": 1, "bots": -1})
	t.check(menu.tourney != null and menu.tourney.entrants.size() == 4, "four in the bracket: the player and three bots")
	var first: Match = menu.match_
	t.check(first != null and first.mode == "tourney" and first.me != null, "his bout begins")
	t.check(first.fight_status().contains(Loc.t("The semi-final")), "the semi-final (%s)" % first.fight_status())
	for e in first.entities:
		if e != first.me:
			e.f.die("wounds")
	var t0 := Time.get_ticks_msec()
	while menu.match_ == first and Time.get_ticks_msec() - t0 < 9000:
		await get_tree().process_frame
	var fin: Match = menu.match_
	t.check(fin != first and fin != null and fin.mode == "tourney", "he goes on to the next bout")
	if fin != first and fin != null:
		t.check(fin.fight_status().contains(Loc.t("The final")), "the final (%s)" % fin.fight_status())
		for e in fin.entities:
			if e != fin.me:
				e.f.die("wounds")
		t0 = Time.get_ticks_msec()
		while menu.tourney != null and Time.get_ticks_msec() - t0 < 9000:
			await get_tree().process_frame
		t.check(menu.tourney == null, "the tournament is over: he is crowned")
	menu._end_match()
	menu.queue_free()
	await get_tree().process_frame

func test_out_in_the_first_bout_ends_it_for_a_lone_player() -> void:
	_no_killcam()
	var menu := _menu()
	await get_tree().process_frame
	menu._tourney_begin({"mode": "tourney", "rounds": 1, "bots": -1})
	var first: Match = menu.match_
	first.me.f.die("wounds")
	var t0 := Time.get_ticks_msec()
	while menu.tourney != null and Time.get_ticks_msec() - t0 < 9000:
		await get_tree().process_frame
	t.check(menu.tourney == null, "no player left in it: it is over")
	menu._end_match()
	menu.queue_free()
	await get_tree().process_frame
