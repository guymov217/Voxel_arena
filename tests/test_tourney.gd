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

# ---------- The tree (user: to be seen through the tournament, to know who goes on) ----------

func test_the_tree_shows_every_round_with_the_places_not_yet_won_empty() -> void:
	var tr := Tourney.make(_four(), 5)
	var tree := tr.tree()
	t.eq(tree.size(), 2, "four: the semi-finals and the final")
	t.eq(tree[0].matches.size(), 2, "two bouts in the first round")
	t.eq(tree[1].matches.size(), 1, "one in the final")
	t.eq(tree[0].title, Loc.t("The semi-final"), "the first round is the semi-final")
	t.eq(tree[1].title, Loc.t("The final"), "the second the final")
	t.check(tree[1].matches[0].a == "" and tree[1].matches[0].b == "", "the final's places are empty until the semi-finals are won")
	t.check(tree[0].matches[0].open and not tree[0].matches[1].open, "the bout being fought is marked")
	var m := tr.open_match()
	tr.report(m, String(m.a))
	tree = tr.tree()
	t.eq(tree[1].matches[0].a, String(m.a), "the winner is in the final's first place")
	t.eq(tree[1].matches[0].b, "", "and the other place waits")
	t.check(tree[0].matches[0].w == String(m.a) and not tree[0].matches[0].open and tree[0].matches[1].open, "the mark goes on to the next bout")
	t.eq(tr.out_keys(), [String(m.b)], "the loser is the one put out")

func test_eight_make_three_rounds_and_five_a_bye_in_the_second() -> void:
	t.eq([Tourney.rounds_for(1), Tourney.rounds_for(2), Tourney.rounds_for(3), Tourney.rounds_for(4), Tourney.rounds_for(5), Tourney.rounds_for(8)], [1, 1, 2, 2, 3, 3], "the rounds of a bracket")
	var list := []
	for i in 8:
		list.append(_e("b%d" % i, "N%d" % i))
	var tr := Tourney.make(list, 2)
	var tree := tr.tree()
	t.eq(tree.map(func(r): return r.matches.size()), [4, 2, 1], "eight: four bouts, two, one")
	t.eq(tree.map(func(r): return r.title), [Loc.t("The quarter-final"), Loc.t("The semi-final"), Loc.t("The final")], "named")
	var five := Tourney.make(list.slice(0, 5), 2)
	var t5 := five.tree()
	t.eq(t5.map(func(r): return r.matches.size()), [3, 2, 1], "five: three bouts (one a bye), two, one")
	t.check(t5[0].matches[2].bye and t5[0].matches[2].w == t5[0].matches[2].a, "the odd one is through at once")
	t.check(t5[1].matches[0].a == "" and t5[1].matches[1].bye, "and the second round's last place is a bye, its man being the third bout's winner")
	t.eq(t5[1].matches[1].a, String(five.current_round()[2].winner), "who is already known")

func test_the_bracket_goes_over_the_wire_and_back_made_safe() -> void:
	var tr := Tourney.make(_four(), 5)
	var m := tr.open_match()
	tr.report(m, String(m.b))
	var back := Tourney.from_dict(JSON.parse_string(JSON.stringify(tr.to_dict())))   # (as it comes by a guest's wire: numbers are floats)
	t.eq(back.tree(), tr.tree(), "the same tree")
	t.eq(back.name_of("p1"), "Aulus", "the names")
	t.check(back.is_bot("bCato") and not back.is_bot("p1"), "who is a bot")
	t.eq(back.out_keys(), tr.out_keys(), "who is out")
	t.eq(Tourney.from_dict(null).tree().size(), 1, "nothing at all is a bracket with nothing in it")
	t.eq(Tourney.from_dict({"e": 5, "r": "x", "i": "no"}).entrants.size(), 0, "rubbish is nothing")
	var junk := Tourney.from_dict({"e": [[1, 2, 3], ["k", "n"], ["a", "A", 0], ["a", "Again", 1]], "r": [[[1, 2, 3], ["a", "b"], ["a", "b", "a"]], 7], "i": 99})
	t.eq(junk.entrants.size(), 1, "one of each key, only the real ones")
	t.eq(junk.rounds_list.size(), 1, "the real bouts only")
	t.eq(junk.round_i, 0, "the round kept within them")
	var many := []
	for i in 30:
		many.append(["k%d" % i, "N", 0])
	t.eq(Tourney.from_dict({"e": many}).entrants.size(), Tourney.MOST, "never past eight")

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

## Plays a tournament out through the menu, bout by bout (the draw puts the player's bout first or second of a round): in each bout of his the player wins, or falls in the first of
## them (`lose_first`), and in each of the others a bot falls. What each bout was, as the HUD had it, in order.
func _drive(menu: Node, lose_first := false) -> Array:
	var seen := {}
	var log := []
	var lost := false
	var t0 := Time.get_ticks_msec()
	while menu.tourney != null and Time.get_ticks_msec() - t0 < 80000:
		var m: Match = menu.match_
		if m != null and not m.over and not seen.has(m):
			seen[m] = true
			var mine: bool = m.me != null
			log.append({"mine": mine, "watching": m.watching(), "tree": m.bracket != null and m.bracket.entrants.size() == 4, "me_key": m.bracket_mine, "big": m.bracket_big_t > 0.0, "out": m.bracket.out_keys().size() if m.bracket != null else -1, "line": m.fight_status()})
			if mine:
				if lose_first and not lost:
					lost = true
					m.me.f.die("wounds")
				else:
					for e in m.entities:
						if e != m.me:
							e.f.die("wounds")
			else:
				for e in m.entities:
					if e.kind == "bot":
						e.f.die("wounds")
						break
		await get_tree().process_frame
	return log

func test_alone_against_bots_to_the_crown() -> void:
	_no_killcam()
	var menu := _menu()
	await get_tree().process_frame
	menu._tourney_begin({"mode": "tourney", "rounds": 1, "bots": -1})
	t.check(menu.tourney != null and menu.tourney.entrants.size() == 4, "four in the bracket: the player and three bots")
	var log := await _drive(menu)
	t.eq(log.size(), 3, "three bouts: the two semi-finals and the final, every one of them fought")
	t.eq(log.filter(func(b): return b.mine).size(), 2, "he is in two of them (his semi-final and the final)")
	t.check(log.filter(func(b): return not b.mine).all(func(b): return b.watching), "and looks on at the other, which two bots fight")
	t.check(log.all(func(b): return b.tree and b.me_key == "p1"), "the tree is on his HUD in every bout, his own name marked")
	t.check(log[0].big and not log[2].big, "the draw is shown large with the first bout, not with the last")
	t.eq(log.map(func(b): return b.out), [0, 1, 2], "and each bout shows who is out so far")
	t.check(String(log[2].line).contains(Loc.t("The final")) and log[2].mine, "he fights the final")
	t.check(menu.tourney == null, "the tournament is over: he is crowned")
	menu._end_match()
	menu.queue_free()
	await get_tree().process_frame

## User: whoever is not in a bout (or is out of the tournament) watches it; every bout is fought where he can see it, the bouts of bots too, to the crown.
func test_out_in_his_bout_he_looks_on_to_the_crown() -> void:
	_no_killcam()
	var menu := _menu()
	await get_tree().process_frame
	menu._tourney_begin({"mode": "tourney", "rounds": 1, "bots": -1})
	var log := await _drive(menu, true)
	t.eq(log.size(), 3, "all three bouts were fought, though he was out of it after his first")
	t.eq(log.filter(func(b): return b.mine).size(), 1, "he was in one")
	t.check(log.filter(func(b): return not b.mine).size() == 2 and log.filter(func(b): return not b.mine).all(func(b): return b.watching), "and looked on at the two others")
	t.check(not log[2].mine, "the final was one he looked on at")
	t.check(menu.tourney == null, "the tournament was played to its end")
	menu._end_match()
	menu.queue_free()
	await get_tree().process_frame
