extends Node
## Bread & Circuses (campaign.js, blessings.js, boutRules.js): the run from day to day, the gods,
## the ludus, the Hall of Fame, and each special bout played headless.

var t

func _bout(day: int, i: int) -> Dictionary:
	return Circus.bout_at(day, i)

func _find(type: String) -> Dictionary:
	for d in Circus.days():
		for b in d.bouts:
			if b.get("type", "") == type:
				return b
	return {}

func _match(bout: Dictionary) -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "circus", "headless": true, "seed": 5, "decrees": [], "hazards": BoutRules.hazards_for(bout),
		"loadout": {"main": "gladius", "off": "roundShield"}, "circus": {"bout": bout, "day": 0, "bout_index": 0}})
	return m

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_a_run_goes_from_day_to_day_and_ends() -> void:
	t.eq(Circus.days().size(), 7, "seven days")
	t.check(Circus.bout_count() >= 25, "a full programme of bouts")
	var lu := Circus.empty_ludus()
	lu.levels = {"purse": 1, "bread": 2}
	var run := Circus.new_run(lu)
	t.eq(int(run.gold), 50, "the fatter purse adds 20")
	t.eq(int(run.inventory.get("bread", 0)), 2, "the bakery contract")
	var n_day0: int = Circus.days()[0].bouts.size()
	for i in n_day0 - 1:
		t.eq(Circus.finish(run, true, 1, 10), "next", "the next bout")
	t.eq(Circus.finish(run, true, 1, 10), "dayEnd", "the day is done")
	t.eq(int(run.day), 1, "day II")
	t.eq(run.pending_blessing.size(), 3, "three gods offer a blessing")
	t.check(Circus.grant(run, run.pending_blessing[0]) and run.pending_blessing.is_empty(), "one is taken")
	t.check(int(run.gold) > 50, "the pay went into the purse")
	# Pluto sends you back once a day.
	run.blessings.append("pluto")
	t.eq(Circus.finish(run, false, 0, 0), "spared", "Pluto says no")
	t.eq(Circus.finish(run, false, 0, 0), "wipe", "but only once a day")
	t.check(run.over and not run.won, "the run is over")
	var payout := Circus.payout(run)
	t.check(payout > 0, "the ludus keeps a share")
	var hall := Circus.hall_add([], "Maximus", run, "a goose")
	t.eq(hall.size(), 1, "the Hall of Fame remembers")
	t.eq(String(hall[0].fate), "a goose", "and how he fell")

func test_the_last_bout_crowns_the_champion() -> void:
	var run := Circus.new_run(Circus.empty_ludus())
	run.day = 6
	run.bout = Circus.days()[6].bouts.size() - 1
	t.eq(Circus.finish(run, true, 3, 100), "victory", "the Emperor falls")
	t.check(run.won and run.over, "crowned")
	t.check(Circus.payout(run) >= 200, "the crown is worth 200")

func test_the_gods_and_the_ludus() -> void:
	var run := Circus.new_run(Circus.empty_ludus())
	run.blessings = ["mars", "mercury"]
	var bm := Circus.blessing_mods(run, RandomNumberGenerator.new())
	t.check(absf(float(bm.mods.strength) - 1.25) < 0.001 and absf(float(bm.mods.speed) - 1.25) < 0.001, "Mars and Mercury")
	run.blessings = ["fortuna"]
	t.check(Circus.blessing_mods(run, RandomNumberGenerator.new()).fortune != null, "Fortuna spins her wheel")
	var lu := Circus.empty_ludus()
	t.eq(Circus.buy_upgrade(lu, "purse"), "Not enough denarii", "the ludus is not free")
	lu.denarii = 1000
	t.eq(Circus.buy_upgrade(lu, "reroll"), null, "bought")
	t.eq(Circus.buy_upgrade(lu, "reroll"), "Already maxed", "once only")
	t.eq(Circus.scaled_enemies(_bout(0, 0), 3).size(), _bout(0, 0).enemies.size() + 2, "one more enemy per extra player")

func test_an_ordinary_bout_is_won_when_the_enemies_fall() -> void:
	var b := _bout(0, 0)
	var m := _match(b)
	t.eq(m.enemies().size(), b.enemies.size(), "the drunk with a fish")
	var res := []
	m.finished.connect(func(r): res.append(r))
	for e in m.enemies():
		e.f.die("wounds")
	await _steps(3)
	t.check(not res.is_empty() and res[0].won and res[0].get("circus", false), "victory")
	t.check(m.circus_status().begins_with("Day I"), "the HUD knows the day")
	m.queue_free()

func test_gold_rush_and_the_chariots_are_won_on_the_clock() -> void:
	var m := _match(_find("goldrush"))
	await _steps(120)
	t.check(m.items.list.any(func(it): return it.type == "coin"), "gold rains")
	m.rules.on_coin(m.me.f)
	t.eq(m.rules.coins, 1, "a coin for the player")
	m.rules.t = 999.0
	var res := []
	m.finished.connect(func(r): res.append(r))
	await _steps(3)
	t.check(not res.is_empty() and res[0].won and int(res[0].coins) == 1, "time is up, the gold is counted")
	m.queue_free()
	var c := _match(_find("chariots"))
	t.eq(c.hazards.list.filter(func(h): return h.type == "chariot").size(), 2, "two chariots")
	c.queue_free()

func test_the_senator_must_cross_alive() -> void:
	var m := _match(_find("escort"))
	t.check(m.rules.senator != null, "Senator Pompous")
	var x0: float = m.rules.senator.torso.global_position.x
	await _steps(240)
	t.check(m.rules.senator.torso.global_position.x > x0 + 0.3, "he wanders toward the far gate")
	var res := []
	m.finished.connect(func(r): res.append(r))
	m.rules.senator.die("wounds")
	await _steps(3)
	t.check(not res.is_empty() and not res[0].won, "a dead senator loses the bout")
	m.queue_free()

func test_hold_the_circle_and_hot_potato() -> void:
	var m := _match(_find("hold"))
	for e in m.enemies():
		e.f.die("wounds")
	m.me.f.teleport(Vector3.ZERO)
	await _steps(30)
	t.check(m.rules.circle.fill > 0.0, "alone in the circle, the crowd warms up")
	m.queue_free()
	var p := _match(_find("potato"))
	p.rules.bomb.wait = 0.0
	await _steps(2)
	t.check(p.rules.bomb.holder != null, "someone has the bomb")
	var h = p.rules.bomb.holder
	var other = p.entities.filter(func(e): return e.f != h and e.kind != "beast")[0].f
	p.rules.on_hit({"attacker": h, "char": other})
	t.check(p.rules.bomb.holder == other, "a hit passes it on")
	p.rules.bomb.fuse = 0.0
	await _steps(2)
	t.check(p.rules.bomb.holder == null, "and it goes off")
	p.queue_free()

func test_bring_me_his_head() -> void:
	var m := _match(_find("head"))
	var target = m.rules.head_target
	t.check(target != null and target.display_name == "Brutus II", "the insulter")
	target.die("wounds")
	await _steps(2)
	t.check(m.rules.trophy != null, "his head is on the sand")
	m.me.f.teleport(m.rules.trophy.global_position)
	await _steps(3)
	t.check(m.rules.carrier == m.me.f, "picked up")
	var res := []
	m.finished.connect(func(r): res.append(r))
	for e in m.enemies():
		if e.f.alive:
			e.f.die("wounds")
	await _steps(3)
	t.check(res.is_empty(), "killing everyone is not enough")
	m.me.f.teleport(m.rules.goal)
	await _steps(4)
	t.check(not res.is_empty() and res[0].won, "delivered to the Emperor's box")
	m.queue_free()

func test_the_emperor_changes_his_mind() -> void:
	var m := _match(_find("whims"))
	m.rules.whim_t = 0.0
	await _steps(2)
	t.check(m.decrees.size() == 1, "a decree mid-bout")
	t.eq(m.rules.whim_t > 25.0, true, "the next in 30 seconds")
	m.queue_free()
	Engine.time_scale = 1.0
