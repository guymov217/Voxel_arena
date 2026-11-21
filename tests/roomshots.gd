extends Node
## The screens of the two kinds of room (`-- --probe roomshots`, needs a display): the Multiplayer screen with each kind picked,
## the room screen, the Arena's list and the fight settings in a friends' room, the endless arena's kit screen and its reward
## cards for a friend, and the pause menu of each kind of room. PNGs go to SHOT_DIR as room_<name>.png.

var menu: Node
var out := ""

func _snap(name: String, frames := 40) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("room_%s.png" % name))
	print("saved ", name)

func _ready() -> void:
	out = OS.get_environment("SHOT_DIR")
	var st: Dictionary = Save.get_value("settings", {})
	st["quality"] = "low"
	Save.set_value("settings", st)
	menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = OS.get_environment("NO_FIGHT") != ""
	add_child(menu)
	for i in 30:
		await get_tree().process_frame
	# The Multiplayer screen, each kind picked.
	menu._set_mp_kind("arena")
	menu.show_screen("mp")
	await _snap("mp_arena")
	menu._set_mp_kind("campaign")
	menu.show_screen("mp")
	await _snap("mp_campaign")
	menu._set_mp_kind("arena")
	# A friends' room: this game the host (the offline peer), a friend in it, a yard in name only.
	var fake := Match.new()
	fake.mode = "yard"
	add_child(fake)
	menu.match_ = fake
	Net.transport = "test"
	Net.room_kind = Net.KIND_ARENA
	Net.my_name = "Aulus"
	Net.peers[9] = {"name": "Brutus", "loadout": {"main": "gladius"}}
	Net.guest_pings[9] = 34.0
	menu._box_on()
	# The waiting room as the host first sees it (no yard yet), alone and with a friend; then the same over the yard.
	menu.match_ = null
	Net.peers.erase(9)
	menu.show_screen("room")
	await _snap("lobby_wait_alone")
	Net.peers[9] = {"name": "Brutus", "loadout": {"main": "gladius"}}
	await _snap("lobby_wait_arena", 30)
	menu.match_ = fake
	menu.show_screen("room")
	await _snap("lobby_arena")
	# A full room: seven friends with every sort of connection, one with a name too long for his card.
	var friends := [["Cassia", 72.0], ["Decimus Maximus Meridius", 140.0], ["Flavia", 228.0], ["Gaius", 18.0], ["Hector", -1.0], ["Iulia", 95.0]]
	for i in friends.size():
		Net.peers[10 + i] = {"name": friends[i][0], "loadout": {"main": "gladius"}}
		Net.guest_pings[10 + i] = friends[i][1]
	menu.match_ = null
	menu.show_screen("room")
	await _snap("lobby_full", 40)
	menu.match_ = fake
	# The room's screen over the yard (the pause menu's "The room"), the host's.
	menu.over_match = true
	menu.show_screen("room")
	await _snap("lobby_over_yard", 20)
	menu.over_match = false
	for i in friends.size():
		Net.peers.erase(10 + i)
		Net.guest_pings.erase(10 + i)
	menu.show_screen("fights")
	await _snap("fights_arena")
	for k in ["teams", "ffa", "tourney", "bo3"]:
		menu.fight_pick = k
		menu.show_screen("fight_setup")
		await _snap("setup_" + k)
	menu.endless_back = "fights"
	menu.show_screen("endless")
	await _snap("endless_room")
	menu._toggle_pause()
	await _snap("pause_arena")
	menu._toggle_pause()
	# The endless arena's reward cards, held out to a friend.
	menu._endless_offer(Endless.clean_offer([["blade", "axe"], ["pot", "nailPot"], ["armour", "lorica"]]), 3, 25.0, true)
	await _snap("endless_offer")
	menu._endless_done()
	# The campaign's room: its room screen, its pause menu.
	menu._box_off()
	Net.room_kind = Net.KIND_CAMPAIGN
	menu.match_ = null
	menu.show_screen("room")
	await _snap("lobby_campaign")
	menu.match_ = fake
	menu._toggle_pause()
	await _snap("pause_campaign")
	menu._toggle_pause()
	Net.peers.erase(9)
	Net.transport = ""
	get_tree().quit()
