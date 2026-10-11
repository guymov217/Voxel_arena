extends Node
## The Ludus yard (yard.js): the stations, the dummies that never fall, the shoving ring and the
## throwing boards; missions counted from a fight and paid; ranks from reputation.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_missions_and_ranks() -> void:
	var ms := Yard.roll_missions(7)
	t.eq(ms.size(), 3, "three missions for the next fight")
	var ids := ms.map(func(x): return x.id)
	t.check(ids.size() == 3 and ids[0] != ids[1] and ids[1] != ids[2], "all different")
	var mine := [{"id": "kill2", "n": 0}, {"id": "head", "n": 0}, {"id": "survive", "n": 0}]
	var done := Yard.apply_counts(mine, {"kill": 3, "head": 2, "survive": 1})
	t.check(done.has("kill2") and done.has("survive") and not done.has("head"), "two done, the head shots are 2 of 5")
	t.eq(int(mine[1].n), 2, "progress is kept")
	var pay := Yard.payout(done, 0)
	t.eq(int(pay.coins), 55, "they pay their denarii")
	t.eq(String(Yard.rank_of(0).name), "Tiro", "a recruit")
	t.eq(String(Yard.rank_of(950).name), "Champion", "a champion")
	t.check(Yard.mission_pay(950) > 1.0, "whose missions pay more")
	t.eq(Yard.station_at(Vector3(0, 0, 11.4)), "gate", "the gate")
	t.eq(Yard.target_score(0.1), 10, "a bullseye")

func test_the_yard_plays() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "roundShield"}})
	t.check(m.yard != null and m.yard.dummies.size() == 2 and m.yard.champ != null, "two dummies and the ring champion")
	var opened := []
	m.station.connect(func(id): opened.append(id))
	m.me.f.teleport(Yard.STATIONS.market.p)
	await _steps(5)
	m.yard.update(0.01, {"grab": true})
	t.check(opened.has("market"), "G at the market opens it")
	var d = m.yard.dummies[0]
	d.blood = 1.0
	await _steps(2)
	t.check(d.alive and d.blood >= 99.0, "the dummy never falls")
	m.yard.champ.last_attacker = m.me.f
	m.yard.champ.teleport(Yard.RING.p + Vector3(5, 0, 0))
	await _steps(3)
	t.eq(m.yard.ring_outs, 1, "a ring out for the player")
	var w := m.spawn_loose_weapon(Data.preset("javelin"), Yard.TARGETS[0] + Vector3(0.05, 0, 0))
	w.linear_velocity = Vector3(6, 0, 0)
	await _steps(1)
	t.check(m.yard.best_throw >= 5, "a throw on the board scores")
	await _steps(240)
	t.check(not m.over, "the yard never ends")
	m.queue_free()
