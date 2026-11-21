extends Node
## Two-process test of an Arena room through the game's own menus, host side (`-- --probe net_room_host`): the host opens an
## Arena room (Menu._host_room), a guest comes in and is told what the room is, both have the sandbox (the campaign's purse
## untouched, money no object), the room opens on its lobby and the host opens the yard from it, the host sets a team fight (the circles in the yard), the guest walks into
## the other circle, the host begins, and the fight starts on both sides with each on his own team.

const MenuScript := preload("res://scripts/ui/menu.gd")

var menu: Node

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17781
	Save.data["coins"] = 150          # (the campaign's purse: it must be 150 at the end)
	Net.my_name = "Host"
	menu = MenuScript.new()
	menu.backdrop_off = true
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	menu._set_mp_kind(Net.KIND_ARENA)
	menu._host_room(func(): print("HOST listen ", Net.host_enet(port)))
	var ok := true
	# A room opens on its lobby: the host waits there for his friends and opens the yard when they are in.
	ok = await _until(func(): return menu.screen == "room", 10.0, "the host's lobby") and ok
	print("HOST in the lobby ", menu.screen == "room", " (yard ", menu.in_yard(), ") room kind ", Net.room_kind, " sandbox ", Save.boxed, " purse ", menu.coins())
	ok = ok and not menu.in_yard() and Save.boxed and menu.coins() == Save.UNLIMITED
	ok = await _until(func(): return not Net.peers.is_empty(), 25.0, "a guest") and ok
	var gid: int = Net.peers.keys()[0]
	await get_tree().create_timer(1.5).timeout   # (the roster goes to the guest, his connection is measured)
	var listed: Array = Net.room_list().map(func(r): return r.name)
	print("HOST the lobby lists ", listed, " and has his card ", menu.find_child("Slot1", true, false) != null)
	ok = ok and listed.size() == 2 and menu.find_child("Slot1", true, false) != null
	var enter: Button = menu.find_child("LobbyEnter", true, false)
	print("HOST the way into the yard is a button ", enter != null)
	ok = ok and enter != null
	if enter != null:
		enter.pressed.emit()
	ok = await _until(func(): return menu.in_yard() and menu.match_ != null and menu.match_.humans().size() == 2, 20.0, "the guest in the yard") and ok
	print("HOST the room: ", menu.match_.humans().size(), " in the yard; the guest's arms ", Net.peers[gid].get("loadout", {}).get("main", "?"))
	# The Arena's list: the team fight, two rounds, two bots. The circles are drawn in the yard; the guest is told.
	menu._set_fight_opt("teams", "rounds", 3)
	menu._set_fight_opt("teams", "bots", 2)
	menu._fight_go("teams")
	await get_tree().create_timer(0.5).timeout
	var ts: TeamSetup = menu.match_.yard.team_setup
	print("HOST circles up ", ts != null, " ready ", ts != null and ts.ready())
	ok = ok and ts != null and not ts.ready()
	# The host walks into red; the guest's own man is put into blue (the guest walks there on his own screen in a game; here
	# he stands in it as he would have walked).
	var host_e = menu.match_.me
	var guest_e = null
	for e in menu.match_.humans():
		if e != host_e:
			guest_e = e
	host_e.f.teleport(Vector3(TeamSetup.CENTRES[0].x, 0, TeamSetup.CENTRES[0].z))
	await get_tree().create_timer(0.6).timeout
	print("HOST only he is in a circle: ready ", ts.ready(), " waiting ", ts.waiting())
	ok = ok and not ts.ready()
	guest_e.f.teleport(Vector3(TeamSetup.CENTRES[1].x, 0, TeamSetup.CENTRES[1].z))
	ok = await _until(func(): return ts.ready(), 5.0, "both in a circle") and ok
	print("HOST everyone is in a circle: ready ", ts.ready(), " teams ", ts.assignment())
	await get_tree().create_timer(1.0).timeout
	menu._team_go()
	ok = await _until(func(): return menu.match_ != null and menu.match_.mode == "teams", 10.0, "the team fight") and ok
	await get_tree().create_timer(1.5).timeout
	var teams_of := {}
	for e in menu.match_.entities:
		teams_of[String(e.f.display_name)] = int(e.team)
	print("HOST the fight: ", teams_of, " rounds ", menu.match_.series.get("n", "-"), " status: ", menu.match_.fight_status())
	var host_team: int = int(menu.match_.me.team)
	var guest_team := -1
	for e in menu.match_.humans():
		if e != menu.match_.me:
			guest_team = int(e.team)
	ok = ok and host_team == 0 and guest_team == 1 and int(menu.match_.series.get("n", 0)) == 3
	# The campaign's purse is where it was.
	print("HOST the campaign's purse ", Save.data.coins, " (the room's ", menu.coins(), ")")
	ok = ok and int(Save.data.coins) == 150
	await get_tree().create_timer(1.5).timeout
	Net.send_all("bye", {})
	await get_tree().create_timer(0.8).timeout
	print("HOST ", "ok" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)

func _until(cond: Callable, secs: float, what: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > int(secs * 1000.0):
			print("HOST timed out waiting for ", what)
			return false
	return true
