extends Node
## The campaign's flow: the web game's stage tables, each stage played as a single bout (one
## foe, harder every time, beasts and bosses in their turn), pay, the smith's arithmetic.

var t

func test_stage_tables_match_the_web_game() -> void:
	for n in [1, 4, 8, 12, 20, 64]:
		var st := Data.stage(n, 1)
		t.eq(Data.campaign.stages[n - 1].byPlayers["1"].rounds.size(), 3, "stage %d has three rounds in the tables" % n)
		t.eq(st.rounds.size(), 1, "stage %d is one bout" % n)
		t.eq(st.boss, n % 4 == 0, "stage %d boss flag" % n)
		t.check(int(st.stagePay) > 0, "stage %d pays" % n)
	t.eq(Data.stage(26, 1).rounds[0].size(), 2, "bout 26 is a pair")
	t.eq(Data.stage(59, 1).rounds[0].size(), 3, "bout 59 is a trio")
	t.eq(Data.stage(2, 1).rounds[0].size(), 1, "a beast's bout stays one on one")
	t.eq(Data.stage(5, 1).late.size(), 1, "bout 5 keeps a man back for the other gate")
	t.eq(String(Data.stage(5, 1).foe_name), "Coward", "and the board names the first wave alone")
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

## What the bot-versus-bot survey made of each kind (tests/zz_balance: the plain swordsman's
## losses, blood lost, damage taken; see README): the ladder is checked against it.
const DANGER := {"drunk": 14, "medicus": 1, "retiarius": 1, "boar": 13, "recruit": 27, "dimachaerus": 29, "sagittarius": 30, "mimic": 41, "coward": 44,
	"wolf": 55, "hyena": 60, "ostrich": 50, "veles": 71, "hydra": 73, "berserker": 82, "executioner": 93, "dragon": 105, "cyclops": 107, "lion": 117, "brute": 118,
	"bull": 120, "flailman": 128, "emperor": 130, "tiger": 130, "shieldbearer": 143, "python": 150, "elephant": 150, "rhino": 155, "pyro": 158, "champion": 158,
	"griffin": 160, "mammoth": 163, "murmillo": 164, "praetorian": 166, "hoplite": 166, "scorpion": 171, "giant": 175, "cerberus": 177, "troll": 179, "gorilla": 180,
	"chimera": 180, "basilisk": 180, "titan": 181, "manticore": 182, "spider": 186, "bear": 188, "minotaur": 194, "crocodile": 210,
	"rat": 40}

static func _kind(en: Dictionary) -> String:
	return String(en.get("e", en.get("beast", "")))

func test_the_ladder_climbs_and_never_repeats_itself() -> void:
	var beasts := 0
	var bosses := []
	var late := 0
	var band := []   # the mean danger of the plain bouts, eight stages at a time
	var seen := {}   # every line-up so far (the kinds that come in, at once and later), and its bout
	var sum := 0.0
	var cnt := 0
	for n in range(1, 65):
		var st := Data.stage(n, 1)
		var first: Array = st.rounds[0]
		t.check(first.size() >= 1 and first.size() <= 3, "bout %d sends in one to three at once (%d)" % [n, first.size()])
		if first[0].has("beast"):
			beasts += 1
		if st.boss:
			t.eq(first.size(), 1, "the boss of bout %d comes alone" % n)
			t.check(first[0].get("boss", false), "bout %d's foe is a boss" % n)
			bosses.append(_kind(first[0]))
		else:
			t.check(not first[0].get("boss", false), "bout %d brings no boss" % n)
			var d := 0.0
			for en in first:
				d += float(DANGER.get(_kind(en), 100))
			for en in st.get("late", []):
				d += 0.6 * float(DANGER.get(_kind(en), 100))
			sum += d
			cnt += 1
		if not st.get("late", []).is_empty():
			late += 1
		# A new foe or a new company of them every bout (user): never the same line-up twice.
		var kinds := {}
		for en in first + st.get("late", []):
			kinds[_kind(en)] = true
		var key := kinds.keys()
		key.sort()
		var line := ", ".join(key)
		t.check(not seen.has(line), "bout %d is no other bout over again (%s, as bout %d)" % [n, line, int(seen.get(line, 0))])
		seen[line] = n
		if n > 1:
			var prev: Array = Data.stage(n - 1, 1).rounds[0]
			t.check(_kind(first[0]) != _kind(prev[0]) or st.boss, "bout %d is not bout %d again (%s)" % [n, n - 1, _kind(first[0])])
		if n % 8 == 0:
			band.append(sum / maxf(1.0, cnt))
			sum = 0.0
			cnt = 0
	t.eq(bosses, ["cyclops", "lion", "elephant", "giant", "griffin", "cerberus", "troll", "minotaur", "gorilla", "titan", "chimera", "mammoth", "basilisk", "manticore", "hydra", "dragon"], "sixteen bosses, none of them twice, the gentlest first, the Dragon last")
	for i in range(1, band.size()):
		t.check(band[i] > band[i - 1], "the plain bouts get harder band by band, to the end (%s)" % [band.map(func(x): return roundi(x))])
	t.check(beasts >= 20, "beasts come through the gate in their turn (%d of 64)" % beasts)
	t.check(late >= 20, "a second gate opens on many a bout (%d)" % late)
	for n in range(1, 25):
		var k := _kind(Data.stage(n, 1).rounds[0][0])
		t.check(k != "hoplite" and k != "brute" and k != "crocodile" and k != "troll", "no %s before bout 25 (bout %d)" % [k, n])

func test_coop_gives_every_friend_a_foe_and_bosses_come_alone() -> void:
	for n in [1, 2, 3, 5, 6]:
		var st := Data.stage(n, 3)
		t.eq(st.rounds.size(), 1, "co-op bout %d is one fight" % n)
		t.eq(st.rounds[0].size(), Data.stage(n, 1).rounds[0].size() + 1, "three friends, one foe more than alone, in bout %d" % n)
	t.eq(Data.stage(5, 3).late.size(), 1, "the second wave comes as authored, for a party as for one")
	var boss := Data.stage(4, 3)
	t.eq(boss.rounds[0].size(), 1, "a boss comes alone")
	t.check(float(boss.rounds[0][0].mods.toughness) > float(Data.stage(4, 1).rounds[0][0].get("mods", {}).get("toughness", 1.0)), "and tougher for a party")

## Four at most fight the co-op campaign; the room, and every other fight in it, takes eight
## (user). With a fifth in the room the campaign's buttons are held back, the reason under them,
## and it does not begin when asked; every other fight stays open to them all.
func test_the_co_op_campaign_takes_four_at_most() -> void:
	t.eq(Net.MAX_PLAYERS, 8, "a room takes eight")
	t.eq(Net.CAMPAIGN_PLAYERS, 4, "the co-op campaign four")
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	Net.transport = "test"   # (the offline peer: this game is the host)
	t.check(Net.active() and Net.is_host(), "hosting a room")
	for id in [9, 10, 11]:
		Net.peers[id] = {"name": "Friend %d" % id, "loadout": {"main": "gladius"}}
	var held := func(prefix: String) -> Array:
		return menu.find_children("*", "Button", true, false).filter(func(b): return String(b.text).begins_with(prefix)).map(func(b): return b.disabled)
	t.check(not Net.campaign_full(), "four in the room: the campaign takes them")
	menu.show_screen("room")
	await get_tree().process_frame
	t.eq(held.call("Start the co-op campaign"), [false], "four: it can be started from the room")
	Net.peers[12] = {"name": "Friend 12", "loadout": {"main": "gladius"}}
	t.check(Net.campaign_full(), "five: one too many")
	menu.show_screen("room")
	await get_tree().process_frame
	t.eq(held.call("Start the co-op campaign"), [true], "five: held back in the room")
	var why: String = menu.campaign_full_text()
	t.check(why.contains("4") and why.contains("5") and why.contains("8"), "the reason names the numbers: " + why)
	t.eq(menu.find_children("*", "Label", true, false).filter(func(l): return l.text == why).size(), 1, "and is shown under it")
	if not Edition.demo_over(int(Save.get_value("coop_stage", 1))):
		menu.show_screen("gate")
		await get_tree().process_frame
		t.eq(held.call("The co-op campaign"), [true], "held back at the yard's gate too")
	menu.show_screen("fights")
	await get_tree().process_frame
	var cards: Array = menu.find_children("*", "Button", true, false).filter(func(b): return b.custom_minimum_size == Vector2(262, 104))
	t.check(cards.size() > 8, "the fights for the room (%d)" % cards.size())
	t.eq(cards.filter(func(b): return b.disabled).map(func(b): return b.tooltip_text), [why], "among the fights only the co-op campaign's card is held back")
	menu.start({"mode": "coop", "role": "host"})
	await get_tree().process_frame
	t.check(menu.match_ == null, "asked anyway, it does not begin")
	t.eq(menu.screen, "fights", "the screen it was asked from is drawn again")
	t.eq(YardPlay.next_fight(6), YardPlay.next_fight(4), "the board by the gate never shows a bout for more than four")
	for id in [9, 10, 11, 12]:
		Net.peers.erase(id)
	Net.transport = ""
	menu.queue_free()
	await get_tree().process_frame

func test_the_other_gate_opens_on_the_second_wave() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 5, "headless": true, "loadout": {"main": "gladius", "off": "roundShield"}, "seed": 5})
	var said := []
	m.feed.connect(func(s): said.append(s))
	t.eq(m.enemies().size(), 1, "the coward comes in alone")
	for i in 120 * 2:
		await get_tree().physics_frame
	t.eq(m.enemies().size(), 1, "and is alone two seconds in")
	for i in int(120 * (Ladder.LATE_AFTER - 1.0)):
		await get_tree().physics_frame
	t.eq(m.enemies().size(), 2, "the second man is in once the other gate has opened")
	var late = m.enemies()[1]
	t.check(late.f.torso.global_position.x < -2.0, "through the far gate (x %.1f)" % late.f.torso.global_position.x)
	t.check(said.any(func(x): return String(x).begins_with("The other gate opens")), "the feed says so (%s)" % [said])
	m.queue_free()

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
	t.eq(r.sold, ["R"], "a two-handed sword takes the main hand")
	t.eq(str(r.arms.off.name), "Dagger", "and leaves the dagger in the off hand (held in one hand beside it)")
	r = Arms.buy(Arms.buy(Arms.empty(), "zweihander").arms, "dagger")
	t.check(not r.has("choose") and r.side == "L", "beside a two-hander, a dagger goes in the free off hand")
	# Asked for the off hand, a one-handed weapon goes there even with the main hand free.
	r = Arms.buy(Arms.empty(), "gladius", "", "L")
	t.eq(r.side, "L", "a gladius bought for the off hand goes there")
	t.check(Arms.is_stick(r.arms.main), "the main hand keeps its stick")
	r = Arms.buy(Arms.buy(Arms.empty(), "axe").arms, "dagger", "", "L")
	t.check(r.side == "L" and str(r.arms.main.name) == "Axe" and str(r.arms.off.name) == "Dagger", "beside the axe in the main hand")
	t.check(Arms.off_hand_ok("gladius") and Arms.off_hand_ok("zweihander") and not Arms.off_hand_ok("roundShield"), "any weapon (a shield goes there anyway)")
	r = Arms.buy(Arms.empty(), "longsword", "", "L")
	t.check(r.side == "L" and str(r.arms.off.name) == "Longsword", "even a longsword can be bought for the off hand")

## A hand lost in a bout: the weapon goes into the hand he has left, what that hand held up on the
## smith's rack; with no hand to hold them, both go up on the rack, and come down again into a hand
## that can hold them (user).
func test_a_lost_hands_weapon_goes_to_the_other_hand_or_the_rack() -> void:
	var a: Dictionary = Arms.buy(Arms.buy(Arms.empty(), "axe").arms, "roundShield").arms
	var shield_name := str(a.off.name)
	t.check((Arms.fit_hands(a, Body.empty()).moved as Array).is_empty(), "both hands whole: nothing moves")
	var no_r := Body.empty()
	no_r.missing = ["forearmR"]
	var r := Arms.fit_hands(a, no_r)
	t.eq(str(r.arms.off.name), "Axe", "the right hand lost: the axe in the left hand")
	t.check(Arms.is_stick(r.arms.main), "the main hand left with nothing to hold")
	t.check(r.arms.rack.size() == 1 and str(r.arms.rack[0].name) == shield_name, "the shield up on the smith's rack")
	var hooked := Body.empty()
	hooked.prosthetics = {"forearmR": "hook"}
	t.eq(str(Arms.fit_hands(a, hooked).arms.off.name), "Axe", "a hook holds no weapon either")
	var no_l := Body.empty()
	no_l.missing = ["forearmL"]
	r = Arms.fit_hands(a, no_l)
	t.check(str(r.arms.main.name) == "Axe" and r.arms.off == null and r.arms.rack.size() == 1, "the left hand lost: the axe stays, the shield goes up on the rack")
	var none := Body.empty()
	none.missing = ["upperArmR", "forearmR", "forearmL"]
	r = Arms.fit_hands(a, none)
	t.check(Arms.is_stick(r.arms.main) and r.arms.off == null and r.arms.rack.size() == 2, "no hand left: both up on the rack")
	var kept: Dictionary = Arms.sanitize(r.arms)
	t.eq(kept.rack.size(), 2, "the rack is kept with his arms")
	var back := Arms.take_from_rack(kept, 0, "L")
	t.check(back.has("arms") and str(back.arms.off.name) == "Axe" and back.arms.rack.size() == 1, "taken down again into a hand")
	t.check(Arms.take_from_rack(kept, 5, "R").has("error"), "nothing there to take down")

## Either hand's weapon can be sold to the smith outright, for what a trade-in fetches (user).
func test_a_weapon_is_sold_for_half_its_worth() -> void:
	var a: Dictionary = Arms.buy(Arms.buy(Arms.empty(), "axe").arms, "dagger").arms
	var back := Arms.sale_price(a.main)
	t.check(back > 0 and back == int(Arms.value(a.main) * 0.5), "the axe fetches half its worth (%d)" % back)
	t.eq(int(Arms.buy(a, "gladius", "R").trade_in), back, "as much as it fetches traded in")
	var r := Arms.sell(a, "R")
	t.eq(int(r.cost), -back, "the purse gains it")
	t.check(Arms.is_stick(r.arms.main), "the main hand is left with the training stick")
	t.eq(str(r.arms.off.name), "Dagger", "the dagger stays")
	r = Arms.sell(r.arms, "L")
	t.check(r.arms.off == null and int(r.cost) < 0, "the dagger sold, the off hand empty")
	t.check(Arms.sell(r.arms, "R").has("error") and Arms.sell(r.arms, "L").has("error"), "nothing left to sell: the stick fetches nothing")
	t.eq(Arms.sale_price(r.arms.main), 0, "the stick is worth nothing to him")

## At the smith both hands are offered the same things (user), greyed with why where they cannot
## be done to that weapon.
func test_the_smith_offers_both_hands_the_same() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu.set_arms(Arms.buy(Arms.buy(Arms.empty(), "warhammer").arms, "gladius", "", "L").arms)
	menu.smith_tab = "weapons"
	menu.show_screen("yard")
	await get_tree().process_frame
	var seen := {}
	for b in menu.find_children("*", "Button", true, false):
		var k := String(b.text).get_slice(" · ", 0)
		seen[k] = int(seen.get(k, 0)) + 1
	for k in ["Sound", "Hone the edge", "Temper the blade", "Reshape in the forge", "Forge a new one for this hand", "Sell"]:
		t.eq(int(seen.get(k, 0)), 2, "%s: offered for both hands" % k)
	menu.queue_free()
	await get_tree().process_frame

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

## Vulcanus's masterworks grow with the campaign (user): the first bouts' are fine steel and no
## gems, the late bouts' a tier or more above, dearer, keener and set with gems; three kinds on
## each stall; every one two-handed, with a grip, liftable, within its tier's load on the arms, and
## taken by the host as it is in a party.
func test_the_masterworks_grow_with_the_campaign() -> void:
	var early := []
	var late := []
	var cost := [0, 0]
	var bad := []
	for seed_ in 10:
		for k in 2:
			var stage: int = [1, 50][k]
			var kinds := {}
			for d in Arms.oddities(seed_ * 17 + 5, stage):
				var tier := int(d.oddity.tier)
				(early if k == 0 else late).append(tier)
				kinds[d.oddity.kind] = true
				cost[k] += Arms.oddity_price(d)
				var st := ForgeLib.compute_stats(d)
				var why := ForgeLib.too_heavy(d, st)
				if why != "" or not d.twoHanded or ForgeLib.grip_points(d) == null or Masterworks.load_of(st) > Masterworks.LOAD[tier - 1] + 0.61:
					bad.append("%s (%s, tier %d, load %.2f) %s" % [d.name, d.oddity.kind, tier, Masterworks.load_of(st), why])
				# (In a party the host takes a guest's weapon as the forge could make it, or he
				# fights with a gladius: within its grid, of its stuff, no more blocks than it holds.)
				if Net.clean_design(d) == null:
					bad.append("%s (%s, tier %d): refused over the wire" % [d.name, d.oddity.kind, tier])
			t.eq(kinds.size(), 3, "three kinds on the stall at bout %d" % stage)
	t.check(early.max() <= 2 and late.min() >= 5, "tiers I-II at the first bout (%s), V-VI at bout 50 (%s)" % [early, late])
	t.check(cost[1] > 4 * cost[0], "the late stall far dearer: %d against %d" % [cost[1], cost[0]])
	t.check(bad.is_empty(), "every masterwork can be lifted and swung within its tier: %s" % ", ".join(bad.slice(0, 3)))
	# The tiers follow the bouts through the run, never going back.
	var last := 0
	for stage in range(1, 65):
		var tier := Masterworks.tier_of(stage)
		t.check(tier >= last, "tier %d at bout %d (after %d)" % [tier, stage, last])
		last = tier
	t.eq(Masterworks.tier_of(64), 6, "the last bouts: godforged")

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

## An archer keeps his bow at every bout (user: a "Veteran Bowman" came at him with a mace: the
## bout's weapon had been put in his hands for his bow).
func test_an_archer_keeps_his_bow() -> void:
	var m := Match.new()
	m.mode = "campaign"
	var bad := []
	for st in [3, 9, 17, 30, 50]:
		m.stage = st
		for sd in 6:
			m.rng.seed = sd
			var spec := m.enemy_spec({"e": "sagittarius", "gear": {"rank": "Veteran", "temper": "iron"}}, 0, 1)
			var main: Dictionary = spec.loadout.main
			if not main.has("shoots"):
				bad.append("bout %d: %s" % [st, str(main.get("name", "?"))])
	t.check(bad.is_empty(), "every archer holds a bow (%s)" % ", ".join(bad))
	m.free()

## The first bouts are gentle: the Cyclops (the gentlest giant in the survey) is the first boss
## and the Big Lion waits for the eighth bout, the wolf and the boar bite less hard, and the men
## of bouts 2 to 4 climb slower.
func test_the_first_bouts_are_gentler() -> void:
	t.eq(String(Data.stage(4, 1).rounds[0][0].get("e", "")), "cyclops", "the Cyclops is the first boss")
	t.eq(String(Data.stage(8, 1).rounds[0][0].get("beast", "")), "lion", "the Big Lion comes at the eighth bout")
	t.check(float(Data.stage(8, 1).rounds[0][0].get("scale", 2.2)) <= 2.0, "and no bigger than twice a man")
	t.check(float(Data.beasts.wolf.bite) < 22.0 and float(Data.beasts.boar.bite) < 30.0, "the wolf and the boar bite less hard")
	t.check(Match.ladder_skill(4) < 0.68 and Match.ladder_skill(12) < 0.8 and Match.ladder_skill(23) < 1.0 and is_equal_approx(Match.ladder_skill(24), 1.0), "their skill climbs slowly, at its best from the 24th bout")
	t.check(float(Data.stage(3, 1).rounds[0][0].get("gear", {}).get("diff", 0.85)) <= 0.9 if Data.stage(3, 1).rounds[0][0].get("gear") is Dictionary else true, "bout 3's man is no sharper")

## A player bleeds well under a bot's rate from the same wounds (PLAYER_BLEED), and clots sooner.
func test_a_player_bleeds_slower() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "seed": 3})
	t.eq(float(m.me.f.mods.bleed), Match.PLAYER_BLEED, "the player's own bleeding")
	for e in m.enemies():
		if e.f is Fighter:
			t.eq(float(e.f.mods.bleed), 1.0, "a foe bleeds as before")
	m.queue_free()

## A party has the numbers: fewer foes than friends on a men's bout, and a boss tougher by a
## third for each friend, not more.
func test_a_party_has_the_better_of_it() -> void:
	var count := func(st): return st.rounds.reduce(func(a, r): return a + r.size(), 0)
	t.eq(count.call(Data.stage(2, 2)), 2, "two friends: two men")
	t.eq(count.call(Data.stage(2, 3)), 2, "three friends: two men")
	t.eq(count.call(Data.stage(2, 4)), 3, "four friends: three men")
	var boss3: Dictionary = Data.stage(8, 3).rounds[0][0]
	t.check(is_equal_approx(float(boss3.mods.toughness), 1.0 + 0.35 * 2), "a boss for three is 70%% tougher (%.2f)" % float(boss3.mods.toughness))
	t.eq(Data.stage(3, 3).rounds[0].size(), 2, "a beast's bout for three: a pair of them")

## In a party a player's death is not the end: he falls to death's door, his bleeding stopped,
## and a friend who holds the revive key beside him lifts him back into the fight. The door
## shuts after DYING_T seconds, or at once when nobody else stands.
func test_a_friend_lifts_a_man_from_deaths_door() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "role": "host", "headless": true, "peers": [{"id": 2, "name": "Friend", "loadout": {"main": "axe"}}], "seed": 9})
	for e in m.enemies():
		e.erase("bot")
		e.drive = func(_e): return {"limp": true}
	var a: Fighter = m.me.f
	var friend: Dictionary = m.humans().filter(func(x): return x.kind == "remote")[0]
	var fr: Fighter = friend.f
	for i in 30:
		await get_tree().physics_frame
	a.blood = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	t.check(a.alive and a.dying > 0.0 and a.state != "stand", "bled white beside a friend, he is at death's door, not dead (dying %.1f)" % a.dying)
	t.check(a.blood > 0.0, "his bleeding is stopped")
	fr.teleport(a.torso.global_position + Vector3(0.8, 0, 0))
	friend.drive = func(_e): return {"revive": true}
	for i in int(Fighter.LIFT_T * 120) + 30:
		await get_tree().physics_frame
	t.check(a.alive and a.dying <= 0.0 and a.blood >= 30.0, "lifted by his friend, he lives (blood %.0f)" % a.blood)
	# Alone at death's door he dies as before: the friend gone, no one to spare him.
	friend.drive = func(_e): return {}
	fr.die("test")
	await get_tree().physics_frame
	a.blood = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	t.check(not a.alive, "with no friend standing, his death is his own")
	m.queue_free()

## A boss of men past the 36th bout comes better armed: the steel set and his own coating on his
## weapon, where the bosses of men before it wear bronze and iron. (Any foe's weapon may come
## coated by chance from the twelfth bout on; the late boss's always is, with his own.)
func test_a_late_boss_comes_in_steel() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "seed": 3})
	for n in [4, 16, 28, 32]:
		m.stage = n
		var early := m.enemy_spec(Data.stage(n, 1).rounds[0][0], 0, 1)
		t.check(not early.loadout.armor.has("steelLorica"), "bout %d (%s): no steel (%s)" % [n, early.name, str(early.loadout.armor)])
	var titan: Dictionary = Data.stage(40, 1).rounds[0][0]
	t.eq(_kind(titan), "titan", "the Titan is bout 40's boss")
	m.stage = 24
	var first := m.enemy_spec(titan, 0, 1)
	m.stage = 40
	var late := m.enemy_spec(titan, 0, 1)
	t.check(not first.loadout.armor.has("steelLorica"), "had he come by bout 24: no steel (%s)" % str(first.loadout.armor))
	t.check(late.loadout.armor.has("steelLorica") and late.loadout.armor.has("murmilloHelm") and not late.loadout.armor.has("helmet"), "at bout 40: in steel (%s)" % str(late.loadout.armor))
	t.eq(String(late.loadout.main.get("imbue", "")), "fire", "his weapon coated")
	t.check(late.loadout.armor.has("mon_horns") == first.loadout.armor.has("mon_horns"), "and still looks the part")
	m.queue_free()

## The campaign won and begun again (the rudis): the same tables, the men a third tougher and
## the beasts a tenth bigger each time round.
func test_the_second_campaign_is_tougher() -> void:
	var first := Match.new()
	add_child(first)
	first.setup({"mode": "campaign", "stage": 2, "headless": true, "lap": 1, "seed": 3})
	var again := Match.new()
	add_child(again)
	again.setup({"mode": "campaign", "stage": 2, "headless": true, "lap": 2, "seed": 3})
	t.eq(again.lap, 2, "the second time round")
	var boar1 = first.enemies()[0].f
	var boar2 = again.enemies()[0].f
	t.check(is_equal_approx(float(boar2.S), float(boar1.S) * (1.0 + Match.LAP_SCALE)), "the boar is bigger (%.2f from %.2f)" % [float(boar2.S), float(boar1.S)])
	first.stage = 1
	again.stage = 1
	var m1 := first.enemy_spec(Data.stage(1, 1).rounds[0][0], 0, 1)
	var m2 := again.enemy_spec(Data.stage(1, 1).rounds[0][0], 0, 1)
	t.check(is_equal_approx(float(m2.mods.toughness), float(m1.mods.toughness) * (1.0 + Match.LAP_TOUGH)), "the recruit a third tougher (%.2f from %.2f)" % [float(m2.mods.toughness), float(m1.mods.toughness)])
	first.queue_free()
	again.queue_free()

## The crowd pays a little for a lively bout and nothing for a dull one: the heat of a fight is
## the share of its time near a blow and the party's favour, and the bonus a quarter of the
## stage's pay at the most.
func test_the_crowd_pays_for_a_lively_bout() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "headless": true, "seed": 3})
	var sp: Spectacle = m.spectacle
	for i in 60:
		sp.update(0.1)
	t.check(is_zero_approx(sp.heat(m.humans())), "a bout without a blow: no heat (%.2f)" % sp.heat(m.humans()))
	var foe = m.enemies()[0].f
	for i in 60:
		if i % 10 == 0:
			sp.on_hit({"attacker": m.me.f, "char": foe, "J": 24.0, "res": {}})
		sp.update(0.1)
	var h := sp.heat(m.humans())
	t.check(h > 0.4 and h <= 1.0, "a bout of blows runs hot (%.2f)" % h)
	t.check(int(round(100 * Match.CROWD_BONUS * h)) <= 25, "and the crowd's bonus stays small (%d on 100)" % int(round(100 * Match.CROWD_BONUS * h)))
	m.queue_free()

## A player dead on the sand in a bout his party goes on to win is carried off it: he walks into
## the yard alive with the wounds he died of (the limb he lost, the bone broken, the flesh torn),
## not whole as he came into the campaign (a death healed him of everything). What is done to
## his body after his death is not on him, and the body is one he can live in.
func test_a_man_dead_in_a_bout_won_is_carried_off_with_his_wounds() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "role": "host", "headless": true, "peers": [{"id": 2, "name": "Friend", "loadout": {"main": "axe"}}], "seed": 9})
	for e in m.enemies():
		e.erase("bot")
		e.drive = func(_e): return {"limp": true}
	var a: Fighter = m.me.f
	var friend: Dictionary = m.humans().filter(func(x): return x.kind == "remote")[0]
	friend.drive = func(_e): return {}
	var said := []
	m.feed.connect(func(line): said.append(String(line)))
	var results := []
	m.finished.connect(func(r): results.append(r))
	for i in 30:
		await get_tree().physics_frame
	# The bout's wounds: a forearm off, a hole in the thigh, the shin broken, and what kills him,
	# his chest and his head stove in.
	a.detach_limb(a.by_name.forearmL, {"removed": [], "severed": []})
	var th: VoxelPart = a.by_name.thighR
	var hole := []
	for i in th.fx.size():
		if th.fx[i] < 2 and th.fy[i] > 6 and th.fy[i] < 10:
			hole.append(i)
	th.remove_voxels(hole)
	a.by_name.shinR.fracture = 2
	a.torso.remove_voxels(Array(a.torso.voxels_within(Vector3(0, 0.05, a.torso.half_ext.z), 0.14)), false, false)
	a.head.remove_voxels(Array(a.head.voxels_within(Vector3(0, 0, a.head.half_ext.z), 0.07)), false, false)
	var chest_gone := a.torso.fx.size() - a.torso.alive_count
	t.check(chest_gone > 100, "his chest stove in (%d voxels)" % chest_gone)
	a.spared = true   # (no door left open: he dies of it)
	a.die("wounds")
	t.check(not a.alive and friend.f.alive, "he is dead on the sand, his friend still stands")
	for i in 3:
		await get_tree().physics_frame
	# A blade swung over his body after it takes a leg off the corpse: not his to carry.
	a.detach_limb(a.by_name.shinL, {"removed": [], "severed": []})
	friend.f.by_name.thighL.remove_voxels([1, 2, 3, 4, 5, 6])
	for i in 3:
		await get_tree().physics_frame
	var bodies := m.final_bodies()
	var b: Dictionary = bodies[m.me.id]
	t.check(b.missing.has("forearmL"), "the forearm he lost is still lost")
	t.check(not b.missing.has("shinL"), "what was cut off his body afterwards is not")
	t.check(b.scars.has("thighR") and b.scars.has("torso") and b.scars.has("head"), "his wounds are on him: %s" % Body.summary(b))
	t.eq(int(b.fractures.get("shinR", 0)), 2, "the shin still broken")
	t.check(not (b.fresh as Dictionary).is_empty(), "the wounds fresh, for the physician to close")
	t.check((bodies[friend.id].scars as Dictionary).has("thighL"), "the living are read as they stand")
	# A man of that body lives, and takes a knock.
	var e2 = m.spawn_fighter({"kind": "bot", "name": "B", "loadout": {"main": "gladius", "off": ""}, "team": 0, "pos": Vector3(7, 0, -7), "yaw": 0.0, "body": b})
	e2.erase("bot")
	e2.drive = func(_e): return {}
	var g: Fighter = e2.f
	for i in 240:
		await get_tree().physics_frame
	t.check(g.alive and g.dying <= 0.0, "a man of that body lives")
	t.check(g.torso.integrity > 0.6 and g.head.integrity > 0.6, "his trunk and his head well above what kills (%.2f, %.2f of them left)" % [g.torso.integrity, g.head.integrity])
	t.check(g.heart_t < 0.0 and g.organ_lost.is_empty() and g.torso.bleed == 0.0, "nothing in him torn open or bleeding")
	var front: Vector3 = g.torso.global_transform.basis.z
	g.apply_hit(g.torso, {"impulse": 10.0, "type": "blunt", "hardness": 0.3, "sharpness": 0.0, "point": g.torso.global_position + front * g.torso.half_ext.z, "dir": -front, "axis": -front, "edge": Vector3.ZERO})
	for i in 60:
		await get_tree().physics_frame
	t.check(g.alive, "and a knock on the chest does not kill him")
	# The party wins the bout: he is carried off, told so, and the body the bout hands him is that one.
	for e in m.enemies():
		e.f.die("test")
	for i in 10:
		await get_tree().physics_frame
	t.check(results.size() == 1 and bool(results[0].won), "the bout is won without him")
	if results.size() == 1:
		t.check(bool(results[0].get("fell", false)), "the result says he fell")
		t.check((results[0].body.missing as Array).has("forearmL") and not (results[0].body.missing as Array).has("shinL"), "and hands him the body he died in")
	t.check(said.any(func(x): return x.contains("carried off the sand")), "the arena is told he is carried off the sand")
	m.queue_free()

## Beheaded, he is carried off with his head on (a body must have one), the rest of his wounds
## kept; and a man who dies on the bout's last step is read as he lies.
func test_a_man_beheaded_is_carried_off_with_a_head() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "role": "host", "headless": true, "peers": [{"id": 2, "name": "Friend", "loadout": {"main": "axe"}}], "seed": 9})
	for e in m.enemies():
		e.erase("bot")
		e.drive = func(_e): return {"limp": true}
	var a: Fighter = m.me.f
	var friend: Dictionary = m.humans().filter(func(x): return x.kind == "remote")[0]
	friend.drive = func(_e): return {}
	for i in 30:
		await get_tree().physics_frame
	a.detach_limb(a.by_name.forearmR, {"removed": [], "severed": []})
	a.head.severed = true
	a.die("decap")
	t.check(not a.alive, "his head off, he is dead")
	# (The very step he died: nothing read yet, he is read as he lies.)
	var now: Dictionary = m.final_bodies()[m.me.id]
	t.check((now.missing as Array).has("forearmR") and not (now.missing as Array).has("head"), "read the step he died: the arm lost, a head on him")
	for i in 3:
		await get_tree().physics_frame
	var b: Dictionary = m.final_bodies()[m.me.id]
	t.check((b.missing as Array).has("forearmR") and not (b.missing as Array).has("head") and not (b.fractures as Dictionary).has("skull"), "carried off: the arm lost, his head whole on him")
	var e2 = m.spawn_fighter({"kind": "bot", "name": "B", "loadout": {"main": "gladius", "off": ""}, "team": 0, "pos": Vector3(7, 0, -7), "yaw": 0.0, "body": b})
	e2.erase("bot")
	e2.drive = func(_e): return {}
	for i in 120:
		await get_tree().physics_frame
	t.check(e2.f.alive and not e2.f.head.severed and e2.f.state == "stand", "a man of that body stands, his head on")
	m.queue_free()
