extends Node
## The Ludus yard (yard.js): the stations, the dummies that never fall, the throwing boards and
## the board of the next fight; missions counted from a fight and paid; ranks from reputation.

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
	t.check(m.yard != null and m.yard.dummies.size() == 2, "two dummies")
	var nx := Data.stage(int(Save.get_value("stage", 1)))
	t.check(m.yard.next_text.contains(String(nx.get("foe_name", "?"))), "the board by the gate names the next foe (%s)" % m.yard.next_text.replace("\n", " / "))
	t.check(m.find_children("*", "Fighter", true, false).all(func(f): return f.display_name != "Ring champion"), "no shoving ring any more")
	var opened := []
	m.station.connect(func(id): opened.append(id))
	m.me.f.teleport(Yard.STATIONS.market.p)
	await _steps(5)
	m.yard.update(0.01, {"talk": true})
	t.check(opened.has("market"), "E by the trader opens the market")
	var solid := 0
	for n in m.find_children("*", "StaticBody3D", true, false):
		if n.get_parent() != m and n.get_parent().get_parent() == m:
			solid += 1
	t.check(solid >= 3 or VoxelArt.make("smithy") == null, "the stalls stand solid (%d)" % solid)
	var d = m.yard.dummies[0]
	d.blood = 1.0
	await _steps(2)
	t.check(d.alive and d.blood >= 99.0, "the dummy never falls")
	var w := m.spawn_loose_weapon(Data.preset("javelin"), Yard.TARGETS[0] + Vector3(0.05, 0, 0))
	w.linear_velocity = Vector3(6, 0, 0)
	await _steps(1)
	t.check(m.yard.best_throw >= 5, "a throw on the board scores")
	await _steps(240)
	t.check(not m.over, "the yard never ends")
	m.queue_free()

## Training offers the campaign's foes too: the giant comes as he does in the campaign.
func test_training_brings_the_giant() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "foe:giant", "count": 1}, "decrees": [], "hazards": [], "headless": true})
	await _steps(30)
	var en: Array = m.enemies()
	t.check(en.size() == 1 and en[0].f.boss and en[0].f.S > 3.0, "the giant stands in the training ring (%s)" % [en[0].f.display_name if en.size() else "nobody"])
	m.queue_free()

## Killed in the yard (by a friend, as like as not), a player is back three seconds later.
func test_a_man_killed_in_the_yard_is_back_in_three_seconds() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "headless": true, "seed": 2, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "inventory": {"bread": 2}})
	await _steps(30)
	var old: Fighter = m.me.f
	var id: int = m.me.id
	old.head.hp = 0.0
	old.die("test")
	await _steps(int(2.5 * 120))
	t.check(m.me.f == old, "still down at two and a half seconds")
	await _steps(int(1.0 * 120))
	t.check(m.me.f != old and is_instance_valid(m.me.f) and m.me.f.alive, "up again by three and a half")
	t.eq(m.me.id, id, "the same player")
	t.eq(int(m.me.get("inventory", {}).get("bread", 0)), 2, "with his kit")
	t.eq(m.humans().size(), 1, "and only once")
	m.queue_free()
