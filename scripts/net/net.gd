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

func set_lag(ms: int, loss_pct := 0.0) -> void:
	lag_ms = maxi(0, ms)
	jitter_ms = lag_ms / 4
	loss = clampf(loss_pct / 100.0, 0.0, 0.9)

func _process(_dt: float) -> void:
	if steam_ready:
		steam.run_callbacks()
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
		connection_failed.emit("Steam could not make the lobby (%d)" % result)
		return
	lobby_id = id
	steam.call("setLobbyData", id, "game", LOBBY_KEY)
	steam.call("setLobbyData", id, "name", "%s's arena" % my_name)
	steam.call("setLobbyJoinable", id, true)
	var p = ClassDB.instantiate("SteamMultiplayerPeer")
	var err = p.call("create_host", 0)
	if err != OK:
		connection_failed.emit("Steam networking failed (%d)" % err)
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
		out.append({"id": int(id), "name": String(steam.call("getLobbyData", id, "name")), "players": int(steam.call("getNumLobbyMembers", id)), "mode": String(steam.call("getLobbyData", id, "mode"))})
	return out

func join_steam(id: int) -> void:
	if not steam_ready:
		connection_failed.emit("Steam is not running")
		return
	steam.call("joinLobby", id)

func _on_lobby_joined(id: int, _perm: int, _locked: bool, response: int) -> void:
	if response != 1:
		connection_failed.emit("Could not join that lobby (%d)" % response)
		return
	lobby_id = id
	var owner := int(steam.call("getLobbyOwner", id))
	if owner == steam_user:
		return # our own lobby
	var p = ClassDB.instantiate("SteamMultiplayerPeer")
	var err = p.call("create_client", owner, 0)
	if err != OK:
		connection_failed.emit("Steam networking failed (%d)" % err)
		return
	multiplayer.multiplayer_peer = p
	transport = "steam"

# ---------- ENet ----------

func host_enet(port := PORT) -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = p
	transport = "enet"
	connected.emit()
	return OK

func join_enet(address: String, port := PORT) -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = p
	transport = "enet"
	return OK

# ---------- Both ----------

func active() -> bool:
	return transport != "" and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func is_host() -> bool:
	return transport != "" and multiplayer.is_server()

func my_id() -> int:
	return multiplayer.get_unique_id() if transport != "" else 1

func leave() -> void:
	if steam_ready and lobby_id:
		steam.call("leaveLobby", lobby_id)
	lobby_id = 0
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
	# The guest introduces itself with "hello". A guest whose game closes without a word is
	# missed within seconds, not ENet's half a minute: his fighter leaves the yard with him.
	if transport == "enet" and is_host() and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var pp: ENetPacketPeer = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(id)
		if pp:
			pp.set_timeout(0, 4000, 8000)

func _on_peer_disconnected(id: int) -> void:
	if peers.erase(id):
		peer_left.emit(id)
	inputs.erase(id)

func _on_connected() -> void:
	connected.emit()
	send_host("hello", {"name": my_name, "loadout": my_loadout, "kit": my_kit, "body": my_body})

func send_all(type: String, data, reliable := true) -> void:
	if not active():
		return
	if reliable:
		_msg.rpc(type, data)
	else:
		_umsg.rpc(type, data)

func send_to(id: int, type: String, data, reliable := true) -> void:
	if not active():
		return
	if reliable:
		_msg.rpc_id(id, type, data)
	else:
		_umsg.rpc_id(id, type, data)

func send_host(type: String, data, reliable := true) -> void:
	send_to(1, type, data, reliable)

## A kit from the wire: only known throwables, sane counts.
static func sanitize_kit(k) -> Dictionary:
	var out := {}
	if k is Dictionary:
		for id in k:
			if Data.shop.get("throwables", {}).has(str(id)):
				out[str(id)] = clampi(int(k[id]), 0, 20)
	return out

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
	if not _hold(type, data, from, true):
		_receive(type, data, from)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _umsg(type: String, data) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not _hold(type, data, from, false):
		_receive(type, data, from)

func _receive(type: String, data, from: int) -> void:
	# Only the host may tell guests what happens; guests may only say hello and send input.
	if not is_host() and from != 1:
		return
	if is_host():
		match type:
			"hello":
				if data is Dictionary:
					var info := {"name": String(data.get("name", "Guest")).left(24), "loadout": data.get("loadout", {}) if data.get("loadout") is Dictionary else {}, "kit": sanitize_kit(data.get("kit")), "body": Body.sanitize(data.get("body"))}
					peers[from] = info
					peer_joined.emit(from, info)
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
