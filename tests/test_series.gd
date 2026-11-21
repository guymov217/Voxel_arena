extends Node
## A fight over several rounds (Series): the setting each fight offers, the score, when the match is decided, and what is told
## to the guests.

var t

func test_each_fight_offers_the_numbers_it_means() -> void:
	t.eq(Series.choices("ffa"), [1, 3, 5, 7, 9], "a free for all: rounds")
	t.eq(Series.choices("bo3"), [3, 5, 7, 9], "the duel: best of")
	t.eq(Series.choices("king"), [3, 5, 7, 9], "the king: a reign")
	t.eq(Series.choices("hunt"), [0, 3, 5, 7, 10], "the hunt: waves, or no end")
	t.eq(Series.choices("endless"), [], "the endless arena has none")
	t.eq(Series.choices("campaign"), [], "nor the campaign")
	t.eq(Series.default_rounds("ffa"), 1, "one bout unless told")
	t.eq(Series.default_rounds("bo3"), 3, "three for the duel")
	t.eq(Series.default_rounds("king"), 7, "seven for the king")
	t.eq(Series.default_rounds("hunt"), 0, "the hunt without end")

func test_every_fight_on_a_card_has_its_setting_but_the_endless_one() -> void:
	var menu := load("res://scripts/ui/menu.gd")
	for g in menu.FIGHT_GROUPS:
		for k in g[1]:
			if k == "endless":
				continue
			t.check(not FightOpts.offers(k).is_empty(), "%s has a setting" % k)
			t.check(Modes.ALL.has(k), "%s is a fight the game knows" % k)

func test_what_the_host_asked_is_made_safe() -> void:
	t.eq(Series.clean_rounds("ffa", 5), 5, "a number on offer")
	t.eq(Series.clean_rounds("ffa", 5.0), 5, "as a float over the wire")
	t.eq(Series.clean_rounds("ffa", 4), 1, "one not on offer: the fight's own")
	t.eq(Series.clean_rounds("ffa", "9"), 1, "not a number")
	t.eq(Series.clean_rounds("ffa", null), 1, "nothing")
	t.eq(Series.clean_rounds("ffa", INF), 1, "infinity")
	t.eq(Series.clean_rounds("king", 5), 5, "a reign of five")
	t.eq(Series.clean_rounds("king", 1), 7, "one is not a reign")
	t.eq(Series.clean_rounds("hunt", 0), 0, "no end")
	t.eq(Series.clean_rounds("hunt", 10), 10, "ten waves")
	t.eq(Series.clean_rounds("endless", 5), 0, "a fight with no setting")

func test_the_match_is_played_to_the_end_unless_nobody_can_catch_up() -> void:
	var s := Series.new(5)
	s.record("a", "Aulus")
	s.record("a", "Aulus")
	t.check(not s.decided(), "2 : 0 with three to play: it can turn")
	s.record("a", "Aulus")
	t.check(s.decided() and s.winner() == "a", "3 : 0 with two to play: nobody can catch him")
	t.eq(s.played, 3, "the other two are not played")

func test_all_the_rounds_are_played_when_it_stays_close() -> void:
	var s := Series.new(3)
	s.record("a", "Aulus")
	s.record("b", "Brutus")
	t.check(not s.decided(), "one each, one to play")
	s.record("b", "Brutus")
	t.check(s.decided() and s.winner() == "b", "the third decides it")

func test_level_after_the_last_round_is_played_on_then_a_draw() -> void:
	var s := Series.new(3)
	s.record("a", "Aulus")
	s.record("b", "Brutus")
	s.record("", "")
	t.check(not s.decided() and s.extra == 1, "level after three: one deciding round more")
	s.record("a", "Aulus")
	t.check(s.decided() and s.winner() == "a", "the deciding round is his")
	var d := Series.new(1)
	for i in 3:
		d.record("", "")
	t.check(d.decided() and d.winner() == "", "nobody wins one in three tries: a draw")
	t.eq(d.extra, Series.MAX_EXTRA, "no more than the deciding rounds allowed")

func test_many_players_each_have_their_rounds() -> void:
	var s := Series.new(5)
	s.record("a", "Aulus")
	s.record("b", "Brutus")
	s.record("c", "Cato")
	t.check(not s.decided(), "one each: a long way to go")
	t.eq(s.leaders(), ["a", "b", "c"], "three level")
	s.record("a", "Aulus")
	s.record("a", "Aulus")
	t.check(s.decided() and s.winner() == "a", "three rounds to Aulus of five")

func test_the_score_reads() -> void:
	var s := Series.new(5)
	s.record("a", "Aulus")
	s.record("b", "Brutus")
	s.record("a", "Aulus")
	t.eq(s.score_line(), "Aulus 2 : 1 Brutus", "two players: with the colon")
	t.eq(s.round_text(), Loc.t("Round %d of %d") % [4, 5], "the round to come")
	t.check(s.hud_line().contains("Aulus 2 : 1 Brutus") and s.hud_line().contains("Round 4 of 5"), "the HUD's line")
	s.record("c", "Cato")
	t.check(s.score_line().contains("Aulus 2") and s.score_line().contains("Brutus 1") and s.score_line().contains("Cato 1"), "three: a list")
	t.eq(Series.new(3).hud_line(), Loc.t("Round %d of %d") % [1, 3], "before any round: the round alone")

func test_teams_are_keyed_and_named() -> void:
	t.eq(Series.team_key(0), "t0", "key")
	t.eq(Series.team_name(0), Loc.t("Red"), "Red")
	t.eq(Series.team_name(1), Loc.t("Blue"), "Blue")
	t.eq(Series.human_key(1), "p1", "the host's player")
	t.check(Series.bot_key("Crixus").begins_with("b"), "a bot by name")

func test_the_wire_keeps_the_match() -> void:
	var s := Series.new(5)
	s.record("p1", "Aulus")
	s.record("t1", "Blue")
	var back := Series.from_dict(s.to_dict())
	t.eq(back.rounds, 5, "rounds")
	t.eq(back.played, 2, "played")
	t.eq(back.wins, s.wins, "wins")
	t.eq(back.name_of("t1"), "Blue", "names")
	t.eq(back.decided(), s.decided(), "and where it stands")

func test_what_a_guest_is_told_is_made_safe() -> void:
	t.eq(Series.clean(null), {}, "nothing")
	t.eq(Series.clean("x"), {}, "not a dictionary")
	t.eq(Series.clean({"n": "five"}), {}, "rounds not a number")
	t.eq(Series.clean({"n": INF}), {}, "infinite rounds")
	var c := Series.clean({"n": 99, "p": -4, "x": 50, "w": {"a": 1e9, "b": "many", 7: 2}, "nm": {"a": "Aulus"}})
	t.eq(int(c.n), Series.MOST, "rounds no more than the most")
	t.eq(int(c.p), 0, "played not below nothing")
	t.eq(int(c.x), Series.MAX_EXTRA, "deciding rounds no more than allowed")
	t.check((c.w as Dictionary).has("a") and not (c.w as Dictionary).has("b") and not (c.w as Dictionary).has(7), "only a name with a number of rounds")
	t.check(int(c.w.a) <= Series.MOST + Series.MAX_EXTRA, "rounds won within bounds")
	var many := {}
	for i in 30:
		many["k%d" % i] = 1
	t.eq((Series.clean({"n": 3, "w": many}).w as Dictionary).size(), Series.MOST_KEYS, "no more than a room's worth kept")
	var long := Series.clean({"n": 3, "w": {"x".repeat(80): 1}})
	t.check((long.w as Dictionary).keys().all(func(k): return String(k).length() <= 24), "keys kept short")
