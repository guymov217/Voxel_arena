extends Node
## Friends who are not there through every mode of a room (`-- --probe friend_modes [--port N] [--quick]`): the host does what a host
## does, through the game's own screens, and the friends (Friends, FriendPilot: games of their own) are only what they are in a
## player's seat, with nothing done for them. If a friend does not answer something a friend must, it is the host that waits for
## him here, and the run says where: the circles of a team fight, the tournament, the Arena's other modes, Forge and Fight, the
## endless arena's rewards, and a campaign room's bout and gate. Exit 0 when every check held; user://e2e/friendmodes.txt has
## what was seen. `--quick` leaves out the tournament and the single modes.

const Kit := preload("res://tests/e2e_kit.gd")
const MenuScript := preload("res://scripts/ui/menu.gd")
const SMOKE := [["bo3", "Duel"], ["king", "King of the Arena"], ["hunt", "Monster Hunt"], ["emperor", "The Emperor watches"], ["hill", "King of the Hill"], ["lastLimb", "Last Limb Standing"]]

var k: RefCounted
var menu: Node
var strip: FriendsStrip
var port := 17990
var quick := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	port = int(args[args.find("--port") + 1]) if args.has("--port") and args.size() > args.find("--port") + 1 else 17990
	quick = args.has("--quick")
	k = Kit.new("friendmodes", self)
	Save.data["coins"] = 150
	Save.data["name"] = "Aulus"
	menu = MenuScript.new()
	menu.backdrop_off = true
	add_child(menu)
	get_tree().create_timer(2400.0).timeout.connect(func():
		k.check("run.time", false, "the run finished in time")
		if strip:
			strip.friends.kill_all()
		get_tree().quit(2))
	await k.pause(0.5)
	await _run()
	if strip:
		strip.friends.kill_all()
	if k.fails > 0:
		_dump_logs()
	print("FRIENDMODES %d ok, %d failed" % [k.passes, k.fails])
	await k.pause(0.5)
	get_tree().quit(1 if k.fails > 0 else 0)

func _run() -> void:
	if not await _room(Net.KIND_ARENA):
		return
	await _teams()
	if not quick:
		await _tourney()
		for mm in SMOKE:
			await _smoke(mm[0], mm[1])
	await _forge()
	await _endless()
	await _campaign()

# ---------- Helpers ----------

func m() -> Match:
	return menu.match_

## What each friend's game said of what he did (his log), to read why a check did not hold.
func _dump_logs() -> void:
	for p in Friends.PERSONAS:
		var f := FileAccess.open("user://friend_%s.log" % String(p.name).to_lower(), FileAccess.READ)
		if f == null:
			continue
		while not f.eof_reached():
			var line := f.get_line()
			if line.begins_with("FRIEND "):
				print("LOG ", line)

func _in_yard_with(n: int) -> bool:
	return menu.in_yard() and m() != null and m().humans().size() == n

## Everyone but the host falls (the round, or the bout, is the host's).
func _kill_others() -> void:
	var mine = m().me
	for e in m().entities.duplicate():
		if e != mine and is_instance_valid(e.f) and e.f.alive:
			e.f.die("decap")

## The gate's list over the yard, and the card of a fight on it pressed (its settings screen, if it has one, begun).
func _pick_fight(title: String, settings := true) -> bool:
	menu._open_station("gate")
	await k.pause(0.3)
	if not Kit.press(Kit.button_with(menu, title)):
		return false
	await k.pause(0.3)
	if settings and menu.screen == "fight_setup":
		return Kit.press(Kit.button_with(menu, "Begin"))
	return true

## Back in the yard, everyone: the host's own call, from the pause menu.
func _call_back() -> bool:
	menu._toggle_pause()
	await k.pause(0.3)
	var ok := Kit.press(Kit.button_with(menu, "Back to the yard (everyone)"))
	await k.pause(0.3)
	return ok

## The friends in a match: how many of those who are in it have a fighter, and how many of them are on their feet.
func _friends_in_match() -> Array:
	var n := 0
	var up := 0
	if m() != null:
		for e in m().humans():
			if e != m().me and is_instance_valid(e.f):
				n += 1
				if e.f.alive:
					up += 1
	return [n, up]

## A room of the kind, the host's, and two friends in it, and the yard with the three of them.
func _room(kind: String) -> bool:
	menu.show_screen("mp")
	await k.pause(0.3)
	menu._set_mp_kind(kind)
	menu._host_room(func(): Net.host_enet(port))
	await k.pause(0.4)
	if strip == null:
		strip = FriendsStrip.new()
		get_tree().root.add_child(strip)
	strip.friends.port = port
	await k.pause(0.3)
	strip.friends.add()
	strip.friends.add()
	var came: bool = await k.until(func(): return Net.peers.size() == 2, 90.0, "two friends in the room")
	k.check("%s.friends" % kind, came, "two friends join the %s room by address" % kind, str(Net.peers.values().map(func(p): return String(p.name))))
	if not came:
		return false
	if kind == Net.KIND_ARENA:
		Kit.press(Kit.button_named(menu, "LobbyEnter"))
		var yard: bool = await k.until(func(): return _in_yard_with(3), 90.0, "the yard with both")
		k.check("arena.yard", yard, "the yard with the three of them")
		return yard
	return true

# ---------- Red against Blue: the circles ----------

func _teams() -> void:
	menu._set_fight_opt("teams", "rounds", 1)
	var ok := await _pick_fight("Red vs Blue")
	var circles: bool = await k.until(func(): return m() != null and m().yard != null and m().yard.team_setup != null, 20.0, "the circles")
	k.check("teams.circles", ok and circles, "the team fight lays two circles on the sand")
	if not circles:
		return
	var ts: TeamSetup = m().yard.team_setup
	m().me.f.teleport(Vector3(TeamSetup.CENTRES[0].x, 0, TeamSetup.CENTRES[0].z))
	var all_in: bool = await k.until(func(): return ts.ready(), 60.0, "the friends in the circles")
	k.check("teams.walk", all_in, "the friends walk into a circle each by themselves, and the host may begin", ts.line(true))
	var sides := [ts.members(0).size(), ts.members(1).size()]
	k.check("teams.sides", sides[0] + sides[1] == 3 and sides[0] > 0 and sides[1] > 0, "and they stand in both: the circles are not left to one side", str(sides))
	m().station.emit("team_go")
	var fight: bool = await k.until(func(): return m() != null and m().mode == "teams", 30.0, "the team fight")
	await k.pause(2.0)
	var teams := []
	if fight:
		for e in m().humans():
			teams.append(int(e.team))
	k.check("teams.fight", fight and teams.size() == 3 and teams.all(func(t): return t == 0 or t == 1) and teams.has(0) and teams.has(1), "the fight begins with each friend on the side of his circle", str(teams))
	var inm := _friends_in_match()
	k.check("teams.friends", inm[0] == 2, "both friends are in the fight", str(inm))
	await k.pause(4.0)
	_kill_others()
	var yard: bool = await k.until(func(): return _in_yard_with(3), 40.0, "back in the yard")
	k.check("teams.back", yard, "the fight over, the three are back in the yard")

# ---------- The tournament ----------

func _tourney() -> void:
	menu._set_fight_opt("tourney", "rounds", 1)
	var ok := await _pick_fight("The Tournament")
	var began: bool = await k.until(func(): return menu.tourney != null and m() != null and m().mode == "tourney", 40.0, "a bout of the tournament")
	k.check("tourney.start", ok and began, "a tournament is drawn and its first bout begins with the friends in the draw")
	if not began:
		return
	await k.pause(4.0)
	var first = m()
	var fallen := 0
	for e in m().entities.duplicate():
		if fallen == 0 and e != m().me and is_instance_valid(e.f) and e.f.alive:
			e.f.die("decap")
			fallen += 1
	var moved: bool = await k.until(func(): return m() != first or menu.tourney == null or m().over, 30.0, "the bout settled")
	k.check("tourney.bout", moved, "a bout won, the tournament goes on")
	if await _call_back():
		var yard: bool = await k.until(func(): return _in_yard_with(3), 40.0, "back in the yard")
		k.check("tourney.back", yard, "the host calls them back and the three are in the yard")
	menu.tourney = null

# ---------- The other modes ----------

func _smoke(mode: String, title: String) -> void:
	var ok := await _pick_fight(title)
	var began: bool = await k.until(func(): return m() != null and m().mode == mode, 40.0, mode)
	k.check("mode.%s" % mode, ok and began, "%s begins from its card at the gate" % title)
	if not began:
		return
	await k.pause(5.0)
	var inm := _friends_in_match()
	k.check("mode.%s.friends" % mode, inm[0] == 2, "with both friends in it", str(inm))
	if not await _call_back():
		k.check("mode.%s.back" % mode, false, "the host calls everyone back to the yard from the pause menu")
		return
	var yard: bool = await k.until(func(): return _in_yard_with(3), 40.0, "back in the yard")
	k.check("mode.%s.back" % mode, yard, "and the three are back in the yard")

# ---------- Forge and Fight ----------

func _forge() -> void:
	var ok := await _pick_fight("Forge and Fight", false)
	await k.pause(0.3)
	var lit := Kit.press(Kit.button_with(menu, "To the forges"))
	var began: bool = await k.until(func(): return not menu.ff.is_empty() and menu.screen == "ff_contest", 20.0, "the forges")
	k.check("forge.start", ok and lit and began, "Forge and Fight lights the forges")
	if not began:
		return
	# The host is ready with what he has, in each phase; the friends say so themselves, and the clock need not run out.
	var fight: bool = false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 150000:
		await k.pause(0.5)
		if m() != null and m().mode == "forgefight":
			fight = true
			break
		if not menu.ff.is_empty() and not bool(menu.ff.get("ready", true)) and menu.screen == "ff_contest":
			menu._ff_ready(true)
	k.check("forge.ready", fight, "the friends are ready on their own and the sand comes before the clock runs out", "%.0f s" % (float(Time.get_ticks_msec() - t0) / 1000.0))
	if not fight:
		menu._ff_quit()
		menu.enter_yard()
		return
	await k.pause(4.0)
	var inm := _friends_in_match()
	k.check("forge.friends", inm[0] == 2, "both friends fight with what they had", str(inm))
	if await _call_back():
		var yard: bool = await k.until(func(): return _in_yard_with(3), 40.0, "back in the yard")
		k.check("forge.back", yard, "the host calls everyone back to the yard")

# ---------- The endless arena ----------

func _endless() -> void:
	var ok := await _pick_fight("The endless arena", false)
	await k.pause(0.4)
	Kit.press(Kit.button_with(menu, "Into the arena"))
	var began: bool = await k.until(func(): return m() != null and m().mode == "endless" and m().modes != null and m().modes.endless != null and m().modes.endless.wave >= 1, 40.0, "the first wave")
	k.check("endless.start", ok and began, "the endless arena begins for the three of them")
	if not began:
		return
	var en: Endless = m().modes.endless
	await k.pause(2.0)
	for e in m().enemies():
		e.f.die("wounds")
	var rest: bool = await k.until(func(): return en.phase == "rest", 30.0, "the rest after wave 1")
	k.check("endless.offers", rest and en.offers.size() == 3, "a wave beaten holds out a reward to each of the three", "offers %s" % str(en.offers.keys()))
	var ids: Array = Net.peers.keys()
	var picked: bool = await k.until(func(): return ids.all(func(id): return not en.offers.has(id)), 40.0, "the friends' picks")
	k.check("endless.picks", picked, "each friend picks his reward from his cards by himself", str(en.offers.keys()))
	var host_cards: Array = menu.endless_layer.find_children("*", "Button", true, false) if menu.endless_layer != null else []
	if not host_cards.is_empty():
		host_cards[0].pressed.emit()
	var next: bool = await k.until(func(): return en.phase == "next" or en.phase == "fight" and en.wave >= 2, 20.0, "the next wave")
	k.check("endless.next", next, "everyone has picked, the next wave comes")
	if await _call_back():
		var yard: bool = await k.until(func(): return _in_yard_with(3), 40.0, "back in the yard")
		k.check("endless.back", yard, "and the three are back in the yard")

# ---------- A campaign room ----------

func _campaign() -> void:
	# The Arena room is closed from the pause menu; the friends find it gone and close.
	menu._toggle_pause()
	await k.pause(0.3)
	var closed := Kit.press(Kit.button_with(menu, "Close the room"))
	await k.pause(0.5)
	k.check("close.room", closed and not Net.active(), "the Arena room is closed")
	var gone: bool = await k.until(func(): return strip.friends.count() == 0, 40.0, "the friends' games closed")
	k.check("close.friends", gone, "and the friends, finding it gone, close their games", "%d games" % strip.friends.count())
	if not await _room(Net.KIND_CAMPAIGN):
		return
	k.check("campaign.start", Kit.press(Kit.button_named(menu, "LobbyCampaign")), "the host begins bout 1 of the co-op campaign")
	var fight: bool = await k.until(func(): return m() != null and m().mode == "campaign" and m().coop and m().enemies().size() > 0, 60.0, "the bout")
	k.check("campaign.bout", fight, "the bout begins with foes for the three")
	if not fight:
		return
	await k.pause(4.0)
	var inm := _friends_in_match()
	k.check("campaign.friends", inm[0] == 2, "both friends are in it", str(inm))
	for e in m().enemies():
		e.f.die("wounds")
	var yard: bool = await k.until(func(): return _in_yard_with(3), 90.0, "back in the yard")
	k.check("campaign.won", yard and int(Save.get_value("coop_stage", 1)) == 2, "the bout won, the party is back in the yard and the campaign moves on", "stage %s" % str(Save.get_value("coop_stage", 1)))
	if not yard:
		return
	# The gate: the host opens it and the friends are sent to it; each votes for a card on his own screen.
	menu._open_station("gate")
	await k.pause(0.5)
	for id in Net.peers:
		Net.send_to(int(id), "friend_cmd", "stall:gate")
	var voted: bool = await k.until(func(): return m().yard != null and (m().yard.stands() as Array).slice(1).all(func(v): return int(v) >= 0), 90.0, "the friends' votes at the gate")
	k.check("campaign.gate", voted, "at the gate each friend votes for a card of his own", str(m().yard.stands()) if m() != null and m().yard != null else "")
