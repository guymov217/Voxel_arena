extends Node
## The party's campaign gives every player, the host as much as a guest, a gladiator of the run's own: begun as a new single
## campaign begins a man (the stick, the purse of a new save, a whole body, no armour, no bag), kept in his own save under the
## run's number, with a purse, a bag, arms, armour and wounds that are his alone, while the single campaign's are never touched. A run
## that ends begins everyone again; a campaign room takes four, an Arena room eight; and the endless arena of a room goes in with what
## each bought and built in its yard.

var t

func _menu() -> Node:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	return menu

func _steps(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _single_campaign_values() -> void:
	Save.set_value("coins", 999)
	Save.set_value("kit", {"nailPot": 3})
	Save.set_value("arms", Arms.sanitize({"main": Data.preset("axe"), "off": null}))
	Save.set_value("armor_worn", ["helmet"])
	Save.set_value("body", {"missing": ["forearmL"]})

func test_a_man_begins_the_party_campaign_as_a_new_campaign_begins_him() -> void:
	var menu := _menu()
	_single_campaign_values()
	menu._coop_on(11)
	t.check(Save.coop() and Save.box_run == 11, "in the run's profile")
	t.eq(menu.coins(), int(Save.DEFAULTS.coins), "the purse a new save has")
	t.eq(JSON.stringify(menu.arms()), JSON.stringify(Arms.empty()), "the stick, nothing of his single campaign's blade")
	t.eq(menu.kit(), {}, "no bag")
	t.eq(menu.worn_armor(), [], "no armour")
	t.check((menu.body().missing as Array).is_empty(), "a whole body, the wound his single campaign left on him is not here")
	t.eq(Net.my_kit, {}, "and the room is told so")
	t.check((Net.my_body.get("missing", []) as Array).is_empty(), "his body too")
	menu._box_off()
	t.eq(int(Save.data.coins), 999, "out of the run: the single campaign's purse is as it was")
	t.eq(menu.kit().get("nailPot", 0), 3, "its bag")
	t.eq((menu.body().missing as Array), ["forearmL"], "its wound")
	menu.queue_free()

func test_the_purse_is_his_own_and_the_run_keeps_it() -> void:
	var menu := _menu()
	Save.set_value("coins", 500)
	menu._coop_on(21)
	menu.add_coins(40)
	t.eq(menu.coins(), int(Save.DEFAULTS.coins) + 40, "what he earns goes into his own purse")
	menu.add_coins(-100)
	t.eq(menu.coins(), int(Save.DEFAULTS.coins) - 60, "and what he buys comes out of it")
	menu.set_kit({"thunderPot": 2})
	menu._box_off()
	t.eq(menu.coins(), 500, "the single campaign's purse is untouched")
	menu._coop_on(21)
	t.eq(menu.coins(), int(Save.DEFAULTS.coins) - 60, "the same run: his purse as he left it")
	t.eq(menu.kit().get("thunderPot", 0), 2, "and his bag")
	menu._coop_on(22)
	t.eq(menu.coins(), int(Save.DEFAULTS.coins), "another run: a new man, a new purse")
	t.eq(menu.kit(), {}, "and a bare bag")
	menu._box_off()
	menu.queue_free()

func test_only_the_last_few_runs_are_kept() -> void:
	var menu := _menu()
	for run in range(1, Save.COOP_KEPT + 4):
		menu._coop_on(100 + run)
		menu.add_coins(run)
	menu._box_off()
	var kept: Dictionary = Save.data.get(Save.COOP_KEY, {})
	t.eq(kept.size(), Save.COOP_KEPT, "no more than %d runs kept" % Save.COOP_KEPT)
	t.check(kept.has(str(100 + Save.COOP_KEPT + 3)) and not kept.has("101"), "the newest stay, the oldest goes")
	menu.queue_free()

func test_a_run_that_ends_begins_everyone_again() -> void:
	var menu := _menu()
	Net.transport = "test"   # (the offline peer: this game is the host)
	Save.set_value("coins", 321)
	menu._coop_on(31)
	Net.coop_run = 31
	menu.add_coins(200)
	menu.set_kit({"nailPot": 1})
	menu.set_arms(Arms.sanitize({"main": Data.preset("axe"), "off": null}))
	menu._coop_new_run()
	t.check(Net.coop_run != 31 and Net.coop_run > 0, "the run has a new number")
	t.eq(int(Save.get_value("coop_run", 0)), Net.coop_run, "kept in the host's save")
	t.eq(menu.coins(), menu.START_COINS, "a beginner's purse")
	t.eq(menu.kit(), {}, "the pots went with him")
	t.eq(JSON.stringify(menu.arms()), JSON.stringify(Arms.empty()), "the stick")
	t.check(not (Save.data.get(Save.COOP_KEY, {}) as Dictionary).has("31"), "the old run's man is put away")
	menu._box_off()
	t.eq(int(Save.data.coins), 321, "and the single campaign's purse is as it was")
	menu.queue_free()
	Net.transport = ""
	Net.coop_run = 0

func test_the_party_campaign_restarted_is_a_new_run_for_the_host() -> void:
	var menu := _menu()
	await _steps(2)
	Net.transport = "test"
	Net.room_kind = Net.KIND_CAMPAIGN
	menu._coop_on(41)
	Save.set_value("coop_stage", 9)
	Save.set_value("stage", 3)
	menu.add_coins(100)
	menu.restart_campaign()
	t.eq(int(Save.get_value("coop_stage", 1)), 1, "the party's campaign is at bout 1")
	t.eq(int(Save.get_value("stage", 1)), 3, "the single campaign's bout is where it was")
	t.eq(menu.coins(), menu.START_COINS, "his purse begins again")
	t.eq(menu.screen, "campaign_mode", "and how death is dealt with is asked, as it is alone")
	menu._box_off()
	menu.queue_free()
	Net.transport = ""
	Net.room_kind = Net.KIND_CAMPAIGN
	Net.coop_run = 0

func test_a_campaign_room_takes_four_and_an_arena_room_eight() -> void:
	Net.room_kind = Net.KIND_CAMPAIGN
	t.eq(Net.room_cap(), 4, "the campaign's room: four")
	Net.room_kind = Net.KIND_ARENA
	t.eq(Net.room_cap(), 8, "the friends' Arena: eight")
	Net.room_kind = Net.KIND_CAMPAIGN

func test_the_endless_arena_of_a_room_goes_in_with_what_each_bought() -> void:
	var menu := _menu()
	await _steps(2)
	Net.transport = "test"
	Net.room_kind = Net.KIND_ARENA
	menu._box_on()
	var mine := Arms.sanitize({"main": Data.preset("longsword"), "off": null})
	Save.set_value("arms", mine)
	Save.set_value("armor_worn", ["helmet"])
	Save.set_value("kit", {"nailPot": 2})
	menu.start({"mode": "endless", "decrees": [], "hazards": [], "headless": true, "endless": {"daily": false}})
	await _steps(2)
	t.check(menu.match_ != null and menu.match_.me != null, "the fight begins at once")
	var f: Fighter = menu.match_.me.f
	t.eq(String(f.weapons.R.design.get("name", "")), String(Data.preset("longsword").get("name", "")), "with the blade he bought")
	t.check(f.weapons.L == null, "and no shield he does not own")
	t.check(Endless.new(null, {})._worn(f).has("helmet"), "in the helmet he bought")
	t.eq(int(menu.match_.me.inventory.get("nailPot", 0)), 2, "and the bag he filled")
	menu._end_match()
	# The card of a room goes straight in: no picking of arms and bag.
	menu._fight_press("endless")
	await _steps(2)
	t.check(menu.screen != "endless" and menu.match_ != null, "the card of a room does not open the picker")
	menu._end_match()
	menu._box_off()
	menu.queue_free()
	Net.transport = ""
	Net.room_kind = Net.KIND_CAMPAIGN

func test_alone_the_endless_arena_still_asks_for_arms_and_bag() -> void:
	var menu := _menu()
	await _steps(2)
	menu._fight_press("endless")
	await _steps(2)
	t.eq(menu.screen, "endless", "alone, the picker is where it was")
	menu.queue_free()
