extends Node
## The trader's table (Market): the wares in tabs by what they do, the basics there from the first
## visit and one more brought after each boss beaten, never taken back; the Hand of Jupiter dearer
## as the purses grow (user).

var t

func _buttons(n: Node, out: Array) -> Array:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_buttons(c, out)
	return out

## The first node of the script class `cls` under `root` (a stall's screen).
static func _screen(root: Node, cls: Script) -> Node:
	for n in root.find_children("*", "VBoxContainer", true, false):
		if is_instance_of(n, cls):
			return n
	return null

func test_every_ware_is_in_one_tab_and_planned_once() -> void:
	var table: Dictionary = Data.shop.get("throwables", {})
	var menu_s = load("res://scripts/ui/menu.gd")
	var seen := {}
	for tab in Market.TABS:
		for id in tab[2]:
			t.check(table.has(id), "%s is sold" % id)
			t.check(not seen.has(id), "%s is in one tab only" % id)
			seen[id] = true
	for id in table:
		if menu_s.kit_use(id) == "self":
			t.check(not seen.has(id), "%s is the physician's, not the trader's" % id)
		else:
			t.check(seen.has(id), "%s has a tab" % id)
	var planned: Array = Market.BASIC + Market.AFTER_BOSS
	t.eq(planned.size(), seen.size(), "every ware on the table is planned: the basics and one for each boss")
	for id in seen:
		t.eq(planned.count(id), 1, "%s is planned once" % id)
	for tab in Market.TABS:
		t.check((tab[2] as Array).any(func(id): return Market.BASIC.has(id)), "%s has something from the first visit" % tab[1])

func test_a_boss_beaten_brings_one_more_ware_and_it_stays() -> void:
	var bosses := range(1, Ladder.BOUTS.size() + 1).filter(func(b): return GateChoice.boss_bout(b))
	t.eq(Market.AFTER_BOSS.size(), bosses.size() - 1, "a ware for every boss but the last (the campaign's end)")
	t.eq(Market.bosses_beaten(1, 1), 0, "nothing beaten at the first bout")
	t.eq(Market.bosses_beaten(int(bosses[0]), 1), 0, "facing the first boss: not yet")
	t.eq(Market.bosses_beaten(int(bosses[0]) + 1, 1), 1, "past him: one")
	t.eq(Market.bosses_beaten(1, 2), Market.AFTER_BOSS.size(), "the second time round: everything")
	t.check(Market.is_open("thunderPot", 0) and not Market.is_open("torch", 0), "the first visit: the basics, not the torch")
	t.check(Market.is_open("torch", 1) and not Market.is_open("goat", 1), "the first boss brings the torch, and only it")
	t.eq(Market.comes_after("torch"), int(bosses[0]), "the torch comes after the first boss's bout")
	t.eq(Market.comes_after("telekinesis"), int(bosses[Market.AFTER_BOSS.size() - 1]), "the Hand of Jupiter after the last but one")
	t.eq(Market.comes_after("thunderPot"), 0, "a basic comes after nobody")
	t.eq(Market.opened(false, int(bosses[1]) + 1, 1), 2, "two bosses beaten: two wares brought")
	t.eq(Market.opened(false, 1, 1), 2, "and a death that sends him back to bout 1 takes nothing off the table")
	t.eq(Market.opened(true, 1, 1), 0, "the party's table is its own")

func test_the_hand_of_jupiter_costs_more_as_the_purses_grow() -> void:
	t.eq(Market.price("telekinesis", 90, 1), 90, "at the first bout its list price")
	var last := 0
	var cheaper := []
	for st in range(1, Ladder.BOUTS.size() + 1):
		var p := Market.price("telekinesis", 90, st)
		if p < last:
			cheaper.append(st)
		last = p
	t.eq(cheaper, [], "never cheaper further on")
	t.check(Market.price("telekinesis", 90, 60) > 900, "by bout 60 it costs most of a bout's purse (%d)" % Market.price("telekinesis", 90, 60))
	t.eq(Market.price("thunderPot", 50, 60), 50, "the other wares keep their price")

func test_the_road_lists_what_each_boss_brings() -> void:
	var road := Market.road(3)
	t.eq(road.size(), Market.AFTER_BOSS.size(), "a stop for every ware a boss brings")
	t.eq(road.filter(func(r): return r.brought).size(), 3, "three of them brought")
	t.check(road[3].next and not road[2].next and not road[4].next, "the fourth is the next to come")
	var order_ok := true
	for i in road.size():
		order_ok = order_ok and String(road[i].id) == String(Market.AFTER_BOSS[i]) and int(road[i].bout) == Market.comes_after(String(road[i].id))
	t.check(order_ok, "in the order they come, each with the bout whose boss brings it")
	t.eq(Market.road(0).filter(func(r): return r.next).size(), 1, "at the start one is next")
	t.eq(Market.road(Market.AFTER_BOSS.size()).filter(func(r): return r.next).size(), 0, "none is next once all are brought")

func test_the_market_shows_what_is_to_come_and_sells_what_is_there() -> void:
	Save.set_value("coins", 5000)
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	var first_boss: int = Market.comes_after("torch")
	menu.market_tab = "fire"
	menu.market_sel = "torch"
	menu.show_screen("market")
	await get_tree().process_frame
	var ms: MarketScreen = _screen(menu, MarketScreen)
	t.check(ms != null, "the trader's table is there")
	if ms == null:
		menu.queue_free()
		return
	t.check(ms.buy_btn == null, "the torch is on the table but not for sale yet")
	var later := _buttons(ms.detail_card, []).filter(func(b): return (b as Button).disabled and (b as Button).text == Loc.t("After the boss of bout %d") % first_boss)
	t.eq(later.size(), 1, "it says it comes after bout %d's boss" % first_boss)
	var texts: Array = _buttons(menu, []).map(func(b): return (b as Button).text)
	for tab in Market.TABS:
		t.check(texts.any(func(x): return String(x).begins_with(Loc.t(String(tab[1])))), "a tab for %s" % tab[1])
	# A ware that is there: for sale at its price, and bought it goes in the bag and the purse is lighter.
	menu.market_sel = "thunderPot"
	menu.show_screen("market")
	await get_tree().process_frame
	ms = _screen(menu, MarketScreen)
	var price := int(Data.shop.throwables.thunderPot.price)
	t.check(ms.buy_btn != null and not ms.buy_btn.disabled and ms.buy_btn.text == Loc.t("Buy · %d denarii") % price, "the thunder pot is for sale (%s)" % (ms.buy_btn.text if ms.buy_btn else "no button"))
	var coins0: int = menu.coins()
	var had := int(menu.kit().get("thunderPot", 0))
	ms.buy_btn.pressed.emit()
	await get_tree().process_frame
	t.eq(menu.coins(), coins0 - price, "paid for")
	t.eq(int(menu.kit().get("thunderPot", 0)), had + 1, "and in the bag")
	# Past the first boss the torch is for sale.
	Save.set_value("stage", first_boss + 1)
	menu.market_sel = "torch"
	menu.show_screen("market")
	await get_tree().process_frame
	ms = _screen(menu, MarketScreen)
	t.check(ms.buy_btn != null and not ms.buy_btn.disabled and ms.buy_btn.text == Loc.t("Buy · %d denarii") % int(Data.shop.throwables.torch.price), "past the first boss the torch is for sale (%s)" % (ms.buy_btn.text if ms.buy_btn else "no button"))
	menu.queue_free()
