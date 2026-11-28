extends Node
## What an Arena fight offers the host to set (FightOpts): its rounds, the bots beside the players, the Emperor's decrees; and
## that the fights take them.

var t

func _match(mode: String, opts := {}) -> Match:
	var m := Match.new()
	add_child(m)
	var o := {"mode": mode, "headless": true, "seed": 3, "decrees": [], "hazards": []}
	o.merge(opts, true)
	m.setup(o)
	return m

func test_each_fight_offers_its_own_settings() -> void:
	t.eq(FightOpts.offers("ffa"), ["time", "bots", "decrees"], "the free for all: its length, bots and decrees (it is on a clock unless said: one match, no rounds)")
	t.eq(FightOpts.offers("ffa", {"time": 0}), ["time", "rounds", "bots", "decrees"], "with no clock it is played over rounds")
	t.eq(FightOpts.offers("teams"), ["time", "rounds", "bots"], "red against blue: its length, rounds and bots (no clock as it was)")
	t.eq(FightOpts.offers("teams", {"time": 5}), ["time", "bots"], "on a clock the teams too are one match")
	for k in ["hill", "lastLimb"]:
		t.eq(FightOpts.offers(k), ["rounds", "bots"], "%s: rounds and bots" % k)
	for k in ["bo3", "king", "hunt", "forgefight"]:
		t.eq(FightOpts.offers(k), ["rounds"], "%s: its rounds" % k)
	t.eq(FightOpts.offers("endless"), [], "the endless arena sets nothing here")

func test_the_numbers_on_offer() -> void:
	t.eq(FightOpts.choices("ffa", "bots"), [0, 1, 2, 3, 4, 5, 6, 7], "no bots to seven")
	t.eq(FightOpts.choices("teams", "bots"), [-1, 0, 1, 2, 3, 4, 5, 6, 7], "and, for the teams, to fill the sides")
	t.eq(FightOpts.choices("ffa", "decrees"), [0, 1, 3], "none, one or three decrees")
	t.eq(FightOpts.choices("hunt", "bots"), [], "a fight whose foes are beasts has no bots to set")
	t.eq(FightOpts.default_of("ffa", "bots"), 3, "three bots as it was")
	t.eq(FightOpts.default_of("teams", "bots"), -1, "the sides filled as they were")
	t.eq(FightOpts.default_of("ffa", "decrees"), 0, "no decrees as it was")

func test_a_setting_is_made_safe() -> void:
	t.eq(FightOpts.clean("ffa", {"time": 0, "rounds": 5, "bots": 0, "decrees": 3}), {"time": 0, "rounds": 5, "bots": 0, "decrees": 3}, "what is offered stays")
	t.eq(FightOpts.clean("ffa", {"time": 3, "rounds": 5, "bots": 0, "decrees": 3}), {"time": 3, "bots": 0, "decrees": 3}, "on a clock there are no rounds to keep")
	t.eq(FightOpts.clean("ffa", {"time": 0, "rounds": 4, "bots": 99, "decrees": 2}), {"time": 0, "rounds": 1, "bots": 3, "decrees": 0}, "what is not: the fight's own")
	t.eq(FightOpts.clean("ffa", {"bots": "many", "rounds": INF, "time": "long"}), {"time": 5, "bots": 3, "decrees": 0}, "not numbers")
	t.eq(FightOpts.clean("ffa", null), {"time": 5, "bots": 3, "decrees": 0}, "nothing at all")
	t.eq(FightOpts.clean("hunt", {"bots": 5, "decrees": 3}), {"rounds": 0}, "only what the hunt offers")
	t.eq(FightOpts.clean_value("teams", "bots", -1), -1, "the sides filled is one of the teams'")
	t.eq(FightOpts.clean_value("ffa", "bots", -1), 3, "and not the free for all's")

func test_the_bots_the_sand_holds() -> void:
	t.eq(FightOpts.bots_allowed(1, 7), 7, "one man: seven bots")
	t.eq(FightOpts.bots_allowed(8, 7), 0, "a full room fills the sand: no bots")
	t.eq(FightOpts.bots_allowed(5, 7), 3, "five in the room: three bots")
	t.eq(FightOpts.MAX_FIGHTERS, 8, "the sand holds eight")
	t.eq(FightOpts.bots_allowed(12, 5), 0, "none when the room fills it")
	t.eq(FightOpts.bots_allowed(3, -1), 0, "never below none")

func test_the_clock_is_for_the_melee_and_the_teams() -> void:
	t.eq(FightOpts.choices("ffa", "time"), [0, 3, 5, 10], "none, three, five or ten minutes")
	t.eq(FightOpts.choices("teams", "time"), [0, 3, 5, 10], "the teams too")
	t.eq(FightOpts.choices("bo3", "time"), [], "not the duel")
	t.eq(FightOpts.default_of("ffa", "time"), 5, "the melee is fought for five minutes unless said")
	t.eq(FightOpts.default_of("teams", "time"), 0, "the teams as they were")
	t.eq(FightOpts.clean_value("ffa", "time", 7), 5, "a number not on offer is the fight's own")
	t.eq(FightOpts.clean_value("ffa", "time", 0), 0, "none is one on offer")
	t.eq(FightOpts.label("ffa", "time", 0), Loc.t("Last one standing"), "no clock: the last one standing")
	t.eq(FightOpts.label("teams", "time", 0), Loc.t("Last team standing"), "the teams': the last team")
	t.eq(FightOpts.label("ffa", "time", 5), Loc.t("%d minutes") % 5, "minutes")
	t.eq(FightOpts.title("time"), Loc.t("Length"), "its name")

func test_the_words() -> void:
	t.eq(FightOpts.label("ffa", "bots", 0), Loc.t("No bots"), "none")
	t.eq(FightOpts.label("ffa", "bots", 1), Loc.t("1 bot"), "one")
	t.eq(FightOpts.label("ffa", "bots", 4), Loc.t("%d bots") % 4, "four")
	t.eq(FightOpts.label("teams", "bots", -1), Loc.t("Fill the sides"), "fill")
	t.eq(FightOpts.label("ffa", "decrees", 3), Loc.t("%d decrees") % 3, "three decrees")
	t.check(FightOpts.fighters_text(3, 2).contains("2"), "who fights")

# ---------- The fights take them ----------

func test_the_free_for_all_has_as_many_bots_as_asked() -> void:
	for n in [0, 1, 5]:
		var m := _match("ffa", {"bots": n, "peers": [{"id": 51, "name": "Friend", "loadout": {}}]})
		var bots: int = m.entities.filter(func(e): return e.kind == "bot").size()
		t.eq(bots, n, "%d bots with a friend in the room" % n)
		m.queue_free()
		await get_tree().physics_frame
	var d := _match("ffa", {"peers": [{"id": 51, "name": "Friend", "loadout": {}}]})
	t.eq(d.entities.filter(func(e): return e.kind == "bot").size(), 3, "three as it was, when none is asked")
	d.queue_free()

func test_the_players_brawl_is_the_free_for_all_with_no_bots() -> void:
	var m := _match("ffa", {"bots": 0, "peers": [{"id": 51, "name": "A", "loadout": {}}, {"id": 52, "name": "B", "loadout": {}}]})
	t.eq(m.entities.size(), 3, "the three of them, nobody else")
	var teams := {}
	for e in m.entities:
		teams[e.team] = true
	t.eq(teams.size(), 3, "each for himself")
	m.queue_free()

func test_a_lone_man_with_no_bots_still_has_a_foe() -> void:
	var m := _match("ffa", {"bots": 0})
	t.eq(m.entities.size(), 2, "a fight needs two: a bot is added")
	m.queue_free()

func test_the_bots_never_crowd_the_sand_past_what_it_holds() -> void:
	var peers := []
	for i in 7:
		peers.append({"id": 60 + i, "name": "G%d" % i, "loadout": {}})
	var m := _match("ffa", {"bots": 7, "peers": peers})
	t.eq(m.entities.size(), FightOpts.MAX_FIGHTERS, "eight players fill the sand: the bots asked for do not come")
	m.queue_free()

func test_red_against_blue_takes_its_bots() -> void:
	var m := _match("teams", {"bots": 2})
	t.eq(m.entities.filter(func(e): return e.kind == "bot").size(), 2, "two bots as asked")
	m.queue_free()
	var d := _match("teams")
	t.eq(d.entities.size(), 4, "four on the sand as it was")
	d.queue_free()

func test_the_free_for_all_is_under_the_decrees_asked_for() -> void:
	for n in [0, 1, 3]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "ffa", "headless": true, "seed": 5, "decrees_n": n, "hazards": []})
		t.eq(m.decrees.size(), n, "%d decrees" % n)
		m.queue_free()
		await get_tree().physics_frame
	t.eq(Modes.decree_count("duel", {}), 1, "the duel's one, as it was")
	t.eq(Modes.decree_count("ffa", {}), 0, "none for the free for all unless asked")
	t.eq(Modes.decree_count("ffa", {"decrees_n": 2}), 0, "a number that is not on offer: none")
