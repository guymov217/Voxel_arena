extends Node
## The fight chosen at the gate (GateChoice; the campaign a different way each run, user): what the
## gate offers, that a whole run wins every bout of the ladder once whatever is chosen, the
## party's choice, the bout and the crowd's fight as the match fights them, the won bouts kept with
## a checkpoint, and the gate in the yard and its cards (GateScreen) over it.

var t

## Two or three of the stretch's bouts: the ladder's own first, the crowd's fight of it, another of
## the stretch (beasts for a bout of men); a boss's day one boss, of the stretch's two.
func test_the_boards_offer_the_stretchs_bouts() -> void:
	var o: Array = GateChoice.offers(1, 7, [])
	t.eq(o.map(func(x): return String(x.kind)), ["ladder", "crowd", "other"], "the first bout: the ladder's, the crowd's and another")
	t.eq(int(o[0].bout), 1, "the ladder's own bout first")
	t.eq(int(o[1].bout), 1, "the crowd's fight is that bout")
	var other := int(o[2].bout)
	t.check(other >= 2 and other <= 8 and not GateChoice.boss_bout(other) and GateChoice.beasts(other), "the other is a beast hunt of the same stretch, no boss's (bout %d)" % other)
	t.eq(GateChoice.offers(1, 7, []), o, "the same run offers the same")
	# Won already this time round: never offered again; the first of the stretch still to win leads.
	var o2: Array = GateChoice.offers(2, 7, [1, 2])
	t.check(o2.all(func(x): return int(x.bout) != 1 and int(x.bout) != 2), "a bout won is not offered again (%s)" % str(o2))
	t.eq(int(o2[0].bout), 3, "the first of the stretch still to win leads")
	# The last bout of a stretch left: it and the crowd's fight of it.
	var last: Array = GateChoice.offers(7, 7, [1, 2, 3, 5, 6])
	t.eq(last.map(func(x): return [int(x.bout), String(x.kind)]), [[7, "ladder"], [7, "crowd"]], "the stretch's last bout left: two boards")
	# A boss's day.
	var b: Array = GateChoice.offers(4, 7, [])
	t.check(b.size() == 1 and String(b[0].kind) == "boss" and [4, 8].has(int(b[0].bout)), "a boss's day: one boss, of the stretch's two (%s)" % str(b))
	var firsts := {}
	var last_swapped := 0
	for sd in 40:
		firsts[int(GateChoice.offers(4, sd, [])[0].bout)] = true
		if int(GateChoice.offers(64, sd, [])[0].bout) != 64 or int(GateChoice.offers(60, sd, [])[0].bout) != 60:
			last_swapped += 1
	t.check(firsts.has(4) and firsts.has(8), "some runs meet the Cyclops first, some the Big Lion (%s)" % str(firsts.keys()))
	t.eq(last_swapped, 0, "the last stretch's bosses never swapped: the Dragon ends every run")
	# The Emperor is one man: no crowd's fight of his bout.
	t.check(not GateChoice.crowd_ok(63), "the Emperor's bout has no crowd's fight")

## Whatever is chosen at each board, a run wins every bout of the ladder once, every boss once, and
## always has a fight on offer.
func test_any_way_through_wins_every_bout_once() -> void:
	var n := Ladder.BOUTS.size()
	for sd in [1, 2, 3, 11, 29]:
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		var won := []
		var ok := true
		for stage in range(1, n + 1):
			var o: Array = GateChoice.offers(stage, sd * 977, won)
			if o.is_empty():
				ok = false
				break
			var pick: Dictionary = o[rng.randi_range(0, o.size() - 1)]
			var b := int(pick.bout)
			# The bout is of the stage's stretch, a boss's on a boss's day only.
			if (b - 1) / GateChoice.BAND != (stage - 1) / GateChoice.BAND or GateChoice.boss_bout(b) != GateChoice.boss_bout(stage) or won.has(b):
				ok = false
				break
			won.append(b)
		won.sort()
		t.check(ok and won == range(1, n + 1), "run %d: every bout won once, each in its stretch (%d of %d)" % [sd, won.size(), n])

## A party has the board most of them stand by; the host's when as many stand by two; nobody by
## any: the gate's own.
func test_the_party_has_the_board_most_stand_by() -> void:
	t.eq(GateChoice.majority([-1, 1, 1, 0], 3), 1, "two by the second board, one by the first")
	t.eq(GateChoice.majority([0, 1], 3), 0, "one each: the host's")
	t.eq(GateChoice.majority([2, 1, 1, 2], 3), 2, "two each: the host's")
	t.eq(GateChoice.majority([-1, 2, 1], 3), 1, "two each, the host by none: the first of them")
	t.eq(GateChoice.majority([-1, -1], 3), 0, "nobody by a board: the gate's own")
	t.eq(GateChoice.majority([5, 9], 2), 0, "a board that is not there counts for nothing")

## The stage is fought as the bout chosen: its foes, the stage's gear and prize; the crowd's fight
## one more of them for double the prize.
func test_the_bout_chosen_is_fought() -> void:
	var own := Data.stage(5)
	var other := Data.stage(5, 1, 6)
	t.eq(int(other.bout), 6, "fought as bout 6")
	var first: Array = (other.rounds as Array)[0]
	t.check(String(first[0].get("beast", "")) == "wolf", "with bout 6's foes (%s)" % str(first.map(func(f): return f.get("e", f.get("beast")))))
	t.eq(int(other.stagePay), int(own.stagePay), "for the stage's prize")
	t.eq(other.gear, own.gear, "with the stage's gear")
	var crowd := Data.stage(5, 1, 5, true)
	t.eq((crowd.rounds[0] as Array).size(), (own.rounds[0] as Array).size() + 1, "the crowd's fight: one more of them")
	t.eq(int(crowd.stagePay), int(own.stagePay) * 2, "for double the prize")
	t.eq(Body.bout_pay(5, true), Match.paid(float(own.stagePay) * 2.0) + Match.paid(float(own.roundPay) * 2.0), "and the board says so")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 5, "bout": 6, "crowd": false, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	t.eq(int(m.stage_info.get("bout", 0)), 6, "the match fights the bout chosen")
	t.check(not m.enemies().is_empty() and m.enemies().all(func(e): return e.f is Beast and String(e.f.species) == "wolf"), "against its foes")
	m.queue_free()
	await get_tree().physics_frame

## The bouts won by a checkpoint are kept with it, and a death there puts them back as they were.
func test_the_won_bouts_go_back_with_a_checkpoint() -> void:
	CampaignRun.begin("legionary")
	GateChoice.clear(false)
	for b in [1, 2, 3, 4]:
		GateChoice.mark_won(b, false)
	Save.set_value("checkpoint", 5)
	Save.set_value("stage", 5)
	CampaignRun.keep()
	GateChoice.mark_won(6, false)
	Save.set_value("stage", 6)
	t.eq(CampaignRun.fall_back(), 5, "a death goes back to bout 5")
	t.eq(GateChoice.won_list(false), [1, 2, 3, 4], "with the bouts won by then, and not the one after")
	t.eq(GateChoice.won_list(true), [], "the party's own are not touched")

## The yard: the fights on offer, chosen at the gate (no boards by it: user); E there, the gate's
## cards, and through to the one taken.
func test_the_gate_offers_its_fights() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	var offers := GateChoice.now(false)
	t.eq(m.yard.board_texts_now.size(), offers.size(), "a fight on offer for each of the gate's (%d)" % offers.size())
	t.check(String(m.yard.board_texts_now[1]).contains("K|"), "the crowd's fight says so")
	t.eq(m.yard.station_here(Yard.STATIONS.gate.p), "gate", "and the gate is the gate")
	t.eq(m.yard.stands(), [-1], "he has picked none of them")
	m.queue_free()
	await get_tree().physics_frame
	# Through the menu: E at the gate, the gate's cards; the third taken, and the bout it offered is
	# fought.
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	await get_tree().process_frame
	menu.enter_yard()
	await get_tree().process_frame
	menu._open_station("gate")
	await get_tree().process_frame
	t.check(menu.gate_screen != null and menu.gate_screen.at == 0, "E at the gate: the gate's cards, the first forward")
	t.check(menu.match_ != null and menu.match_.mode == "yard", "still in the yard while he chooses")
	if menu.gate_screen:
		menu.gate_screen._focus(2)
		menu.gate_screen._press(2)
		await _through(menu)
	t.check(menu.match_ != null and menu.match_.mode == "campaign" and int(menu.match_.stage_info.get("bout", 0)) == int(offers[2].bout), "its fight: its bout (%d)" % int(offers[2].bout))
	menu._end_match()
	menu.enter_yard()
	await get_tree().process_frame
	menu._open_station("gate")
	await get_tree().process_frame
	if menu.gate_screen:
		menu.gate_screen._focus(1)
		menu.gate_screen._press(1)
		await _through(menu)
	t.check(menu.match_ != null and bool(menu.match_.stage_info.get("crowd", false)), "the crowd's card: the crowd's fight")
	# Esc at the gate: back to the yard as it was.
	menu._end_match()
	menu.enter_yard()
	await get_tree().process_frame
	menu._open_station("gate")
	await get_tree().process_frame
	t.check(menu.gate_screen != null and menu.gate_screen.at == 0, "at the gate itself: the gate's cards, the first forward")
	if menu.gate_screen:
		menu.gate_screen.close()
	await get_tree().process_frame
	t.check(menu.gate_screen == null and not menu.visible and menu.match_ != null and menu.match_.mode == "yard" and menu.match_.input.enabled, "Esc: back in the yard, his hands on him again")
	menu._end_match()
	menu.queue_free()
	await get_tree().process_frame

## (Through the gate: the screen goes dark, then the fight.)
func _through(menu) -> void:
	var t0 := Time.get_ticks_msec()
	while menu.gate_screen != null and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	await get_tree().process_frame
