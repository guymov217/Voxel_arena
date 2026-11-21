extends Node
## The end-to-end multiplayer run, a guest's game (`-- --probe e2e_guest`, started by e2e_run.gd; `--role late` is the friend who
## comes in late). It does what a friend does, through the game's own screens: joins the host's room by address, waits in its
## lobby, walks into the host's yard, buys an axe at the smith, is brought into every fight the host picks (and looks at it as a
## guest does, from the host's snapshots), picks his reward in the endless arena from the cards on his screen, is removed (the
## late friend) or told the host left, and joins a campaign room. At each step the host cues, he looks and writes what he saw
## (e2e_kit.gd) and says he is done. `--quick` leaves out the tournament and the single modes' smoke runs, as the host's does.

const Kit := preload("res://tests/e2e_kit.gd")
const MenuScript := preload("res://scripts/ui/menu.gd")
const SMOKE := ["bo3", "king", "hunt", "emperor", "hill", "lastLimb"]

var k: RefCounted
var menu: Node
var role := "guest"
var port := 17900
var quick := false
var snaps := 0
var my_name := "Brutus"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--role") and args.size() > args.find("--role") + 1:
		role = args[args.find("--role") + 1]
	port = int(args[args.find("--port") + 1]) if args.has("--port") and args.size() > args.find("--port") + 1 else 17900
	quick = args.has("--quick")
	my_name = "Cassia" if role == "late" else "Brutus"
	k = Kit.new(role, self)
	Save.data["coins"] = 77              # (his campaign's purse: it must be 77 until the campaign room)
	Save.data["name"] = my_name
	menu = MenuScript.new()
	menu.backdrop_off = true
	add_child(menu)
	var lag := args.find("--lag")
	if lag >= 0 and args.size() > lag + 1:
		var ls := args.find("--loss")
		Net.set_lag(int(args[lag + 1]), float(args[ls + 1]) if ls >= 0 and args.size() > ls + 1 else 0.0)
	Net.message.connect(func(type, _d, _f):
		if type == "snap":
			snaps += 1)
	get_tree().create_timer(1500.0).timeout.connect(func():
		k.check("run.time", false, "the run finished in time")
		get_tree().quit(2))
	await k.pause(0.5)
	if role == "late":
		await _run_late()
	else:
		await _run_guest()
	print("E2E %s finished: %d ok, %d failed" % [role, k.passes, k.fails])
	await k.pause(0.5)
	get_tree().quit(1 if k.fails > 0 else 0)

## The steps of the run: the host's cue, and what this game does at it.
func _steps(list: Array) -> void:
	for st in list:
		if not await k.wait_line("host", "CUE", st[0], 150.0):
			k.check("cue.%s" % st[0], false, "the host's cue '%s' came" % st[0])
			return
		await st[1].call()
		k.done(st[0])

func _join() -> bool:
	for attempt in 6:
		if Net.join_enet("127.0.0.1", port) == OK and await k.until(func(): return Net.active(), 10.0, "the connection"):
			return true
		Net.leave()
		await k.pause(1.0)
	return false

func m() -> Match:
	return menu.match_

func _yard_of(n: int) -> bool:
	return menu.in_yard() and m() != null and m().humans().size() == n

func _flow() -> float:
	var s0 := snaps
	await k.pause(1.0)
	return float(snaps - s0)

# ---------- The friend who is there from the first ----------

func _run_guest() -> void:
	if not await k.wait_line("host", "CUE", "lobby", 120.0):
		k.check("cue.lobby", false, "the host opened a room")
		return
	var joined := await _join()
	k.check("join", joined, "he joins the host's room by address")
	if not joined:
		return
	var steps := [
		["lobby", _lobby], ["yard", _yard], ["shop", _shop], ["stall", _stall], ["respawn", _respawn],
		["ffa.start", _ffa_start], ["ffa.round2", _ffa_round2], ["ffa.end", _back_in_yard],
		["teams.circles", _teams_circles], ["teams.fight", _teams_fight], ["teams.end", _back_in_yard]]
	if not quick:
		steps.append_array([["tourney.start", _tourney_start], ["tourney.end", _back_in_yard]])
		for mode in SMOKE:
			steps.append(["mode.%s" % mode, _mode.bind(mode)])
			steps.append(["mode.%s.end" % mode, _back_in_yard])
		steps.append_array([["forge", _forge_lit], ["forge.end", _back_in_yard]])
	steps.append_array([["late", _late_seen], ["endless.start", _endless_start], ["endless.offer", _endless_offer], ["endless.done", _endless_done], ["endless.end", _back_in_yard3],
		["kick", _kick_seen], ["campaign.closed", _host_left], ["campaign.lobby", _campaign_lobby], ["campaign.fight", _campaign_fight], ["campaign.end", _campaign_end]])
	await _steps(steps)

func _lobby() -> void:
	await k.until(func(): return Net.room_kind == Net.KIND_ARENA, 10.0, "told the kind of room")
	k.check("lobby.kind", Net.room_kind == Net.KIND_ARENA and Save.boxed and menu.coins() == Save.UNLIMITED, "he is told it is an Arena room: the sandbox, money no object", "kind %s" % Net.room_kind)
	await k.until(func(): return String(Net.room_list()[0].name) != "The host", 10.0, "the roster")
	var list: Array = Net.room_list()
	k.check("lobby.roster", list.size() == 2 and list[0].host and list[0].name == "Aulus" and list[1].you and list[1].name == my_name, "his lobby lists the host first and himself, as the host's does", str(list.map(func(r): return r.name)))
	var lobby = menu.find_child("Lobby", true, false)
	await k.until(func(): return lobby != null and lobby._title.text.contains("Aulus"), 3.0, "the title")
	k.check("lobby.title", lobby != null and lobby._title.text.contains("Aulus"), "its title is the host's room", lobby._title.text if lobby else "")
	k.check("lobby.waits", menu.screen == "room" and menu.find_child("LobbyWait", true, false) != null and Kit.button_named(menu, "LobbyEnter") == null and Kit.button_named(menu, "LobbyLeave") != null, "he waits for the host in the lobby, with a way out", "screen %s" % menu.screen)
	k.check("lobby.buttons", Kit.button_named(menu, "Mute0") != null and Kit.button_named(menu, "Remove0") == null, "he can mute the host, but not remove him")
	var ping: bool = await k.until(func(): return Net.ping_ms >= 0.0, 10.0, "his connection")
	k.check("lobby.ping", ping, "his own connection is measured", "%d ms" % int(Net.ping_ms))
	await k.shot("lobby")

func _yard() -> void:
	var ok: bool = await k.until(func(): return _yard_of(2), 40.0, "the yard")
	var names: Array = m().humans().map(func(e): return String(e.f.display_name)) if m() != null else []
	k.check("yard.both", ok and names.has("Aulus") and names.has(my_name), "he walks into the host's yard and sees the host's gladiator there", str(names))
	k.check("yard.purses", int(Save.data.coins) == 77 and menu.coins() == Save.UNLIMITED, "his campaign's purse is untouched, and money is no object here", "campaign %s" % str(Save.data.coins))
	await k.shot("yard")

func _shop() -> void:
	var r := Arms.buy(menu.arms(), "axe", "R")   # (both hands are full: the smith takes the gladius in part exchange)
	var bought: bool = r.has("arms")
	if bought:
		menu.set_arms(r.arms)
	var main: Dictionary = menu.arms().main
	k.check("shop.buy", bought and String(main.get("name", "")).to_lower().contains("axe") and menu.coins() == Save.UNLIMITED and int(Save.data.coins) == 77, "he buys an axe at the smith: nothing comes off any purse", str(r.get("error", main.get("name", ""))))

## A stall's menu open over the yard: the host holds him untouchable until he leaves it.
func _stall() -> void:
	menu._open_station("market")
	await k.pause(0.5)
	k.check("stall.open", menu.visible and menu.screen == "market", "he opens the market's stall", "screen %s" % menu.screen)
	await k.wait_line("host", "CUE", "stall.close", 30.0)
	menu._close_overlay()
	await k.pause(0.3)

## R, the key: up again by the gate; a second press at once does nothing (a wait of ten seconds).
func _respawn() -> void:
	var old = m().me.f if m() != null and m().me != null else null
	_press_r()
	var ok: bool = await k.until(func(): return m() != null and m().me != null and is_instance_valid(m().me.f) and m().me.f != old and m().me.f.alive, 15.0, "himself again")
	k.check("respawn.seen", ok, "R brings him up again by the gate, built anew here from the host's word")
	var mid = m().me.f if m() != null and m().me != null else null
	_press_r()
	await k.pause(1.5)
	k.check("respawn.wait", m() != null and m().me != null and m().me.f == mid, "R again at once changes nothing: he waits ten seconds")

func _press_r() -> void:
	var ev := InputEventAction.new()
	ev.action = "va_restart"
	ev.pressed = true
	menu._unhandled_input(ev)

func _ffa_start() -> void:
	var ok: bool = await k.until(func(): return m() != null and m().mode == "ffa" and m().entities.size() >= 4, 40.0, "the free for all")
	var flow := await _flow()
	k.check("ffa.guest", ok and int(m().series.get("n", 0)) == 3 and m().fight_status() != "" and flow > 5.0, "the free for all is drawn here from the host's snapshots: three rounds, a state line", "%d fighters, series %s, '%s', %d snapshots a second" % [m().entities.size() if m() else 0, str(m().series) if m() else "", m().fight_status() if m() else "", int(flow)])
	await k.shot("ffa")

func _ffa_round2() -> void:
	var ok: bool = await k.until(func(): return m() != null and m().mode == "ffa" and int(m().series.get("p", 0)) == 1, 40.0, "round 2")
	k.check("ffa.round2", ok, "he is brought into the next round with the score carried", "series %s" % str(m().series) if m() else "")

func _back_in_yard() -> void:
	var ok: bool = await k.until(func(): return _yard_of(2), 40.0, "the yard again")
	k.check("yard.back.%s" % str(Time.get_ticks_msec()), ok, "he is back in the yard with the host", "humans %d" % (m().humans().size() if m() else 0))

func _back_in_yard3() -> void:
	var ok: bool = await k.until(func(): return _yard_of(3), 40.0, "the yard again")
	k.check("yard.back3.%s" % str(Time.get_ticks_msec()), ok, "the three of them are back in the yard", "humans %d" % (m().humans().size() if m() else 0))

func _teams_circles() -> void:
	var ok: bool = await k.until(func(): return m() != null and m().mode == "yard" and m().yard != null and m().yard.teams_on(), 30.0, "the circles")
	k.check("teams.circles", ok, "the circles are on the sand for him too, with the line of who is awaited", m().yard.team_line() if ok else "")
	await k.shot("circles")

func _teams_fight() -> void:
	var ok: bool = await k.until(func(): return m() != null and m().mode == "teams", 40.0, "the team fight")
	await k.pause(0.5)
	var team := int(m().me.team) if ok and m().me != null else -1
	k.check("teams.fight", ok and team == 1 and m().fight_status() != "", "he is in the fight on the team of the circle he stood in", "team %d, '%s'" % [team, m().fight_status() if m() else ""])

func _tourney_start() -> void:
	var ok: bool = await k.until(func(): return m() != null and m().mode == "tourney", 40.0, "the tournament")
	k.check("tourney.guest", ok, "he is in the room for the tournament's bout (in it, or looking on)", m().fight_status() if m() else "")

func _mode(mode: String) -> void:
	var ok: bool = await k.until(func(): return m() != null and m().mode == mode, 40.0, mode)
	var flow := await _flow()
	k.check("mode.%s.guest" % mode, ok and flow > 5.0, "%s is drawn here from the host's snapshots" % mode, "%d snapshots a second" % int(flow))

func _forge_lit() -> void:
	var ok: bool = await k.until(func(): return not menu.ff.is_empty() and menu.screen == "ff_contest", 30.0, "the forges")
	k.check("forge.guest", ok, "Forge and Fight lights his forge too, when the host says so", "screen %s" % menu.screen)

func _late_seen() -> void:
	var ok: bool = await k.until(func(): return _yard_of(3) and Net.room_list().size() == 3, 40.0, "three in the yard")
	k.check("late.guest", ok, "the late friend walks in and the lobby lists three", str(Net.room_list().map(func(r): return r.name)))

func _endless_start() -> void:
	var ok: bool = await k.until(func(): return m() != null and m().mode == "endless" and String(m().fight_status()).begins_with("Wave"), 40.0, "the first wave")
	k.check("endless.guest", ok, "the endless arena begins for him too, with the host's state line", m().fight_status() if m() else "")

func _endless_offer() -> void:
	var up: bool = await k.until(func(): return menu.endless_layer != null, 40.0, "the rewards")
	var cards: Array = menu.endless_layer.find_children("*", "Button", true, false) if up else []
	k.check("endless.offer", up and cards.size() >= 2, "a wave beaten holds out rewards to him, as cards on his screen", "%d cards" % cards.size())
	await k.shot("endless_offer")
	await k.pause(1.0)
	if cards.size() >= 2:
		cards[1].pressed.emit()
	k.check("endless.picked", menu.endless_layer == null, "he picks the second: the cards go and his pick is the host's to read")

func _endless_done() -> void:
	var ok: bool = await k.until(func(): return m() != null and m().mode == "endless" and (String(m().fight_status()).contains("Wave 2") or String(m().fight_status()).contains("in ")), 40.0, "the next wave")
	k.check("endless.next", ok, "when everyone has picked, the next wave comes", m().fight_status() if m() else "")

func _kick_seen() -> void:
	var ok: bool = await k.until(func(): return Net.room_list().size() == 2, 20.0, "two in the room")
	k.check("kick.guest", ok, "the lobby lists two again after the late friend is removed", str(Net.room_list().map(func(r): return r.name)))

func _host_left() -> void:
	var ok: bool = await k.until(func(): return not Net.active() and menu.screen == "mp", 20.0, "the host's leaving")
	k.check("close.guest", ok and not Save.boxed and int(Save.data.coins) == 77, "the host closes the room: he is told and is himself again, with his own purse", "screen %s, purse %s" % [menu.screen, str(Save.data.coins)])

func _campaign_lobby() -> void:
	var joined := await _join()
	k.check("campaign.join", joined, "he joins the campaign room")
	if not joined:
		return
	await k.until(func(): return Net.room_kind == Net.KIND_CAMPAIGN and menu.screen == "room" and menu.shared_purse == 150, 15.0, "told it is a campaign room")
	var list: Array = Net.room_list()
	k.check("campaign.lobby", Net.room_kind == Net.KIND_CAMPAIGN and not Save.boxed and menu.coins() == 150 and list.size() == 2 and menu.find_child("LobbyWait", true, false) != null, "a campaign room: no sandbox, the purse is the host's (150), the host's lobby listed", "kind %s, purse %d" % [Net.room_kind, menu.coins()])
	await k.shot("campaign_lobby")

func _campaign_fight() -> void:
	var ok: bool = await k.until(func(): return m() != null and m().mode == "campaign" and m().coop and m().enemies().size() > 0, 40.0, "the bout")
	k.check("campaign.guest", ok, "the co-op campaign's bout begins for him with the foes", "%d foes" % (m().enemies().size() if m() else 0))

func _campaign_end() -> void:
	var ok: bool = await k.until(func(): return _yard_of(2), 60.0, "the yard")
	await k.pause(1.0)
	k.check("campaign.end", ok and menu.coins() == int(menu.shared_purse) and menu.coins() > 150, "the bout won, he is in the yard and the party's purse (the host's) has grown", "purse %d" % menu.coins())

# ---------- The friend who comes in late ----------

func _run_late() -> void:
	if not await k.wait_line("host", "CUE", "late", 400.0):
		k.check("cue.late", false, "the host's cue 'late' came")
		return
	var joined := await _join()
	k.check("join", joined, "he joins the room late, by address")
	if not joined:
		return
	await _steps([["late", _late_in], ["endless.start", _endless_start], ["endless.offer", _endless_offer], ["endless.done", _endless_done], ["endless.end", _back_in_yard3], ["kick", _removed]])

func _late_in() -> void:
	var ok: bool = await k.until(func(): return _yard_of(3), 40.0, "the yard")
	var names: Array = m().humans().map(func(e): return String(e.f.display_name)) if m() != null else []
	k.check("late.in", ok and names.has("Aulus") and names.has("Brutus") and names.has(my_name), "he walks into the yard that is already up and sees the other two", str(names))
	await k.shot("late")

func _removed() -> void:
	var ok: bool = await k.until(func(): return not Net.active() and menu.screen == "mp", 20.0, "the removal")
	k.check("kick.removed", ok and not Save.boxed, "he is told the host removed him and is back at the Multiplayer screen, himself again", "screen %s" % menu.screen)
	# He cannot come back in: the host turns him away.
	var back := false
	if Net.join_enet("127.0.0.1", port) == OK:
		await k.until(func(): return Net.active(), 6.0, "a connection")
		await k.pause(1.5)
		back = Net.active()
	k.check("kick.banned", not back, "and he cannot come back in until the host opens a new room")
	Net.leave()
