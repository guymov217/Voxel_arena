extends Node
## The end-to-end multiplayer run, the host's game (`-- --probe e2e_host`, started by e2e_run.gd with a guest and a late guest).
## It does what a host does, through the game's own screens and buttons: opens an Arena room, waits in its lobby for friends, enters
## the yard, picks fights at the gate (rounds and bots, the team circles, the tournament, every other mode of the Arena, the endless
## arena with three), removes a friend, closes the room, opens a campaign room and plays a bout of the co-op campaign. At each step
## it writes what it saw (e2e_kit.gd); the guests, each its own game, write what they saw of the same step.
## `--quick` leaves out the tournament and the single modes' smoke runs.

const Kit := preload("res://tests/e2e_kit.gd")
const MenuScript := preload("res://scripts/ui/menu.gd")
## The Arena's other modes, each begun from its card at the gate and ended by the host's "back to the yard".
const SMOKE := [["bo3", "Duel"], ["king", "King of the Arena"], ["hunt", "Monster Hunt"], ["emperor", "The Emperor watches"], ["hill", "King of the Hill"], ["lastLimb", "Last Limb Standing"]]

var k: RefCounted
var menu: Node
var port := 17900
var quick := false
var gid := 0                     # the guest's peer id
var lid := 0                     # the late guest's

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	port = int(args[args.find("--port") + 1]) if args.has("--port") and args.size() > args.find("--port") + 1 else 17900
	quick = args.has("--quick")
	Match.screen_emulated = args.has("--staged")
	k = Kit.new("host", self)
	Save.data["coins"] = 150            # (the campaign's purse: it must be 150 until the campaign room)
	Save.data["name"] = "Aulus"
	menu = MenuScript.new()
	menu.backdrop_off = true
	add_child(menu)
	_lag(args)
	get_tree().create_timer(1500.0).timeout.connect(func():
		k.check("run.time", false, "the run finished in time")
		get_tree().quit(2))
	await k.pause(0.5)
	await _run()
	k.cue("end")
	await k.pause(1.0)
	print("E2E host finished: %d ok, %d failed" % [k.passes, k.fails])
	get_tree().quit(1 if k.fails > 0 else 0)

func _lag(args: PackedStringArray) -> void:
	var lag := args.find("--lag")
	if lag >= 0 and args.size() > lag + 1:
		var ls := args.find("--loss")
		Net.set_lag(int(args[lag + 1]), float(args[ls + 1]) if ls >= 0 and args.size() > ls + 1 else 0.0)

func _run() -> void:
	if not await _lobby():
		return
	await _yard()
	await _ffa()
	await _teams()
	if not quick:
		await _tourney()
		for m in SMOKE:
			await _smoke(m[0], m[1])
		await _forge()
	await _late()
	await _endless()
	await _kick()
	await _campaign()

# ---------- Helpers ----------

func m() -> Match:
	return menu.match_

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

func _in_yard_with(n: int) -> bool:
	return menu.in_yard() and m() != null and not m().hold and m().humans().size() == n   # (not held: with a screen the yard's start waits for everyone to be built, Match.hold)

# ---------- The lobby ----------

func _lobby() -> bool:
	menu.show_screen("mp")
	await k.pause(0.3)
	var kinds: Array = menu.find_children("*", "Button", true, false).filter(func(b): return b.toggle_mode)
	k.check("mp.screen", kinds.size() == 2 and Kit.button_with(menu, "Host by address") != null, "the Multiplayer screen offers the two kinds of room and a way to host", "%d kind cards" % kinds.size())
	menu._set_mp_kind(Net.KIND_ARENA)
	menu._host_room(func(): k.check("lobby.open", Net.host_enet(port) == OK, "an Arena room is opened by address"))
	await k.pause(0.4)
	k.check("lobby.screen", menu.screen == "room" and not menu.in_yard() and Kit.button_named(menu, "LobbyEnter") != null, "the host lands in the room's lobby, with a button to enter the yard", "screen %s" % menu.screen)
	k.check("lobby.kind", Net.room_kind == Net.KIND_ARENA and Save.boxed and menu.coins() == Save.UNLIMITED, "an Arena room: the friends' sandbox, money no object")
	k.check("lobby.invite", Kit.button_named(menu, "LobbyInvite0") != null or Net.lan_addresses().is_empty(), "a free place gives a friend the way in (the address, copied)")
	await k.shot("lobby_alone")
	k.cue("lobby")
	var joined: bool = await k.until(func(): return Net.peers.size() >= 1, 60.0, "a friend to join")
	k.check("lobby.joined", joined, "a friend joins by address and appears in the room")
	if not joined:
		return false
	gid = Net.peers.keys()[0]
	await k.until(func(): return menu.find_child("Slot1", true, false) != null, 5.0, "his card")
	var list: Array = Net.room_list()
	k.check("lobby.cards", list.size() == 2 and list[0].host and list[1].name == "Brutus" and menu.find_child("Slot1", true, false) != null, "the lobby shows the host first and the friend on a card", str(list.map(func(r): return r.name)))
	var pinged: bool = await k.until(func(): return float(Net.guest_pings.get(gid, -1.0)) >= 0.0, 12.0, "his connection")
	k.check("lobby.ping", pinged, "the friend's connection is measured and shown", "%d ms" % int(Net.guest_pings.get(gid, -1.0)))
	# Mute is for the listener alone and toggles.
	var mute := Kit.button_named(menu, "Mute1")
	Kit.press(mute)
	var muted: bool = VoiceChat.muted.has(gid)
	Kit.press(Kit.button_named(menu, "Mute1"))
	k.check("lobby.mute", muted and not VoiceChat.muted.has(gid), "Mute stops a friend's voice for the host alone, and again lets it through")
	await k.shot("lobby_two")
	k.check("lobby.guest_saw", await k.wait_line("guest", "DONE", "lobby", 40.0), "the friend's own lobby agrees (his checks)")
	return true

# ---------- The yard ----------

## The friend's fighter in the host's match.
func _guest_entity():
	if m() == null:
		return null
	for e in m().humans():
		if e.kind == "remote" and int(e.peer) == gid:
			return e
	return null

func _yard() -> void:
	k.check("yard.button", Kit.press(Kit.button_named(menu, "LobbyEnter")), "the host presses Enter the yard")
	var ok: bool = await k.until(func(): return _in_yard_with(2), 30.0, "both in the yard")
	k.check("yard.both", ok, "the host and the friend stand in the yard", "humans %d" % (m().humans().size() if m() != null else 0))
	# With a screen (or a game that builds as one does, `--staged`) the yard's start was held until the friend said he had built the men too, and began at his word: the men came in together.
	var held_over: bool = await k.until(func(): return m() != null and not m().hold, 30.0, "the start's hold over")
	var why := String(m().hold_stats.get("why", "")) if m() != null else ""
	k.check("yard.held", held_over and (not Match.screen_emulated or (why == "everyone is ready" and int(m().hold_stats.get("men", 0)) >= 2)), "the yard's start waited for the friend to say he had built the men, and began at his word", "hold %s" % [str(m().hold_stats) if m() != null else ""])
	k.check("yard.campaign_untouched", int(Save.data.coins) == 150 and menu.coins() == Save.UNLIMITED, "the campaign's purse is untouched and money is no object here", "campaign %s" % str(Save.data.coins))
	k.cue("yard")
	await k.shot("yard")
	k.check("yard.guest_saw", await k.wait_line("guest", "DONE", "yard", 40.0), "the friend sees the host in the same yard")
	# The friend buys an axe at the smith: it reaches the host, and he is armed with it.
	k.cue("shop")
	var armed: bool = await k.until(func():
		var lo: Dictionary = Net.peers.get(gid, {}).get("loadout", {})
		var main = lo.get("main")
		return (main is Dictionary and String(main.get("name", "")).to_lower().contains("axe")) or (main is String and String(main).to_lower().contains("axe")), 20.0, "his new weapon")
	k.check("yard.shop", armed, "what the friend buys in the yard reaches the host (an axe in his hand)")
	await k.wait_line("guest", "DONE", "shop", 30.0)
	# A friend at a stall (its menu open) cannot be hurt; R brings a man up again by the gate, but not twice in ten seconds.
	k.cue("stall")
	var ge = null
	var hid: bool = await k.until(func():
		var e = _guest_entity()
		return e != null and is_instance_valid(e.f) and e.f.untouchable, 15.0, "the friend at a stall")
	ge = _guest_entity()   # (a lambda keeps what it sets to itself)
	var res := {}
	if hid:
		res = ge.f.apply_hit(ge.f.torso, {"impulse": 60.0, "type": "edge", "hardness": 0.9, "sharpness": 0.8, "point": ge.f.torso.global_position, "dir": Vector3.BACK, "axis": Vector3.RIGHT, "edge": Vector3.BACK})
	k.check("stall.guest", hid and bool(res.get("blocked", false)), "a friend whose stall is open (the market) cannot be hurt")
	k.cue("stall.close")
	await k.wait_line("guest", "DONE", "stall", 30.0)
	var left: bool = await k.until(func():
		var e = _guest_entity()
		return e != null and is_instance_valid(e.f) and not e.f.untouchable, 10.0, "the friend out of it")
	k.check("stall.left", left, "and when he leaves it he can be hurt again")
	k.cue("respawn")
	ge = _guest_entity()
	var old_f = ge.f if ge != null else null
	var up: bool = await k.until(func():
		var e = _guest_entity()
		return e != null and is_instance_valid(e.f) and e.f != old_f and e.f.alive, 15.0, "the friend up again")
	k.check("respawn.guest", up, "R brings the friend up again by the gate")
	ge = _guest_entity()
	var again_f = ge.f if ge != null else null
	await k.wait_line("guest", "DONE", "respawn", 30.0)
	ge = _guest_entity()
	k.check("respawn.cooldown", ge != null and ge.f == again_f, "and a second R at once changes nothing: ten seconds between")
	# The pause menu's door to the room, over the yard.
	menu._toggle_pause()
	await k.pause(0.3)
	var door := Kit.button_starting(menu, "The room")
	k.check("pause.door", door != null, "the pause menu has a door to the room", door.text if door else "")
	Kit.press(door)
	await k.pause(0.3)
	k.check("pause.room", menu.over_match and menu.screen == "room" and Kit.button_named(menu, "LobbyGate") != null and Kit.button_named(menu, "Remove1") != null, "over the yard the room's screen lists the friends, with Remove and the way on to the gate")
	var out: Array = menu.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("leave"))
	Kit.press(out[0] if not out.is_empty() else null)
	await k.pause(0.3)
	k.check("pause.back", not menu.visible and not menu.over_match, "and its way back leads to the yard")

# ---------- Free for all: rounds and bots ----------

func _ffa() -> void:
	menu._set_fight_opt("ffa", "rounds", 3)
	menu._set_fight_opt("ffa", "bots", 2)
	menu._open_station("gate")
	await k.pause(0.3)
	k.check("fights.list", menu.screen == "fights" and Kit.button_with(menu, "Free for all") != null and Kit.button_with(menu, "Red vs Blue") != null, "the gate opens the Arena's fights, a card for each", "screen %s, visible %s, over_match %s, in_yard %s, buttons %s" % [menu.screen, menu.visible, menu.over_match, menu.in_yard(), str(menu.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree()).map(func(b): return String(b.text).left(20)).slice(0, 12))])
	Kit.press(Kit.button_with(menu, "Free for all"))
	await k.pause(0.3)
	k.check("ffa.setup", menu.screen == "fight_setup" and Kit.button_with(menu, "Begin") != null, "a fight with settings opens them first (rounds, bots)")
	Kit.press(Kit.button_with(menu, "Begin"))
	var ok: bool = await k.until(func(): return m() != null and not m().hold and m().mode == "ffa" and m().entities.size() >= 4, 40.0, "the free for all")
	k.check("ffa.start", ok and int(m().series.get("n", 0)) == 3, "a free for all of three rounds with two bots begins", "%d fighters, series %s" % [m().entities.size() if m() else 0, str(m().series) if m() else ""])
	k.check("ffa.held", not Match.screen_emulated or (m() != null and String(m().hold_stats.get("why", "")) == "everyone is ready"), "the fight's start waited for the friend to have built the men: they came in together", "hold %s" % [str(m().hold_stats) if m() != null else ""])
	k.cue("ffa.start")
	k.check("ffa.guest_start", await k.wait_line("guest", "DONE", "ffa.start", 40.0), "the friend is in the same fight, drawn from the host's snapshots")
	# The round is won: the next begins, and when the match is decided everyone is back in the yard.
	var first = m()
	_kill_others()
	var next: bool = await k.until(func(): return m() != first and m() != null and not m().hold and m().mode == "ffa" and int(m().series.get("p", 0)) == 1, 40.0, "round 2")
	k.check("ffa.round2", next, "a round won, the next begins with the score carried", "series %s" % str(m().series) if m() else "")
	k.cue("ffa.round2")
	k.check("ffa.guest_round2", await k.wait_line("guest", "DONE", "ffa.round2", 40.0), "the friend is brought into the next round")
	await k.pause(1.0)
	_kill_others()
	var yard: bool = await k.until(func(): return _in_yard_with(2), 40.0, "back in the yard")
	k.check("ffa.back", yard, "the match decided, everyone is back in the yard")
	k.cue("ffa.end")
	k.check("ffa.guest_back", await k.wait_line("guest", "DONE", "ffa.end", 40.0), "and the friend too")

# ---------- Red against Blue: the circles ----------

func _teams() -> void:
	menu._set_fight_opt("teams", "rounds", 1)
	var ok := await _pick_fight("Red vs Blue")
	var ts_ok: bool = await k.until(func(): return m() != null and m().yard != null and m().yard.team_setup != null, 20.0, "the circles")
	k.check("teams.circles", ok and ts_ok, "the team fight lays two circles on the sand of the yard")
	k.cue("teams.circles")
	await k.until(func(): return _in_yard_with(2), 30.0, "the friend's man in the yard")   # (with a screen the friends' men are built over the frames that follow the yard's start)
	var ts: TeamSetup = m().yard.team_setup
	var host_e = m().me
	var guest_e = null
	for e in m().humans():
		if e != host_e:
			guest_e = e
	host_e.f.teleport(Vector3(TeamSetup.CENTRES[0].x, 0, TeamSetup.CENTRES[0].z))
	await k.pause(0.6)
	k.check("teams.waiting", not ts.ready() and ts.waiting().size() == 1, "with one still out of the circles the host cannot begin", ts.line(true))
	guest_e.f.teleport(Vector3(TeamSetup.CENTRES[1].x, 0, TeamSetup.CENTRES[1].z))   # (the friend walks there on his own screen in a game)
	var ready: bool = await k.until(func(): return ts.ready(), 8.0, "both in a circle")
	k.check("teams.ready", ready, "when everyone stands in a circle the host may begin", ts.line(true))
	k.check("teams.guest_saw", await k.wait_line("guest", "DONE", "teams.circles", 40.0), "the friend sees the circles and who stands in them")
	m().station.emit("team_go")
	var fight: bool = await k.until(func(): return m() != null and not m().hold and m().mode == "teams", 30.0, "the team fight")
	await k.pause(1.0)
	var host_team: int = int(m().me.team) if fight else -1
	var guest_team := -1
	if fight:
		for e in m().humans():
			if e != m().me:
				guest_team = int(e.team)
	k.check("teams.fight", fight and host_team == 0 and guest_team == 1, "the fight begins, each on the side of his circle", "host team %d, friend team %d" % [host_team, guest_team])
	k.cue("teams.fight")
	k.check("teams.guest_fight", await k.wait_line("guest", "DONE", "teams.fight", 40.0), "the friend is on his own team in the same fight")
	for e in m().entities.duplicate():
		if int(e.team) == 1 and is_instance_valid(e.f) and e.f.alive:
			e.f.die("decap")
	var yard: bool = await k.until(func(): return _in_yard_with(2), 40.0, "back in the yard")
	k.check("teams.back", yard, "a team's win ends the fight and brings everyone back")
	k.cue("teams.end")
	await k.wait_line("guest", "DONE", "teams.end", 40.0)

# ---------- The tournament ----------

func _tourney() -> void:
	menu._set_fight_opt("tourney", "rounds", 1)
	var ok := await _pick_fight("The Tournament")
	var began: bool = await k.until(func(): return menu.tourney != null and m() != null and not m().hold and m().mode == "tourney", 40.0, "a bout of the tournament")
	k.check("tourney.start", ok and began, "a tournament is drawn and its first bout begins", menu.tourney.round_name() if menu.tourney else "")
	k.cue("tourney.start")
	k.check("tourney.guest_saw", await k.wait_line("guest", "DONE", "tourney.start", 40.0), "the friend is in the room for it (in the bout or looking on)")
	# One falls: the winner goes on. (With a screen the men of a bout come in over the frames that follow its start: all of them are in first.)
	await k.until(func(): return m() != null and m().coming == 0 and not m().hold, 30.0, "the men of the bout in")
	var first = m()
	var fallen := 0
	for e in m().entities.duplicate():
		if fallen == 0 and e != m().me and is_instance_valid(e.f) and e.f.alive:
			e.f.die("decap")
			fallen += 1
	var moved: bool = await k.until(func(): return m() != first or menu.tourney == null or m().over, 30.0, "the bout settled")
	k.check("tourney.bout", moved, "a bout won, the tournament goes on")
	if await _call_back():
		await k.until(func(): return _in_yard_with(2), 40.0, "back in the yard")
	menu.tourney = null
	k.cue("tourney.end")
	await k.wait_line("guest", "DONE", "tourney.end", 40.0)

# ---------- The other modes: begun from their cards, seen by both, ended by the host ----------

func _smoke(mode: String, title: String) -> void:
	var ok := await _pick_fight(title)
	var began: bool = await k.until(func(): return m() != null and not m().hold and m().mode == mode, 40.0, mode)
	k.check("mode.%s" % mode, ok and began, "%s begins from its card at the gate" % title, "mode %s" % (m().mode if m() else "none"))
	k.cue("mode.%s" % mode)
	k.check("mode.%s.guest" % mode, await k.wait_line("guest", "DONE", "mode.%s" % mode, 50.0), "and the friend is in it too")
	if not await _call_back():
		k.check("mode.%s.back" % mode, false, "the host calls everyone back to the yard from the pause menu")
		return
	var yard: bool = await k.until(func(): return _in_yard_with(2), 40.0, "back in the yard")
	k.check("mode.%s.back" % mode, yard, "the host calls everyone back to the yard from the pause menu")
	k.cue("mode.%s.end" % mode)
	await k.wait_line("guest", "DONE", "mode.%s.end" % mode, 40.0)

## Forge and Fight is for hands (every friend forges his own weapon against the clock): here only that the forges are lit on both
## screens, and that the host's way back to the yard takes everyone there.
func _forge() -> void:
	var ok := await _pick_fight("Forge and Fight", false)
	await k.pause(0.3)
	var lit := Kit.press(Kit.button_with(menu, "To the forges"))
	var began: bool = await k.until(func(): return not menu.ff.is_empty() and menu.screen == "ff_contest", 20.0, "the forges")
	k.check("forge.start", ok and lit and began, "Forge and Fight lights the forges for the host", "screen %s" % menu.screen)
	k.cue("forge")
	k.check("forge.guest", await k.wait_line("guest", "DONE", "forge", 40.0), "and for the friend (the forging itself is for hands)")
	menu._ff_quit()
	menu.enter_yard()
	var yard: bool = await k.until(func(): return _in_yard_with(2), 40.0, "back in the yard")
	k.check("forge.back", yard, "the host calls everyone back to the yard")
	k.cue("forge.end")
	await k.wait_line("guest", "DONE", "forge.end", 40.0)

# ---------- A third friend comes in late ----------

func _late() -> void:
	k.cue("late")
	var joined: bool = await k.until(func(): return Net.peers.size() >= 2, 60.0, "the late friend")
	k.check("late.joined", joined, "a friend who comes while the yard is up joins the room")
	if not joined:
		return
	for id in Net.peers:
		if int(id) != gid:
			lid = int(id)
	var in_yard: bool = await k.until(func(): return _in_yard_with(3), 30.0, "three in the yard")
	k.check("late.yard", in_yard, "and walks into the yard by himself", "humans %d" % (m().humans().size() if m() else 0))
	k.check("late.roster", Net.room_list().size() == 3, "the room lists the three", str(Net.room_list().map(func(r): return r.name)))
	k.check("late.guest_saw", await k.wait_line("guest", "DONE", "late", 40.0) and await k.wait_line("late", "DONE", "late", 40.0), "both friends see the three of them")

# ---------- The endless arena with friends ----------

func _endless() -> void:
	var ok := await _pick_fight("The endless arena", false)
	await k.pause(0.4)
	# (A room picks no arms and bag at the gate: each goes in with what he bought and built in the yard, so no kit screen comes up.)
	var no_kit_screen: bool = menu.screen != "endless" and Kit.button_with(menu, "Into the arena") == null
	var began: bool = await k.until(func(): return m() != null and not m().hold and m().mode == "endless" and m().modes != null and m().modes.endless != null and m().modes.endless.wave >= 1, 40.0, "the first wave")
	k.check("endless.start", ok and no_kit_screen and began, "the endless arena begins for the three of them at once from the gate, with no kit screen in a room")
	if not began:
		return
	var en: Endless = m().modes.endless
	k.cue("endless.start")
	await k.wait_line("guest", "DONE", "endless.start", 40.0)
	await k.pause(1.0)
	# (With a screen a wave comes in over the frames: the foes still on their way are killed as they come, until the wave is beaten.)
	var slain_at := Time.get_ticks_msec()
	while en.phase != "rest" and Time.get_ticks_msec() - slain_at < 30000:
		for e in m().enemies():
			if e.f.alive:
				e.f.die("wounds")
		await k.pause(0.25)
	var rest: bool = await k.until(func(): return en.phase == "rest", 30.0, "the rest after wave 1")
	k.check("endless.offers", rest and en.offers.size() == 3, "a wave beaten holds out a reward to each of the three", "offers %s" % str(en.offers.keys()))
	k.cue("endless.offer")
	# Each friend picks on his own screen; the host picks his own last.
	var picked: bool = await k.until(func(): return not en.offers.has(gid) and not en.offers.has(lid), 30.0, "the friends' picks")
	k.check("endless.picks", picked, "each friend's pick comes back to the host over the wire")
	var host_cards: Array = menu.endless_layer.find_children("*", "Button", true, false) if menu.endless_layer != null else []
	k.check("endless.host_cards", host_cards.size() >= 2, "the host's own cards are on his screen", "%d cards" % host_cards.size())
	if not host_cards.is_empty():
		host_cards[0].pressed.emit()
	var next: bool = await k.until(func(): return en.phase == "next" or en.phase == "fight" and en.wave >= 2, 20.0, "the next wave")
	k.check("endless.next", next, "when everyone has picked the next wave comes")
	k.cue("endless.done")
	await k.wait_line("guest", "DONE", "endless.done", 40.0)
	if await _call_back():
		await k.until(func(): return _in_yard_with(3), 40.0, "back in the yard")
	k.cue("endless.end")
	await k.wait_line("guest", "DONE", "endless.end", 40.0)

# ---------- A friend is removed ----------

func _kick() -> void:
	menu._toggle_pause()
	await k.pause(0.3)
	Kit.press(Kit.button_starting(menu, "The room"))
	await k.pause(0.4)
	var slot := -1
	var list: Array = Net.room_list()
	for i in list.size():
		if int(list[i].id) == lid:
			slot = i
	var rm := Kit.button_named(menu, "Remove%d" % slot)
	Kit.press(rm)
	var asked: bool = rm != null and rm.has_meta("armed")
	Kit.press(Kit.button_named(menu, "Remove%d" % slot))
	var gone: bool = await k.until(func(): return not Net.peers.has(lid), 10.0, "the friend gone")
	k.check("kick.remove", slot >= 0 and asked and gone, "Remove asks twice, then the friend is out of the room", "slot %d" % slot)
	k.cue("kick")
	k.check("kick.late_saw", await k.wait_line("late", "DONE", "kick", 40.0), "he is told and cannot come back in")
	await k.pause(0.5)
	k.check("kick.roster", Net.room_list().size() == 2, "the room lists two again")
	var out: Array = menu.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("leave"))
	Kit.press(out[0] if not out.is_empty() else null)

# ---------- A campaign room ----------

func _campaign() -> void:
	# The room is closed from the pause menu: the friend is told the host left.
	menu._toggle_pause()
	await k.pause(0.3)
	var closed := Kit.press(Kit.button_with(menu, "Close the room"))
	await k.pause(0.5)
	k.check("close.room", closed and not Net.active() and menu.screen == "main", "Close the room ends it and the host is at the main menu")
	k.check("close.purse", not Save.boxed and int(Save.data.coins) == 150, "his own gladiator and the campaign's purse are back", "purse %s" % str(Save.data.coins))
	k.cue("campaign.closed")
	await k.wait_line("guest", "DONE", "campaign.closed", 40.0)
	# A campaign room.
	menu.show_screen("mp")
	await k.pause(0.3)
	menu._set_mp_kind(Net.KIND_CAMPAIGN)
	menu._host_room(func(): k.check("campaign.open", Net.host_enet(port) == OK, "a campaign room is opened"))
	await k.pause(0.4)
	k.check("campaign.lobby", menu.screen == "room" and Net.room_kind == Net.KIND_CAMPAIGN and Save.coop() and menu.coins() == 150 and Kit.button_named(menu, "LobbyCampaign") != null and Kit.button_named(menu, "LobbyDeath") != null, "the campaign's lobby starts the co-op campaign and asks how death is dealt with, and the purse is the host's")
	k.cue("campaign.lobby")
	var joined: bool = await k.until(func(): return Net.peers.size() >= 1, 60.0, "the friend again")
	k.check("campaign.joined", joined, "the friend joins the campaign room")
	if not joined:
		return
	await k.wait_line("guest", "DONE", "campaign.lobby", 40.0)
	await k.pause(0.5)
	# A campaign for another group of friends, and back: the lobby keeps a card for each campaign and the plus begins a new one; the
	# friend is told which run is open and has his gladiator of it.
	var run_a: int = Net.coop_run
	k.check("slots.row", Kit.button_named(menu, "LobbySave%d" % run_a) != null and Kit.button_named(menu, "LobbyNewSave") != null, "the lobby has a card for the campaign that is open and a plus for another group's", "run %d" % run_a)
	k.check("slots.new", Kit.press(Kit.button_named(menu, "LobbyNewSave")), "the host presses the plus: a campaign for another group of friends")
	await k.pause(0.6)
	var run_b: int = Net.coop_run
	k.check("slots.opened", run_b != run_a and run_b > 0 and Save.coop() and Save.box_run == run_b and int(Save.get_value("coop_stage", 1)) == 1 and menu.coins() == 150 and Kit.button_named(menu, "LobbySave%d" % run_a) != null and Kit.button_named(menu, "LobbySave%d" % run_b) != null, "the other campaign is open at bout 1 with a new man, and each has its card", "run %d -> %d, purse %d" % [run_a, run_b, menu.coins()])
	k.cue("campaign.slot_new")
	await k.wait_line("guest", "DONE", "campaign.slot_new", 40.0)
	k.check("slots.back", Kit.press(Kit.button_named(menu, "LobbySave%d" % run_a)), "the host presses the first campaign's card")
	await k.pause(0.6)
	k.check("slots.reopened", Net.coop_run == run_a and Save.box_run == run_a and menu.coins() == 150, "the first campaign is open again, with his gladiator of it", "run %d, purse %d" % [Net.coop_run, menu.coins()])
	k.cue("campaign.slot_back")
	await k.wait_line("guest", "DONE", "campaign.slot_back", 40.0)
	await k.pause(0.3)
	k.check("campaign.start", Kit.press(Kit.button_named(menu, "LobbyCampaign")), "the host begins the co-op campaign")
	var in_yard: bool = await k.until(func(): return menu.in_yard() and _in_yard_with(2), 40.0, "the yard")
	k.check("campaign.yard", in_yard, "it begins in the yard, the lobby, as it does alone")
	menu.start({"mode": "coop", "role": "host"})   # (the gate's pick, in a word)
	var fight: bool = await k.until(func(): return m() != null and not m().hold and m().mode == "campaign" and m().coop and m().enemies().size() > 0, 40.0, "the bout")
	k.check("campaign.bout", fight, "the bout begins with foes for two", "%d foes" % (m().enemies().size() if m() else 0))
	k.cue("campaign.fight")
	await k.wait_line("guest", "DONE", "campaign.fight", 40.0)
	await k.pause(1.0)
	# The friend loses a forearm in the bout (the host's own copy of him: where the blows fall): what the host's own man would keep, he keeps.
	var friend_e: Variant = null
	for e in m().humans():
		if e.kind == "remote":
			friend_e = e
	if friend_e != null and is_instance_valid(friend_e.f):
		friend_e.f.detach_limb(friend_e.f.by_name.forearmL, {"removed": [], "severed": []})
	for e in m().enemies():
		e.f.die("wounds")
	var yard: bool = await k.until(func(): return _in_yard_with(2), 60.0, "back in the yard")
	k.check("campaign.won", yard and int(Save.get_value("coop_stage", 1)) == 2, "the bout won, the party is back in the yard and the campaign has moved on", "stage %s" % str(Save.get_value("coop_stage", 1)))
	k.check("campaign.purse", yard and menu.coins() > 150 and int(Save.data.coins) == 150, "his purse is his own and grew with the bout's pay; the single campaign's is as it was", "run purse %d, single %s" % [menu.coins(), str(Save.data.coins)])
	k.cue("campaign.end")
	k.check("campaign.guest_end", await k.wait_line("guest", "DONE", "campaign.end", 40.0), "the friend is back in the yard with a purse of his own")
