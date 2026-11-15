extends Node
## The arena gate's cards (GateScreen): a card a fight on offer, its foes the very ones the fight
## brings, picked with the pointer or the keys, through the gate or back to the yard; in a room
## each one's pick on the cards and the host leading them through, and what of it comes over the
## wire made safe.

var t

func _screen(o := {}, stage := 3) -> GateScreen:
	var holder := Control.new()
	add_child(holder)
	var opts := {"previews": false}
	for k in o:
		opts[k] = o[k]
	return GateScreen.open(holder, GateChoice.offers(stage, 7, []), stage, 1, opts)

func _gone(g: GateScreen) -> void:
	var holder := g.get_parent()
	holder.queue_free()
	await get_tree().process_frame

func _key(g: GateScreen, action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	g._unhandled_input(e)

## A card each: its kind, its foes by name and what they carry, what it pays; the crowd's fight
## says it is one more foe for double the prize.
func test_a_card_for_each_fight() -> void:
	var g := _screen()
	t.eq(g.cards.size(), 3, "three fights at the third bout's gate")
	var texts: Array = g.find_children("*", "Label", true, false).map(func(l): return String(l.text))
	t.check(texts.has(Loc.t("The ladder's bout").to_upper()) and texts.has(Loc.t("For the crowd").to_upper()), "each kind on its ribbon")
	t.check(texts.any(func(x): return x.begins_with("Armed with:")), "what the men carry")
	t.check(texts.has(Loc.t("%d denarii") % Body.bout_pay(3, true)), "the crowd's prize")
	t.check(texts.has(Loc.t("Double prize")) and texts.has(Loc.t("One more foe")), "the crowd's fight says so")
	t.check(not texts.any(func(x): return x.length() > 2 and x.split("\n").size() > 3), "no word broken a letter a line")
	await _gone(g)

## The foes on a card are the ones the fight brings: the same men by name, with the same arms,
## and the second wave as it will come through the other gate.
func test_the_cards_foes_are_the_fights_own() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	await get_tree().process_frame
	for c in [[3, 3, false], [5, 5, true], [9, 9, false], [13, 13, false]]:
		var specs := Match.bout_foes(int(c[0]), 1, int(c[1]), bool(c[2]))
		menu.start({"mode": "campaign", "stage": int(c[0]), "bout": int(c[1]), "crowd": bool(c[2])})
		var m: Match = menu.match_
		var first: Array = specs.filter(func(f): return not f.late).map(func(f): return _said(f.spec))
		var late: Array = specs.filter(func(f): return f.late).map(func(f): return _said(f.spec))
		t.eq(m.enemies().map(func(e): return _said(e.spec)), first, "bout %d%s: the first wave" % [int(c[1]), " (the crowd's)" if c[2] else ""])
		t.eq(m.late_specs.map(func(sp): return _said(sp)), late, "bout %d: the second wave" % int(c[1]))
		if not m.late_wave.is_empty():
			m._spawn_late()
			t.eq(m.enemies().slice(first.size()).map(func(e): return _said(e.spec)), late, "and it comes as shown")
		menu._end_match()
		await get_tree().process_frame
	menu.queue_free()
	await get_tree().process_frame

static func _said(sp: Dictionary) -> String:
	if String(sp.get("kind", "")) == "beast":
		return String(sp.beast)
	var lo: Dictionary = sp.get("loadout", {})
	var main = lo.get("main")
	return "%s/%s" % [String(sp.get("name", "")), String(main.get("name", "")) if main is Dictionary else ""]

## Picked with the keys, then through the gate with Enter: the screen goes dark, then the fight is
## the card's. Esc goes back.
func test_picked_and_through_the_gate() -> void:
	var g := _screen()
	t.eq(g.at, 0, "the first forward")
	_key(g, "ui_right")
	_key(g, "ui_right")
	t.eq(g.at, 2, "→ →: the third")
	_key(g, "ui_right")
	t.eq(g.at, 2, "no further than the last")
	_key(g, "ui_left")
	t.eq(g.at, 1, "←: back to the second")
	var went := []
	g.chosen.connect(func(i): went.append(i))
	_key(g, "ui_accept")
	t.check(g.done, "Enter: through the gate")
	_key(g, "ui_left")
	t.eq(g.at, 1, "and no more picking once it is")
	var t0 := Time.get_ticks_msec()
	while went.is_empty() and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	t.eq(went, [1], "the second card's fight")
	await _gone(g)
	var g2 := _screen()
	var back := []
	g2.closed.connect(func(): back.append(true))
	_key(g2, "ui_cancel")
	t.eq(back, [true], "Esc: back to the yard")
	await _gone(g2)

## A boss's day: one card, nothing to choose.
func test_a_boss_day_is_one_card() -> void:
	var g := _screen({}, 4)
	t.eq(g.cards.size(), 1, "one card")
	t.check(g.find_children("*", "Label", true, false).any(func(l): return String(l.text) == Loc.t("A boss's day").to_upper()), "a boss's day")
	await _gone(g)

## In a room: the card's button is his pick (the host is told), the party's picks on the cards and
## the one they are led to; a guest cannot lead them through, nor the host while the room is too full.
func test_a_party_picks_its_fight() -> void:
	var g := _screen({"party": true, "host": false, "mine": 0})
	var picks := []
	g.voted.connect(func(i): picks.append(i))
	g._press(2)
	t.eq([g.mine, picks], [2, [2]], "his pick: the third")
	t.eq(String((g.cards[2].go as Button).text), Loc.t("Your pick"), "and the card says so")
	g.set_votes([["Ann"], [], ["Bob", "Cy"]], 2)
	var chips: Array = (g.cards[2].chips as Node).get_children()
	t.eq(chips.size(), 3, "the party's pick and the two for it")
	var went := []
	g.chosen.connect(func(i): went.append(i))
	g._go(2)
	_key(g, "ui_accept")
	t.check(went.is_empty() and not g.done, "a guest leads nobody through")
	await _gone(g)
	var h := _screen({"party": true, "host": true, "lead_block": "Too many"})
	t.check(h.lead != null and h.lead.disabled, "too many in the room: the party is not led through")
	h._go(0)
	t.check(not h.done, "not even with the keys")
	await _gone(h)

## The party's picks at the host's: each one's the card he picked last; a pick that is not a card
## is none.
func test_the_hosts_tally_of_the_picks() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "role": "host", "headless": true, "name": "Ann", "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": [{"id": 2, "name": "Bob", "loadout": {"main": "axe"}}]})
	await get_tree().physics_frame
	var n: int = m.yard.board_texts_now.size()
	t.eq(m.yard.stands(), [-1, -1], "nobody's pick yet")
	m.yard.take_pick(2, 1)
	t.eq(m.yard.stands(), [-1, 1], "Bob picked the second on his cards")
	m.yard.take_pick(2, "1")
	t.eq(m.yard.stands(), [-1, -1], "a pick that is not a number is none")
	m.yard.take_pick(2, n)
	t.eq(m.yard.stands()[1], -1, "nor one past the cards")
	m.yard.take_pick(2, NAN)
	t.eq(m.yard.stands()[1], -1, "nor nothing at all")
	m.yard.take_pick(2, n - 1)
	var bob = m.humans().filter(func(e): return e.kind == "remote")[0]
	for i in 3:
		await get_tree().physics_frame
	t.eq(m.yard.stands()[1], n - 1, "the last card: his pick, where he stands in the yard notwithstanding (%s)" % str(bob.f.torso.global_position))
	var names: Array = m.yard.pick_names()
	t.check((names[n - 1] as Array).has("Bob"), "his name on it: %s" % str(names))
	m.queue_free()
	await get_tree().physics_frame

## What a guest is told of the gate's fights and of the party's picks, made safe.
func test_the_gate_from_the_wire_is_made_safe() -> void:
	var gi := YardPlay.clean_gate({"s": 1e9, "l": -3, "b": [[3, "ladder"], [1e9, "crowd"], ["x", "other"], [2, "dragon"], [5, "other"]]})
	t.eq(gi.get("b", []), [{"bout": 3, "kind": "ladder"}, {"bout": Ladder.BOUTS.size(), "kind": "crowd"}], "bouts as bouts, kinds as kinds, three fights at most")
	t.eq([int(gi.s), int(gi.l)], [Ladder.BOUTS.size(), 1], "the stage and the time round in bounds")
	t.eq(YardPlay.clean_gate({"b": []}), {}, "nothing to choose: nothing")
	t.eq(YardPlay.clean_gate("x"), {}, "not a gate: nothing")
	var pk := YardPlay.clean_picks({"v": [["[b]Ann[/b]", "B", "C", "D", "E"], "x", []], "l": 40})
	t.eq((pk.v[0] as Array).size(), Net.CAMPAIGN_PLAYERS, "no more names than a party holds")
	t.check(not String(pk.v[0][0]).contains("["), "a name as a name: %s" % str(pk.v[0][0]))
	t.eq(pk.v[1], [], "a card's names that are not a list: none")
	t.eq(int(pk.l), YardPlay.MOST_FIGHTS - 1, "the card they are led to is a card")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "role": "guest", "headless": true, "seed": 1, "decrees": [], "hazards": []})
	var told := []
	m.gate_picks.connect(func(): told.append(true))
	m.guest_message("yard_next", {"t": "B|X", "o": ["B|PVGNA 3\nF|Recruit"], "g": {"s": 3, "l": 1, "b": [[3, "ladder"]]}})
	t.eq(m.yard.gate_info.get("b", []), [{"bout": 3, "kind": "ladder"}], "the guest knows the fights on offer")
	m.guest_message("gate_picks", {"v": [["Ann"], ["Bob"]], "l": 1})
	t.eq([m.yard.picks_seen.get("l"), told], [1, [true]], "and the party's picks, his cards told")
	m.queue_free()
	await get_tree().physics_frame
