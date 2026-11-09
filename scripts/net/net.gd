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
signal connection_failed(reason: String)
signal disconnected
signal lobbies(list: Array)

const PORT := 7777
const MAX_PLAYERS := 8
## The co-op campaign is fought by four at most (its bouts are made for one to four); the room,
## and every other way to fight in it, takes eight (user).
const CAMPAIGN_PLAYERS := 4
const LOBBY_KEY := "voxelarena"

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
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.is_echo() and e.keycode == KEY_F3 and active():
		if meter and is_instance_valid(meter):
			meter.queue_free()
			meter = null
			stats_on = false
		else:
			meter = load("res://scripts/ui/net_meter.gd").new()
			add_child(meter)
			stats_on = true

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

func steam_available() -> bool:
	return steam_ready

func _init_steam() -> void:
	if not Engine.has_singleton("Steam"):
		return
	steam = Engine.get_singleton("Steam")
	var app_id := int(OS.get_environment("SteamAppId")) if OS.get_environment("SteamAppId") != "" else 480
	var res = steam.call("steamInitEx", app_id, true) if steam.has_method("steamInitEx") else steam.call("steamInit")
	var ok: bool = (res is Dictionary and int(res.get("status", 1)) == 0) or res == true
	if not ok:
		push_warning("Steam is not running; multiplayer falls back to direct connections.")
		return
	steam_ready = true
	steam_user = int(steam.call("getSteamID"))
	my_name = String(steam.call("getPersonaName"))
	steam.connect("lobby_created", _on_lobby_created)
	steam.connect("lobby_joined", _on_lobby_joined)
	steam.connect("lobby_match_list", func(list): lobbies.emit(_describe(list)))
	if steam.has_signal("join_requested"):
		steam.connect("join_requested", func(lobby, _friend): join_steam(int(lobby)))

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

func host_steam(public := true) -> void:
	if not steam_ready:
		connection_failed.emit("Steam is not running")
		return
	steam.call("createLobby", 2 if public else 1, MAX_PLAYERS) # LOBBY_TYPE_PUBLIC = 2, FRIENDS_ONLY = 1

func _on_lobby_created(result: int, id: int) -> void:
	if result != 1:
		connection_failed.emit(Loc.t("Steam could not make the lobby (%d)") % result)
		return
	lobby_id = id
	steam.call("setLobbyData", id, "game", LOBBY_KEY)
	steam.call("setLobbyData", id, "name", Loc.t("%s's arena") % my_name)
	steam.call("setLobbyJoinable", id, true)
	var p = ClassDB.instantiate("SteamMultiplayerPeer")
	var err = p.call("create_host", 0)
	if err != OK:
		connection_failed.emit(Loc.t("Steam networking failed (%d)") % err)
		return
	multiplayer.multiplayer_peer = p
	transport = "steam"
	connected.emit()

func list_steam_lobbies() -> void:
	if not steam_ready:
		lobbies.emit([])
		return
	steam.call("addRequestLobbyListStringFilter", "game", LOBBY_KEY, 0)
	steam.call("requestLobbyList")

func _describe(list: Array) -> Array:
	var out := []
	for id in list:
		# (A stranger's lobby names itself: shown as a name, never as markup.)
		out.append({"id": int(id), "name": clean_name(steam.call("getLobbyData", id, "name"), 40), "players": int(steam.call("getNumLobbyMembers", id)), "mode": clean_name(steam.call("getLobbyData", id, "mode"), 20, "")})
	return out

func join_steam(id: int) -> void:
	if not steam_ready:
		connection_failed.emit("Steam is not running")
		return
	steam.call("joinLobby", id)

func _on_lobby_joined(id: int, _perm: int, _locked: bool, response: int) -> void:
	if response != 1:
		connection_failed.emit(Loc.t("Could not join that lobby (%d)") % response)
		return
	lobby_id = id
	var owner := int(steam.call("getLobbyOwner", id))
	if owner == steam_user:
		return # our own lobby
	var p = ClassDB.instantiate("SteamMultiplayerPeer")
	var err = p.call("create_client", owner, 0)
	if err != OK:
		connection_failed.emit(Loc.t("Steam networking failed (%d)") % err)
		return
	multiplayer.multiplayer_peer = p
	transport = "steam"

# ---------- ENet ----------

## A game joined by address is encrypted (DTLS) as Steam's sockets are: the host makes a key and a
## certificate for the session, the guests take it without a name to check it against (friends
## have no certificate authority between them): enough that nobody on the wire between them can
## read the game or the voices (user: friends playing together, completely safely).
const DTLS_NAME := "wrecksmith-host"
var dtls := true

func host_enet(port := PORT) -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, MAX_PLAYERS - 1)   # (the guests: the host is one of the eight)
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
	_banned.clear()
	_rate.clear()
	purse_credit.clear()
	ping_ms = -1.0
	host_rate = -1.0
	guest_pings.clear()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	transport = ""
	peers.clear()
	inputs.clear()
	_held.clear()

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
func _turn_away(id: int) -> void:
	send_to(id, "kicked", {})
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
	if transport == "steam" and mp != null and mp.has_method("get_steam64_from_peer_id"):
		return "steam:%d" % int(mp.call("get_steam64_from_peer_id", id))
	return ""

func _on_peer_disconnected(id: int) -> void:
	guest_pings.erase(id)
	if peers.erase(id):
		peer_left.emit(id)
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
	send_host("hello", {"name": my_name, "loadout": my_loadout, "kit": my_kit, "body": my_body})

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
var snap_rate := 0.0            # snapshot messages a second (guest)
var snap_gap := 0               # the longest wait between two snapshots in the last second (ms)
var _snaps := 0
var _snap_last := 0
var _gap := 0
var _meter_t := 0.0
var _frames0 := -1
var _wall0 := 0

func _meter(dt: float) -> void:
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
	if active() and not is_host():
		send_host("_ping", {"t": now, "p": ping_ms}, false)

func _count_in(type: String, data) -> void:
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

## A kit from the wire: only known throwables, sane counts.
static func sanitize_kit(k) -> Dictionary:
	var out := {}
	if k is Dictionary:
		for id in k:
			if Data.shop.get("throwables", {}).has(str(id)):
				out[str(id)] = clampi(int(num(k[id])), 0, 20)
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
const FROM_GUESTS := ["hello", "me", "input", "vc", "_ping", "purse_add", "doctor_done", "ff_kit", "ff_ready"]
var _rate := {}   # peer id -> [the second's start (ms), messages in it]

func _flooding(from: int) -> bool:
	var now := Time.get_ticks_msec()
	var r: Array = _rate.get(from, [now, 0])
	if now - int(r[0]) >= 1000:
		r = [now, 0]
	r[1] = int(r[1]) + 1
	_rate[from] = r
	return int(r[1]) > MSG_PER_S

## The party's purse is the host's own (his save): a guest puts into it no more than he has
## taken out of it (a sale fetches half a price; a cheaper piece of armour for a dearer one),
## what a fight's missions pay him, and a little for what he brought to sell. A game changed
## to send more than that adds nothing more.
const PURSE_JOIN := 400
const PURSE_PER_FIGHT := 400   # three missions at the best rank pay 360
var purse_credit := {}         # a guest ("ip:..."/"steam:...") -> denarii he may still put in

func _purse_key(id: int) -> String:
	var k := _peer_key(id)
	return k if k != "" else "id:%d" % id

## A guest spent `n` denarii of the purse (what it really lost): as much may come back.
func purse_spent(id: int, n: int) -> void:
	var k := _purse_key(id)
	purse_credit[k] = int(purse_credit.get(k, PURSE_JOIN)) + maxi(0, n)

## What of the `n` denarii a guest puts in the purse it takes.
func purse_take(id: int, n: int) -> int:
	var k := _purse_key(id)
	var c := int(purse_credit.get(k, PURSE_JOIN))
	var ok := clampi(n, 0, c)
	purse_credit[k] = c - ok
	return ok

## A fight is over: its missions may pay every guest.
func purse_fight_over() -> void:
	for id in peers:
		var k := _purse_key(int(id))
		purse_credit[k] = int(purse_credit.get(k, PURSE_JOIN)) + PURSE_PER_FIGHT

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
	if type == "kicked" and not is_host():
		leave_reason = "The host removed you from the room"
		leave()
		disconnected.emit()
		return
	# The meter's own round trip (never passed on to the game).
	if type == "_ping":
		if is_host() and data is Dictionary:
			guest_pings[from] = clampf(num(data.get("p", -1.0), -1.0), -1.0, 9999.0)
			send_to(from, "_pong", {"t": int(num(data.get("t", 0))), "s": snappedf(step_rate, 0.1)}, false)
		return
	if type == "_pong":
		if not is_host() and data is Dictionary:
			ping_ms = clampf(float(Time.get_ticks_msec() - int(num(data.get("t", 0)))), 0.0, 9999.0)
			host_rate = clampf(num(data.get("s", -1.0), -1.0), -1.0, 1000.0)
		return
	if is_host():
		match type:
			"hello":
				# Once a guest: a second hello would have walked a second fighter of his in.
				if data is Dictionary and not peers.has(from) and not _banned.has(_peer_key(from)):
					var info := {"name": clean_name(data.get("name", "Guest")), "loadout": sanitize_loadout(data.get("loadout")), "kit": sanitize_kit(data.get("kit")), "body": Body.sanitize(data.get("body"))}
					peers[from] = info
					peer_joined.emit(from, info)
				return
			"me":
				# A guest's gladiator as he is now (push_me), read as his hello was.
				if data is Dictionary and peers.has(from):
					peers[from].loadout = sanitize_loadout(data.get("loadout"))
					peers[from].kit = sanitize_kit(data.get("kit"))
					peers[from].body = Body.sanitize(data.get("body"))
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
