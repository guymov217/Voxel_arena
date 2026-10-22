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
	t.check(int(r.trade_in) > 0 and int(r.cost) < Arms.base_price(Arms.base("axe")), "the dagger is taken in part exchange")
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

## Vulcanus's oddities: the same through a bout (every visit), other ones the next bout, other
## ones every run; each can be held and bought, at a little over its worth; later bouts bring
## better stuff and, now and then, gem sockets.
func test_the_smiths_oddities() -> void:
	var a := Arms.oddities(1234, 3)
	var b := Arms.oddities(1234, 3)
	t.eq(a.size(), 3, "three on the stall")
	t.check(a.map(func(d): return d.voxels.hash()) == b.map(func(d): return d.voxels.hash()), "the same on every visit through the bout")
	var other_run := Arms.oddities(98765, 3)
	var next_bout := Arms.oddities(1234, 4)
	t.check(a[0].voxels.hash() != other_run[0].voxels.hash(), "another run, other weapons")
	t.check(a[0].voxels.hash() != next_bout[0].voxels.hash(), "the next bout, other weapons")
	var shapes := {}
	for i in 3:
		shapes[a[i].voxels.hash()] = true
	t.eq(shapes.size(), 3, "no two alike on the stall")
	for d in a:
		var r := Arms.buy_design(Arms.empty(), d, "", Arms.oddity_price(d))
		t.check(not r.has("error"), "%s can be bought" % d.name)
		var plain: Dictionary = d.duplicate()
		plain.erase("oddity")
		t.check(Arms.oddity_price(d) > Arms.design_price(plain), "a one-off costs a little over its worth")
	var steel := [0, 0]
	var gems := [0, 0]
	for seed_ in 40:
		for k in 2:
			for d in Arms.oddities(seed_ * 7 + 1, [1, 12][k]):
				for v in d.voxels:
					if v[3] == "steel":
						steel[k] += 1
					if Weapon.GEMS.has(v[3]):
						gems[k] += 1
	t.check(steel[1] > steel[0], "later bouts: more steel (%d vs %d)" % [steel[1], steel[0]])
	t.check(gems[0] == 0 and gems[1] > 0, "gem sockets only later (%d at bout 1, %d at bout 12)" % gems)

## Every oddity (and every "surprise me") is one piece: no voxel off on its own in the air.
func test_every_oddity_is_one_piece() -> void:
	var bad := 0
	var n := 0
	for seed_ in 60:
		for stage in [1, 5, 12]:
			for d in Arms.oddities(seed_ * 31 + 7, stage):
				var cells := {}
				for v in d.voxels:
					cells[Vector3i(int(v[0]), int(v[1]), int(v[2]))] = [v[3], v[4]]
				n += 1
				if ForgeLib.pieces(cells).size() != 1:
					bad += 1
	t.eq(bad, 0, "all %d oddities are one piece" % n)

## The oddities have depth: not one sheet of voxels, a thickness where the kind of weapon has
## one (a blade's spine, an axe's cheeks, a mace's ball).
func test_oddities_are_not_flat() -> void:
	var flat := 0
	var n := 0
	for seed_ in 40:
		for d in Arms.oddities(seed_ * 13 + 3, 1):
			n += 1
			if not d.voxels.any(func(v): return int(v[2]) != 0):
				flat += 1
	t.check(flat <= n / 10, "hardly any flat (%d of %d)" % [flat, n])

## The price is what it can do: a club with a lead head is cheap stuff and a heavy blow, and the
## smith asks for the blow; a weapon in the shop is never cheaper than its harm either.
func test_a_weapon_costs_what_it_can_do() -> void:
	var wood := {"name": "Club", "voxels": []}
	ForgeLib.box(wood, 0, 0, 0, 5, 0, 0, "wood", "grip")
	ForgeLib.box(wood, -1, 1, 6, 12, -1, 1, "wood", "blunt")
	var lead := wood.duplicate(true)
	for v in lead.voxels:
		if v[4] == "blunt":
			v[3] = "lead"
	t.eq(Arms.value(lead), Arms.value(wood), "lead costs the smith no more than wood")
	t.check(Arms.design_price(lead) > Arms.design_price(wood) * 2, "but the lead club costs far more (%d vs %d)" % [Arms.design_price(lead), Arms.design_price(wood)])
	t.check(Arms.design_price(lead) >= Arms.power_price(lead), "at least what its blow is worth")
	for b in Arms.bases():
		t.check(Arms.base_price(b) >= Arms.power_price(Data.preset(b.key)), "%s is not sold under its worth" % b.key)

## The campaign's foes come up the ladder: at the first bout nothing better than a dagger or a
## fish, a little more every bout (weapons random, within the bout's budget), their skill rising
## too; no spear against the starting stick.
func test_foes_grow_bout_by_bout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var avg := []
	for st in [1, 3, 6, 10]:
		var tot := 0.0
		var seen := {}
		for i in 40:
			var k := Match.ladder_weapon(st, ["spear", "gladius"], rng)
			seen[k] = true
			t.check(Match.ladder_power(k) <= Match.weapon_budget(st), "bout %d: %s within its budget" % [st, k])
			tot += Match.ladder_power(k)
		avg.append(tot / 40.0)
		t.check(seen.size() >= 2, "bout %d: the weapons vary (%s)" % [st, seen.keys()])
	t.check(avg[0] < avg[1] and avg[1] < avg[2] and avg[2] < avg[3], "and grow bout by bout %s" % [avg])
	var first := []
	for i in 40:
		first.append(Match.ladder_weapon(1, ["spear"], rng))
	t.check(not first.has("spear"), "no spear at the first bout")
	t.check(Match.ladder_skill(1) < Match.ladder_skill(5) and Match.ladder_skill(5) < Match.ladder_skill(9), "their skill rises")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "seed": 3})
	for e in m.enemies():
		if e.f is Fighter and e.f.weapons.R:
			t.check(Arms.power_price(e.f.weapons.R.design) <= Match.weapon_budget(1) + 1, "in the arena too: %s" % e.f.weapons.R.design.get("name", "?"))
	m.queue_free()

## A keener edge costs more: every edge and point voxel is dearer the higher the sharpness is
## set; a blunt weapon costs the same however it is set.
func test_sharper_voxels_cost_more() -> void:
	var blade := {"kind": "weapon", "sharpness": 0.3, "voxels": [[0, 0, 0, "wood", "grip"], [0, 1, 0, "steel", "edge"], [0, 2, 0, "steel", "point"]]}
	var keen := blade.duplicate(true)
	keen.sharpness = 1.0
	t.check(Arms.value(keen) > Arms.value(blade), "honed keener, dearer (%d vs %d)" % [Arms.value(keen), Arms.value(blade)])
	t.eq(Arms.sharp_price("blunt", 1.0), 0, "a blunt voxel costs no honing")
	t.check(Arms.sharp_price("edge", 1.0) > Arms.sharp_price("edge", 0.5), "an edge costs more the keener it is")

## A new weapon from nothing starts at next to nothing: one grip block is not a smith's day.
func test_a_blank_anvil_costs_next_to_nothing() -> void:
	var blank := {"name": "New weapon", "kind": "weapon", "sharpness": 0.8, "voxels": [[0, 0, 0, "wood", "grip"]]}
	t.eq(Arms.design_price(blank), 0, "the grip block it starts from costs nothing")
	t.check(Arms.design_price(Data.preset("gladius")) > 30, "a whole gladius still costs what it is worth (%d)" % Arms.design_price(Data.preset("gladius")))

## Late in the campaign (the budget past the dearest weapon) foes still come with the strongest
## weapons, never with a dagger.
func test_late_foes_keep_strong_weapons() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var strongest := 0
	for k in Match.LADDER_WEAPONS:
		strongest = maxi(strongest, Match.ladder_power(k))
	for st in [24, 32, 48, 64]:
		var weak := 0
		for i in 40:
			var k := Match.ladder_weapon(st, [], rng)
			if Match.ladder_power(k) < strongest * 0.5:
				weak += 1
		t.eq(weak, 0, "bout %d: no weak weapon in the foes' hands" % st)

## The first bouts are gentle: the Big Lion is the first boss and the Cyclops waits for the
## eighth bout, the wolf and the boar bite less hard, and the men of bouts 2 to 4 climb slower.
func test_the_first_bouts_are_gentler() -> void:
	t.eq(String(Data.stage(4, 1).rounds[0][0].get("beast", "")), "lion", "the Big Lion is the first boss")
	t.eq(String(Data.stage(8, 1).rounds[0][0].get("e", "")), "cyclops", "the Cyclops comes at the eighth bout")
	t.check(float(Data.beasts.wolf.bite) < 22.0 and float(Data.beasts.boar.bite) < 30.0, "the wolf and the boar bite less hard")
	t.check(Match.ladder_skill(2) < 0.65 and Match.ladder_skill(4) < 0.75 and is_equal_approx(Match.ladder_skill(5), 0.8), "bouts 2 to 4 climb slower, bout 5 as before")
	t.check(float(Data.stage(3, 1).rounds[0][0].get("gear", {}).get("diff", 0.85)) <= 0.9 if Data.stage(3, 1).rounds[0][0].get("gear") is Dictionary else true, "bout 3's man is no sharper")

## A player bleeds a quarter slower than a bot from the same wounds.
func test_a_player_bleeds_slower() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "seed": 3})
	t.eq(float(m.me.f.mods.bleed), Match.PLAYER_BLEED, "the player's own bleeding")
	for e in m.enemies():
		if e.f is Fighter:
			t.eq(float(e.f.mods.bleed), 1.0, "a foe bleeds as before")
	m.queue_free()
