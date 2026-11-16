extends Node
## The run's scroll for one man alone (RunScroll; user: the scroll a party gets, for the single
## player too): the bouts won, the kills, the limbs he cut off and lost, the falls, the weapon that
## killed the most, counted bout by bout and read out when the run ends.

var t

func test_the_scroll_adds_up_a_lone_run() -> void:
	var s := RunScroll.add_bout({}, {"kills": 2, "cut": 3, "limbs": 1, "w:Gladius": 2}, true)
	s = RunScroll.add_bout(s, {"kills": 1, "w:Axe": 1}, true)
	s = RunScroll.add_bout(s, {"kills": 1, "limbs": 2, "w:Gladius": 1}, false)
	t.eq(int(s.bouts), 2, "two bouts won")
	t.eq(int(s.falls), 1, "one fall")
	t.eq(int(s.kills), 4, "four kills")
	t.eq(int(s.cut), 3, "three limbs cut off")
	t.eq(int(s.limbs), 3, "three of his own lost")
	t.eq(RunScroll.best_weapon(s), ["Gladius", 3], "the gladius killed the most")
	t.eq(RunScroll.best_weapon({}), [], "nothing killed, no weapon named")

func test_a_lone_campaign_bout_counts_for_his_scroll() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "name": "Ann", "seed": 9})
	for e in m.enemies():
		e.erase("bot")
		e.drive = func(_e): return {"limp": true}
	m._tally(m.me.f, "kills")
	m._tally(m.me.f, "cut", 2)
	m._tally(m.me.f, RunScroll.WEAPON + "Gladius")
	m._tally(m.enemies()[0].f, "kills")   # (a foe is not on his scroll)
	var results := []
	m.finished.connect(func(r): results.append(r))
	for e in m.enemies():
		e.f.die("test")
	for i in 10:
		await get_tree().physics_frame
	t.check(results.size() == 1 and bool(results[0].won), "the bout is won")
	if results.size() == 1:
		var party: Dictionary = results[0].get("party", {})
		t.eq(party.size(), 1, "his tally only")
		var mine: Dictionary = party.values()[0] if party.size() == 1 else {}
		t.eq(int(mine.get("kills", 0)), 1, "his kill counted")
		t.eq(int(mine.get("cut", 0)), 2, "the limbs he cut off")
		t.eq(int(mine.get(RunScroll.WEAPON + "Gladius", 0)), 1, "and the weapon that killed")
	m.queue_free()
	await get_tree().physics_frame
