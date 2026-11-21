extends Node
## Friends who are not there, through the whole of it (`-- --probe friend_probe [--port N]`): this game opens an Arena room as a host does,
## brings friends in with the strip's own buttons (Friends opens a game of this project for each, FriendPilot plays him), and looks:
## that they join with their own names and arms, that they walk the yard and go into a stall when told (the host holds him untouchable
## there), that they fight as bots in a free for all, that a friend asked to leave leaves and one whose line is cut is found gone.
## Exit 0 when every check held. (e2e_kit.gd writes what was seen to user://e2e/friends.txt.)

const Kit := preload("res://tests/e2e_kit.gd")
const MenuScript := preload("res://scripts/ui/menu.gd")

var k: RefCounted
var menu: Node
var strip: FriendsStrip
var port := 17950

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	port = int(args[args.find("--port") + 1]) if args.has("--port") and args.size() > args.find("--port") + 1 else 17950
	k = Kit.new("friends", self)
	Save.data["name"] = "Aulus"
	menu = MenuScript.new()
	menu.backdrop_off = true
	add_child(menu)
	get_tree().create_timer(600.0).timeout.connect(func():
		k.check("run.time", false, "the run finished in time")
		if strip:
			strip.friends.kill_all()
		get_tree().quit(2))
	await k.pause(0.5)
	await _run()
	if strip:
		strip.friends.kill_all()
	print("FRIENDS %d ok, %d failed" % [k.passes, k.fails])
	await k.pause(0.5)
	get_tree().quit(1 if k.fails > 0 else 0)

func m() -> Match:
	return menu.match_

func _entity_of(name: String):
	if m() == null:
		return null
	for e in m().humans():
		if is_instance_valid(e.f) and String(e.f.display_name) == name:
			return e
	return null

## What each friend carries in his main hand, as the room was told: {his name: the weapon's name}.
func _mains() -> Dictionary:
	var out := {}
	for id in Net.peers:
		var mn = (Net.peers[id].get("loadout", {}) as Dictionary).get("main")
		out[String(Net.peers[id].name)] = String((mn as Dictionary).get("name", "?")) if mn is Dictionary else ""
	return out

func _in_yard_with(n: int) -> bool:
	return menu.in_yard() and m() != null and m().humans().size() == n

func _run() -> void:
	menu.show_screen("mp")
	await k.pause(0.3)
	menu._set_mp_kind(Net.KIND_ARENA)
	menu._host_room(func(): Net.host_enet(port))
	await k.pause(0.4)
	k.check("room", Net.is_host() and menu.screen == "room", "an Arena room is open on its lobby", "screen %s" % menu.screen)
	strip = FriendsStrip.new()
	get_tree().root.add_child(strip)
	strip.friends.port = port
	await k.pause(0.3)
	k.check("strip", Kit.button_named(strip, "Friend_add") != null and Kit.button_named(strip, "Friend_leave") != null and Kit.button_named(strip, "Friend_drop") != null and Kit.button_named(strip, "Friend_poor") != null, "the strip has its buttons: a friend in, away, cut off, a poor line")
	# Two friends in, by the strip's own button and by its key.
	Kit.press(Kit.button_named(strip, "Friend_add"))
	var key := InputEventKey.new()
	key.keycode = KEY_F6
	key.pressed = true
	strip._unhandled_input(key)
	k.check("start", strip.friends.count() == 2, "the + button and F6 each open a friend's game", "%d" % strip.friends.count())
	var came: bool = await k.until(func(): return Net.peers.size() == 2, 90.0, "two friends in the room")
	var names: Array = Net.peers.values().map(func(p): return String(p.name))
	k.check("join", came and names.has("Brutus") and names.has("Cassia"), "they join the room by address, each a friend of his own name", str(names))
	var want := {"Brutus": String(Data.preset("gladius").name), "Cassia": String(Data.preset("spear").name)}
	var told: bool = await k.until(func(): return _mains() == want, 30.0, "both told the room their arms")
	k.check("arms", told, "each is told to the room with arms of his own: the gladius and the spear", str(_mains()))
	k.check("strip.names", strip.names_label.text.contains("Brutus") and strip.names_label.text.contains("Cassia"), "the strip names the friends who are in", strip.names_label.text)
	# The yard.
	Kit.press(Kit.button_named(menu, "LobbyEnter"))
	var yard: bool = await k.until(func(): return _in_yard_with(3), 90.0, "the yard with both")
	k.check("yard", yard, "the host enters the yard and both friends are in it", "humans %d" % (m().humans().size() if m() else 0))
	if not yard:
		return
	var brutus = _entity_of("Brutus")
	var cassia = _entity_of("Cassia")
	# They walk.
	var walked := {"Brutus": 0.0, "Cassia": 0.0}
	var last := {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000:
		await k.pause(0.25)
		for n in walked:
			var e = _entity_of(n)
			if e != null:
				var p: Vector3 = e.f.torso.global_position
				if last.has(n):
					walked[n] += Vector2(p.x - last[n].x, p.z - last[n].z).length()
				last[n] = p
		if walked.Brutus > 4.0 and walked.Cassia > 4.0:
			break
	k.check("walk", walked.Brutus > 4.0 and walked.Cassia > 4.0, "each walks the yard by himself", "Brutus %.1f m, Cassia %.1f m" % [walked.Brutus, walked.Cassia])
	# A stall, on the host's word: he is held untouchable while he is in it, and comes out again.
	var bid := -1
	for id in Net.peers:
		if String(Net.peers[id].name) == "Brutus":
			bid = int(id)
	Net.send_to(bid, "friend_cmd", "stall:market")
	var held: bool = await k.until(func(): return _entity_of("Brutus") != null and bool(_entity_of("Brutus").f.untouchable), 60.0, "Brutus at the market")
	k.check("stall", held, "told to go into the market he walks there, opens it, and the host holds him untouchable")
	var out: bool = await k.until(func(): return _entity_of("Brutus") != null and not bool(_entity_of("Brutus").f.untouchable), 40.0, "Brutus out of the market")
	k.check("stall.out", out, "and after a while he comes out of it")
	# A quarrel in the yard.
	Net.send_to(bid, "friend_cmd", "brawl")
	var cid := -1
	for id in Net.peers:
		if String(Net.peers[id].name) == "Cassia":
			cid = int(id)
	Net.send_to(cid, "friend_cmd", "brawl")
	await k.pause(12.0)
	var hurt := 0
	for e in m().humans():
		if is_instance_valid(e.f):
			for p in e.f.parts:
				if p.hp < 99.5 or p.severed:
					hurt += 1
	k.check("quarrel", hurt > 0, "friends who pick a quarrel hurt someone in the yard", "%d parts hurt" % hurt)
	# A fight: a free for all, the friends fight as bots.
	menu._set_fight_opt("ffa", "rounds", 1)
	menu._set_fight_opt("ffa", "bots", 0)
	menu._open_station("gate")
	await k.pause(0.4)
	Kit.press(Kit.button_with(menu, "Free for all"))
	await k.pause(0.3)
	Kit.press(Kit.button_with(menu, "Begin"))
	var fight: bool = await k.until(func(): return m() != null and m().mode == "ffa" and m().entities.size() >= 3, 60.0, "the free for all")
	k.check("fight", fight, "a free for all begins with both friends in it")
	if fight:
		await k.pause(25.0)
		var moved := 0
		var hurt2 := 0
		for e in m().humans():
			if is_instance_valid(e.f):
				if e.f.torso.global_position.length() > 0.5:
					moved += 1
				for p in e.f.parts:
					if p.hp < 99.5 or p.severed:
						hurt2 += 1
		k.check("fight.play", moved >= 2 and hurt2 > 0, "the friends take part: they close on one another and blows land", "%d moved, %d parts hurt" % [moved, hurt2])
		# The host wins it: everyone is back in the yard.
		for e in m().entities.duplicate():
			if e != m().me and is_instance_valid(e.f) and e.f.alive:
				e.f.die("decap")
		var back: bool = await k.until(func(): return _in_yard_with(3), 60.0, "back in the yard")
		k.check("fight.back", back, "the bout decided, all three are back in the yard")
	# One says goodbye.
	var before := strip.friends.count()
	Kit.press(Kit.button_named(strip, "Friend_leave"))
	var one: bool = await k.until(func(): return Net.peers.size() == 1, 30.0, "one friend left")
	k.check("leave", one, "the newest friend is asked to leave and goes: the room lists one friend", str(Net.peers.values().map(func(p): return String(p.name))))
	var closed: bool = await k.until(func(): return strip.friends.count() == before - 1, 20.0, "his game closed")
	k.check("leave.closed", closed, "and his game closes", "%d games" % strip.friends.count())
	# The other one's line is cut.
	Kit.press(Kit.button_named(strip, "Friend_drop"))
	var gone: bool = await k.until(func(): return Net.peers.is_empty(), 60.0, "the second friend found gone")
	k.check("drop", gone, "a friend whose line is cut without a word is found gone by the room", "%d in the room" % Net.peers.size())
	# A poor line for the next.
	Kit.press(Kit.button_named(strip, "Friend_poor"))
	k.check("poor", strip.friends.poor, "the ~ button makes the next friends come over a poor line")
