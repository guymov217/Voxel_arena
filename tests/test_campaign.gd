extends Node
## The campaign's flow: the web game's stage tables, each stage played as a single bout (one
## foe, harder every time, beasts and bosses in their turn), pay, the smith's arithmetic.

var t

func test_stage_tables_match_the_web_game() -> void:
	for n in [1, 4, 8, 12, 20, 64]:
		var st := Data.stage(n, 1)
		t.eq(Data.campaign.stages[n - 1].byPlayers["1"].rounds.size(), 3, "stage %d has three rounds in the tables" % n)
		t.eq(st.rounds.size(), 1, "stage %d is one bout" % n)
		t.eq(st.rounds[0].size(), 1, "stage %d is against one foe" % n)
		t.eq(st.boss, n % 4 == 0, "stage %d boss flag" % n)
		t.check(int(st.stagePay) > 0, "stage %d pays" % n)
	t.eq(Data.stage(5, 1).rounds[0].size(), 2, "bout 5 is a pair")
	t.eq(Data.stage(11, 1).rounds[0].size(), 3, "bout 11 is a trio")
	t.eq(Data.stage(9, 1).rounds[0].size(), 1, "a beast's bout stays one on one")
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
	for i in 120 * 240:   # long fights happen (a man down bleeds out slowly): the flow is what is tested
		await get_tree().physics_frame
		rounds_seen[m.round] = true
		if not result.is_empty():
			break
	var who := []
	for e in m.entities:
		if is_instance_valid(e.f):
			var tp: Vector3 = e.f.torso.global_position
			who.append("%s %s blood %.0f stamina %.0f at (%.1f, %.1f)" % [e.f.display_name, e.f.state, e.f.blood, e.f.stamina, tp.x, tp.z])
	t.check(not result.is_empty(), "the stage ended (round %d; %s)" % [m.round, ", ".join(who)])
	if not result.is_empty():
		print("   stage 1: won=%s pay=%d rounds=%s kills=%s" % [result[0].won, result[0].pay, str(rounds_seen.keys()), str(result[0].kills)])
		if result[0].won:
			t.eq(rounds_seen.size(), 1, "the bout was fought")
			t.check(result[0].pay > 0, "it paid")
	m.queue_free()

func test_the_ladder_brings_beasts_bosses_and_the_giant() -> void:
	var beasts := 0
	var bosses := []
	var last_diff := 0.0
	for n in range(1, 41):
		var st := Data.stage(n, 1)
		var foe: Dictionary = st.rounds[0][0]
		if foe.has("beast"):
			beasts += 1
		if st.boss:
			bosses.append(str(foe.get("e", foe.get("beast", ""))))
		var d := float(st.gear.get("diff", 1.0))
		t.check(d >= last_diff - 1e-6, "bout %d is no easier than the one before (%.2f)" % [n, d])
		last_diff = d
	t.check(beasts >= 10, "beasts come through the gate in their turn (%d of 40)" % beasts)
	t.check(bosses.has("giant") and bosses.has("cyclops") and bosses.has("dragon"), "the bosses come, the giant among them (%s)" % [bosses])

func test_coop_gives_every_friend_a_foe_and_bosses_come_alone() -> void:
	for n in [1, 2, 3, 5, 6]:
		var st := Data.stage(n, 3)
		t.eq(st.rounds.size(), 1, "co-op bout %d is one fight" % n)
		t.eq(st.rounds[0].size(), 2 + Data.pack_size(n), "three friends, a foe each (and the pack's extra men) in bout %d" % n)
	var boss := Data.stage(4, 3)
	t.eq(boss.rounds[0].size(), 1, "a boss comes alone")
	t.check(float(boss.rounds[0][0].mods.toughness) > float(Data.stage(4, 1).rounds[0][0].get("mods", {}).get("toughness", 1.0)), "and tougher for a party")

func test_the_giants_of_myth_look_the_part() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var cy: Dictionary = m.enemy_spec({"e": "cyclops"}, 0, 1)
	t.eq(String(cy.mods.get("look", "")), "cyclops", "the Cyclops has his look")
	var mino: Dictionary = m.enemy_spec({"e": "minotaur"}, 0, 1)
	t.check(mino.loadout.armor.has("mon_horns") and mino.loadout.armor.has("mon_muzzle"), "the Minotaur wears a bull's head")
	t.check(m.enemy_spec({"e": "troll"}, 0, 1).loadout.armor.has("mon_tusks"), "the troll has tusks")
	mino.pos = Vector3(3, 0.1, 3)
	var e = m.spawn_fighter(mino)
	t.check(e.f.head.get_node_or_null("Armor_mon_horns") != null, "and the horns are on his head")
	cy.pos = Vector3(-3, 0.1, 3)
	var c = m.spawn_fighter(cy)
	var white := 0
	for i in c.f.head.fx.size():
		var col: Color = c.f.head.colors[i]
		if col.r > 0.85 and col.g > 0.85 and col.b > 0.8 and c.f.head.fy[i] >= 5 and c.f.head.fy[i] <= 8:
			white += 1
	t.check(white >= 8, "one great eye in the middle of his brow (%d)" % white)
	m.queue_free()

## A weapon bought goes into a free hand; with both full the buyer picks which one is sold.
func test_buying_fills_a_free_hand_or_asks_what_to_sell() -> void:
	var a := Arms.empty()
	var r := Arms.buy(a, "gladius")
	t.eq(r.side, "R", "the stick's hand takes the first blade")
	t.eq(int(r.trade_in), 0, "the stick fetches nothing")
	a = r.arms
	r = Arms.buy(a, "dagger")
	t.eq(r.side, "L", "a second weapon goes into the free hand")
	t.eq(str(r.arms.main.name), "Gladius", "the first one is kept")
	t.eq(str(r.arms.off.name), "Dagger", "the dagger in the off hand")
	a = r.arms
	r = Arms.buy(a, "axe")
	t.check(r.has("choose") and r.choose.size() == 2, "both hands full: he is asked which to sell")
	r = Arms.buy(a, "axe", "L")
	t.eq(str(r.arms.main.name), "Gladius", "the gladius stays")
	t.eq(str(r.arms.off.name), "Axe", "the axe where the dagger was")
	t.check(int(r.trade_in) > 0 and int(r.cost) < int(Arms.base("axe").price), "the dagger is taken in part exchange")
	r = Arms.buy(a, "roundShield")
	t.eq(r.side, "L", "a shield goes on the left")
	t.eq(r.sold, ["L"], "taking the place of what was there")
	r = Arms.buy(a, "zweihander")
	t.eq(r.sold, ["R", "L"], "a two-handed sword takes both hands")
	t.check(r.arms.off == null, "nothing left in the off hand")
	var big: Dictionary = r.arms
	r = Arms.buy(big, "dagger")
	t.check(not r.has("choose") and r.side == "R", "the only thing to sell is the two-handed sword")

## A design from the gallery is made by the smith at its worth (its stuff and his labour), and
## goes in a free hand like any weapon bought; the forge on the main menu takes nothing.
func test_a_design_from_the_gallery_is_made_at_the_smith() -> void:
	var d := Data.preset("gladius").duplicate(true)
	d.name = "My blade"
	for v in d.voxels:
		if v[4] == "edge" and randi() % 2 == 0:
			v[3] = "ruby"
	var plain := Data.preset("gladius").duplicate(true)
	t.check(Arms.design_price(d) > Arms.design_price(plain), "rubies make it dearer (%d vs %d)" % [Arms.design_price(d), Arms.design_price(plain)])
	t.check(Arms.design_price(plain) >= Arms.value(plain), "the stuff and the labour")
	var r := Arms.buy_design(Arms.empty(), d)
	t.check(not r.has("error") and str(r.arms.main.name) == "My blade", "made, in the hand that held the stick")
	t.eq(int(r.cost), Arms.design_price(d), "at its price")
	t.check(Arms.buy_design(Arms.empty(), {"name": "air", "voxels": [[0, 0, 0, "steel", "edge"]]}).has("error"), "nothing without a grip")
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.workshop = true
	f.open(d, 0, func(_d, _c): pass)
	var labels: Array = f.find_children("*", "Button", true, false).map(func(b): return b.text)
	t.check(not labels.has("Take it") and not labels.has("Pay and take it") and labels.has("Save design"), "the main menu's forge saves, it does not hand over (%s)" % [labels.filter(func(x): return x.contains("ake") or x.contains("Save"))])
	f.queue_free()
