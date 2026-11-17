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

## The scroll read "Kills 0" after two bouts won (user): the foes had been put down by the blood
## they lost after his blow, or beaten and left lying, and no killing blow was ever dealt. A foe he
## struck last is his kill however he went down.
func test_a_foe_who_bleeds_out_after_his_blow_is_his_kill() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "name": "Ann", "seed": 9})
	var foes := m.enemies()
	for e in foes:
		e.erase("bot")
		e.drive = func(_e): return {"limp": true}
		e.f.last_attacker = m.me.f
	var results := []
	m.finished.connect(func(r): results.append(r))
	for e in foes:
		e.f.die("bleed")
	for i in 10:
		await get_tree().physics_frame
	t.check(results.size() == 1 and bool(results[0].won), "the bout is won")
	if results.size() == 1:
		var mine: Dictionary = results[0].get("party", {}).values()[0]
		t.eq(int(mine.get("kills", 0)), foes.size(), "every foe he bled to death is his kill")
	m.queue_free()
	await get_tree().physics_frame

## A foe struck dead by the blow is counted once, not again when his death is read out of who struck
## him last.
func test_a_killing_blow_is_counted_once() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "name": "Ann", "seed": 9})
	var foes := m.enemies()
	for e in foes:
		e.erase("bot")
		e.drive = func(_e): return {"limp": true}
	var results := []
	m.finished.connect(func(r): results.append(r))
	for e in foes:
		var f: Fighter = e.f
		f.last_attacker = m.me.f
		f.die("test")
		m.report_hit({"kind": "hit", "p": f.torso.global_position, "dir": Vector3.DOWN, "J": 3.0, "type": "edge", "char": f, "part": f.torso, "attacker": m.me.f, "res": {}, "killed": true})
	for i in 10:
		await get_tree().physics_frame
	t.check(results.size() == 1 and bool(results[0].won), "the bout is won")
	if results.size() == 1:
		var mine: Dictionary = results[0].get("party", {}).values()[0]
		t.eq(int(mine.get("kills", 0)), foes.size(), "one kill for each foe struck down")
		t.eq(int(results[0].get("kills", {}).get(m.me.f.display_name, 0)), foes.size(), "and in the bout's own count")
	m.queue_free()
	await get_tree().physics_frame

## A beast beaten (no bite, no legs to run on) but still on its feet when the bout is won goes down
## and dies with the call, not seconds after, behind the kill cam (user, the Big Lion: "you won",
## and it stood there a few seconds longer); it is his kill.
func test_a_beast_beaten_dies_when_the_bout_is_won() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "name": "Ann", "seed": 9})
	var lion = m.spawn_beast({"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(8, 0.1, 0), "yaw": 0.0})
	var beast: Beast = lion.f
	beast.last_attacker = m.me.f
	for e in m.enemies():
		if e != lion:
			e.erase("bot")
			e.drive = func(_e): return {"limp": true}
	var results := []
	m.finished.connect(func(r): results.append(r))
	m._hold_beaten([lion])   # (out of the fight: the bout is called with it standing)
	for e in m.enemies():
		if e != lion:
			e.f.die("test")
	for i in 10:
		await get_tree().physics_frame
	t.check(results.size() == 1 and bool(results[0].won), "the bout is won")
	t.check(not beast.alive, "the beaten beast is dead with it")
	if results.size() == 1:
		var mine: Dictionary = results[0].get("party", {}).values()[0]
		t.eq(int(mine.get("kills", 0)), 1, "and it is his kill")
	m.queue_free()
	await get_tree().physics_frame
