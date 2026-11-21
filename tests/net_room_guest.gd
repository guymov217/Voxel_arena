extends Node
## Two-process test of an Arena room through the game's own menus, guest side: joins by address, is told what the room is and
## takes up the sandbox (his campaign's purse untouched, money no object), stands in the host's yard, sees the circles and who
## stands in them, and the team fight begin with the host's rounds and the state line.

const MenuScript := preload("res://scripts/ui/menu.gd")

var menu: Node
var circles_seen := false
var team_line := ""
var fight_seen := ""
var fight_rounds := 0
var _bye := false
var sandbox_seen := false
var lobby_seen := false
var lobby_names := []

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17781
	Save.data["coins"] = 77           # (his campaign's purse: it must be 77 at the end)
	Net.my_name = "Guest"
	Net.my_loadout = {"main": "gladius", "gear": ["helmet"]}   # (what his campaign gladiator would say of himself)
	menu = MenuScript.new()
	menu.backdrop_off = true
	add_child(menu)
	Net.message.connect(func(type, _d, _f):
		if type == "bye":
			_bye = true)
	await get_tree().process_frame
	await get_tree().process_frame
	print("GUEST join ", Net.join_enet("127.0.0.1", port))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and not _bye:
		await get_tree().process_frame
		if Save.boxed and menu.coins() == Save.UNLIMITED:
			sandbox_seen = true
		if not lobby_seen and menu.screen == "room" and menu.find_child("LobbyWait", true, false) != null and Net.room_list().size() == 2 and String(Net.room_list()[0].name) != "The host":
			lobby_seen = true   # (the host's lobby, as the guest sees it: the two of them, and he waits)
			lobby_names = Net.room_list().map(func(r): return "%s%s" % [r.name, "*" if r.host else ""])
		var m = menu.match_
		if m != null and is_instance_valid(m):
			if m.mode == "yard" and m.yard != null and m.yard.teams_on() and not circles_seen:
				circles_seen = true
				team_line = m.yard.team_line()
			if m.mode == "teams" and fight_seen == "":
				fight_seen = m.fight_status()
				fight_rounds = int(m.series.get("n", 0))
	var ok: bool = _bye
	print("GUEST the room was for ", Net.room_kind, "; the sandbox was on for him ", sandbox_seen)
	print("GUEST circles seen ", circles_seen, ": ", team_line, "; the fight: ", fight_seen, " over ", fight_rounds, " rounds")
	print("GUEST his campaign's purse ", Save.data.coins)
	print("GUEST the lobby he waited in listed ", lobby_names)
	ok = ok and sandbox_seen and lobby_seen and circles_seen and fight_rounds == 3 and int(Save.data.coins) == 77 and fight_seen != ""
	print("GUEST ", "ok" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
