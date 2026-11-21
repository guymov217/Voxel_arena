extends Node
## Friends who are not there (Friends, FriendsStrip, FriendPilot), the parts that need no second game: what a friend's game is started
## with, the table of who they are, who comes next, what the strip's buttons and keys do, and what the host's words make a friend
## do. (A game that opens games, and one that joins by address, is tests/friend_probe.gd.)

var t

## The game a friend plays is this project's, run with no window; what makes it a friend comes after `--` (the game's own arguments).
func test_a_friends_game_is_started_with_its_room_and_its_persona() -> void:
	var a := Friends.args_for(2, 17950, "/the/project", true, 0, 0, "/tmp/f.log")
	var dash := a.find("--")
	t.check(dash > 0, "the game's own arguments are set apart by --")
	var mine := a.slice(dash + 1)
	t.eq(Array(mine), ["--friend", "--join", "127.0.0.1", "--port", "17950", "--persona", "2"], "he is a friend, joining the room by its address and port, as the persona asked")
	var engine := a.slice(0, dash)
	t.check(engine.has("--headless") and engine.has("--path") and engine[engine.find("--path") + 1] == "/the/project", "with no window, on the project's folder")
	t.check(engine.has("--log-file") and engine[engine.find("--log-file") + 1] == "/tmp/f.log", "and what he says in a file of his own")
	t.check(not a.has("--lag"), "a good line unless asked for a poor one")
	var poor := Friends.args_for(0, 8080, "", false, Friends.POOR_LAG, Friends.POOR_LOSS, "")
	t.check(not poor.has("--headless") and not poor.has("--path") and not poor.has("--log-file"), "a game of an exported build is not told a folder, and a window is left to him that asked")
	var pd := poor.find("--")
	t.eq(Array(poor.slice(pd + 1)), ["--friend", "--join", "127.0.0.1", "--port", "8080", "--persona", "0", "--lag", str(Friends.POOR_LAG), "--loss", str(Friends.POOR_LOSS)], "a poor line is the game's own pretend lag and loss")

## Each friend has a name of his own and arms the smith has: the room tells them apart by both.
func test_the_friends_have_names_and_arms_of_their_own() -> void:
	var names := {}
	var mains := {}
	var all_arms := true
	var bad := ""
	for p in Friends.PERSONAS:
		names[String(p.name)] = true
		mains[String(p.main)] = true
		var a := Arms.empty()
		for key in [String(p.main), String(p.off)]:
			if key == "":
				continue
			var r := Arms.buy(a, key, "R", "")
			if not r.has("arms"):
				all_arms = false
				bad = "%s: %s" % [p.name, key]
			else:
				a = r.arms
	t.eq(names.size(), Friends.PERSONAS.size(), "no two friends share a name")
	t.check(Friends.PERSONAS.size() >= Friends.MAX_FRIENDS, "there is a persona for every friend the room has a place for (%d)" % Friends.PERSONAS.size())
	t.check(all_arms, "every weapon a friend carries is one the smith sells (%s)" % bad)
	t.check(mains.size() >= 3, "and they do not all carry the same")
	for p in Friends.PERSONAS:
		t.check(float(p.temper) >= 0.0 and float(p.temper) <= 1.0 and float(p.shops) >= 0.0 and float(p.shops) <= 1.0, "%s's temper and taste for the stalls are shares" % p.name)

## What a persona carries is what his table says: his weapon in the main hand, and a shield in the other if he has one.
func test_a_friend_carries_what_his_persona_does() -> void:
	for i in Friends.PERSONAS.size():
		var p: Dictionary = Friends.PERSONAS[i]
		var lo := Arms.loadout(Friends.arms_of(i))
		t.eq(String(lo.main.name), String(Data.preset(String(p.main)).name), "%s carries his %s" % [p.name, p.main])
		if String(p.off) != "":
			t.check(lo.off is Dictionary and String(lo.off.name) == String(Data.preset(String(p.off)).name), "%s has a shield on his arm" % p.name)

## The next friend is the first of the table not in the room now; a table all taken goes round again.
func test_the_next_friend_is_the_first_not_in() -> void:
	var f := Friends.new()
	t.eq(f.next_persona(), 0, "the first friend is the first persona")
	f.friends.append({"pid": 0, "persona": 0, "name": String(Friends.PERSONAS[0].name), "at": 0})
	t.eq(f.next_persona(), 1, "the second is the next one")
	f.friends.append({"pid": 0, "persona": 1, "name": String(Friends.PERSONAS[1].name), "at": 0})
	f.friends.remove_at(0)
	t.eq(f.next_persona(), 0, "one who left leaves his place to the next who comes")
	f.friends.clear()
	for i in Friends.PERSONAS.size():
		f.friends.append({"pid": 0, "persona": i, "name": String(Friends.PERSONAS[i].name), "at": 0})
	t.eq(f.next_persona(), 0, "with every persona in, the table goes round to the first")
	t.eq(f.names().size(), Friends.PERSONAS.size(), "the names are those of the friends in")
	f.friends.clear()
	f.free()

## A room of eight has no place for another friend; no game is opened for one.
func test_a_full_room_opens_no_game() -> void:
	var f := Friends.new()
	for i in Friends.MAX_FRIENDS:
		f.friends.append({"pid": 0, "persona": i, "name": String(Friends.PERSONAS[i].name), "at": 0})
	t.check(not f.add(), "seven friends and the host fill the room: no more")
	t.eq(f.count(), Friends.MAX_FRIENDS, "and none was added")
	f.friends.clear()
	t.check(not f.leave_one() and not f.drop_one(), "with no friend in, none is sent away or cut off")
	f.free()

## The strip's buttons (named, for the end-to-end probe) and keys do what they say; the friends he shows are those in.
func test_the_strip_has_its_buttons_and_keys() -> void:
	var strip := FriendsStrip.new()
	add_child(strip)
	for n in ["Friend_add", "Friend_leave", "Friend_drop", "Friend_poor"]:
		t.check(strip.find_child(n, true, false) is Button, "a button %s" % n)
	t.eq(FriendsStrip.KEYS.size(), 4, "four keys")
	t.eq(String(FriendsStrip.KEYS[KEY_F6]) + String(FriendsStrip.KEYS[KEY_F7]) + String(FriendsStrip.KEYS[KEY_F8]) + String(FriendsStrip.KEYS[KEY_F9]), "addleavedroppoor", "F6 a friend comes, F7 goes, F8 is cut off, F9 a poor line")
	t.check(not strip.friends.poor, "a good line at first")
	strip.act("poor")
	t.check(strip.friends.poor and (strip.find_child("Friend_poor", true, false) as Button).button_pressed, "the poor line is chosen, and its button shows it")
	var key := InputEventKey.new()
	key.keycode = KEY_F9
	key.pressed = true
	strip._unhandled_input(key)
	t.check(not strip.friends.poor and not (strip.find_child("Friend_poor", true, false) as Button).button_pressed, "F9 chooses the good line again")
	t.check(not strip.names_label.visible, "no friend in: no names shown")
	strip.friends.friends.append({"pid": OS.get_process_id(), "persona": 0, "name": "Brutus", "at": 0})
	strip.friends.friends.append({"pid": OS.get_process_id(), "persona": 1, "name": "Cassia", "at": 0})
	strip.friends.changed.emit()
	t.check(strip.names_label.visible and strip.names_label.text == "Brutus, Cassia", "the names of the friends in are shown (%s)" % strip.names_label.text)
	strip.friends.friends.clear()   # (leaving the tree stops every game it holds: these were not games)
	strip.queue_free()
	await get_tree().process_frame

## What the host's word makes a friend do: a stall means he goes to it, a quarrel means he picks one now.
func test_a_friend_obeys_the_hosts_word() -> void:
	var pilot := FriendPilot.new()
	pilot.setup(null, 1, "127.0.0.1", 17950)
	t.eq(String(pilot.persona.name), "Cassia", "persona 1 is Cassia")
	pilot._on_message("friend_cmd", "stall:market", 1)
	t.eq(pilot.stall, "market", "told the market, he goes to the market")
	t.eq(pilot.state, "walk", "on foot")
	var there := Yard.STATIONS.market.p as Vector3
	t.check(Vector2(pilot.target.x - there.x, pilot.target.z - there.z).length() < 2.0, "to a place in front of its counter (%.1f m from it)" % Vector2(pilot.target.x - there.x, pilot.target.z - there.z).length())
	pilot._on_message("friend_cmd", "brawl", 1)
	t.check(pilot._quarrel_now and pilot._act_t == 0.0, "told to quarrel, he picks one at his next turn")
	pilot._on_message("something_else", "stall:smith", 1)
	t.eq(pilot.stall, "market", "a word that is not the host's friend_cmd changes nothing")
	pilot._on_message("friend_cmd", "stall:nowhere", 1)
	t.eq(pilot.state, "walk", "a stall the yard has not is no new errand")
	pilot.free()
