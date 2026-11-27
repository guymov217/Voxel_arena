extends Node
## The report at the end of a campaign bout (BoutReport, ReportScreen; user, #346): what is counted (the damage a man dealt and took, his hardest blow, his kills...), how the money the
## crowd paid is shared among the party, the awards and the most valuable man, what comes over the wire made safe, and the screen that draws it.

var t

# ---------- The money the crowd paid ----------

func test_the_crowds_money_is_shared_by_the_favour_each_earned() -> void:
	t.eq(BoutReport.split([20.0, 55.0], 7), [2, 5], "by weight: 7 in 20:55 is 1.87 and 5.13, the odd one to the larger remainder")
	t.eq(BoutReport.split([1.0, 1.0, 1.0], 10), [4, 3, 3], "alike: the odd one to the first")
	t.eq(BoutReport.split([0.0, 0.0], 5), [3, 2], "nobody earned any favour: shared alike")
	t.eq(BoutReport.split([5.0, 0.0], 4), [4, 0], "all to the one who earned it")
	t.eq(BoutReport.split([3.0, 9.0], 0), [0, 0], "nothing to share")
	t.eq(BoutReport.split([], 9), [], "nobody to share it with")
	for amount in [1, 2, 9, 28, 100, 997]:
		var w := [13.0, 55.0, 0.0, 7.0, 31.0]
		var parts := BoutReport.split(w, amount)
		var total := 0
		for p in parts:
			total += int(p)
		t.eq(total, amount, "every denarius is given out (%d)" % amount)

func test_the_report_counts_what_each_man_did_and_won() -> void:
	var tallies := {"Ann": {"kills": 3, "dmg": 183.6, "hurt": 40.4, "big": 47.5, "hits": 9, "cut": 2, "limbs": 1, "lifts": 0}, "Bob": {"kills": 1, "dmg": 60.0, "hurt": 90.0, "big": 21.0, "hits": 4, "lifts": 2}}
	var purse := {"each": 150, "base": 100, "rounds": 20, "crowd": 24, "fav": 6, "favourite": "Bob"}
	var rep := BoutReport.build(["Ann", "Bob"], tallies, {"Ann": true, "Bob": false}, {"Ann": 40.0, "Bob": 70.0}, purse, 161.4, true)
	var ann: Dictionary = rep.rows[0]
	var bob: Dictionary = rep.rows[1]
	t.eq([ann.name, int(ann.kills), int(ann.dmg), int(ann.hurt), int(ann.big), int(ann.cut), int(ann.limbs), bool(ann.alive)], ["Ann", 3, 184, 40, 48, 2, 1, true], "Ann's figures, whole numbers")
	t.eq([bob.name, int(bob.lifts), int(bob.fav), bool(bob.alive)], ["Bob", 2, 70, false], "Bob's, who fell")
	t.eq(int(ann.earned) + int(bob.earned), 24 + 6, "what the crowd paid and its favourite's bonus, all given out")
	t.eq(int(bob.earned) - 6, 17, "Bob's share by his favour: 50 of 70 above indifference, and the favourite's bonus is his")
	t.eq(int(ann.earned), 7, "Ann's: 20 of 70")
	t.eq(rep.purse, {"each": 150, "base": 100, "rounds": 20, "crowd": 24, "fav": 6, "favourite": "Bob"}, "the purse, what each takes home and what it is made of")
	t.check(absf(float(rep.secs) - 161.4) < 0.05 and bool(rep.won), "how long, and that it was won")
	# Alone: the whole of the crowd's part is his.
	var solo := BoutReport.build(["Ann"], tallies, {"Ann": true}, {"Ann": 55.0}, {"each": 130, "base": 100, "rounds": 10, "crowd": 20, "fav": 0, "favourite": ""}, 90.0, true)
	t.eq(int(solo.rows[0].earned), 20, "a man alone brought in all of it")
	# A man nothing is known of: nothing done.
	var none := BoutReport.build(["Zed"], {}, {}, {}, {}, 5.0, false)
	t.eq([int(none.rows[0].kills), int(none.rows[0].dmg), int(none.rows[0].earned), bool(none.rows[0].alive), bool(none.won)], [0, 0, 0, false, false], "no tally: nothing, nobody standing, a bout lost")

# ---------- The awards ----------

func _rows(list: Array) -> Array:
	return list.map(func(r): return {"name": r[0], "kills": r[1], "dmg": r[2], "big": r[3], "cut": r[4], "hurt": r[5], "limbs": 0, "lifts": r[6], "fav": r[7], "earned": r[8], "alive": r[9]})

func test_the_awards_go_to_each_measures_leader() -> void:
	var rows := _rows([["Ann", 3, 180, 47, 2, 40, 0, 60, 12, true], ["Bob", 1, 220, 30, 0, 90, 2, 30, 0, true]])
	var aw := BoutReport.awards(rows)
	var by := {}
	for a in aw:
		by[a[0]] = a
	t.eq(by.kills[2], ["Ann"], "kills: Ann")
	t.eq(by.dmg[2], ["Bob"], "damage dealt: Bob")
	t.eq(by.big[2], ["Ann"], "the hardest blow: Ann")
	t.eq(by.hurt[2], ["Bob"], "the most punishment taken: Bob")
	t.eq(by.lifts[2], ["Bob"], "friends lifted: Bob")
	t.eq(by.earned[2], ["Ann"], "the crowd's money: Ann")
	t.eq(int(by.kills[3]), 3, "and by how much")
	t.check(by.kills[1] == "Slayer" and by.earned[1] == "Top earner", "each with its title")
	t.check(not by.has("limbs"), "(limbs lost is no honour)")
	# A tie shares the title; a tie of everyone, or nothing done, gives none.
	var tie := BoutReport.awards(_rows([["Ann", 2, 100, 20, 1, 10, 0, 40, 0, true], ["Bob", 2, 100, 20, 1, 10, 0, 40, 0, true]]))
	t.eq(tie.size(), 0, "men who did exactly alike are set apart by nothing")
	var share := BoutReport.leaders(_rows([["Ann", 2, 0, 0, 0, 0, 0, 20, 0, true], ["Bob", 2, 0, 0, 0, 0, 0, 20, 0, true], ["Cy", 1, 0, 0, 0, 0, 0, 20, 0, true]]), "kills")
	t.eq(share, ["Ann", "Bob"], "two at the top share it")
	t.eq(BoutReport.leaders(_rows([["Ann", 0, 0, 0, 0, 0, 0, 20, 0, true], ["Bob", 0, 0, 0, 0, 0, 0, 20, 0, true]]), "kills"), [], "nobody has any: no leader")
	t.eq(BoutReport.awards(_rows([["Ann", 5, 100, 20, 1, 10, 1, 90, 30, true]])).size(), 0, "a man alone takes no title: he is set against nobody")

func test_the_most_valuable_man_takes_the_crown() -> void:
	var rows := _rows([["Ann", 3, 180, 47, 2, 40, 0, 60, 12, true], ["Bob", 1, 220, 30, 0, 90, 2, 30, 0, true]])
	t.eq(BoutReport.mvp(rows), "Ann", "three kills and a laurel's worth outweigh forty points more of damage")
	# Standing at the end counts.
	var close := _rows([["Ann", 1, 100, 10, 0, 0, 0, 20, 0, false], ["Bob", 1, 100, 10, 0, 0, 0, 20, 0, true]])
	t.eq(BoutReport.mvp(close), "Bob", "all else alike, the one still standing")
	t.eq(BoutReport.mvp(_rows([["Ann", 1, 100, 10, 0, 0, 0, 20, 0, true], ["Bob", 1, 100, 10, 0, 0, 0, 20, 0, true]])), "", "worth the same: no crown")
	t.eq(BoutReport.mvp(_rows([["Ann", 9, 900, 90, 9, 0, 9, 90, 9, true]])), "", "a man alone is crowned over nobody")
	t.check(BoutReport.worth({"kills": 1, "alive": true, "fav": 20}) == 15.0, "a kill is ten and standing five (%.1f)" % BoutReport.worth({"kills": 1, "alive": true, "fav": 20}))
	t.check(BoutReport.worth({"fav": 10}) == 0.0, "favour under the crowd's indifference is worth nothing, not less")

# ---------- What comes over the wire ----------

func test_a_report_from_the_wire_is_made_safe() -> void:
	var rows := []
	for i in 12:
		rows.append({"name": "P%d" % i, "kills": i})
	rows.insert(0, {"name": "[b]Ann[/b]", "kills": 1e12, "dmg": "x", "hurt": -4, "big": NAN, "hits": 2.9, "alive": "yes", "fav": INF, "earned": 17.0})
	rows.insert(1, "nonsense")
	rows.insert(2, {"name": 5, "kills": 3})
	var c := BoutReport.clean({"rows": rows, "purse": {"each": 9e9, "base": "x", "rounds": -1, "crowd": 5, "fav": 2, "favourite": "[i]Bob[/i]"}, "secs": 1e12, "won": "yes"})
	t.check((c.rows as Array).size() <= BoutReport.MOST, "no more than %d men (%d)" % [BoutReport.MOST, (c.rows as Array).size()])
	var a: Dictionary = c.rows[0]
	t.check(String(a.name) == "(b)Ann(/b)", "no markup in a name (%s)" % a.name)
	t.eq([int(a.kills), int(a.dmg), int(a.hurt), int(a.big), int(a.hits), int(a.fav), int(a.earned)], [99999, 0, 0, 0, 2, 0, 17], "every figure a whole number 0..99999 (a hostile one is none)")
	t.check(a.alive == false, "standing is a plain yes: anything else is not")
	t.check(c.rows.all(func(r): return r is Dictionary and r.has("kills") and r.has("name")), "a row that is not one is left out; every one has what it must")
	t.eq(String(c.rows[1].name), "5", "a name that is a number is read as one")
	t.eq([int(c.purse.each), int(c.purse.base), int(c.purse.rounds), int(c.purse.crowd), String(c.purse.favourite)], [99999, 0, 0, 5, "(i)Bob(/i)"], "the purse, as safe")
	t.check(float(c.secs) <= 36000.0 and c.won == false, "a time within a day, and won only on a plain yes")
	for junk in ["nonsense", 5, null, [], {"rows": 5}, {"rows": [1, 2]}, {"purse": []}]:
		var e := BoutReport.clean(junk)
		t.check((e.rows as Array).is_empty() and int(e.purse.each) == 0 and float(e.secs) == 0.0, "junk is an empty report (%s)" % str(junk))
	# Clean is what it sends: a made report goes through it as it is.
	var rep := BoutReport.build(["Ann", "Bob"], {"Ann": {"kills": 2, "dmg": 55.5}, "Bob": {"lifts": 1}}, {"Ann": true, "Bob": true}, {"Ann": 50.0, "Bob": 30.0}, {"each": 90, "base": 60, "rounds": 10, "crowd": 15, "fav": 5, "favourite": "Ann"}, 61.0, true)
	var back := BoutReport.clean(rep)
	t.eq(back.rows, rep.rows, "the host's rows come out as they went in")
	t.eq(back.purse, rep.purse, "and its purse")

func test_a_clock() -> void:
	t.eq(BoutReport.clock(161.4), "2:41", "two minutes forty-one")
	t.eq(BoutReport.clock(5.0), "0:05", "seconds padded")
	t.eq(BoutReport.clock(-3.0), "0:00", "never less than nothing")
	t.eq(BoutReport.clock(3600.0), "60:00", "an hour is sixty minutes")

# ---------- The match counts ----------

func _kill_all(m: Match) -> void:
	for e in m.enemies():
		e.f.die("test")

func test_the_match_counts_a_bouts_blows_and_hands_the_report_to_its_end() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "coop": true, "stage": 1, "role": "host", "headless": true, "name": "Ann", "peers": [{"id": 2, "name": "Bob", "loadout": {"main": "axe"}}], "seed": 9})
	for e in m.enemies():
		e.erase("bot")
		e.drive = func(_e): return {"limp": true}
	var ann = m.me
	var bob = m.humans().filter(func(e): return e.kind == "remote")[0]
	var foe = m.enemies()[0]
	m._tally_hit({"char": foe.f, "attacker": ann.f, "res": {"dmg": 12.4}, "J": 30.0})
	m._tally_hit({"char": foe.f, "attacker": ann.f, "res": {"dmg": 12.4}, "J": 45.0})
	m._tally_hit({"char": foe.f, "attacker": bob.f, "res": {"dmg": 8.0}, "J": 20.0})
	m._tally_hit({"char": ann.f, "attacker": foe.f, "res": {"dmg": 30.0}, "J": 25.0})
	m._tally_hit({"char": bob.f, "attacker": ann.f, "res": {"dmg": 5.0}, "J": 50.0})
	m._tally_hit({"char": foe.f, "attacker": ann.f, "res": {"dmg": 0.0, "blocked": true}, "J": 60.0})
	m._tally_hit({"char": foe.f, "attacker": null, "res": {"dmg": 4.0}, "J": 9.0})
	var tl: Dictionary = m.party_tallies()
	t.eq([int(round(tl.Ann.dmg)), int(tl.Ann.hits), int(round(tl.Ann.big)), int(round(tl.Ann.hurt))], [25, 2, 45, 30], "Ann dealt 24.8 in two blows, her hardest 45, and took 30 from the foe")
	t.eq([int(round(tl.Bob.dmg)), int(tl.Bob.hits), int(round(tl.Bob.hurt))], [8, 1, 5], "Bob dealt 8 and took Ann's blow (5)")
	t.check(not tl.Ann.has("kills") or int(tl.Ann.kills) == 0, "(and no kill that was not made)")
	t.check(float(tl.Ann.dmg) < 25.0 + 0.5, "a friend struck is no damage dealt, a blow the shield took no blow at all (%.1f)" % float(tl.Ann.dmg))
	m.spectacle.favor[ann.f] = 40.0
	m.spectacle.favor[bob.f] = 75.0
	var results := []
	m.finished.connect(func(r): results.append(r))
	_kill_all(m)
	for i in 10:
		await get_tree().physics_frame
	t.check(results.size() == 1 and bool(results[0].won), "the bout is won")
	if results.size() == 1:
		var r: Dictionary = results[0]
		t.check(r.get("report") is Dictionary, "the result carries the bout's report")
		var rep: Dictionary = r.report
		t.eq((rep.rows as Array).map(func(x): return x.name), ["Ann", "Bob"], "the party in the order it is listed, the host first, and not its foes")
		var ra: Dictionary = rep.rows[0]
		var rb: Dictionary = rep.rows[1]
		t.eq([int(ra.dmg), int(ra.hits), int(ra.big), int(ra.hurt), bool(ra.alive)], [25, 2, 45, 30, true], "Ann's row")
		t.eq([int(rb.dmg), int(rb.hurt)], [8, 5], "Bob's")
		t.check(absi(int(ra.fav) - 40) <= 6 and absi(int(rb.fav) - 75) <= 6, "the crowd's favour for each as it ended (%d, %d)" % [int(ra.fav), int(rb.fav)])
		t.eq(int(rep.purse.each), int(r.pay), "what each takes home is the bout's pay")
		t.eq(int(rep.purse.base) + int(rep.purse.rounds) + int(rep.purse.crowd) + int(rep.purse.fav), int(rep.purse.each), "and it is made of the stage's, the rounds', the crowd's and its favourite's")
		t.eq(String(rep.purse.favourite), "Bob", "the crowd's favourite")
		t.eq(int(ra.earned) + int(rb.earned), int(rep.purse.crowd) + int(rep.purse.fav), "what the crowd paid is all won by one of them")
		t.check(int(rb.earned) >= int(rep.purse.fav), "the favourite's bonus is Bob's")
		t.check(bool(rep.won) and float(rep.secs) >= 0.0, "won, and how long it took")
		t.eq(BoutReport.clean(rep).rows, rep.rows, "it goes over the wire as it is")
	m.queue_free()
	await get_tree().physics_frame

func test_a_man_alone_has_a_report_of_his_own() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "name": "Ann", "seed": 9})
	for e in m.enemies():
		e.erase("bot")
		e.drive = func(_e): return {"limp": true}
	m._tally_hit({"char": m.enemies()[0].f, "attacker": m.me.f, "res": {"dmg": 10.0}, "J": 22.0})
	var results := []
	m.finished.connect(func(r): results.append(r))
	_kill_all(m)
	for i in 10:
		await get_tree().physics_frame
	t.check(results.size() == 1 and results[0].get("report") is Dictionary, "a bout alone has its report")
	if results.size() == 1 and results[0].get("report") is Dictionary:
		var rep: Dictionary = results[0].report
		t.eq((rep.rows as Array).size(), 1, "one man on it")
		t.eq(int(rep.rows[0].dmg), 10, "the damage he dealt")
		t.eq(BoutReport.awards(rep.rows).size(), 0, "and no titles to take")
	m.queue_free()
	await get_tree().physics_frame

func test_a_guest_is_told_the_report_and_makes_it_safe() -> void:
	var g := Match.new()
	add_child(g)
	g.setup({"mode": "campaign", "coop": true, "stage": 1, "role": "guest", "headless": true, "seed": 9})
	var results := []
	g.finished.connect(func(r): results.append(r))
	var told := {"rows": [{"name": "[b]Ann[/b]", "kills": 2, "dmg": 1e12}], "purse": {"each": 90}, "secs": 40.0, "won": true}
	g.guest_end({"won": true, "text": "Stage 1 cleared", "sub": "", "pay": 90, "report": told})
	for i in 5:
		await get_tree().physics_frame
	t.check(results.size() == 1, "the guest's bout ends")
	if results.size() == 1:
		var rep: Dictionary = results[0].get("report", {})
		t.check(rep.get("rows") is Array and (rep.rows as Array).size() == 1, "with the host's report")
		t.eq([String(rep.rows[0].name), int(rep.rows[0].kills), int(rep.rows[0].dmg), int(rep.purse.each)], ["(b)Ann(/b)", 2, 99999, 90], "made safe as it came")
	g.queue_free()
	await get_tree().physics_frame
	# A host that says nothing of it: a result without one.
	var g2 := Match.new()
	add_child(g2)
	g2.setup({"mode": "campaign", "coop": true, "stage": 1, "role": "guest", "headless": true, "seed": 9})
	var again := []
	g2.finished.connect(func(r): again.append(r))
	g2.guest_end({"won": false, "text": "You fall", "sub": "", "pay": 0})
	for i in 5:
		await get_tree().physics_frame
	t.check(again.size() == 1 and not again[0].has("report"), "no report from the host, none on the result")
	g2.queue_free()
	await get_tree().physics_frame

# ---------- The screen ----------

func _sample(n: int) -> Dictionary:
	var rows := []
	for i in n:
		rows.append({"name": "Gladiator %d" % (i + 1), "kills": i, "dmg": 40 * (i + 1), "hurt": 20 + i * 3, "big": 20 + i, "hits": 5 + i, "cut": i % 3, "limbs": 0, "lifts": 1 if i == 1 else 0, "fav": 20 + 10 * i, "earned": i, "alive": i != 1})
	return {"rows": rows, "purse": {"each": 120, "base": 90, "rounds": 10, "crowd": 15, "fav": 5, "favourite": "Gladiator 2" if n > 1 else ""}, "secs": 95.0, "won": true}

func _bars(sc: Node) -> Array:
	return sc.find_children("*", "Control", true, false).filter(func(c): return c is ReportScreen.StatBar)

func _texts(sc: Node) -> Array:
	return sc.find_children("*", "Label", true, false).map(func(l): return String(l.text))

func test_the_screen_draws_a_party_as_a_table_with_medals() -> void:
	var rep := _sample(3)
	var sc := ReportScreen.new(rep, "Gladiator 1")
	add_child(sc)
	await get_tree().process_frame
	var shown := 0
	for m in BoutReport.MEASURES:
		var any := false
		for r in rep.rows:
			if int(r.get(m[0], 0)) > 0:
				any = true
		if any or ReportScreen.ALWAYS.has(m[0]):
			shown += 1
	t.eq(_bars(sc).size(), shown * 3, "a bar for each man on each measure shown (%d measures, three men)" % shown)
	var names := _texts(sc)
	t.check(names.has("Gladiator 1") and names.has("Gladiator 2") and names.has("Gladiator 3"), "each man's name on his column")
	t.check(names.has(Loc.t("Standing")) and names.has(Loc.t("Fallen")), "who is standing and who has fallen")
	t.check(names.any(func(x): return x.contains("120")), "the purse, what each takes home (%s)" % str(names.filter(func(x): return x.contains("denarii"))))
	var medals := sc.find_children("*", "VBoxContainer", true, false).filter(func(c): return c is ReportScreen.Medal)
	t.eq(medals.size(), BoutReport.awards(rep.rows).size() + 1, "a medal for each award and the crown of the most valuable man")
	# Played out: every bar full and every row seen.
	sc.finish()
	t.check(_bars(sc).all(func(b): return b.progress == 1.0), "finished: every bar full")
	sc.queue_free()
	await get_tree().process_frame

func test_the_screen_draws_a_man_alone_as_tiles_and_a_lost_bout_without_a_purse() -> void:
	var sc := ReportScreen.new(_sample(1), "Gladiator 1")
	add_child(sc)
	await get_tree().process_frame
	t.eq(_bars(sc).size(), 0, "no bars for a man set against nobody")
	var tx := _texts(sc)
	t.check(tx.has(Loc.t("Damage dealt")) and tx.has(Loc.t("Kills")), "a tile for each thing he did")
	t.check(tx.any(func(x): return x.contains("120")), "and his purse")
	sc.queue_free()
	var lost := _sample(2)
	lost.won = false
	var sl := ReportScreen.new(lost, "")
	add_child(sl)
	await get_tree().process_frame
	t.check(not _texts(sl).any(func(x): return x.contains("denarii")), "a bout lost pays nothing and says nothing of it")
	sl.queue_free()
	# Nothing on it, or what is not a report: an empty screen, not an error.
	for junk in [{}, {"rows": []}, {"rows": "x"}]:
		var se := ReportScreen.new(junk, "")
		add_child(se)
		await get_tree().process_frame
		t.check(se.body.get_child_count() == 0, "no rows, nothing drawn (%s)" % str(junk))
		se.queue_free()
	await get_tree().process_frame

func test_eight_men_and_a_long_name_keep_to_the_panel() -> void:
	var rep := _sample(8)
	rep.rows[0].name = "Gaius Julius Caesar the Long-Named Conqueror of Gaul"
	var sc := ReportScreen.new(rep, "")
	add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	t.eq(_bars(sc).size() % 8, 0, "a bar for each of the eight on every measure shown")
	var widest := 0.0
	for c in sc.body.get_children():
		widest = maxf(widest, (c as Control).get_combined_minimum_size().x)
	t.check(widest <= 1180.0, "no row wider than the menu's panel (%.0f)" % widest)
	sc.queue_free()
	await get_tree().process_frame

func test_the_menu_shows_the_report_and_goes_on_at_a_button() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	await get_tree().process_frame
	menu.report_info = {"report": _sample(2), "title": "Stage 3 cleared"}
	menu.report_wait = true
	menu.show_screen("report")
	await get_tree().process_frame
	var tx: Array = menu.find_children("*", "Label", true, false).map(func(l): return String(l.text))
	t.check(tx.has("Stage 3 cleared"), "its heading")
	var go: Array = menu.find_children("*", "Button", true, false).filter(func(b): return String(b.text).begins_with(Loc.t("Continue")))
	t.eq(go.size(), 1, "and a button to go on")
	if go.size() == 1:
		go[0].pressed.emit()
		t.check(not menu.report_wait, "pressed, the report is let go")
	menu.queue_free()
	await get_tree().process_frame

func test_the_menu_holds_a_finished_bout_on_its_report_until_he_goes_on() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	await get_tree().process_frame
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 3, "headless": true, "name": "Ann", "seed": 9})
	menu.match_ = m
	var state := {"done": false}
	var r := {"won": true, "stage": 3, "report": _sample(2)}
	var held := func() -> void:
		await menu._report_wait(r, m)
		state.done = true
	held.call()
	await get_tree().process_frame
	t.check(not state.done and menu.report_wait and String(menu.screen) == "report", "the finished bout is held on its report")
	t.check(not m.input.enabled if m.input != null else true, "the hands are off the arena under it")
	# Space in its first moment is a key still held from the fight: no way out.
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	menu._unhandled_input(space)
	await get_tree().process_frame
	t.check(not state.done and menu.report_wait, "Space at once does not take him off it")
	menu.report_t0 -= 1000
	menu._unhandled_input(space)
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(state.done and not menu.report_wait, "Space after its first moment goes on")
	# A match put away under it (the host has moved on): it lets him go too.
	var m2 := Match.new()
	add_child(m2)
	m2.setup({"mode": "campaign", "stage": 3, "headless": true, "name": "Ann", "seed": 9})
	menu.match_ = m2
	state.done = false
	var held2 := func() -> void:
		await menu._report_wait(r, m2)
		state.done = true
	held2.call()
	await get_tree().process_frame
	t.check(not state.done and menu.report_wait, "held again")
	menu.match_ = null
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(state.done, "the match put away: the report lets go")
	m.queue_free()
	m2.queue_free()
	menu.queue_free()
	await get_tree().process_frame
