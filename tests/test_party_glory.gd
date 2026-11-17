extends Node
## A party's own glory in the co-op campaign (PartyGlory): the crowd's favourite of a bout won,
## paid and crowned with the laurel through the next; the run's scroll; the one rudis, shared or
## fought for; and what of it comes over the wire, made safe.

var t

## The crowd's favourite: the one it loved most, above its indifference; none alone or when nobody
## gave it anything. A fifth of the prize more.
func test_the_crowd_crowns_its_favourite() -> void:
	t.eq(PartyGlory.favourite({"Ann": 55.0, "Bob": 70.0}), "Bob", "the most loved of the party")
	t.eq(PartyGlory.favourite({"Ann": 90.0}), "", "alone: no favourite of a party")
	t.eq(PartyGlory.favourite({"Ann": 20.0, "Bob": 12.0}), "", "nobody above indifference: none")
	t.eq(PartyGlory.bonus(100), 20, "a fifth of the bout's prize")
	t.eq(PartyGlory.bonus(-5), 0, "never less than nothing")

## The scroll adds the bouts up, and its honours go to whoever leads each tally.
func test_the_scroll_adds_up_the_run() -> void:
	var sc := PartyGlory.add_bout({}, {"Ann": {"kills": 2, "limbs": 1}, "Bob": {"lifts": 1}}, "Ann")
	sc = PartyGlory.add_bout(sc, {"Ann": {"kills": 1}, "Bob": {"kills": 3, "limbs": 2}}, "Bob")
	sc = PartyGlory.add_bout(sc, {"Ann": {}, "Bob": {}}, "Bob")
	t.eq([int(sc.Ann.kills), int(sc.Ann.limbs), int(sc.Ann.fav), int(sc.Ann.bouts)], [3, 1, 1, 3], "Ann's three bouts")
	t.eq([int(sc.Bob.kills), int(sc.Bob.lifts), int(sc.Bob.limbs), int(sc.Bob.fav)], [3, 1, 2, 2], "Bob's")
	var h := PartyGlory.honours(sc)
	t.eq(h.map(func(x): return "%s:%s:%d" % x), ["kills:Ann:3", "lifts:Bob:1", "limbs:Bob:2", "fav:Bob:2"], "each honour to its leader (as many as two: the first on the scroll)")
	t.eq(PartyGlory.honours(PartyGlory.add_bout({}, {"Ann": {}}, "")), [], "nothing done, no honours")

## The party's word on the one rudis: fought for only when more would fight than share.
func test_the_party_says_share_or_fight() -> void:
	t.eq(PartyGlory.verdict(["share", "fight"]), "share", "as many each: shared")
	t.eq(PartyGlory.verdict(["fight", "fight", "share"]), "fight", "more would fight")
	t.eq(PartyGlory.verdict([]), "share", "nobody spoke: shared")

## What comes over the wire of a scroll is names as names and small whole numbers only.
func test_a_scroll_from_the_wire_is_made_safe() -> void:
	var raw := {"[b]Ann[/b]": {"kills": 1e12, "lifts": "x", "limbs": -4, "fav": 2.0, "bouts": NAN}, "Bob": "nonsense"}
	for i in 12:
		raw["P%d" % i] = {"kills": i}
	var c := PartyGlory.clean(raw)
	t.check(c.has("(b)Ann(/b)") and not c.has("[b]Ann[/b]"), "no markup in a name: %s" % str(c.keys().slice(0, 3)))
	t.eq(c.get("(b)Ann(/b)", {}), {"kills": 9999, "lifts": 0, "limbs": 0, "fav": 2, "bouts": 0}, "each tally a small whole number")
	t.check(not c.has("Bob"), "a row that is not one is left out")
	t.check(c.size() <= PartyGlory.MOST, "no more than %d names (%d)" % [PartyGlory.MOST, c.size()])
	t.eq(PartyGlory.clean("nonsense"), {}, "not a scroll: an empty one")

## A party's bout won: the tallies of each of them, the favourite crowned and paid for.
func test_a_partys_bout_counts_and_crowns() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "coop": true, "stage": 1, "role": "host", "headless": true, "name": "Ann", "peers": [{"id": 2, "name": "Bob", "loadout": {"main": "axe"}}], "seed": 9})
	for e in m.enemies():
		e.erase("bot")
		e.drive = func(_e): return {"limp": true}
	var bob = m.humans().filter(func(e): return e.kind == "remote")[0]
	m._tally(m.me.f, "kills", 2)
	m._tally(bob.f, "lifts")
	m._tally(m.enemies()[0].f, "kills")   # (a foe is not on the party's scroll)
	m.spectacle.favor[m.me.f] = 40.0
	m.spectacle.favor[bob.f] = 75.0
	var said := []
	m.feed.connect(func(line): said.append(String(line)))
	var results := []
	m.finished.connect(func(r): results.append(r))
	for e in m.enemies():
		e.f.die("test")
	for i in 10:
		await get_tree().physics_frame
	t.check(results.size() == 1 and bool(results[0].won), "the bout is won")
	if results.size() == 1:
		var r: Dictionary = results[0]
		t.eq(String(r.get("favourite", "")), "Bob", "the crowd crowns Bob")
		t.eq(int((r.party as Dictionary).get("Ann", {}).get("kills", 0)), 2, "Ann's kills on the bout's tally")
		t.eq(int((r.party as Dictionary).get("Bob", {}).get("lifts", 0)), 1, "Bob's friend lifted")
		t.eq((r.party as Dictionary).size(), 2, "the party only, not its foes")
		var base := Match.paid(float(m.stage_info.get("stagePay", 30)))
		t.check(int(r.pay) >= base + PartyGlory.bonus(base), "his crown paid into the purse (%d, base %d)" % [int(r.pay), base])
	t.check(said.any(func(x): return x.contains("crowns Bob")), "the arena is told")
	m.queue_free()
	await get_tree().physics_frame

## The favourite of the bout before wears the laurel, on his own screen and on every guest's (a
## plain yes in the spawn: anything else is not one).
func test_the_favourite_wears_the_laurel() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "coop": true, "stage": 1, "role": "host", "headless": true, "name": "Ann", "crowned": "Bob", "peers": [{"id": 2, "name": "Bob", "loadout": {"main": "axe"}}], "seed": 9})
	var bob = m.humans().filter(func(e): return e.kind == "remote")[0]
	t.check(bob.f.wreath != null and is_instance_valid(bob.f.wreath), "Bob wears the laurel")
	t.check(m.me.f.wreath == null, "Ann does not")
	t.check(m._spawn_msg(bob).get("wreath") == true, "the guests are told so with his spawn")
	t.check(bob.f.head.draw_with.has(bob.f.wreath), "drawn where his head is drawn")
	t.check(bob.f.wreath.multimesh.instance_count > 0, "leaves round his head")
	m.queue_free()
	await get_tree().physics_frame
	var g := Match.new()
	add_child(g)
	g.setup({"mode": "campaign", "coop": true, "stage": 1, "role": "guest", "headless": true, "crowned": "Ann", "seed": 9})
	g.guest_spawn({"id": 40, "kind": "remote", "peer": 1, "name": "Ann", "team": 0, "pos": [0.0, 0.0, -6.0], "loadout": {"main": "gladius"}, "wreath": true})
	g.guest_spawn({"id": 41, "kind": "remote", "peer": 3, "name": "Cy", "team": 0, "pos": [1.5, 0.0, -6.0], "loadout": {"main": "gladius"}, "wreath": "yes"})
	t.check(g.entity_by_id(40).f.wreath != null, "a guest draws the laurel the host's spawn gives")
	t.check(g.entity_by_id(41).f.wreath == null, "and nothing but a plain yes")
	g.queue_free()
	await get_tree().physics_frame

## The run over: its scroll unrolled and begun anew. The ladder won by a party alone in its room:
## the rudis is his. The brawl for it won: the winner's name in the Hall of Fame and on the screen.
func test_the_scroll_and_the_one_rudis() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	await get_tree().process_frame
	var hall_was = Save.get_value("hall", [])
	Save.set_value("coop_scroll", {"Ann": {"kills": 3, "lifts": 0, "limbs": 1, "fav": 1, "bouts": 4}, "Bob": {"kills": 1, "lifts": 2, "limbs": 0, "fav": 2, "bouts": 4}})
	Save.set_value("coop_favourite", "Bob")
	menu._scroll_open("lost")
	t.check(menu.scroll_due and menu.scroll_shown.has("Ann") and menu.scroll_shown.has("Bob"), "the run's scroll to be unrolled")
	t.eq(Save.get_value("coop_scroll", null), {}, "and a new one begun")
	t.eq(String(Save.get_value("coop_favourite", "x")), "", "nobody crowned in the new run")
	menu.show_screen("scroll")
	var texts: Array = menu.find_children("*", "Label", true, false).map(func(l): return String(l.text))
	t.check(texts.any(func(x): return x.contains("Ann (3)")) and texts.any(func(x): return x.contains("Bob (2)")), "its honours read out")
	# The ladder won with nobody else in the room: the rudis is the party's, shared.
	Save.set_value("coop_scroll", {"Ann": {"bouts": 64}, "Bob": {"bouts": 64}})
	menu._rudis_open(12, 64)
	t.eq(String(menu.screen), "campaign_end", "no vote alone in the room")
	t.eq(menu.rudis_end.get("shared", []), ["Ann", "Bob"], "the glory shared")
	t.check((Save.get_value("hall", []) as Array).any(func(h): return String(h.name) == "Ann & Bob"), "their names together in the Hall of Fame")
	# A vote that is not one is not counted.
	menu.scroll_why = "won"
	menu.rudis_end = {}
	menu.rudis_votes = {}
	menu.rudis_take(1, "both")
	t.eq(menu.rudis_votes, {}, "neither share nor fight: nothing")
	# The brawl for it won by Bob.
	menu._rudis_won("Bob")
	texts = menu.find_children("*", "Label", true, false).map(func(l): return String(l.text))
	t.check(texts.any(func(x): return x.contains("Bob took the one rudis")), "Bob took it: %s" % str(texts.slice(0, 3)))
	t.check((Save.get_value("hall", []) as Array).any(func(h): return String(h.name) == "Bob"), "his name in the Hall of Fame")
	# What a host says of it over the wire, made safe on a guest's screen.
	menu._on_net("campaign_end", {"winner": "[color=red]Eve[/color]"}, 1)
	t.eq(String(menu.rudis_end.get("winner", "")), "(color=red)Eve(/color)", "a name as a name")
	menu._on_net("scroll", {"s": {"Zed": {"kills": "lots"}}}, 1)
	t.eq(menu.scroll_shown, {"Zed": {"kills": 0, "lifts": 0, "limbs": 0, "fav": 0, "bouts": 0}}, "a scroll as a scroll")
	Save.set_value("hall", hall_was)
	menu._end_match()
	menu.queue_free()
	await get_tree().process_frame
