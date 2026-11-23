extends Node
## The host plays the party's campaign with different friends at different times, and each group has a campaign of its own: how far it
## has got (the stage, the lap, the gate's wins, the run's scroll...) kept apart from the others', the friends who play it noted for the
## lobby's card, a new one begun for a new group, an old one come back to as it was (with the host's gladiator of it, and the guests' told
## which run it is), a lost run begun again as the same group's, and only the last forty kept.

var t

func _menu() -> Node:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	return menu

func _steps(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## What a campaign keeps of how far it has got (the party's `coop_` keys of the save).
func _progress(stage: int, lap := 1) -> void:
	Save.set_value("coop_stage", stage)
	Save.set_value("coop_lap", lap)
	Save.set_value("coop_checkpoint", stage)
	Save.set_value("coop_gate_won", [stage])
	Save.set_value("coop_scroll", {"Ann": {"bouts": stage}})
	Save.set_value("coop_favourite", "Ann")

func _slot(run: int) -> Dictionary:
	for s in Save.coop_slots():
		if int(s.run) == run:
			return s
	return {}

func test_each_group_keeps_its_own_progress() -> void:
	Save.data["coop_run"] = 1000
	_progress(5, 2)
	Save.coop_open(2000)
	t.eq(int(Save.data.coop_run), 2000, "another group's campaign is open")
	t.eq(int(Save.get_value("coop_stage", 1)), 1, "at bout 1")
	t.eq(int(Save.get_value("coop_lap", 1)), 1, "in its first lap")
	t.eq(Save.get_value("coop_gate_won", []), [], "none of the first group's gate wins")
	t.eq(Save.get_value("coop_scroll", {}), {}, "nor its scroll")
	t.eq(String(Save.get_value("coop_favourite", "")), "", "nor its favourite")
	_progress(3)
	Save.coop_open(1000)
	t.eq(int(Save.get_value("coop_stage", 1)), 5, "the first group's campaign is at the bout it was")
	t.eq(int(Save.get_value("coop_lap", 1)), 2, "in its lap")
	t.eq(Save.get_value("coop_gate_won", []), [5], "with its gate's wins")
	t.eq(Save.get_value("coop_scroll", {}), {"Ann": {"bouts": 5}}, "its scroll")
	t.eq(String(Save.get_value("coop_favourite", "")), "Ann", "and its favourite")
	Save.coop_open(2000)
	t.eq(int(Save.get_value("coop_stage", 1)), 3, "the second's is where it was left too")

func test_the_slots_say_who_plays_each_and_how_far_it_has_got() -> void:
	Save.data["coop_run"] = 1000
	_progress(5)
	Save.coop_note_members(["Ann", "Bob"])
	Save.coop_open(2000)
	_progress(3)
	Save.coop_note_members(["Cy"])
	var s: Array = Save.coop_slots()
	t.eq(s.size(), 2, "two campaigns kept")
	t.eq(int(s[0].run), 1000, "in the order they were begun")
	t.eq(int(s[0].stage), 5, "the first at bout 5")
	t.eq(s[0].members, ["Ann", "Bob"], "played by Ann and Bob")
	t.check(not bool(s[0].active), "and put away")
	t.eq(int(s[1].run), 2000, "the second")
	t.eq(int(s[1].stage), 3, "at bout 3")
	t.eq(s[1].members, ["Cy"], "played by Cy")
	t.check(bool(s[1].active), "and open")

func test_a_new_group_begins_a_campaign_and_the_others_are_kept() -> void:
	Save.data["coop_run"] = 1000
	_progress(5)
	var run := Save.coop_begin_new()
	t.check(run > 0 and run != 1000, "a number of its own")
	t.eq(int(Save.data.coop_run), run, "and it is the open one")
	t.eq(int(Save.get_value("coop_stage", 1)), 1, "at bout 1")
	t.eq(Save.coop_slots().size(), 2, "the other is kept")
	t.eq(int(_slot(1000).stage), 5, "at its bout")
	Save.coop_open(1000)
	t.eq(int(Save.get_value("coop_stage", 1)), 5, "and comes back as it was")

func test_a_save_from_before_there_were_campaigns_to_choose_from_opens_as_it_was() -> void:
	Save.data["coop_run"] = 77
	Save.data["coop_stage"] = 6
	Save.data["coop_lap"] = 2
	t.check(not Save.data.has(Save.SLOTS_KEY), "no slots in it")
	var s: Array = Save.coop_slots()
	t.eq(s.size(), 1, "its one campaign is listed")
	t.check(int(s[0].run) == 77 and int(s[0].stage) == 6 and bool(s[0].active), "open, at its bout")
	Save.coop_begin_new()
	t.eq(int(Save.get_value("coop_stage", 1)), 1, "a new group's is at bout 1")
	Save.coop_open(77)
	t.check(int(Save.get_value("coop_stage", 1)) == 6 and int(Save.get_value("coop_lap", 1)) == 2, "and the old one comes back whole")

func test_a_campaign_begun_again_is_the_same_group_under_a_new_number() -> void:
	Save.data["coop_run"] = 1000
	Save.coop_note_members(["Ann"])
	Save.box_begin({}, "coop", 1000)
	Save.box_end()
	Save.coop_open(2000)
	Save.coop_open(1000)
	Save.set_value("coop_campaign_mode", "legionary")
	Save.coop_restart(555)
	t.eq(int(Save.data.coop_run), 555, "the campaign has a new number")
	t.eq(Save.coop_slots().size(), 2, "the other group's is kept, and the old number is not a campaign of its own")
	t.check(_slot(1000).is_empty() and int(_slot(555).run) == 555, "the slot goes on under the new number")
	t.eq(_slot(555).members, ["Ann"], "with the friends who play it")
	t.check(not (Save.data.get(Save.COOP_KEY, {}) as Dictionary).has("1000"), "the old run's gladiator is given up")
	t.eq(String(Save.get_value("coop_campaign_mode", "")), "legionary", "and how death is dealt with is as the party chose it")

func test_only_the_last_campaigns_are_kept() -> void:
	Save.data["coop_run"] = 1
	Save.box_begin({"coins": 5}, "coop", 1)
	Save.box_end()
	for i in range(2, Save.COOP_KEPT + 6):
		Save.coop_open(i)
	var s: Array = Save.coop_slots()
	t.eq(s.size(), Save.COOP_KEPT, "no more than %d kept" % Save.COOP_KEPT)
	t.check(not _slot(Save.COOP_KEPT + 5).is_empty() and bool(_slot(Save.COOP_KEPT + 5).active), "the open one is never the one to go")
	t.check(_slot(1).is_empty() and _slot(2).is_empty(), "the ones played longest ago go")
	t.check(not (Save.data.get(Save.COOP_KEY, {}) as Dictionary).has("1"), "with the gladiator of the first")

func test_the_friends_of_a_campaign_are_noted_once_each_and_the_newest_last() -> void:
	Save.data["coop_run"] = 9
	Save.coop_note_members(["Ann", "Bob"])
	Save.coop_note_members(["Bob", "Cy", "", "  "])
	t.eq(_slot(9).members, ["Ann", "Bob", "Cy"], "each once, nobody nameless")
	for i in 20:
		Save.coop_note_members(["F%d" % i])
	var m: Array = _slot(9).members
	t.eq(m.size(), Save.SLOT_MEMBERS, "no more than %d names kept" % Save.SLOT_MEMBERS)
	t.eq(String(m[m.size() - 1]), "F19", "the newest last")

func test_the_host_opens_another_campaign_with_his_gladiator_of_it() -> void:
	var menu := _menu()
	await _steps(2)
	Net.transport = "test"   # (the offline peer: this game is the host)
	Net.room_kind = Net.KIND_CAMPAIGN
	Save.data["coop_run"] = 4242
	menu._coop_on(4242)
	Save.set_value("coop_stage", 7)
	menu.add_coins(40)
	menu._coop_new_slot()
	var b: int = Net.coop_run
	t.check(b != 4242 and b > 0 and Save.coop() and Save.box_run == b, "a campaign for a new group: a run of its own, in a profile of its own")
	t.eq(int(Save.data.coop_run), b, "kept in the host's save")
	t.eq(menu.coins(), int(Save.DEFAULTS.coins), "a new man, as a new campaign begins him")
	t.eq(int(Save.get_value("coop_stage", 1)), 1, "at bout 1")
	menu.add_coins(5)
	menu._coop_open_slot(4242)
	t.check(Net.coop_run == 4242 and Save.coop() and Save.box_run == 4242, "the first campaign opened again: its run, its profile")
	t.eq(menu.coins(), int(Save.DEFAULTS.coins) + 40, "his gladiator of it as he left it")
	t.eq(int(Save.get_value("coop_stage", 1)), 7, "and the campaign at the bout it was")
	menu._coop_open_slot(b)
	t.eq(menu.coins(), int(Save.DEFAULTS.coins) + 5, "the other's man is his own too")
	# The one open is not opened again, nor a number that is nothing.
	menu._coop_open_slot(b)
	menu._coop_open_slot(0)
	t.check(Net.coop_run == b and Save.box_run == b, "opening the open one, or none, changes nothing")
	menu._box_off()
	menu.queue_free()
	Net.transport = ""
	Net.coop_run = 0

func test_a_lost_run_is_the_same_group_begun_again() -> void:
	var menu := _menu()
	await _steps(2)
	Net.transport = "test"
	Net.room_kind = Net.KIND_CAMPAIGN
	Save.data["coop_run"] = 31
	menu._coop_on(31)
	Save.coop_note_members(["Ann"])
	Save.set_value("coop_campaign_mode", "legionary")
	menu._coop_new_run()
	t.check(Net.coop_run != 31 and Net.coop_run > 0 and int(Save.data.coop_run) == Net.coop_run, "a new number")
	var s: Array = Save.coop_slots()
	t.eq(s.size(), 1, "still one campaign: the group's own")
	t.check(int(s[0].run) == Net.coop_run and s[0].members == ["Ann"], "with its friends")
	t.eq(String(Save.get_value("coop_campaign_mode", "")), "legionary", "and how death is dealt with is as they chose it")
	menu._box_off()
	menu.queue_free()
	Net.transport = ""
	Net.coop_run = 0

func test_the_friends_in_the_room_are_noted_as_the_group_that_plays() -> void:
	var menu := _menu()
	await _steps(2)
	Net.transport = "test"
	Net.room_kind = Net.KIND_CAMPAIGN
	Net.my_name = "Aulus"
	Net.peers[12] = {"name": "Cassia"}
	Net.peers[13] = {"name": "Decimus"}
	Save.data["coop_run"] = 4242
	menu._coop_on(4242)
	menu._coop_note_friends()
	t.eq(_slot(4242).members, ["Cassia", "Decimus"], "the friends, not the host whose campaign it is")
	Net.room_kind = Net.KIND_ARENA
	Net.peers[14] = {"name": "Ennius"}
	menu._coop_note_friends()
	t.eq(_slot(4242).members, ["Cassia", "Decimus"], "and nobody from the friends' Arena room")
	menu._box_off()
	menu.queue_free()
	Net.peers.clear()
	Net.transport = ""
	Net.room_kind = Net.KIND_CAMPAIGN
	Net.coop_run = 0
