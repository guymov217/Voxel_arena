extends Node
## The Arena alone (user: in every mode a single player can pick his gear before the game starts): each fight's settings screen shows the gear he goes in with and
## lets him change it (the kit screen of Menu._endless, for the fight it was opened from), and the fight begins with it, a tournament's every bout too.

var t

func _all(n: Node, pred: Callable, out: Array) -> void:
	if pred.call(n):
		out.append(n)
	for c in n.get_children():
		_all(c, pred, out)

func _menu() -> Node:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	return menu

func test_every_fight_alone_offers_the_gear_before_it_begins() -> void:
	var menu := _menu()
	await get_tree().process_frame
	for k in ["bo3", "king", "tourney", "ffa", "teams", "hunt", "hill", "lastLimb"]:
		menu.fight_pick = k
		menu.show_screen("fight_setup")
		await get_tree().process_frame
		var picks := []
		_all(menu, func(n): return n is Button and (n as Button).text == "Choose your gear", picks)
		t.eq(picks.size(), 1, "%s: a button to choose the gear" % k)
		var lines := []
		_all(menu, func(n): return n is Label and (n as Label).text.begins_with("Your gear:"), lines)
		t.check(lines.size() == 1 and (lines[0] as Label).text.contains("·"), "%s: and the gear he has now in a line (%s)" % [k, str(lines.map(func(l): return l.text))])
		if picks.is_empty():
			continue
		(picks[0] as Button).pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		t.check(menu.screen == "endless" and menu.kit_for == k and menu.endless_back == "fight_setup", "%s: the kit screen, for that fight, going back to its settings" % k)
		var titles := []
		_all(menu, func(n): return n is Label and (n as Label).text == "Your gear", titles)
		t.eq(titles.size(), 1, "%s: titled Your gear, not the endless arena's" % k)
		var into := []
		_all(menu, func(n): return n is Button and (n as Button).text == "Into the arena", into)
		t.check(into.is_empty(), "%s: no way into the endless arena from it" % k)
		var daily := []
		_all(menu, func(n): return n is CheckBox, daily)
		t.check(daily.is_empty(), "%s: nor the endless arena's daily challenge" % k)
		var done := []
		_all(menu, func(n): return n is Button and (n as Button).text == "Done", done)
		t.eq(done.size(), 1, "%s: a Done that takes him back" % k)
		if done.size() == 1:
			(done[0] as Button).pressed.emit()
			await get_tree().process_frame
			t.eq(menu.screen, "fight_setup", "%s: to the fight's settings" % k)
	menu.queue_free()
	await get_tree().process_frame

func test_the_endless_arena_keeps_its_own_screen() -> void:
	var menu := _menu()
	await get_tree().process_frame
	menu.kit_for = "endless"
	menu.endless_back = "fights"
	menu.show_screen("endless")
	await get_tree().process_frame
	var into := []
	_all(menu, func(n): return n is Button and (n as Button).text == "Into the arena", into)
	var daily := []
	_all(menu, func(n): return n is CheckBox, daily)
	var titles := []
	_all(menu, func(n): return n is Label and (n as Label).text == "The endless arena", titles)
	t.check(into.size() == 1 and daily.size() == 1 and titles.size() == 1, "the endless arena's screen has its title, its daily challenge and the way in")
	menu.queue_free()
	await get_tree().process_frame

func test_the_fight_begins_with_the_gear_he_picked() -> void:
	var menu := _menu()
	await get_tree().process_frame
	var k: Dictionary = menu._endless_kit()
	var was := k.duplicate(true)
	k.main = "axe"
	k.off = "none"
	k.armor = ["helmet"]
	k.pots = ["smoke", "nailPot"]
	k.bag = {"smoke": 2, "nailPot": 2}
	for mode in ["bo3", "king", "tourney", "ffa", "teams", "hunt", "hill", "lastLimb"]:
		var o: Dictionary = menu._fight_begin_opts(mode)
		t.check(o.has("loadout_override") and o.has("inventory_override"), "%s: it begins with his gear" % mode)
		var lo: Dictionary = o.get("loadout_override", {})
		t.check(lo.get("main") == "axe" and lo.get("off") == "" and (lo.get("armor", []) as Array).has("helmet"), "%s: his arms and armour (%s)" % [mode, str(lo.get("main"))])
		t.eq((o.get("inventory_override", {}) as Dictionary).size(), 2, "%s: and the two kinds of pot he took" % mode)
	t.check(not menu._fight_begin_opts("forgefight").has("loadout_override"), "forge and fight gives its own arms: his kit is not put on it")
	# A tournament: every bout of his has it.
	menu.tourney_opts = menu._fight_begin_opts("tourney")
	menu.tourney = Tourney.make([{"key": "p1", "name": "Me", "peer": 1, "bot": false}, {"key": "bCato", "name": "Cato", "peer": -1, "bot": true}], 3, 1)
	var bout: Dictionary = menu._tourney_bout(menu.tourney.open_match())
	t.check(bout.has("loadout_override") and bout.loadout_override.main == "axe" and bout.has("inventory_override"), "a tournament's bout goes in with it too")
	menu.tourney = null
	for key in was:
		k[key] = was[key]
	if not was.has("bag"):
		k.erase("bag")
	menu._endless_keep()
	menu.queue_free()
	await get_tree().process_frame

## User: why is the choice of gear so small? The kit screen had been the endless arena's few arms and six pots: a fight of the Arena now has every weapon of the game (but the ones kept
## aside and the two men's), every ware of the market and the whole of the armourer's shop.
func test_the_kit_offers_every_weapon_the_game_has() -> void:
	var menu := _menu()
	var mains: Array = menu.kit_mains()
	var offs: Array = menu.kit_offs()
	t.check(mains.size() >= 30, "the main hand has the game's weapons, not a handful (%d)" % mains.size())
	for key in ["built", "fists", "gladius", "javelin", "bow", "goose", "chair", "executionerAxe", "telescopicSpear"]:
		t.check(mains.has(key), "main hand: %s" % key)
	for key in ["roundShield", "scutum", "twoPersonSword", "ram", "flail", "whip", "crossbow", "imperialFlail", "meteorHammer"]:
		t.check(not mains.has(key), "main hand: not %s (a shield, two men's, or kept aside)" % key)
	for key in ["none", "built", "roundShield", "scutum", "dagger", "gladius", "chicken", "mace"]:
		t.check(offs.has(key), "off hand: %s" % key)
	for key in ["zweihander", "bow", "spear", "flail", "twoPersonSword", "crossbow"]:
		t.check(not offs.has(key), "off hand: not %s (two hands, shot, two men's, or kept aside)" % key)
	t.check(mains.slice(2, 12).has("gladius") and mains.find("gladius") < mains.find("goose"), "the smith's own come first")
	for list in [mains, offs]:
		var seen := {}
		for key in list:
			seen[key] = true
			t.check(["built", "fists", "none"].has(String(key)) or Data.presets.has(String(key)), "%s is a weapon of the game" % key)
		t.eq(seen.size(), list.size(), "no weapon twice")
	menu.queue_free()

func test_the_kit_screen_has_the_whole_market_for_a_fight_and_the_pots_for_the_endless_arena() -> void:
	var menu := _menu()
	await get_tree().process_frame
	var k: Dictionary = menu._endless_kit()
	var was := k.duplicate(true)
	k.erase("bag")
	k.pots = ["thunderPot"]
	menu.fight_pick = "ffa"
	menu.kit_for = "ffa"
	menu.endless_back = "fight_setup"
	menu.show_screen("endless")
	await get_tree().process_frame
	var plus := []
	_all(menu, func(n): return n is Button and (n as Button).text == "+", plus)
	t.eq(plus.size(), (Data.shop.throwables as Dictionary).size(), "a fight of the Arena: a + for every ware of the market")
	# The bag he has already was made from the pots the kit had (two of each); a first ware (a pot, three to a bag at most): five presses, three in the bag, kept.
	t.eq(int((menu._endless_kit().bag as Dictionary).get("thunderPot", 0)), 2, "he opens it with the pot of his kit, two of it")
	var first: String = (Data.shop.throwables as Dictionary).keys()[0]
	if not plus.is_empty():
		for i in 5:
			(plus[0] as Button).pressed.emit()
	t.eq(int((menu._endless_kit().bag as Dictionary).get(first, 0)), Throwables.stack_max(first), "its stack fills and no more")
	t.eq(int(menu._fight_begin_opts("ffa").inventory_override.get(first, 0)), Throwables.stack_max(first), "and the fight begins with it")
	# The endless arena's own screen keeps its few pots.
	menu.kit_for = "endless"
	menu.endless_back = "fights"
	menu.show_screen("endless")
	await get_tree().process_frame
	plus.clear()
	_all(menu, func(n): return n is Button and (n as Button).text == "+", plus)
	var toggles := []
	_all(menu, func(n): return n is Button and (n as Button).toggle_mode and not (n is OptionButton) and not (n is CheckBox), toggles)
	t.check(plus.is_empty() and toggles.size() == Endless.POTS.size(), "the endless arena: its %d pots to take or leave, no market (%d, %d)" % [Endless.POTS.size(), plus.size(), toggles.size()])
	for key in was:
		k[key] = was[key]
	if not was.has("bag"):
		k.erase("bag")
	menu._endless_keep()
	menu.queue_free()
	await get_tree().process_frame

func test_bare_hands_and_odd_weapons_go_into_the_fight() -> void:
	var menu := _menu()
	await get_tree().process_frame
	var k: Dictionary = menu._endless_kit()
	var was := k.duplicate(true)
	k.main = "fists"
	k.off = "chicken"
	var lo: Dictionary = menu._fight_begin_opts("bo3").loadout_override
	t.check(lo.main == "" and lo.off == "chicken", "bare hands in the main hand, a rubber chicken in the off (%s, %s)" % [str(lo.main), str(lo.off)])
	t.check(menu._kit_summary().begins_with("Bare hands · Rubber Chicken"), "and the line of his gear says so (%s)" % menu._kit_summary())
	k.main = "goose"
	k.off = "scutum"
	lo = menu._fight_begin_opts("bo3").loadout_override
	t.check(lo.main == "goose" and lo.off == "scutum", "a goose on a stick and a scutum")
	for key in was:
		k[key] = was[key]
	menu._endless_keep()
	menu.queue_free()
	await get_tree().process_frame
