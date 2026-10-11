extends Node
## The campaign's flow: a stage's three rounds from the tables, pay, the smith's arithmetic.

var t

func test_stage_tables_match_the_web_game() -> void:
	for n in [1, 4, 8, 12, 20, 64]:
		var st := Data.stage(n, 1)
		t.eq(st.rounds.size(), 3, "stage %d has three rounds" % n)
		t.eq(st.boss, n % 4 == 0, "stage %d boss flag" % n)
		t.check(int(st.stagePay) > 0, "stage %d pays" % n)
	var more := Data.stage(6, 4)
	var one := Data.stage(6, 1)
	var count := func(st): return st.rounds.reduce(func(a, r): return a + r.size(), 0)
	t.check(count.call(more) >= count.call(one), "friends bring more enemies")

func test_enemy_specs_carry_gear() -> void:
	var m := Match.new()
	add_child(m)
	m.rng.seed = 3
	var st := Data.stage(12, 1)
	var en: Dictionary = st.rounds[0][0]
	var spec := m.enemy_spec(en, 0, 1)
	if spec.kind == "bot":
		t.check(spec.diff > 0.8, "a stage-12 man is skilled (%.2f)" % spec.diff)
		var steel := 0
		for v in spec.loadout.main.get("voxels", []):
			if v[3] == "steel":
				steel += 1
		t.check(steel > 0 or spec.loadout.main.is_empty(), "his blade is tempered to steel")
	m.queue_free()

func test_arms_buy_wear_mend() -> void:
	var a := Arms.empty()
	t.eq(a.main.name, "Training Stick", "everyone starts with a stick")
	var r := Arms.buy(a, "gladius")
	t.check(not r.has("error") and r.cost > 0, "a gladius base is for sale (%s)" % str(r.get("cost")))
	a = r.arms
	a = Arms.add_wear(a, {"R": [1, 2, 3, 999]})
	t.eq(a.wear.R.size(), 3, "chips kept, nonsense dropped")
	t.check(Arms.repair_cost(a, "R") >= 3, "mending costs")
	a = Arms.repair(a, "R").arms
	t.eq(a.wear.R.size(), 0, "mended")
	t.check(Arms.can_upgrade("whetstone", a.main), "a blade can be honed")
	var lost := Arms.add_wear(a, {"R": "lost"})
	t.check(lost.wear.R.size() > 0, "a lost weapon is chipped all over")
	t.check(Arms.buy(a, "nonsense").has("error"), "no such base")

func test_a_campaign_stage_plays_through() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "autopilot": true, "loadout": {"main": "gladius", "off": "roundShield"}, "seed": 5})
	var result := []
	m.finished.connect(func(r): result.append(r))
	var spawned := m.enemies().size()
	t.check(spawned > 0, "round 1 enemies are in the arena (%d)" % spawned)
	var rounds_seen := {0: true}
	for i in 120 * 150:
		await get_tree().physics_frame
		rounds_seen[m.round] = true
		if not result.is_empty():
			break
	t.check(not result.is_empty(), "the stage ended (round %d)" % m.round)
	if not result.is_empty():
		print("   stage 1: won=%s pay=%d rounds=%s kills=%s" % [result[0].won, result[0].pay, str(rounds_seen.keys()), str(result[0].kills)])
		if result[0].won:
			t.eq(rounds_seen.size(), 3, "all three rounds were fought")
			t.check(result[0].pay > 0, "it paid")
	m.queue_free()
