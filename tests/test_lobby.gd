extends Node
## The room's waiting room: who is in the room as each side tells it (Net.room_list, the roster a host sends and a guest reads),
## the screen that draws it (LobbyScreen: a card for each of the eight places, Mute, Remove, the way in for the host, the pause
## menu's door to it), and the way a room opens on it before anyone is in the yard.

var t

func _menu() -> Node:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	return menu

func _steps(n: int) -> void:
	for i in n:
		await get_tree().process_frame

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
	Net.my_name = "Aulus"
	if kind == Net.KIND_ARENA:
		menu._box_on()
	return [menu, fake]

func _leave_room_menu(pair: Array) -> void:
	pair[0]._box_off()
	pair[0].match_ = null
	pair[1].queue_free()
	pair[0].queue_free()
	Net.peers.clear()
	Net.guest_pings.clear()
	VoiceChat.muted.clear()
	Net.transport = ""
	Net.room_kind = Net.KIND_CAMPAIGN

func _named(menu: Node, what: String) -> Node:
	return menu.find_child(what, true, false)

func _buttons(menu: Node, prefix := "") -> Array:
	return menu.find_children("*", "Button", true, false).filter(func(b): return String(b.text).begins_with(prefix))

func _slots(menu: Node) -> Array:
	return menu.find_children("Slot*", "PanelContainer", true, false)

# ---------- Who is in the room ----------

func test_the_list_has_the_host_first_and_every_guest_as_he_came() -> void:
	Net.transport = "test"
	Net.my_name = "Aulus"
	Net.peers[12] = {"name": "Cassia"}
	Net.peers[9] = {"name": "Brutus"}
	Net.guest_pings[9] = 40.0
	var list := Net.room_list()
	t.eq(list.map(func(r): return r.name), ["Aulus", "Brutus", "Cassia"], "the host, then the guests by the order of their ids")
	t.eq(list.map(func(r): return r.host), [true, false, false], "only the first is the host")
	t.eq(list.map(func(r): return r.you), [true, false, false], "and the host is this game")
	t.eq(list.map(func(r): return r.ping), [0.0, 40.0, -1.0], "each guest's round trip, unknown until it is measured")
	Net.peers.clear()
	Net.guest_pings.clear()
	Net.transport = ""
	t.eq(Net.room_list(), [], "no room, no list")

func test_a_roster_from_the_wire_is_made_safe() -> void:
	var wire := {"p": [[1, "Aulus", 0], [7, "[b]Bold[/b]", 31.4], [8, "x".repeat(100), 99999], "junk", [3], [4, 5, "ping"], [5, "Eve", NAN], [6, "Ova", -50]]}
	var out := Net.clean_roster(wire)
	t.eq(out.size(), 6, "what is not an entry is dropped: %s" % str(out.map(func(r): return r.name)))
	t.eq(out[1].name, "(b)Bold(/b)", "no markup in a name")
	t.eq(String(out[2].name).length(), 24, "a name of 24 letters at most")
	t.eq(out[2].ping, 9999.0, "a round trip is kept to a sane number")
	t.eq(out[3].name, "5", "a number is a name that is written out")
	t.eq(out[3].ping, -1.0, "and a ping that is not a number is not known")
	t.eq(out[4].ping, -1.0, "NaN is not known either")
	t.eq(out[5].ping, -1.0, "and a ping below nothing is not known")
	var many := []
	for i in 20:
		many.append([i, "P%d" % i, 10])
	t.eq(Net.clean_roster({"p": many}).size(), Net.MAX_PLAYERS, "eight places and no more")
	for bad in [null, 5, "x", [], {"q": 1}, {"p": "no"}]:
		t.eq(Net.clean_roster(bad), [], "anything else is no roster: %s" % str(bad))

func test_the_addresses_to_join_by_are_the_networks_first() -> void:
	var got := Net.lan_from(["::1", "127.0.0.1", "169.254.7.7", "8.8.4.4", "10.1.2.3", "fe80::1", "172.17.0.2", "192.168.1.20", "192.168.1.20", "172.40.0.1", "0.0.0.0", "300.1.1.1", "a.b.c.d", "172.20.3.4"])
	t.eq(got, ["192.168.1.20", "10.1.2.3", "172.17.0.2", "172.20.3.4", "8.8.4.4", "172.40.0.1"], "the private ranges in order, then the rest; never the loopback or a link-local one")
	t.eq(Net.lan_from([]), [], "none found")

func test_the_connection_is_shown_in_bars() -> void:
	t.eq(LobbyScreen.bars_of(-1.0), 0, "not known yet")
	for pair in [[0.0, 4], [60.0, 4], [61.0, 3], [110.0, 3], [111.0, 2], [180.0, 2], [181.0, 1], [9999.0, 1]]:
		t.eq(LobbyScreen.bars_of(pair[0]), pair[1], "%d ms" % int(pair[0]))
	t.check(LobbyScreen.bars_colour(4) != LobbyScreen.bars_colour(2) and LobbyScreen.bars_colour(2) != LobbyScreen.bars_colour(1), "good, middling and poor look different")
	t.eq(LobbyScreen.ping_text(-1.0), "—", "unknown")
	t.eq(LobbyScreen.ping_text(34.4), "34 ms", "a round number of milliseconds")
	t.eq(LobbyScreen.initial_of("  cato"), "C", "the first letter, capital")
	t.eq(LobbyScreen.initial_of(""), "?", "and for no name a question")
	var seen := {}
	for i in Net.MAX_PLAYERS:
		seen[LobbyScreen.tint_of(i)] = true
	t.eq(seen.size(), Net.MAX_PLAYERS, "each place has a colour of its own")

# ---------- The screen ----------

func test_the_lobby_keeps_eight_places_and_says_who_holds_them() -> void:
	var pair := _room_menu(Net.KIND_ARENA)
	var menu: Node = pair[0]
	Net.peers[9] = {"name": "Brutus", "loadout": {"main": "gladius"}}
	Net.guest_pings[9] = 34.0
	menu.show_screen("room")
	await _steps(3)
	var lobby: Node = _named(menu, "Lobby")
	t.check(lobby != null, "the screen is the lobby")
	t.eq(lobby._grid.get_child_count(), Net.MAX_PLAYERS, "eight places, held or waiting")
	t.eq(_slots(menu).size(), 2, "two of them held: the host and a friend")
	t.eq(lobby._count.text, "2 / 8", "the count says so")
	t.check(_named(menu, "Mute1") != null and _named(menu, "Remove1") != null, "the friend can be muted and, by the host, removed")
	t.check(_named(menu, "Mute0") == null and _named(menu, "Remove0") == null, "the host's own card has neither")
	# A friend comes in: his card is there within a moment, without the screen being drawn again.
	var grid_was: Node = lobby._grid
	Net.peers[10] = {"name": "Cassia", "loadout": {"main": "gladius"}}
	await _steps(40)
	t.eq(_slots(menu).size(), 3, "a friend who came is on a card")
	t.eq(lobby._count.text, "3 / 8", "and in the count")
	t.check(lobby._grid == grid_was, "the screen itself stayed")
	Net.peers.erase(9)
	await _steps(40)
	t.eq(_slots(menu).map(func(c): return String(c.name)), ["Slot0", "Slot1"], "one who went is gone from the cards")
	_leave_room_menu(pair)

func test_removing_a_friend_asks_twice() -> void:
	var pair := _room_menu(Net.KIND_ARENA)
	var menu: Node = pair[0]
	Net.peers[9] = {"name": "Brutus", "loadout": {"main": "gladius"}}
	menu.show_screen("room")
	await _steps(3)
	var rm: Button = _named(menu, "Remove1")
	var first := rm.text
	rm.pressed.emit()
	t.check(rm.text != first and rm.has_meta("armed"), "the first press only asks: '%s'" % rm.text)
	t.check(Net.peers.has(9), "and he is still there")
	_leave_room_menu(pair)

func test_mute_is_for_the_listener_alone_and_toggles() -> void:
	var pair := _room_menu(Net.KIND_ARENA)
	var menu: Node = pair[0]
	Net.peers[9] = {"name": "Brutus", "loadout": {"main": "gladius"}}
	menu.show_screen("room")
	await _steps(3)
	var mb: Button = _named(menu, "Mute1")
	var first := mb.text
	mb.pressed.emit()
	t.check(VoiceChat.muted.has(9), "his voice is not played here")
	t.check(mb.text != first, "and the button says how to undo it: '%s'" % mb.text)
	mb.pressed.emit()
	t.check(not VoiceChat.muted.has(9), "pressed again he is heard")
	t.eq(mb.text, first, "and the button is as it was")
	_leave_room_menu(pair)

func test_a_long_name_is_cut_on_its_card_and_kept_in_the_tooltip() -> void:
	var pair := _room_menu(Net.KIND_ARENA)
	var menu: Node = pair[0]
	Net.peers[9] = {"name": "Decimus Maximus Meridius", "loadout": {"main": "gladius"}}
	menu.show_screen("room")
	await _steps(3)
	var names: Array = _named(menu, "Slot1").find_children("*", "Label", true, false).filter(func(l): return String(l.text) == "Decimus Maximus Meridius")
	t.eq(names.size(), 1, "his name is on his card")
	t.check(names[0].clip_text and names[0].text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "cut with dots where the card ends")
	t.eq(names[0].tooltip_text, "Decimus Maximus Meridius", "and whole in its tooltip")
	_leave_room_menu(pair)

# ---------- What the host does next, by the kind of room ----------

func test_the_host_of_an_arena_room_has_the_yard_to_enter() -> void:
	var pair := _room_menu(Net.KIND_ARENA)
	var menu: Node = pair[0]
	menu.match_ = null   # (the waiting room: no yard yet)
	menu.show_screen("room")
	await _steps(3)
	t.check(_named(menu, "LobbyEnter") is Button, "the way into the yard")
	t.check(_named(menu, "LobbyCampaign") == null and _named(menu, "LobbyYard") == null, "no campaign to start in the friends' room")
	t.check(_named(menu, "LobbyLeave") is Button and String(_named(menu, "LobbyLeave").text).contains("CLOSE"), "and the room to close")
	t.check(_named(menu, "LobbyInvite0") != null or Net.lan_addresses().is_empty(), "the first free place gives a friend the way in (the address, copied) when this computer has one")
	t.check(_named(menu, "LobbyWait") == null, "he waits for no one")
	pair[0].match_ = pair[1]
	_leave_room_menu(pair)

func test_the_host_of_a_campaign_room_has_the_campaign_to_start() -> void:
	Save.set_value("coop_stage", 1)
	var pair := _room_menu(Net.KIND_CAMPAIGN)
	var menu: Node = pair[0]
	menu.match_ = null
	menu.show_screen("room")
	await _steps(3)
	t.check(_named(menu, "LobbyCampaign") is Button and _named(menu, "LobbyYard") is Button, "the campaign to start, or the yard first")
	t.check(_named(menu, "LobbyEnter") == null, "the yard is one way in, not the main one")
	t.eq(menu.find_children("*", "OptionButton", true, false).size(), 1, "before the first bout he says how death is dealt with")
	var cap: Button = _named(menu, "LobbyCampaign")
	t.check(not cap.disabled, "alone, the campaign can begin")
	# A fifth in the room: the campaign takes four at most.
	for i in 4:
		Net.peers[20 + i] = {"name": "Friend%d" % i, "loadout": {"main": "gladius"}}
	await _steps(40)
	t.check(Net.campaign_full(), "five in the room are too many")
	t.check(cap.disabled, "the campaign's button is held back")
	t.check(menu.find_children("*", "Label", true, false).any(func(l): return l.visible and String(l.text) == "4 at most"), "with the reason on the screen")
	t.check(String(cap.tooltip_text).contains("takes 4 players at most"), "and in full on the button")
	t.eq(_slots(menu).size(), 5, "and all five are on cards")
	Net.peers.erase(23)
	await _steps(40)
	t.check(not cap.disabled, "one fewer and it can begin")
	menu.match_ = pair[1]
	_leave_room_menu(pair)

func test_over_the_yard_the_room_leads_back_or_to_the_gate() -> void:
	var pair := _room_menu(Net.KIND_ARENA)
	var menu: Node = pair[0]
	Net.peers[9] = {"name": "Brutus", "loadout": {"main": "gladius"}}
	menu._toggle_pause()
	await _steps(2)
	var door := _buttons(menu, "The room")
	t.eq(door.size(), 1, "the pause menu has a door to the room")
	t.check(String(door[0].text).contains("2 of 8"), "and says how many are in it: %s" % door[0].text)
	door[0].pressed.emit()
	await _steps(3)
	t.check(menu.over_match and menu.screen == "room", "the room's screen, over the game")
	t.check(_named(menu, "LobbyGate") is Button, "the host can go on to the gate from it")
	t.check(_named(menu, "LobbyEnter") == null, "he is in the yard: nothing to enter")
	t.check(_named(menu, "Mute1") != null and _named(menu, "Remove1") != null, "and the friends can be muted and removed")
	var way_out: Array = menu.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("leave"))
	t.eq(way_out.size(), 1, "and the way back at the top, as from every stall")
	way_out[0].pressed.emit()
	t.check(not menu.visible and not menu.over_match, "back in the yard")
	_leave_room_menu(pair)

# ---------- A room opens on its waiting room ----------

func test_a_room_opens_on_the_lobby_and_the_yard_waits_for_the_host() -> void:
	var menu := _menu()
	await _steps(2)   # (the menu's world root is added deferred)
	Net.transport = "test"
	Net.room_kind = Net.KIND_ARENA
	Net.my_name = "Aulus"
	Net.connected.emit()
	await _steps(3)
	t.eq(menu.screen, "room", "the room is open: the host is on its waiting room")
	t.check(not menu.in_yard(), "not in the yard yet")
	t.check(Save.boxed, "and the friends' room has its sandbox already")
	var enter: Button = _named(menu, "LobbyEnter")
	t.check(enter != null, "the way in is a button")
	if enter != null:
		enter.pressed.emit()
		await _steps(4)
		t.check(menu.in_yard(), "pressed, the yard is open")
		t.eq(menu.match_.role, "host", "and he is its host")
	menu._end_match()
	menu._box_off()
	menu.queue_free()
	Net.peers.clear()
	Net.transport = ""
	Net.room_kind = Net.KIND_CAMPAIGN

func test_leaving_the_lobby_goes_back_to_the_multiplayer_screen() -> void:
	var menu := _menu()
	await _steps(2)
	Net.transport = "test"
	Net.room_kind = Net.KIND_CAMPAIGN
	Net.connected.emit()
	await _steps(3)
	t.eq(menu.screen, "room", "on the waiting room")
	var out: Button = _named(menu, "LobbyLeave")
	t.check(out != null and String(out.text).contains("CLOSE"), "the host closes the room")
	menu._lobby_leave()
	t.eq(menu.screen, "mp", "and is at the Multiplayer screen")
	t.check(not Net.active(), "the room is closed")
	menu.queue_free()
	Net.transport = ""
