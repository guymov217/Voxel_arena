extends Object
## Steam on one machine, for the two-process network test (tests/net_steam_host.gd and net_steam_guest.gd).
##
## The folder STEAM_FAKE_DIR plays Valve's servers: each lobby is a file in it, each member a marker beside it,
## and what the two games call and are called back with is what GodotSteam gives (the lobby made and its data,
## the list and its filters, the join and its answer, the rich presence, the invite window). The game's own code
## is what is under test: the room's lobby and its build tag, the list and what it asks for, the join and the
## hand-over of the connection to the multiplayer API, the hello, and then the whole of a bout.
##
## Only the bytes between the two games go another way than Steam's relay: over ENet on localhost, through
## FakePeer, which has the two calls of SteamMultiplayerPeer (create_host, create_client). What only Steam can
## show (Valve's own calls, the relay, a friend's invite arriving) is looked at on a PC with Steam:
## `-- --steam-check` and docs/MULTIPLAYER_TEST.md.

signal lobby_created(result: int, lobby: int)
signal lobby_joined(lobby: int, permissions: int, locked: bool, response: int)
signal lobby_match_list(lobbies: Array)
signal join_requested(lobby: int, friend: int)

var dir := ""
var user := 0
var persona := ""
var port := 0
var presence := {}            # what the game set as rich presence
var overlay_invite := 0       # the lobby the invite window was opened for
var in_lobby := 0             # the lobby this one is in
var _filters := {}
var _slots := 0
var _due: Array = []          # callbacks Steam hands over at the next run_callbacks: [signal, [args]]


## SteamMultiplayerPeer's calls over ENet on localhost: a multiplayer peer of its own (as the extension's is, not an
## ENet peer: the game's ENet-only code stays out of this path as it does with Steam), which hands everything on to an
## ENet peer inside. The game calls create_host(0) to open the room and create_client(the host's steam id, 0) to join
## one; the port is the two processes' shared one.
class FakePeer extends MultiplayerPeerExtension:
	var port := 0
	var _enet := ENetMultiplayerPeer.new()

	func create_host(_virtual_port: int) -> int:
		var err := _enet.create_server(port, 7)
		_wire()
		return err

	func create_client(_host_steam_id: int, _virtual_port: int) -> int:
		var err := _enet.create_client("127.0.0.1", port)
		_wire()
		return err

	var _on_connected := Callable()
	var _on_disconnected := Callable()

	func _wire() -> void:
		_on_connected = func(id: int):
			var pp := _enet.get_peer(id)
			if pp:
				pp.throttle_configure(5000, 2, 0)      # (Steam's line sheds nothing for being slow to answer)
			peer_connected.emit(id)
		_on_disconnected = func(id: int): peer_disconnected.emit(id)
		_enet.peer_connected.connect(_on_connected)
		_enet.peer_disconnected.connect(_on_disconnected)

	## Who a peer is, as SteamMultiplayerPeer tells it (the host's turned-away list is kept by this).
	func get_steam64_from_peer_id(id: int) -> int:
		var pp := _enet.get_peer(id)
		return 76561190000000000 + (hash(pp.get_remote_address()) & 0xffffff) if pp else 0

	func _get_packet_script() -> PackedByteArray:
		return _enet.get_packet()
	func _put_packet_script(buffer: PackedByteArray) -> Error:
		return _enet.put_packet(buffer)
	func _get_available_packet_count() -> int:
		return _enet.get_available_packet_count()
	func _get_max_packet_size() -> int:
		return 1 << 24
	func _get_packet_channel() -> int:
		return _enet.get_packet_channel()
	func _get_packet_mode() -> MultiplayerPeer.TransferMode:
		return _enet.get_packet_mode()
	func _set_transfer_channel(channel: int) -> void:
		_enet.transfer_channel = channel
	func _get_transfer_channel() -> int:
		return _enet.transfer_channel
	func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
		_enet.transfer_mode = mode
	func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
		return _enet.transfer_mode
	func _set_target_peer(peer: int) -> void:
		_enet.set_target_peer(peer)
	func _get_packet_peer() -> int:
		return _enet.get_packet_peer()
	func _is_server() -> bool:
		return _enet.is_server()
	func _poll() -> void:
		_enet.poll()
	func _close() -> void:
		_enet.close()
		# (The two connections held this peer and this peer held them: let go, or a test that makes one leaks it.)
		if _on_connected.is_valid() and _enet.peer_connected.is_connected(_on_connected):
			_enet.peer_connected.disconnect(_on_connected)
		if _on_disconnected.is_valid() and _enet.peer_disconnected.is_connected(_on_disconnected):
			_enet.peer_disconnected.disconnect(_on_disconnected)
		_on_connected = Callable()
		_on_disconnected = Callable()
	func _disconnect_peer(peer: int, force: bool) -> void:
		_enet.disconnect_peer(peer, force)
	func _get_unique_id() -> int:
		return _enet.get_unique_id()
	func _set_refuse_new_connections(enable: bool) -> void:
		_enet.refuse_new_connections = enable
	func _is_refusing_new_connections() -> bool:
		return _enet.refuse_new_connections
	func _is_server_relay_supported() -> bool:
		return false
	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return _enet.get_connection_status()


func _init(folder: String, steam_id: int, name_: String, udp_port: int) -> void:
	dir = folder
	user = steam_id
	persona = name_
	port = udp_port
	DirAccess.make_dir_recursive_absolute(dir)


# ---- start and the callbacks' pump

func steamInitEx(_app_id := 0, _embed_callbacks := false) -> Dictionary:
	return {"status": 0, "verbal": "Steamworks active"}

func getSteamID() -> int:
	return user

func getPersonaName() -> String:
	return persona

func initRelayNetworkAccess() -> void:
	pass

func run_callbacks() -> void:
	var due := _due
	_due = []
	for d in due:
		callv("emit_signal", [d[0]] + d[1])


# ---- lobbies

func _path(id: int, ext := "json") -> String:
	return "%s/lobby_%d.%s" % [dir, id, ext]

func _read(id: int) -> Dictionary:
	var f := FileAccess.open(_path(id), FileAccess.READ)
	if f == null:
		return {}
	var j = JSON.parse_string(f.get_as_text())
	return j if j is Dictionary else {}

func _write(id: int, d: Dictionary) -> void:
	var tmp := _path(id, "tmp%d" % user)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	DirAccess.rename_absolute(tmp, _path(id))      # whole or not at all: the other process never reads half a file

func _member(id: int, who: int) -> String:
	return "%s/lobby_%d.m%d" % [dir, id, who]

func createLobby(type: int, max_members: int) -> void:
	var id := 1000000000000 + randi() % 900000000000
	# (A steam id is 17 digits, more than a JSON number keeps exactly: the file holds it as text.)
	_write(id, {"id": id, "owner": str(user), "type": type, "max": max_members, "joinable": false, "data": {}})
	FileAccess.open(_member(id, user), FileAccess.WRITE).close()
	in_lobby = id
	_due.append(["lobby_created", [1, id]])

func setLobbyData(id: int, key: String, value: String) -> bool:
	var d := _read(int(id))
	if d.is_empty() or String(d.owner) != str(user):
		return false
	d.data[key] = value
	_write(int(id), d)
	return true

func getLobbyData(id: int, key: String) -> String:
	return String((_read(int(id)).get("data", {}) as Dictionary).get(key, ""))

func setLobbyJoinable(id: int, on: bool) -> bool:
	var d := _read(int(id))
	if d.is_empty():
		return false
	d.joinable = on
	_write(int(id), d)
	return true

func getLobbyOwner(id: int) -> int:
	return int(String(_read(int(id)).get("owner", "0")))

func getNumLobbyMembers(id: int) -> int:
	var n := 0
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("lobby_%d.m" % int(id)):
			n += 1
	return n

func joinLobby(id: int) -> void:
	var d := _read(int(id))
	var ok := not d.is_empty() and bool(d.get("joinable", false)) and getNumLobbyMembers(id) < int(d.get("max", 0))
	if ok:
		FileAccess.open(_member(int(id), user), FileAccess.WRITE).close()
		in_lobby = int(id)
	# (response 1: entered; 2: the lobby does not exist; 5: full: the codes of EChatRoomEnterResponse)
	_due.append(["lobby_joined", [int(id), 0, false, 1 if ok else 2]])

func leaveLobby(id: int) -> void:
	var d := _read(int(id))
	DirAccess.remove_absolute(_member(int(id), user))
	if not d.is_empty() and String(d.owner) == str(user):      # (the room's owner leaving closes it here)
		DirAccess.remove_absolute(_path(int(id)))
		for f in DirAccess.get_files_at(dir):
			if f.begins_with("lobby_%d.m" % int(id)):
				DirAccess.remove_absolute(dir + "/" + f)
	if in_lobby == int(id):
		in_lobby = 0

func addRequestLobbyListStringFilter(key: String, value: String, comparison: int) -> void:
	_filters[key] = [value, comparison]

func addRequestLobbyListDistanceFilter(_distance: int) -> void:
	pass

func addRequestLobbyListFilterSlotsAvailable(slots: int) -> void:
	_slots = slots

func addRequestLobbyListResultCountFilter(_count: int) -> void:
	pass

func requestLobbyList() -> void:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if not (f.begins_with("lobby_") and f.ends_with(".json")):
			continue
		var id := int(f.trim_prefix("lobby_").trim_suffix(".json"))
		var d := _read(id)
		if d.is_empty() or not bool(d.get("joinable", false)):
			continue
		var fits := true
		for k in _filters:
			if (d.data as Dictionary).get(k, "") != _filters[k][0]:
				fits = false
		if _slots > 0 and getNumLobbyMembers(id) + _slots > int(d.get("max", 0)):
			fits = false
		if fits:
			out.append(id)
	_filters = {}
	_slots = 0
	_due.append(["lobby_match_list", [out]])


# ---- what friends see

func setRichPresence(key: String, value: String) -> bool:
	presence[key] = value
	return true

func clearRichPresence() -> void:
	presence.clear()

func activateGameOverlayInviteDialog(id: int) -> void:
	overlay_invite = id


## Puts this fake in Steam's place in the game that is running (tests/net_steam_host.gd and net_steam_guest.gd): it is
## the "Steam" singleton, SteamMultiplayerPeer is FakePeer, and Net starts Steam over again.
static func install(folder: String, steam_id: int, name_: String, udp_port: int) -> Object:
	var fake = load("res://tests/steam_loopback.gd").new(folder, steam_id, name_, udp_port)
	if Engine.has_singleton("Steam"):
		Engine.unregister_singleton("Steam")
	Engine.register_singleton("Steam", fake)
	Net.steam_peer_factory = func():
		var p := FakePeer.new()
		p.port = udp_port
		return p
	Net.steam = null
	Net.steam_ready = false
	Net._init_steam()
	return fake
