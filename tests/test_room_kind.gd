extends Node
## The two kinds of room: the party's campaign (its purse the host's, limited) and the friends' Arena (a gladiator of his own
## kept apart from the campaign's, money no object). What the sandbox keeps away from the campaign, what the menu does in it,
## and that every way out of the room gives the campaign's own gladiator back.

var t

func _menu() -> Node:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	return menu

func _steps(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func test_a_room_says_what_it_is_for() -> void:
	t.eq(Net.clean_kind("arena"), "arena", "the friends' Arena")
	t.eq(Net.clean_kind("campaign"), "campaign", "the campaign")
	for bad in ["x", "", 5, null, [], {"k": "arena"}, "ARENA"]:
		t.eq(Net.clean_kind(bad), "campaign", "anything else is the campaign: %s" % str(bad))
	t.eq(Net.room_kind, "campaign", "a room not yet opened is the campaign's")

func test_the_sandbox_keeps_the_campaign_apart() -> void:
	Save.set_value("coins", 150)
	Save.set_value("kit", {"nailPot": 2})
	Save.set_value("arms", {"marker": "campaign"})
	Save.set_value("name", "Cato")
	Save.box_begin({"coins": Save.UNLIMITED})
	t.check(Save.boxed, "in the sandbox")
	t.eq(Save.get_value("coins"), Save.UNLIMITED, "a purse with no limit")
	t.eq(Save.get_value("kit", {}), {}, "the campaign's bag is not his here")
	t.check(not (Save.get_value("arms", {}) as Dictionary).has("marker"), "nor its arms")
	Save.set_value("coins", 5)
	Save.set_value("kit", {"thunderPot": 1})
	Save.set_value("body", {"missing": ["shinR"]})
	Save.set_value("name", "Brutus")
	t.eq(int(Save.data.coins), 150, "the campaign's purse is where it was")
	t.eq(Save.data.kit, {"nailPot": 2}, "and its bag")
	t.check(not Save.data.has("body"), "no wound reached the campaign's body")
	t.eq(Save.get_value("name"), "Brutus", "what is the man's own, not the campaign's (his name), is shared")
	Save.box_end()
	t.check(not Save.boxed, "out of it")
	t.eq(Save.get_value("coins"), 150, "the campaign's purse is read again")
	t.eq(Save.get_value("kit", {}), {"nailPot": 2}, "and its bag")
	t.eq(Save.get_value("name"), "Brutus", "the name stayed")
	# The arena gladiator is kept for the next time, in the save, under one key of its own.
	Save.box_begin()
	t.eq(Save.get_value("kit", {}), {"thunderPot": 1}, "the arena profile is kept for the next friends' room")
	t.check(Save.data.has(Save.BOX_KEY) and (Save.data[Save.BOX_KEY] as Dictionary).has("kit"), "under its own key")
	Save.erase("kit")
	t.check(not (Save.data[Save.BOX_KEY] as Dictionary).has("kit") and Save.data.kit == {"nailPot": 2}, "an erase there is only there")
	Save.box_end()

func test_a_test_run_never_starts_in_the_sandbox() -> void:
	Save.box_begin()
	Save.reset()
	t.check(not Save.boxed, "a new player's save is the campaign's")

func test_in_the_friends_room_money_is_no_object() -> void:
	var menu := _menu()
	Save.set_value("coins", 77)
	menu._box_on()
	t.eq(menu.coins(), Save.UNLIMITED, "no limit")
	menu.add_coins(-5000)
	t.eq(menu.coins(), Save.UNLIMITED, "nothing spent comes off it")
	menu.add_coins(400)
	t.eq(menu.coins(), Save.UNLIMITED, "nothing won goes into it")
	t.eq(int(Save.data.coins), 77, "the campaign's purse is where it was")
	menu.set_kit({"thunderPot": 2})
	t.eq(Save.data.get("kit", {}), {}, "a bag bought is the arena's, not the campaign's")
	t.eq(menu.kit().get("thunderPot", 0), 2, "and is his there")
	menu._box_off()
	t.eq(menu.coins(), 77, "out of it: the campaign's own purse")
	t.eq(menu.kit().get("thunderPot", 0), 0, "and bag")
	menu.queue_free()

func test_a_man_new_to_the_friends_room_does_not_start_with_the_stick() -> void:
	var menu := _menu()
	Save.set_value("arms", {"marker": "campaign"})
	menu._box_on()
	var a: Dictionary = menu.arms()
	t.eq(String(a.main.get("name", "")), String(Data.preset("gladius").get("name", "")), "a gladius in his hand")
	t.check(a.off != null and String(a.off.get("kind", "")) == "shield", "a shield on his arm")
	t.eq(menu.worn_armor(), ["helmet"], "a helmet")
	menu._box_off()
	t.check((Save.data.arms as Dictionary).has("marker"), "and the campaign's arms are as they were")
	# What he bought there is kept for the next time.
	menu._box_on()
	var mine := Arms.buy(menu.arms(), "axe", "R")
	t.check(mine.has("arms"), "he bought an axe there")
	Save.set_value("arms", mine.arms)
	menu._box_off()
	menu._box_on()
	t.check(String((menu.arms().off if menu.arms().off != null else menu.arms().main).get("name", "")) != "" and JSON.stringify(menu.arms()) == JSON.stringify(Arms.sanitize(mine.arms)), "the next friends' room finds him with it")
	menu._box_off()
	menu.queue_free()

func test_the_purse_of_the_friends_room_reads_as_an_infinity() -> void:
	t.eq(StationKit.coin_text(Save.UNLIMITED), "∞", "an infinity")
	t.eq(StationKit.coin_text(40), "40", "an ordinary purse as it is")
	var p := StationKit.Purse.new(Save.UNLIMITED, 24)
	add_child(p)
	t.eq(p.num.text, "∞", "the stalls show the same")
	p.set_value(50)
	t.eq(p.num.text, "50", "and a number again when it is one")
	p.queue_free()

func test_any_way_out_gives_the_campaigns_gladiator_back() -> void:
	var menu := _menu()
	Save.set_value("coins", 91)
	menu._box_on()
	t.eq(menu.coins(), Save.UNLIMITED, "in the friends' room")
	menu.show_screen("main")   # (no room: the screens of the menu are the campaign's)
	t.check(not Save.boxed, "any screen out of a room ends the sandbox")
	t.eq(menu.coins(), 91, "his own purse again")
	menu.queue_free()

func test_fights_of_the_friends_room_use_the_arms_of_its_yard() -> void:
	var menu := _menu()
	await _steps(2)   # (the world root of the menu is added deferred)
	Save.set_value("arms", {"marker": "campaign"})
	menu._box_on()
	var arena_arms := Arms.sanitize({"main": Data.preset("longsword"), "off": null})
	Save.set_value("arms", arena_arms)
	Save.set_value("armor_worn", ["helmet"])
	menu.start({"mode": "ffa", "decrees": [], "hazards": [], "headless": true})
	await _steps(2)
	t.check(menu.match_ != null and menu.match_.me != null, "the fight begins")
	var f: Fighter = menu.match_.me.f
	t.eq(String(f.weapons.R.design.get("name", "")), String(Data.preset("longsword").get("name", "")), "he fights with the arms he took in the yard")
	t.check(f.weapons.L == null, "and no shield he does not own")
	t.check(Endless.new(null, {})._worn(f).has("helmet"), "in the helmet he bought")
	menu._end_match()
	# The same fight alone (no friends' room): the fight's own weapons, as it always was.
	menu._box_off()
	menu.start({"mode": "ffa", "decrees": [], "hazards": [], "headless": true})
	await _steps(2)
	var g: Fighter = menu.match_.me.f
	t.eq(String(g.weapons.R.design.get("name", "")), String(Data.preset("gladius").get("name", "")), "alone: the fight hands out its own weapons")
	menu._end_match()
	menu.queue_free()

func test_the_campaigns_gear_is_not_worn_out_by_a_friends_fight() -> void:
	var menu := _menu()
	await _steps(2)
	var camp := Arms.sanitize({"main": Data.preset("axe"), "off": null})
	Save.set_value("arms", camp)
	Save.set_value("coins", 12)
	menu._box_on()
	menu.start({"mode": "ffa", "decrees": [], "hazards": [], "headless": true})
	await _steps(2)
	for e in menu.match_.entities:
		if e != menu.match_.me:
			e.f.die("wounds")
	await _steps(4)
	t.eq(String(Save.data.arms.main.get("name", "")), String(Data.preset("axe").get("name", "")), "the campaign's blade is the same blade")
	t.eq(int(Save.data.coins), 12, "and its purse the same purse")
	menu._end_match()
	menu._box_off()
	menu.queue_free()

# ---------- The screens of each kind of room ----------

## A menu with a yard in name only (what the screens ask is whether he is in it), hosting a room of this kind (the offline peer:
## this game is the host).
func _room_menu(kind: String) -> Array:
	var menu := _menu()
	var fake := Match.new()
	fake.mode = "yard"
	add_child(fake)
	menu.match_ = fake
	Net.transport = "test"
	Net.room_kind = kind
	if kind == Net.KIND_ARENA:
		menu._box_on()
	return [menu, fake]

func _leave_room_menu(pair: Array) -> void:
	pair[0]._box_off()
	pair[0].match_ = null
	pair[1].queue_free()
	pair[0].queue_free()
	Net.transport = ""
	Net.room_kind = Net.KIND_CAMPAIGN

func _buttons(menu: Node, prefix := "") -> Array:
	return menu.find_children("*", "Button", true, false).filter(func(b): return String(b.text).begins_with(prefix) and (prefix != "" or true))

func test_the_multiplayer_screen_offers_both_kinds_and_remembers_the_choice() -> void:
	var menu := _menu()
	menu.show_screen("mp")
	await _steps(2)
	var cards: Array = menu.find_children("*", "Button", true, false).filter(func(b): return b.toggle_mode)
	t.eq(cards.size(), 2, "two kinds of room to pick")
	t.eq(cards.filter(func(b): return b.button_pressed).size(), 1, "one of them picked")
	t.eq(menu._mp_kind(), Net.KIND_ARENA, "the friends' Arena the first time")
	cards[1].pressed.emit()   # (the campaign's card)
	await _steps(2)
	t.eq(menu._mp_kind(), Net.KIND_CAMPAIGN, "the other picked")
	t.eq(Save.get_value("settings", {}).get("room_kind"), "campaign", "and kept in the settings")
	cards = menu.find_children("*", "Button", true, false).filter(func(b): return b.toggle_mode)
	t.check(cards.size() == 2 and cards[1].button_pressed and not cards[0].button_pressed, "the screen shows it")
	var seen := []
	menu._host_room(func(): seen.append(Net.room_kind))
	t.eq(seen, ["campaign"], "a room is opened of the kind on the screen")
	menu._set_mp_kind("arena")
	menu._host_room(func(): seen.append(Net.room_kind))
	t.eq(seen, ["campaign", "arena"], "and of the other when that is picked")
	Net.room_kind = Net.KIND_CAMPAIGN
	menu.queue_free()

func test_the_campaign_room_has_no_arena_to_enter() -> void:
	var pair := _room_menu(Net.KIND_CAMPAIGN)
	var menu: Node = pair[0]
	menu.show_screen("gate")
	await _steps(2)
	t.eq(_buttons(menu, "An arena mode").size(), 0, "no way into the Arena from the campaign room's gate")
	t.eq(_buttons(menu, "Fights and party modes").size(), 0, "nor a way to the fights list")
	menu.show_screen("room")
	await _steps(2)
	t.check(menu.find_child("LobbyCampaign", true, false) is Button, "the room screen leads into the co-op campaign")
	_leave_room_menu(pair)

func test_the_friends_room_has_no_campaign_to_start() -> void:
	var pair := _room_menu(Net.KIND_ARENA)
	var menu: Node = pair[0]
	menu.show_screen("room")
	await _steps(2)
	t.check(menu.find_child("LobbyCampaign", true, false) == null, "no campaign to start in the friends' room")
	t.check(menu.find_child("LobbyEnter", true, false) is Button, "the yard to go into")
	menu.start({"mode": "coop", "role": "host"})
	await _steps(2)
	t.check(menu.match_ == pair[1], "asked anyway, the campaign does not begin (the yard goes on)")
	Save.data["stage"] = 5
	Save.data["coins"] = 321
	menu.restart_campaign()
	t.eq(int(Save.data.stage), 5, "and starting the campaign over is refused: his stage stays")
	t.eq(int(Save.data.coins), 321, "and his purse")
	_leave_room_menu(pair)

func test_the_pause_menu_says_where_he_is_and_never_offers_to_wipe_the_campaign() -> void:
	var pair := _room_menu(Net.KIND_ARENA)
	var menu: Node = pair[0]
	Save.set_value("name", "Cato")
	Net.my_name = "Cato"
	Net.peers[9] = {"name": "Brutus", "loadout": {"main": "gladius"}}
	menu._toggle_pause()
	await _steps(2)
	t.eq(_buttons(menu, "Restart the campaign").size(), 0, "no restart of the campaign from the friends' room")
	t.eq(_buttons(menu, "The Arena: pick a fight").size(), 1, "the host can pick a fight from the pause menu")
	t.eq(_buttons(menu, "Back to the yard").size(), 1, "and the way back is named")
	t.eq(_buttons(menu, "The room").size(), 1, "and a door to the room's own screen, which says who is in it")
	t.check(String(_buttons(menu, "The room")[0].text).contains("2 of 8"), "with how many: %s" % _buttons(menu, "The room")[0].text)
	menu._toggle_pause()
	Net.peers.erase(9)
	_leave_room_menu(pair)
	# The campaign room does offer the restart (to the host, in the yard).
	var pair2 := _room_menu(Net.KIND_CAMPAIGN)
	pair2[0]._toggle_pause()
	await _steps(2)
	t.eq(_buttons(pair2[0], "Restart the campaign").size(), 1, "the campaign room's host can")
	pair2[0]._toggle_pause()
	_leave_room_menu(pair2)

func test_the_arena_list_in_the_friends_yard_goes_back_to_the_yard() -> void:
	var pair := _room_menu(Net.KIND_ARENA)
	var menu: Node = pair[0]
	menu.show_screen("fights")
	await _steps(2)
	t.check(_buttons(menu, "◀  Back to the yard").size() == 1, "the way out at the top says where it leads")
	t.eq(_buttons(menu, "Back to the yard, all of you").size(), 0, "and is the only one (the yard went on behind)")
	t.eq(_buttons(menu, "Co-op").size(), 0, "no co-op campaign card among the fights")
	_leave_room_menu(pair)
