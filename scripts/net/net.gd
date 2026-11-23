extends Node
## Multiplayer, host-authoritative as in the web game: the host's game runs the physics; guests
## send their input (30 Hz) and draw the host's snapshots, with events for spawns, voxels cut
## off, banners and the end of a stage.
##
## Two transports behind one API:
##  - Steam (GodotSteam): lobbies (public ones are listed in the room browser, friends join from
##    the Steam overlay), traffic over Steam networking (relayed, no ports to open). Used when
##    the GodotSteam extension is installed and Steam is running.
##  - ENet (built into Godot): host on a port, join by address. LAN parties, testing, and builds
##    without Steam.
## GodotSteam is reached through Engine.get_singleton/ClassDB, so this script also loads in
## builds that do not ship it.

signal message(type: String, data, from: int)
signal peer_joined(id: int, info: Dictionary)
signal peer_left(id: int)
signal connected
signal room_kind_known(kind: String)   # (a guest) the host has said what the room is for
signal roster_changed                  # (a guest) the host has said who is in the room
signal connection_failed(reason: String)
signal disconnected
signal lobbies(list: Array)

const PORT := 7777
const MAX_PLAYERS := 8
## The co-op campaign is fought by four at most (its bouts are made for one to four): a room opened for it takes four, a
## room opened for the friends' Arena (every other way to fight) takes eight (user).
const CAMPAIGN_PLAYERS := 4
const LOBBY_KEY := "voxelarena"
## Bumped when what two games say to each other changes in a way an older game cannot follow. (2: a guest's inputs carry a number and
## the snapshot row of his man the host's word on it, so that his own man is walked ahead of the host's picture: Match._predict_own.)
const PROTOCOL := 2

## What every player of a room must be running: the game's version, the net protocol and the edition (the demo and
## the full game are separate apps on Steam and never meet there, but a join by address could mix them). A guest
## whose "hello" says another is sent away with the reason, and a Steam lobby carries its host's, so a friend on an
## older or newer build is told before he joins: an update rolling out never puts two builds in one fight.
static func build_tag() -> String:
	return "%s.%d.%s" % [ProjectSettings.get_setting("application/config/version", "0"), PROTOCOL, "demo" if Edition.demo() else "full"]

var transport := ""             # "" | enet | steam
var peers := {}                 # id -> {name, loadout}
var inputs := {}                # id -> last input
var my_name := "Gladiator"
var my_loadout := {}
var my_kit := {}
var my_body := {}
var steam: Object = null
var steam_ready := false
var lobby_id := 0
var steam_user := 0
var launch_lobby := 0           # a lobby Steam asked this game to join as it started (a friend's invite: +connect_lobby)
var steam_problem := ""         # why Steam multiplayer is not there, in a line for the player ("" when it is, or when Steam is not meant to be)
# A pretend bad connection, on one machine: incoming messages held back `lag_ms` (± jitter)
# and some unreliable ones dropped. `--lag 120 --loss 3` on the command line, or NET_LAG/NET_LOSS.
var lag_ms := 0
var jitter_ms := 0
var loss := 0.0
var _held: Array = []
var _held_due := 0

func _ready() -> void:
	# Guests talk to the host and to nobody else: what one sends the others is what the host
	# himself passes on (a voice), so nothing reaches a guest that has not been through the
	# host's checks.
	if multiplayer is SceneMultiplayer:
		(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): connection_failed.emit("Could not reach the host"))
	multiplayer.server_disconnected.connect(func():
		leave()
		disconnected.emit())
	_init_steam()
	if OS.get_environment("NET_LAG") != "":
		set_lag(int(OS.get_environment("NET_LAG")), float(OS.get_environment("NET_LOSS")) if OS.get_environment("NET_LOSS") != "" else 0.0)

var meter: CanvasLayer = null
## The connection's meter in the corner, open or put away: F3 in a room, with the frame rate's
## (FpsMeter, which has the key).
func show_meter(on: bool) -> void:
	if on == (meter != null and is_instance_valid(meter)):
		return
	if on:
		meter = load("res://scripts/ui/net_meter.gd").new()
		add_child(meter)
		stats_on = true
	else:
		meter.queue_free()
		meter = null
		stats_on = false

func set_lag(ms: int, loss_pct := 0.0) -> void:
	lag_ms = maxi(0, ms)
	jitter_ms = lag_ms / 4
	loss = clampf(loss_pct / 100.0, 0.0, 0.9)

func _process(dt: float) -> void:
	if steam_ready:
		steam.run_callbacks()
	_meter(dt)
	if not _held.is_empty():
		var now := Time.get_ticks_msec()
		while not _held.is_empty() and int(_held[0].due) <= now:
			var h: Dictionary = _held.pop_front()
			_receive(h.type, h.data, h.from)

## Hold a message back for the pretend lag; order is kept, as over one connection.
func _hold(type: String, data, from: int, reliable: bool) -> bool:
	if lag_ms <= 0:
		return false
	if not reliable and loss > 0.0 and randf() < loss:
		return true
	_held_due = maxi(_held_due, Time.get_ticks_msec() + lag_ms + randi_range(-jitter_ms, jitter_ms))
	_held.append({"type": type, "data": data, "from": from, "due": _held_due})
	return true

# ---------- Steam ----------

## Steam lobbies can be used: Steam runs and the multiplayer extension (SteamMultiplayerPeer) is in this build.
func steam_available() -> bool:
	return steam_ready and (steam_peer_factory.is_valid() or ClassDB.class_exists("SteamMultiplayerPeer"))

## The Steam transport's peer (the SteamMultiplayerPeer extension), or null where this build has none. Tests put
## their own factory here.
var steam_peer_factory := Callable()
func _steam_peer() -> Object:
	if steam_peer_factory.is_valid():
		return steam_peer_factory.call()
	return ClassDB.instantiate("SteamMultiplayerPeer") if ClassDB.class_exists("SteamMultiplayerPeer") else null

func _init_steam() -> void:
	# The download for people without Steam (the "standalone" feature, tools/package.py) never starts Steam, even
	# if the library is about: with the Steam client open it would show the player as playing Valve's test app 480.
	if OS.has_feature("standalone"):
		return
	# A friend who is not there (Friends) joins by address and has no Steam: the player's Steam is the host's alone.
	if OS.get_cmdline_user_args().has("--friend"):
		return
	if not Engine.has_singleton("Steam"):
		return
	steam = Engine.get_singleton("Steam")
	# The app id goes to Steam's library the way Steam itself gives it to a game it starts, in the environment (a game Steam starts
	# has it set already; one started by hand is Valve's test app 480 unless SteamAppId says otherwise), and the library's init is
	# called with no arguments: which argument of it is the id has changed between GodotSteam's versions.
	var app_id := int(OS.get_environment("SteamAppId")) if OS.get_environment("SteamAppId") != "" else 480
	if OS.get_environment("SteamAppId") == "":
		OS.set_environment("SteamAppId", str(app_id))
	if OS.get_environment("SteamGameId") == "":
		OS.set_environment("SteamGameId", str(app_id))
	var modern := steam.has_method("steamInitEx")
	var res = steam.call("steamInitEx") if modern else steam.call("steamInit")
	# (steamInitEx answers {status: 0} when it worked, the older steamInit {status: 1}.)
	var ok: bool = (res is Dictionary and int(res.get("status", -1)) == (0 if modern else 1)) or res == true
	if not ok:
		steam_problem = "Steam is not running"
		push_warning("Steam is not running; multiplayer falls back to direct connections.")
		return
	steam_ready = true
	steam_user = int(steam.call("getSteamID"))
	my_name = String(steam.call("getPersonaName"))
	if not (steam_peer_factory.is_valid() or ClassDB.class_exists("SteamMultiplayerPeer")):
		steam_problem = "Steam is running but this game has no Steam multiplayer library"
		push_warning("SteamMultiplayerPeer is missing: Steam lobbies are off, joining by address still works.")
	steam.connect("lobby_created", _on_lobby_created)
	steam.connect("lobby_joined", _on_lobby_joined)
	steam.connect("lobby_match_list", func(list): lobbies.emit(_describe(list)))
	if steam.has_signal("join_requested"):
		steam.connect("join_requested", func(lobby, _friend): join_steam(int(lobby)))
	# Valve's advice: ask for the relay network at the start, so the first lobby is not slowed by it finding its servers.
	if steam.has_method("initRelayNetworkAccess"):
		steam.call("initRelayNetworkAccess")
	# Steam starts the game with "+connect_lobby <id>" when a friend's invite (or "Join Game") is taken while it is closed.
	launch_lobby = lobby_from_args(OS.get_cmdline_args())

## The lobby id after "+connect_lobby" in these arguments, 0 where there is none.
static func lobby_from_args(args: PackedStringArray) -> int:
	var li := args.find("+connect_lobby")
	if li >= 0 and args.size() > li + 1 and args[li + 1].is_valid_int():
		return int(args[li + 1])
	return 0

## The lobby a friend's invite started this game for, once (the menu joins it when it is up).
func take_launch_lobby() -> int:
	var l := launch_lobby
	launch_lobby = 0
	return l

## A marker on the Steam game recording's timeline (a kill, the kill cam's pick): the player
## finds the moment there and clips it in a click. `clip` 0 none, 1 standard, 2 featured.
## Works with the GodotSteam builds that have the timeline (either generation of its call).
func timeline_event(title: String, desc: String, clip := 1, icon := "steam_combat") -> void:
	if not steam_ready:
		return
	if steam.has_method("addInstantaneousTimelineEvent") and steam.get_method_argument_count("addInstantaneousTimelineEvent") == 6:
		steam.call("addInstantaneousTimelineEvent", title, desc, icon, 0, 0.0, clip)
	elif steam.has_method("addTimelineEvent") and steam.get_method_argument_count("addTimelineEvent") == 7:
		steam.call("addTimelineEvent", icon, title, desc, 0, 0.0, 0.0, clip)

## What a room is for: the party's co-op campaign (every player, the host too, has a gladiator and a purse of his own, begun as a
## single campaign is: Save.box_begin "coop") or the friends' Arena (everyone has a sandbox of his own with no limit on money: the
## campaign is never touched). The host chooses it when he opens the room; a guest
## is told when he comes in (Menu keeps the sandbox for the Arena).
const KIND_CAMPAIGN := "campaign"
const KIND_ARENA := "arena"
var room_kind := KIND_CAMPAIGN
var coop_run := 0               # the run of the party's campaign the room plays (the host's number, told to a guest as he comes in)

static func clean_kind(v) -> String:
	return KIND_ARENA if (v is String and v == KIND_ARENA) else KIND_CAMPAIGN

## How many a room takes (the host and his guests): four for a campaign room, eight for an Arena room.
func room_cap() -> int:
	return CAMPAIGN_PLAYERS if room_kind == KIND_CAMPAIGN else MAX_PLAYERS

## ---------- Who is in the room ----------
## A guest knows only the host and himself (the host's books, `peers`, are the host's alone): so the host tells every guest who is in
## the room ("roster": id, name and round trip of each, when someone comes or goes and every ROSTER_EVERY seconds for the pings), and
## room_list() gives each side the same list for the lobby screen to draw.
const ROSTER_EVERY := 2.0
var _roster: Array = []         # (a guest) what the host last said: [{id, name, ping}]
var _roster_t := 0.0

## Everyone in the room, the host first and then the guests as they came: [{id, name, host, you, ping}]. `ping` is that guest's
## round trip to the host in ms (-1: not known yet; 0: the host himself). Empty when there is no room.
func room_list() -> Array:
	var out := []
	if not active():
		return out
	if is_host():
		out.append({"id": 1, "name": my_name, "host": true, "you": true, "ping": 0.0})
		var ids := peers.keys()
		ids.sort()
		for id in ids:
			out.append({"id": int(id), "name": String(peers[id].get("name", "Guest")), "host": false, "you": false, "ping": float(guest_pings.get(id, -1.0))})
		return out
	var me := my_id()
	for r in _roster:
		out.append({"id": int(r.id), "name": String(r.name), "host": int(r.id) == 1, "you": int(r.id) == me, "ping": ping_ms if int(r.id) == me else float(r.ping)})
	if out.is_empty():
		# (Before the host's first word: the host as a stranger, and me.)
		out = [{"id": 1, "name": Loc.t("The host"), "host": true, "you": false, "ping": 0.0}, {"id": me, "name": my_name, "host": false, "you": true, "ping": ping_ms}]
	return out

## The host tells his guests who is in the room.
## The host tells every guest in the room what it is for and which run of the party's campaign it plays (as each is told as he comes in):
## a guest keeps the gladiator of that run, as he left it, or begins a new one's.
func announce_room() -> void:
	if is_host():
		send_all("room", {"k": room_kind, "run": coop_run})

func send_roster() -> void:
	if not active() or not is_host():
		return
	_roster_t = 0.0
	if peers.is_empty():
		return
	var list := [[1, my_name, 0]]
	var ids := peers.keys()
	ids.sort()
	for id in ids:
		list.append([int(id), String(peers[id].get("name", "Guest")), int(roundf(float(guest_pings.get(id, -1.0))))])
	send_all("roster", {"p": list})

## A roster from the wire as it may be kept: eight at most, names without markup, numbers that are numbers.
static func clean_roster(v) -> Array:
	var out := []
	if v is Dictionary and v.get("p") is Array:
		for r in (v.p as Array).slice(0, MAX_PLAYERS):
			if r is Array and r.size() >= 3:
				out.append({"id": int(num(r[0], -1.0)), "name": clean_name(r[1]), "ping": clampf(num(r[2], -1.0), -1.0, 9999.0)})
	return out

## This computer's addresses a friend on the same network can join by: IPv4 only, never the loopback or a link-local one, the
## private ranges first (192.168, then 10., then 172.16-31) as the likeliest to be the LAN.
static func lan_addresses() -> Array:
	return lan_from(IP.get_local_addresses())

## `lan_addresses` of a list of addresses (a test hands its own).
static func lan_from(raw: Array) -> Array:
	var out := []
	for a in raw:
		var s := String(a)
		var parts := s.split(".")
		if parts.size() != 4 or s.begins_with("127.") or s.begins_with("169.254.") or s.begins_with("0."):
			continue
		var ok := true
		for q in parts:
			if not q.is_valid_int() or int(q) < 0 or int(q) > 255:
				ok = false
		if ok and not out.has(s):
			out.append(s)
	out.sort_custom(func(a, b): return _addr_rank(a) < _addr_rank(b))
	return out

static func _addr_rank(a: String) -> int:
	if a.begins_with("192.168."):
		return 0
	if a.begins_with("10."):
		return 1
	if a.begins_with("172."):
		var second := int(a.split(".")[1])
		return 2 if second >= 16 and second <= 31 else 3
	return 3

func host_steam(public := true) -> void:
	if not steam_available():
		connection_failed.emit(Loc.t(steam_problem if steam_problem != "" else "Steam is not running"))
		return
	var kind := room_kind   # (leaving an old room forgets its kind; the one asked for is kept)
	if transport != "" or lobby_id:
		leave()
	room_kind = kind
	steam.call("createLobby", 2 if public else 1, room_cap()) # LOBBY_TYPE_PUBLIC = 2, FRIENDS_ONLY = 1

func _on_lobby_created(result: int, id: int) -> void:
	if result != 1:
		connection_failed.emit(Loc.t("Steam could not make the lobby (%d)") % result)
		return
	lobby_id = id
	steam.call("setLobbyData", id, "game", LOBBY_KEY)
	steam.call("setLobbyData", id, "ver", build_tag())
	steam.call("setLobbyData", id, "kind", room_kind)
	steam.call("setLobbyData", id, "name", (Loc.t("%s's arena") if room_kind == KIND_ARENA else Loc.t("%s's party")) % my_name)   # (as the lobby screen's title says)
	steam.call("setLobbyJoinable", id, true)
	var p = _steam_peer()
	var err = p.call("create_host", 0) if p != null else ERR_UNAVAILABLE
	if err != OK:
		steam.call("leaveLobby", id)
		lobby_id = 0
		connection_failed.emit(Loc.t("Steam networking failed (%d)") % err)
		return
	multiplayer.multiplayer_peer = p
	transport = "steam"
	_presence()
	connected.emit()

func list_steam_lobbies() -> void:
	if not steam_available():
		lobbies.emit([])
		return
	steam.call("addRequestLobbyListStringFilter", "game", LOBBY_KEY, 0)   # (0: equal)
	steam.call("addRequestLobbyListStringFilter", "ver", build_tag(), 0)
	# Rooms anywhere, with a place free, not just the ones near this player (Steam's default).
	if steam.has_method("addRequestLobbyListDistanceFilter"):
		steam.call("addRequestLobbyListDistanceFilter", 3)   # (3: worldwide)
	if steam.has_method("addRequestLobbyListFilterSlotsAvailable"):
		steam.call("addRequestLobbyListFilterSlotsAvailable", 1)
	if steam.has_method("addRequestLobbyListResultCountFilter"):
		steam.call("addRequestLobbyListResultCountFilter", 50)
	steam.call("requestLobbyList")

func _describe(list: Array) -> Array:
	var out := []
	for id in list:
		# (A stranger's lobby names itself: shown as a name, never as markup.)
		out.append({"id": int(id), "name": clean_name(steam.call("getLobbyData", id, "name"), 40), "players": int(steam.call("getNumLobbyMembers", id)), "mode": clean_name(steam.call("getLobbyData", id, "mode"), 20, ""), "kind": clean_kind(steam.call("getLobbyData", id, "kind"))})
	return out

## Join a Steam lobby: from the room list, or a friend's invite ("Join Game", or the overlay's). In a room already, that
## one is left first.
func join_steam(id: int) -> void:
	if not steam_available():
		connection_failed.emit(Loc.t(steam_problem if steam_problem != "" else "Steam is not running"))
		return
	if id == lobby_id and transport != "":
		return
	if transport != "" or lobby_id:
		leave()
		leave_reason = Loc.t("Joining a friend's room...")
		disconnected.emit()
	steam.call("joinLobby", id)

func _on_lobby_joined(id: int, _perm: int, _locked: bool, response: int) -> void:
	if response != 1:
		connection_failed.emit(Loc.t("Could not join that lobby (%d)") % response)
		return
	lobby_id = id
	var owner := int(steam.call("getLobbyOwner", id))
	if owner == steam_user:
		return # our own lobby
	# The host's build must be this one (a friend's invite brings a player to a room that the list's filter never vetted).
	var theirs := str(steam.call("getLobbyData", id, "ver"))
	if theirs != build_tag():
		steam.call("leaveLobby", id)
		lobby_id = 0
		connection_failed.emit(Loc.t("That room runs another version of the game (%s; yours is %s): update the game and join again.") % [theirs if theirs != "" else "?", build_tag()])
		return
	var p = _steam_peer()
	var err = p.call("create_client", owner, 0) if p != null else ERR_UNAVAILABLE
	if err != OK:
		steam.call("leaveLobby", id)
		lobby_id = 0
		connection_failed.emit(Loc.t("Steam networking failed (%d)") % err)
		return
	multiplayer.multiplayer_peer = p
	transport = "steam"
	_presence()

## What friends see of the player on Steam, and the "Join Game" that goes with it: in a lobby, a connect string Steam hands
## to the game when a friend joins (+connect_lobby), and the room's size; out of it, nothing.
func _presence(on := true) -> void:
	if not steam_ready:
		return
	if not on or lobby_id == 0:
		if steam.has_method("clearRichPresence"):
			steam.call("clearRichPresence")
		return
	steam.call("setRichPresence", "connect", "+connect_lobby %d" % lobby_id)
	steam.call("setRichPresence", "status", Loc.t("In an arena"))
	steam.call("setRichPresence", "steam_player_group", str(lobby_id))
	_presence_size()

func _presence_size() -> void:
	if steam_ready and lobby_id and is_host():
		steam.call("setRichPresence", "steam_player_group_size", str(peers.size() + 1))

## Steam's invite window over the game: the friends list, with this room to invite them to.
func invite_friends() -> void:
	if steam_ready and lobby_id and steam.has_method("activateGameOverlayInviteDialog"):
		steam.call("activateGameOverlayInviteDialog", lobby_id)

## Whether the multiplayer extension has a call. The class is asked, not an instance: making a peer before Steam is up may reach
## for Steam's networking too early. (Where a test has put a factory in its place, the peer the factory makes.)
func _peer_has(method: String) -> bool:
	if ClassDB.class_exists("SteamMultiplayerPeer"):
		return ClassDB.class_has_method("SteamMultiplayerPeer", method)
	var p = steam_peer_factory.call() if steam_peer_factory.is_valid() else null
	return p != null and p.has_method(method)

## The calls of the multiplayer extension, each with the names of its arguments, on one line: the extensions do not all
## name things alike, and this is how a difference is seen (steam_check prints it).
static func api_text(methods: Array) -> String:
	var names := PackedStringArray()
	for d in methods:
		var n := String(d.get("name", ""))
		if n == "" or n.begins_with("_"):
			continue
		var args := PackedStringArray()
		for a in d.get("args", []):
			args.append(String(a.get("name", "?")))
		names.append("%s(%s)" % [n, ", ".join(args)])
	return "; ".join(names)

## What a call returned, in words (an Error is named; anything else says what it was).
static func call_result(v) -> String:
	return "%s (%d)" % [error_string(v), v] if typeof(v) == TYPE_INT else "returned %s, not an Error" % [str(v)]

## `-- --steam-check`'s live test of the multiplayer extension, on this PC alone: a room is opened (create_host), this same Steam id
## joins it (create_client; Steam may not let one join oneself, and then it says so: a second PC is the real test), a packet goes
## through, and both are closed. A line that says FAILED is a call that did not do what the game asks of it.
func steam_selftest(wait_ms := 6000) -> Array:
	var out := ["Live test of a room (this PC alone):"]
	var host = _steam_peer()
	if host == null:
		return out + ["  FAILED: no multiplayer extension to test"]
	var err = host.call("create_host", 0)
	out.append("  open a room, create_host(0): %s" % call_result(err))
	if typeof(err) != TYPE_INT or err != OK:
		out.append("  FAILED: the room did not open")
		return out
	var guest = _steam_peer()
	var joined := [0]
	host.peer_connected.connect(func(id: int): joined[0] = id)
	var gerr = guest.call("create_client", steam_user, 0)
	out.append("  join it as yourself, create_client(%d, 0): %s" % [steam_user, call_result(gerr)])
	if typeof(gerr) == TYPE_INT and gerr == OK:
		var t0 := Time.get_ticks_msec()
		while joined[0] == 0 and Time.get_ticks_msec() - t0 < wait_ms:
			host.poll()
			guest.poll()
			await get_tree().process_frame
		if joined[0] != 0:
			out.append("  joined after %d ms (the guest is peer %d)" % [Time.get_ticks_msec() - t0, joined[0]])
			guest.set_target_peer(1)
			guest.put_packet(PackedByteArray([7, 7, 7]))
			t0 = Time.get_ticks_msec()
			while host.get_available_packet_count() == 0 and Time.get_ticks_msec() - t0 < 2000:
				host.poll()
				guest.poll()
				await get_tree().process_frame
			if host.get_available_packet_count() > 0:
				out.append("  a packet sent by the guest arrived: %s" % str(host.get_packet()))
			else:
				out.append("  the guest's packet did not arrive within 2 s")
		else:
			out.append("  nobody joined within %d s: Steam may not let one join oneself, and that is no fault; a second PC is the real test (docs/MULTIPLAYER_TEST.md)" % [wait_ms / 1000])
	host.close()
	guest.close()
	return out

## What this game finds of Steam, line by line (`-- --steam-check`): that the library, the running client, the multiplayer
## extension and the lobby calls are all there, before two people try a room.
func steam_report() -> Array:
	var out := ["WRECKSMITH %s" % build_tag()]
	out.append("Steam library (GodotSteam): %s" % ("found" if Engine.has_singleton("Steam") else "NOT FOUND (addons/godotsteam is missing, or not loaded)"))
	if steam_ready:
		out.append("Steam client: running, signed in as %s (%d)" % [my_name, steam_user])
	else:
		out.append("Steam client: NOT READY (%s)" % (steam_problem if steam_problem != "" else "no Steam library, or this is a download without Steam"))
	var peer_there := steam_peer_factory.is_valid() or ClassDB.class_exists("SteamMultiplayerPeer")
	out.append("Multiplayer extension (SteamMultiplayerPeer): %s" % ("found" if peer_there else "NOT FOUND"))
	if peer_there:
		# The two calls that open and join a room (tools/package.py reads these lines too); the third is the kick's memory of who was turned away.
		for m in ["create_host", "create_client"]:
			out.append("  peer call %s: %s" % [m, "yes" if _peer_has(m) else "MISSING"])
		out.append("  peer call get_steam64_from_peer_id: %s" % ("yes" if _peer_has("get_steam64_from_peer_id") else "no (optional: a guest who was turned away could come back; the game looks for the call by its name)"))
		var api := api_text(ClassDB.class_get_method_list("SteamMultiplayerPeer", true)) if ClassDB.class_exists("SteamMultiplayerPeer") else ""
		if api != "":
			out.append("  peer API: " + api)
	if steam != null:
		for m in ["steamInitEx", "createLobby", "joinLobby", "leaveLobby", "setLobbyData", "getLobbyData", "setLobbyJoinable", "getLobbyOwner", "getNumLobbyMembers", "requestLobbyList", "addRequestLobbyListStringFilter", "addRequestLobbyListDistanceFilter", "setRichPresence", "clearRichPresence", "activateGameOverlayInviteDialog", "initRelayNetworkAccess", "run_callbacks"]:
			out.append("  call %s: %s" % [m, "yes" if steam.has_method(m) else "MISSING"])
		for sg in ["lobby_created", "lobby_joined", "lobby_match_list", "join_requested"]:
			out.append("  signal %s: %s" % [sg, "yes" if steam.has_signal(sg) else "MISSING"])
	out.append("Steam multiplayer: %s" % ("READY" if steam_available() else "not available"))
	return out

# ---------- ENet ----------

## A game joined by address is encrypted (DTLS) as Steam's sockets are: the host makes a key and a
## certificate for the session, the guests take it without a name to check it against (friends
## have no certificate authority between them): enough that nobody on the wire between them can
## read the game or the voices (user: friends playing together, completely safely).
const DTLS_NAME := "wrecksmith-host"
var dtls := true

func host_enet(port := PORT) -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, room_cap() - 1)   # (the guests: the host is one of the room's four or eight)
	if err != OK:
		return err
	if dtls:
		var crypto := Crypto.new()
		var key := crypto.generate_rsa(2048)
		var cert := crypto.generate_self_signed_certificate(key, "CN=" + DTLS_NAME)
		err = p.host.dtls_server_setup(TLSOptions.server(key, cert))
		if err != OK:
			p.close()
			return err
	p.host.compress(ENetConnection.COMPRESS_RANGE_CODER)   # (the guests' side does the same)
	multiplayer.multiplayer_peer = p
	transport = "enet"
	connected.emit()
	return OK

func join_enet(address: String, port := PORT) -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(address, port)
	if err != OK:
		return err
	if dtls:
		err = p.host.dtls_client_setup(DTLS_NAME, TLSOptions.client_unsafe())
		if err != OK:
			p.close()
			return err
	p.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = p
	transport = "enet"
	_set_local(is_this_computer(address))
	return OK

# ---------- Both ----------

func active() -> bool:
	return transport != "" and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func is_host() -> bool:
	return transport != "" and multiplayer.is_server()

## The host: more in the room (he and his guests) than the co-op campaign takes.
func campaign_full() -> bool:
	return active() and is_host() and peers.size() + 1 > CAMPAIGN_PLAYERS

func my_id() -> int:
	return multiplayer.get_unique_id() if transport != "" else 1

func leave() -> void:
	if steam_ready and lobby_id:
		steam.call("leaveLobby", lobby_id)
	lobby_id = 0
	_presence(false)
	_banned.clear()
	_rate.clear()
	ping_ms = -1.0
	host_rate = -1.0
	host_fps = -1.0
	guest_pings.clear()
	_roster.clear()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	transport = ""
	room_kind = KIND_CAMPAIGN
	coop_run = 0
	peers.clear()
	inputs.clear()
	_held.clear()
	_peer_local.clear()
	_set_local(false)
	_pace()   # (alone again: the engine's own cap)

func set_lobby_info(mode: String) -> void:
	if steam_ready and lobby_id and is_host():
		steam.call("setLobbyData", lobby_id, "mode", mode)

func _on_peer_connected(id: int) -> void:
	# One the host turned out of this room does not come back in.
	if is_host() and _banned.has(_peer_key(id)):
		_turn_away(id)
		return
	# The guest introduces itself with "hello". A guest whose game closes without a word is
	# missed within seconds, not ENet's half a minute: his fighter leaves the yard with him.
	if transport == "enet" and is_host() and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var pp: ENetPacketPeer = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(id)
		if pp:
			pp.set_timeout(0, 4000, 8000)
			_no_throttle(pp)
			_peer_local[id] = is_this_computer(pp.get_remote_address())
			_set_local(_peer_local.values().has(true))

# ---------- Two windows on one computer ----------
# A room whose players are windows of this one computer (a guest joined 127.0.0.1, or this computer's own address) shares
# one graphics card, and the window in front takes nearly all of it. From a test video: two full-screen windows at 1440p,
# 9 ms of graphics card to a frame each, the front one drawing 90 frames a second and the host's behind it 17, so that
# the host took its input and sent the world in bursts every 60 ms and every answer came late. Such a room lowers the
# picture of both (Menu.room_scale, Menu.room_fps) so that each keeps up. A room between computers is never touched.

signal local_room_changed

var local_room := false
var _peer_local := {}           # host: id -> that guest's game is on this computer

## Is `address` this computer: loopback, or one of its own addresses?
static func is_this_computer(address: String) -> bool:
	var a := address.strip_edges().to_lower()
	if a.begins_with("::ffff:") and a.contains("."):
		a = a.substr(7)   # an IPv4 address in its IPv6 dress
	if a == "":
		return false
	if a == "localhost" or a == "::1" or a.begins_with("127."):
		return true
	for own in IP.get_local_addresses():
		if own.to_lower() == a:
			return true
	return false

func _set_local(on: bool) -> void:
	if on == local_room:
		return
	local_room = on
	local_room_changed.emit()

var leave_reason := ""   # why a guest's game ended, for the screen he lands on ("": the host left)
var _banned := {}        # turned out of this room: "ip:..." or "steam:..." -> true

## The host turns a guest out of the room (user: friends playing together safely): he is told,
## let go, and cannot come back in until the host opens a new room.
func kick(id: int) -> void:
	if not is_host() or not peers.has(id):
		return
	var key := _peer_key(id)
	if key != "":
		_banned[key] = true
	_turn_away(id)

## Tells a guest he is not wanted here, and lets him go a moment later (the word goes first).
func _turn_away(id: int, why := "") -> void:
	if not multiplayer.get_peers().has(id):
		return
	send_to(id, "kicked", {"why": why, "ver": build_tag()})
	var mp := multiplayer.multiplayer_peer
	get_tree().create_timer(0.3).timeout.connect(func():
		# (Unless he has gone already, as a guest told to go does.)
		if mp != null and multiplayer.multiplayer_peer == mp and multiplayer.get_peers().has(id):
			mp.disconnect_peer(id))

## Who a peer is, for the room's turned-away list: his address (ENet) or his Steam id.
func _peer_key(id: int) -> String:
	var mp := multiplayer.multiplayer_peer
	if transport == "enet" and mp is ENetMultiplayerPeer:
		var pp: ENetPacketPeer = (mp as ENetMultiplayerPeer).get_peer(id)
		return ("ip:" + pp.get_remote_address()) if pp else ""
	if transport == "steam" and mp != null:
		var fn := steam_id_call(mp)
		if fn != "":
			return "steam:%d" % int(mp.call(fn, id))
	return ""

## The call of the multiplayer extension that says whose Steam id a peer is. The extensions name it differently
## (get_steam64_from_peer_id, get_steam_id_from_peer_id...): the known names first, then any "get_" call that has "steam" before
## "peer" in its name and takes the one argument (the opposite, get_peer_id_from_steam64, has "peer" first). "" when there is none.
static func steam_id_call(mp: Object) -> String:
	for m in ["get_steam64_from_peer_id", "get_steam_id_from_peer_id", "get_steamid_from_peer_id", "get_steam64_from_peer", "get_steam_id_from_peer"]:
		if mp.has_method(m):
			return m
	for d in mp.get_method_list():
		var n := String(d.get("name", ""))
		var at_steam := n.find("steam")
		if n.begins_with("get_") and at_steam >= 0 and n.find("peer") > at_steam and (d.get("args", []) as Array).size() == 1:
			return n
	return ""

func _on_peer_disconnected(id: int) -> void:
	guest_pings.erase(id)
	if _peer_local.erase(id):
		_set_local(_peer_local.values().has(true))
	if peers.erase(id):
		_presence_size()
		peer_left.emit(id)
		send_roster()
	inputs.erase(id)

## ENet sheds unreliable packets on purpose whenever the round trip wobbles (its "throttle"):
## on a busy machine or a jittery line it threw away a quarter of the voice and of the
## snapshots, each lost packet a hole in a voice or a hitch in a fighter. What the game sends
## is small (tens of KB a second); it goes out whole, and what the line itself loses is lost.
func _no_throttle(pp: ENetPacketPeer) -> void:
	pp.throttle_configure(5000, 2, 0)

func _on_connected() -> void:
	if transport == "enet" and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var hp: ENetPacketPeer = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(1)
		if hp:
			_no_throttle(hp)
	connected.emit()
	send_host("hello", {"name": my_name, "ver": build_tag(), "loadout": my_loadout, "kit": my_kit, "body": my_body})

# ---------- How the connection is doing (the F3 meter, and the load test) ----------
# Every guest asks the host once a second ("_ping"); the host answers at once ("_pong") with
# its own physics rate. So on Steam as on ENet each game knows its round trip to the host,
# whether the host keeps up (120 physics steps a second), and the host knows every guest's.

var stats_on := false           # count the bytes (the meter is open, or the load test)
var stats := {}                 # type -> bytes sent
var stats_in := {}              # type -> bytes received
var ping_ms := -1.0             # guest: round trip to the host
var host_rate := -1.0           # guest: the host's physics steps a second, as it says
var guest_pings := {}           # host: id -> that guest's round trip
var step_rate := 120.0          # this game's physics steps over the last second
var host_fps := -1.0            # guest: the host's frames a second, as it says
var snap_rate := 0.0            # snapshot messages a second (guest)
var snap_gap := 0               # the longest wait between two snapshots in the last second (ms)
var _snaps := 0
var _snap_last := 0
var _gap := 0
var _meter_t := 0.0
var _frames0 := -1
var _wall0 := 0

# ---------- A room keeps time ----------
# Godot runs at most `max_physics_steps_per_frame` (4 of 120 a second) in one frame and lets the game fall behind the
# clock when a frame takes longer than that: below 30 frames a second the whole game runs in slow motion. Alone that
# is the safe thing (a heavy moment never snowballs). In a room it is the worst: two windows on one computer, one
# of them behind the other, a first-time shader build, and the host's world, which every guest draws, ran at
# half speed (measured: frames of 45 ms, the guest saw 68 of 120 steps a second and 22 snapshots, not 40). So a room
# lets a frame catch up as far as the physics allows: as many steps as fit in PHYSICS_BUDGET_MS of the frame at the
# cost one step has been taking, never fewer than the engine's own cap and never more than ROOM_STEPS_MAX. A room
# whose steps already cost more than the 8.3 ms there is for each (too many fighters for the computer) does not
# raise it: more steps would only make each frame longer, and the host's own picture a slide show (and see OVERLOAD_ON_MS).
const ROOM_STEPS_MAX := 12
const PHYSICS_BUDGET_MS := 50.0
# A host whose steps cost more than the 8.3 ms there is for each, and keep costing it (too many fighters for the computer, in a room or
# alone), cannot keep the game at its speed whatever the cap: it runs behind the clock all the time, and a frame of the engine's 4 steps
# leaves the picture at a quarter of the steps a second (a wave of 8 friends and 8 foes: 50 steps, 12 frames a second, measured). Two steps
# to a frame there give about twice the frames (47 steps, 23 frames: `tests/mix298.gd`) for a few percent of the game's speed (a tenth at
# most, with a frame's whole drawing in it: the README has the table), so that is the cap while it lasts. The steps themselves are the same
# (a step is always 1/120 s: the cap is only how many a frame may take), and a host that keeps up is not touched. The line is where four
# steps stop fitting in a frame of 30 a second (4 x 8.6 ms = 34 ms). Not on a spike (a first-time shader, one heavy step: the smoothed
# cost jumps and comes back within a second): the cost must be over OVERLOAD_ON_MS at OVERLOAD_LOOKS looks (once a second) in a row, and
# it is over when it comes under OVERLOAD_OFF_MS.
const OVERLOAD_ON_MS := 8.6
const OVERLOAD_OFF_MS := 7.8
const OVERLOAD_LOOKS := 2
const OVERLOAD_STEPS := 2

var step_ms := 0.0              # what one physics step has been costing here (ms, smoothed)
var overload_on := true         # (a switch for tests and probes: off, the cap is the room's or the engine's own, as it was before the two steps)
var overloaded := false         # the steps cost more than there is for them, for good (see OVERLOAD_ON_MS)
var _hot_looks := 0             # the looks in a row at which they did
var _steps_alone := -1          # the engine's cap before a room (or an overload) changed it (-1: not changed)
var _frame_steps := 0
var _frame_t0 := 0

static func steps_cap(step_cost_ms: float, base: int, over := false) -> int:
	if over:
		return mini(base, OVERLOAD_STEPS)
	if step_cost_ms <= 0.0:
		return base
	return clampi(int(PHYSICS_BUDGET_MS / step_cost_ms), base, maxi(base, ROOM_STEPS_MAX))

## One look (once a second) at what a step costs: whether the host is over its budget for good, given whether it was, how many looks in a
## row the cost has been high and what it is now. Returns [over, looks in a row].
static func overload_after(was: bool, hot: int, step_cost_ms: float) -> Array:
	hot = hot + 1 if step_cost_ms >= OVERLOAD_ON_MS else 0
	if was:
		return [step_cost_ms > OVERLOAD_OFF_MS, hot]
	return [hot >= OVERLOAD_LOOKS, hot]

func _physics_process(_dt: float) -> void:
	# What came in is read at the start of every physics step, before the game's own (this node comes first), and not only once a
	# frame after them: the engine reads the line in the frame's idle part, so a guest's hands and the host's snapshots were
	# taken up by the physics steps of the NEXT frame: a whole frame late on each side of the round trip (measured, two games
	# at 60 frames a second: 115 ms from pressing forward to the man moving on the guest's screen, 81 ms with this).
	if (transport == "enet" or transport == "steam") and multiplayer.multiplayer_peer != null:
		multiplayer.poll()
	if _frame_steps == 0:
		_frame_t0 = Time.get_ticks_usec()
	_frame_steps += 1

## Every frame, after its physics steps (this node's _process comes before every other's): what they cost each.
func _time_steps() -> void:
	if _frame_steps <= 0:
		return
	var ms := float(Time.get_ticks_usec() - _frame_t0) / 1000.0 / _frame_steps
	step_ms = ms if step_ms <= 0.0 else lerpf(step_ms, ms, 0.05)
	_frame_steps = 0

## Once a second: the room's cap, or the two steps of an overloaded host (and back to the engine's own when neither is so).
func _pace() -> void:
	if overload_on:
		var look := overload_after(overloaded, _hot_looks, step_ms)
		if bool(look[0]) != overloaded:
			FpsMeter.note("room %s: a step costs %.1f ms of the 8.3 there is" % ["over its budget (two steps a frame, the game runs slow)" if bool(look[0]) else "back within its budget", step_ms])
		overloaded = look[0]
		_hot_looks = look[1]
	else:
		overloaded = false
		_hot_looks = 0
	if transport != "" or overloaded:
		if _steps_alone < 0:
			_steps_alone = Engine.max_physics_steps_per_frame
		Engine.max_physics_steps_per_frame = steps_cap(step_ms, _steps_alone, overloaded)
	elif _steps_alone >= 0:
		Engine.max_physics_steps_per_frame = _steps_alone
		_steps_alone = -1

func _meter(dt: float) -> void:
	_time_steps()
	if not peers.is_empty() and is_host():
		_roster_t += dt
		if _roster_t >= ROSTER_EVERY:
			send_roster()   # (the pings move: each guest sees how the others are doing)
	_meter_t += dt
	if _meter_t < 1.0:
		return
	_meter_t = 0.0
	var now := Time.get_ticks_msec()
	var fr := Engine.get_physics_frames()
	if _frames0 >= 0 and now > _wall0:
		step_rate = (fr - _frames0) * 1000.0 / float(now - _wall0)
	_frames0 = fr
	_wall0 = now
	snap_rate = float(_snaps)
	_snaps = 0
	snap_gap = _gap
	_gap = 0
	_pace()
	if active() and not is_host():
		send_host("_ping", {"t": now, "p": ping_ms}, false)

func _count_in(type: String, data) -> void:
	if FpsMeter.prof_on:
		FpsMeter.msg_seen[type] = int(FpsMeter.msg_seen.get(type, 0)) + 1   # (the hitch record's: what came in this frame)
	if stats_on:
		stats_in[type] = int(stats_in.get(type, 0)) + var_to_bytes(data).size()
	if type == "snap":
		# (One fighter to a message: the messages of one snapshot come in the same moment.)
		var now := Time.get_ticks_msec()
		if now - _snap_last > 6:
			_snaps += 1
			if _snap_last > 0:
				_gap = maxi(_gap, now - _snap_last)
			_snap_last = now

func send_all(type: String, data, reliable := true) -> void:
	if not active():
		return
	if stats_on:
		stats[type] = int(stats.get(type, 0)) + var_to_bytes(data).size() * maxi(1, peers.size())
	if reliable:
		_msg.rpc(type, data)
	else:
		_umsg.rpc(type, data)

func send_to(id: int, type: String, data, reliable := true) -> void:
	if not active():
		return
	if stats_on:
		stats[type] = int(stats.get(type, 0)) + var_to_bytes(data).size()
	if reliable:
		_msg.rpc_id(id, type, data)
	else:
		_umsg.rpc_id(id, type, data)

func send_host(type: String, data, reliable := true) -> void:
	send_to(1, type, data, reliable)

## A guest's own gladiator as he is now (his arms, his armour, his bag, his body) told the host
## whenever it changes, once a frame at most (the smith, the physician, a bout's end, a death that
## sends the party back to the checkpoint): the host fights him as he is, not as he came into the
## room.
var _me_due := false
func push_me() -> void:
	if _me_due or not active() or is_host():
		return
	_me_due = true
	_push_me.call_deferred()

func _push_me() -> void:
	_me_due = false
	if active() and not is_host():
		send_host("me", {"loadout": my_loadout, "kit": my_kit, "body": my_body})

## A number from the wire, or `def` where something else came (a string, a list, a NaN):
## what a guest sends is read as data, never trusted to be of the kind it should be.
const OFF_GRID := -9999.0   # (what a coordinate that is not a number reads as: outside every grid)
static func num(v, def := 0.0) -> float:
	return float(v) if (v is int or v is float) and is_finite(float(v)) else def

## A kit from the wire: only known throwables (an old kind under its new name), sane counts.
static func sanitize_kit(k) -> Dictionary:
	var out := {}
	if k is Dictionary:
		for id in k:
			var key := str(Throwables.RENAMED.get(str(id), str(id)))
			if Data.shop.get("throwables", {}).has(key):
				out[key] = clampi(int(out.get(key, 0)) + int(num(k[id])), 0, 20)
	return Throwables.bag_clamp(out)

## A guest's latest input; a one-shot press in it (a jump, a grab) is handed out once.
func input_of(id: int) -> Dictionary:
	var inp: Dictionary = inputs.get(id, {})
	if inp.is_empty():
		return inp
	var out := inp.duplicate()
	for k in PlayerInput.ONE_SHOT:
		inp[k] = false
	inp.useItem = -1
	return out

@rpc("any_peer", "call_remote", "reliable")
func _msg(type: String, data) -> void:
	var from := multiplayer.get_remote_sender_id()
	_count_in(type, data)
	if not _hold(type, data, from, true):
		_receive(type, data, from)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _umsg(type: String, data) -> void:
	var from := multiplayer.get_remote_sender_id()
	_count_in(type, data)
	if not _hold(type, data, from, false):
		_receive(type, data, from)

## What a guest may send the host a second (input at 30, voice, the meter's pings, a few
## events): past it the rest of that second is dropped, so a flood from one guest cannot choke
## the host or, passed on, the others.
const MSG_PER_S := 240
## What a guest may say to the host at all: anything else (a snapshot, a spawn, a banner, the
## end of a bout) is the host's word alone and is dropped when a guest sends it.
const FROM_GUESTS := ["hello", "me", "input", "vc", "_ping", "doctor_done", "ff_kit", "ff_ready", "rudis_vote", "gate_pick", "endless_pick", "stall", "respawn"]
var _rate := {}   # peer id -> [the second's start (ms), messages in it]

func _flooding(from: int) -> bool:
	var now := Time.get_ticks_msec()
	var r: Array = _rate.get(from, [now, 0])
	if now - int(r[0]) >= 1000:
		r = [now, 0]
	r[1] = int(r[1]) + 1
	_rate[from] = r
	return int(r[1]) > MSG_PER_S

## A name from the wire as it may be shown: no markup (a name is drawn in the feed's rich
## text), no control characters, 24 letters at most.
static func clean_name(s, most := 24, none := "Guest") -> String:
	var src := String(s) if (s is String or s is StringName) else (str(s) if (s is int or s is float) else "")
	var t := ""
	for ch in src.left(most * 4).replace("[", "(").replace("]", ")"):
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			t += ch
	t = t.strip_edges().left(most)
	return t if t != "" else none

## A loadout from the wire: known weapons by name, a guest's own forged ones kept to what the
## forge itself can make (its grid, its materials, its number of blocks), armour by known pieces
## and cleaned bench designs. (A design of a million blocks, or of numbers that are not numbers,
## would have stalled the host building it.)
static func sanitize_loadout(lo) -> Dictionary:
	var out := {}
	if not (lo is Dictionary):
		return {"main": "gladius"}
	for side in ["main", "off"]:
		var w = lo.get(side)
		if w is String and (w == "" or not Data.preset(w).is_empty()):
			out[side] = w
		elif w is Dictionary:
			var d = clean_design(w)
			if d != null:
				out[side] = d
	if not out.has("main"):
		out.main = "gladius"
	if lo.get("armor_defs") is Dictionary:
		var defs := {}
		for k in lo.armor_defs:
			if defs.size() >= 16:
				break
			var c = Armory.clean_design(lo.armor_defs[k])
			if c != null:
				defs[str(k).left(40)] = c
		out.armor_defs = defs
	if lo.get("armor") is Array:
		var ids := []
		for a in lo.armor:
			if ids.size() >= 12:
				break
			var id := str(a).left(40)
			if Data.armor.has(id) or (out.has("armor_defs") and out.armor_defs.has(id)):
				ids.append(id)
		out.armor = ids
	# A guest's own gladiator (Menu._net_loadout): his look, the armourer's pieces he wears, those he
	# designed and the plates off them, his teaching, his skin and build, the chips in his blades.
	# Kept to their kind and size here; what they hold is made safe where it is read (Menu.peer_look,
	# Armory.register, Armory.clean_wear, Training.sanitize, Match.clean_worn). (Dropped here, the
	# host fought every guest bare: no armour, no look, nothing he had been taught.)
	for k in ["look", "gear"]:
		if lo.get(k) is Array:
			out[k] = (lo[k] as Array).slice(0, 16).filter(func(x): return x is String).map(func(x): return str(x).left(40))
	if lo.get("gear_defs") is Dictionary:
		var gd := {}
		for k in lo.gear_defs:
			if gd.size() >= 16:
				break
			var c = Armory.clean_design(lo.gear_defs[k])
			if c != null:
				gd[str(k).left(40)] = c
		out.gear_defs = gd
	for k in ["gear_wear", "stats", "worn"]:
		if lo.get(k) is Dictionary and var_to_bytes(lo[k]).size() <= 65536:
			out[k] = (lo[k] as Dictionary).duplicate(true)
	if lo.get("skin") is int or lo.get("skin") is float:
		out.skin = int(num(lo.skin))
	if lo.get("build") is String:
		out.build = str(lo.build).left(24)
	return out

## A forged weapon from the wire, or null: only the fields a design has, each of its kind;
## blocks inside the forge's grid, of known materials and jobs, no more than the forge allows.
static func clean_design(d: Dictionary) -> Variant:
	if not (d.get("voxels") is Array) or (d.voxels as Array).is_empty() or (d.voxels as Array).size() > ForgeLib.MAX_VOXELS:
		return null
	var out := {"name": clean_name(d.get("name", "Weapon")).left(32), "kind": "shield" if str(d.get("kind", "weapon")) == "shield" else "weapon"}
	var vox := []
	for v in d.voxels:
		if not (v is Array) or v.size() < 5:
			return null
		var x := int(num(v[0], OFF_GRID)); var y := int(num(v[1], OFF_GRID)); var z := int(num(v[2], OFF_GRID))
		var mat := str(v[3]) if v[3] is String else ""; var job := str(v[4]) if v[4] is String else ""
		if not ForgeLib.in_grid(x, y, z) or not Data.materials.has(mat) or not ["edge", "point", "blunt", "grip"].has(job):
			return null
		vox.append([x, y, z, mat, job, clampi(int(num(v[5])), 0, 5)] if v.size() > 5 else [x, y, z, mat, job])
	out.voxels = vox
	for k in ["twoHanded", "throwable", "spins", "serrated"]:
		if d.has(k):
			out[k] = bool(d[k])
	out.sharpness = clampf(num(d.get("sharpness", 0.8), 0.8), 0.0, 1.0)
	for k in ["gem", "shoots"]:
		if d.get(k) is String and str(d[k]).length() <= 20:
			out[k] = str(d[k])
	if d.get("imbue") is String and ["", "fire", "frost", "venom", "poison"].has(str(d.imbue)):
		out.imbue = str(d.imbue)
	if d.has("durability"):
		out.durability = clampf(num(d.durability, 1.0), 0.2, 2.5)
	if d.get("balance") is Array and d.balance.size() >= 3:
		var bx := num(d.balance[0], OFF_GRID); var by := num(d.balance[1], OFF_GRID); var bz := num(d.balance[2], OFF_GRID)
		if ForgeLib.in_grid(int(bx), int(by), int(bz)):
			out.balance = [bx, by, bz]
	if d.get("grips") is Dictionary:
		var g := {}
		for hk in ["main", "off"]:
			var gp = d.grips.get(hk)
			if gp is Array and gp.size() == 3 and ForgeLib.in_grid(int(num(gp[0], OFF_GRID)), int(num(gp[1], OFF_GRID)), int(num(gp[2], OFF_GRID))):
				g[hk] = [int(gp[0]), int(gp[1]), int(gp[2])]
		out.grips = g
	if d.get("chain") is Dictionary:
		var head = clean_design(d.chain.get("head", {})) if d.chain.get("head") is Dictionary else null
		if head == null:
			return null
		out.chain = {"head": head, "links": clampi(int(num(d.chain.get("links", 4), 4.0)), 1, 16)}
		for k in d.chain:
			if not out.chain.has(k) and (d.chain[k] is bool or d.chain[k] is String):
				out.chain[k] = d.chain[k]
	return out

func _receive(type: String, data, from: int) -> void:
	# Only the host may tell guests what happens; guests may only say hello and send input.
	if not is_host() and from != 1:
		return
	if is_host() and from != 1 and (not FROM_GUESTS.has(type) or _flooding(from)):
		return
	# The host says what the room is for (a guest keeps the sandbox of an Arena room: Menu).
	if type == "room":
		if not is_host() and data is Dictionary:
			room_kind = clean_kind(data.get("k"))
			coop_run = clampi(int(num(data.get("run", 0))), 0, 2147483647)
			room_kind_known.emit(room_kind)
		return
	if type == "roster":
		if not is_host():
			_roster = clean_roster(data)
			roster_changed.emit()
		return
	if type == "kicked" and not is_host():
		if data is Dictionary and str(data.get("why", "")) == "version":
			leave_reason = Loc.t("The host's game is another version (%s; yours is %s): update the game and join again.") % [clean_name(data.get("ver", "?"), 24), build_tag()]
		elif data is Dictionary and str(data.get("why", "")) == "full":
			leave_reason = Loc.t("The room is full")
		else:
			leave_reason = "The host removed you from the room"
		leave()
		disconnected.emit()
		return
	# The meter's own round trip (never passed on to the game).
	if type == "_ping":
		if is_host() and data is Dictionary:
			guest_pings[from] = clampf(num(data.get("p", -1.0), -1.0), -1.0, 9999.0)
			send_to(from, "_pong", {"t": int(num(data.get("t", 0))), "s": snappedf(step_rate, 0.1), "f": roundi(Engine.get_frames_per_second())}, false)
		return
	if type == "_pong":
		if not is_host() and data is Dictionary:
			ping_ms = clampf(float(Time.get_ticks_msec() - int(num(data.get("t", 0)))), 0.0, 9999.0)
			host_rate = clampf(num(data.get("s", -1.0), -1.0), -1.0, 1000.0)
			host_fps = clampf(num(data.get("f", -1.0), -1.0), -1.0, 10000.0)
		return
	if is_host():
		match type:
			"hello":
				# Once a guest: a second hello would have walked a second fighter of his in.
				if data is Dictionary and not peers.has(from) and not _banned.has(_peer_key(from)):
					if str(data.get("ver", "")) != build_tag():
						_turn_away(from, "version")   # (another build in the room would be a different game)
						return
					if peers.size() + 1 >= room_cap():
						_turn_away(from, "full")   # (the campaign's room takes four: the transport's own limit is the same, this is for a lobby that let one more through)
						return
					var info := {"name": clean_name(data.get("name", "Guest")), "loadout": sanitize_loadout(data.get("loadout")), "kit": sanitize_kit(data.get("kit")), "body": Body.sanitize(data.get("body"))}
					# A room takes nothing of a guest's single campaign (his arms, bag, wounds): he comes in plain, and his gladiator for the
					# room (the Arena's sandbox, the run's gladiator of the party's campaign) follows as "me" as soon as he has been told
					# what the room is (the same breath: Menu). So a man of the single campaign in his armour is never built in the yard
					# for a moment and again.
					info.loadout = {}
					info.kit = {}
					info.body = Body.sanitize({})
					peers[from] = info
					_presence_size()
					send_to(from, "room", {"k": room_kind, "run": coop_run})
					peer_joined.emit(from, info)
					send_roster()
				return
			"me":
				# A guest's gladiator as he is now (push_me), read as his hello was.
				if data is Dictionary and peers.has(from):
					peers[from].loadout = sanitize_loadout(data.get("loadout"))
					peers[from].kit = sanitize_kit(data.get("kit"))
					peers[from].body = Body.sanitize(data.get("body"))
					message.emit(type, null, from)   # (the yard builds him again as he is now)
				return
			"vc":
				# A guest's voice: on to the other guests, and heard here.
				if data is PackedByteArray and data.size() <= 4096:
					for id in peers:
						if int(id) != from:
							send_to(int(id), "vc", {"f": from, "d": data}, false)
					message.emit(type, data, from)
				return
			"input":
				if data is Array:
					var nu := PlayerInput.unpack(data)
					if nu.is_empty():
						return   # (not an input: dropped, the last good one stands)
					# A press not yet acted on survives the next packet.
					var old: Dictionary = inputs.get(from, {})
					for k in PlayerInput.ONE_SHOT:
						if old.get(k, false):
							nu[k] = true
					if old.get("throw", false):
						nu.throwPower = old.throwPower
					if int(old.get("useItem", -1)) >= 0 and int(nu.get("useItem", -1)) < 0:
						nu.useItem = old.useItem
					inputs[from] = nu
				return
	message.emit(type, data, from)
