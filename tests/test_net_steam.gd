extends Node
## The Steam side of multiplayer (scripts/net/net.gd), run against a stand-in for GodotSteam: the test
## machine has no Steam client. It holds what Valve's lobby calls are asked and in what order, what a room
## carries (its build, its name, the presence friends see), that a room of another build is refused on
## either side, that a friend's invite leaves the room one is in, and that a build without the multiplayer
## extension says so instead of failing. (What the real library answers is for `-- --steam-check`.)

var t

## The part of GodotSteam the game calls, answering as a lobby server would.
class FakeSteam extends Object:
	signal lobby_created(result, id)
	signal lobby_joined(id, perm, locked, response)
	signal lobby_match_list(list)
	signal join_requested(lobby, friend)
	var calls := []
	var data := {}
	var owner := {}
	var rich := {}
	var next_lobby := 1001
	func steamInitEx(app_id := 0, _embed := false) -> Dictionary:
		calls.append(["steamInitEx", app_id])
		return {"status": 0, "verbal": "ok"}
	func getSteamID() -> int:
		return 7001
	func getPersonaName() -> String:
		return "Tester"
	func initRelayNetworkAccess() -> void:
		calls.append(["initRelayNetworkAccess"])
	func run_callbacks() -> void:
		pass
	func createLobby(kind, slots) -> void:
		calls.append(["createLobby", kind, slots])
		var id := next_lobby
		next_lobby += 1
		data[id] = {}
		owner[id] = 7001
		lobby_created.emit(1, id)
	func setLobbyData(id, k, v) -> bool:
		data[id][k] = v
		return true
	func getLobbyData(id, k) -> String:
		return str(data.get(id, {}).get(k, ""))
	func setLobbyJoinable(_id, _on) -> bool:
		return true
	func getLobbyOwner(id) -> int:
		return int(owner.get(id, 0))
	func getNumLobbyMembers(_id) -> int:
		return 3
	func leaveLobby(id) -> void:
		calls.append(["leaveLobby", id])
	func joinLobby(id) -> void:
		calls.append(["joinLobby", id])
		lobby_joined.emit(id, 0, false, 1)
	func addRequestLobbyListStringFilter(k, v, cmp) -> void:
		calls.append(["filter", k, v, cmp])
	func addRequestLobbyListDistanceFilter(d) -> void:
		calls.append(["distance", d])
	func addRequestLobbyListFilterSlotsAvailable(n) -> void:
		calls.append(["slots", n])
	func addRequestLobbyListResultCountFilter(n) -> void:
		calls.append(["count", n])
	func requestLobbyList() -> void:
		calls.append(["requestLobbyList"])
	func setRichPresence(k, v) -> bool:
		rich[k] = v
		return true
	func clearRichPresence() -> void:
		rich.clear()
	func activateGameOverlayInviteDialog(id) -> void:
		calls.append(["invite", id])

## The Steam transport's peer, offline: it only says whether it was made as a host or as a client.
class FakePeer extends OfflineMultiplayerPeer:
	var made := ""
	func create_host(_vport) -> int:
		made = "host"
		return OK
	func create_client(host_id, _vport) -> int:
		made = "client:%d" % host_id
		return OK

## A multiplayer extension that can open a room but not join one (another extension's API, or an old one).
class PartialPeer extends OfflineMultiplayerPeer:
	func create_host(_vport) -> int:
		return OK

var _name := ""

func _steam(peer_works := true) -> FakeSteam:
	Net.leave()
	_name = Net.my_name
	var fake := FakeSteam.new()
	Engine.register_singleton("Steam", fake)
	Net.steam = null
	Net.steam_ready = false
	Net.steam_problem = ""
	if peer_works:
		Net.steam_peer_factory = func(): return FakePeer.new()
	Net._init_steam()
	return fake

func _done(fake: FakeSteam) -> void:
	Net.leave()
	Net.steam_peer_factory = Callable()
	Net.steam = null
	Net.steam_ready = false
	Net.steam_problem = ""
	Net.lobby_id = 0
	Net.transport = ""
	Net.my_name = _name
	Engine.unregister_singleton("Steam")
	fake.free()

func _called(fake: FakeSteam, what: Array) -> bool:
	return fake.calls.has(what)

func test_a_room_is_made_with_its_build_its_name_and_the_friends_join_string() -> void:
	var fake := _steam()
	t.check(Net.steam_ready and Net.steam_available(), "Steam is up")
	t.check(_called(fake, ["initRelayNetworkAccess"]), "the relay network is asked for at the start, as Valve advises")
	Net.host_steam(true)
	t.check(_called(fake, ["createLobby", 2, 8]), "a public lobby for eight")
	var id := 1001
	t.eq(Net.lobby_id, id, "the room is that lobby")
	t.eq(Net.transport, "steam", "over Steam")
	t.eq(fake.data[id].game, Net.LOBBY_KEY, "tagged as this game's")
	t.eq(fake.data[id].ver, Net.build_tag(), "and with the host's build, so a friend on another one is told before he joins")
	t.eq(fake.data[id].name, "Tester's arena", "named for its host")
	t.eq(fake.rich.get("connect", ""), "+connect_lobby %d" % id, "friends get a Join Game that starts this game for the room")
	t.eq(fake.rich.get("steam_player_group", ""), str(id), "and see the player in that group")
	Net.invite_friends()
	t.check(_called(fake, ["invite", id]), "the invite button opens Steam's invite window for the room")
	Net.leave()
	t.check(_called(fake, ["leaveLobby", id]), "leaving leaves the lobby")
	t.check(fake.rich.is_empty(), "and the friends' Join Game goes with it")
	Net.host_steam(false)
	t.check(_called(fake, ["createLobby", 1, 8]), "friends only is Steam's friends-only lobby")
	_done(fake)

func test_the_app_id_goes_by_the_environment_and_init_takes_no_guesses() -> void:
	var had_app := OS.get_environment("SteamAppId")
	var had_game := OS.get_environment("SteamGameId")
	OS.unset_environment("SteamAppId")
	OS.unset_environment("SteamGameId")
	var fake := _steam()
	t.check(_called(fake, ["steamInitEx", 0]), "the library's init is called with no id of its own (no argument order to get wrong)")
	t.eq(OS.get_environment("SteamAppId"), "480", "a game started by hand is Valve's test app")
	t.eq(OS.get_environment("SteamGameId"), "480", "under both names")
	_done(fake)
	OS.set_environment("SteamAppId", "123456")
	OS.unset_environment("SteamGameId")
	fake = _steam()
	t.eq(OS.get_environment("SteamAppId"), "123456", "an id Steam (or the player) has set is kept")
	t.eq(OS.get_environment("SteamGameId"), "123456", "and the other name follows it")
	_done(fake)
	for pair in [["SteamAppId", had_app], ["SteamGameId", had_game]]:
		if pair[1] == "":
			OS.unset_environment(pair[0])
		else:
			OS.set_environment(pair[0], pair[1])

func test_the_older_init_is_read_by_its_own_answer() -> void:
	# GodotSteam's older steamInit answers {status: 1} when it worked (steamInitEx {status: 0}).
	var old_steam := OldSteam.new()
	Net.leave()
	Engine.register_singleton("Steam", old_steam)
	Net.steam = null
	Net.steam_ready = false
	Net.steam_problem = ""
	Net.steam_peer_factory = func(): return FakePeer.new()
	Net._init_steam()
	t.check(Net.steam_ready, "an older GodotSteam that answers 1 is up")
	Net.steam = null
	Net.steam_ready = false
	Net.steam_peer_factory = Callable()
	Engine.unregister_singleton("Steam")
	old_steam.free()

## A GodotSteam from before steamInitEx: steamInit only, its answer 1 for "it worked".
class OldSteam extends Object:
	signal lobby_created(result, id)
	signal lobby_joined(id, perm, locked, response)
	signal lobby_match_list(list)
	func steamInit() -> Dictionary:
		return {"status": 1, "verbal": "Steamworks active"}
	func getSteamID() -> int:
		return 7002
	func getPersonaName() -> String:
		return "Old"
	func run_callbacks() -> void:
		pass

func test_the_list_asks_for_this_build_anywhere_with_a_place_free() -> void:
	var fake := _steam()
	Net.list_steam_lobbies()
	for want in [["filter", "game", Net.LOBBY_KEY, 0], ["filter", "ver", Net.build_tag(), 0], ["distance", 3], ["slots", 1], ["count", 50], ["requestLobbyList"]]:
		t.check(_called(fake, want), "asks %s" % str(want))
	t.eq(fake.calls.back(), ["requestLobbyList"], "the filters first, then the request")
	_done(fake)

func test_joining_a_room_of_this_build_makes_a_client_to_its_owner() -> void:
	var fake := _steam()
	fake.data[2001] = {"ver": Net.build_tag(), "name": "Friend's arena"}
	fake.owner[2001] = 9009
	Net.join_steam(2001)
	t.eq(Net.transport, "steam", "joined")
	t.eq(Net.lobby_id, 2001, "that lobby")
	t.eq((Net.multiplayer.multiplayer_peer as FakePeer).made, "client:9009", "a client to the lobby's owner")
	t.eq(fake.rich.get("connect", ""), "+connect_lobby 2001", "and friends can join him there")
	_done(fake)

func test_a_room_of_another_build_is_refused_and_left() -> void:
	var fake := _steam()
	fake.data[2002] = {"ver": "0.0.9.1.full"}
	fake.owner[2002] = 9009
	var told := []
	var on_fail := func(why): told.append(why)
	Net.connection_failed.connect(on_fail)
	Net.join_steam(2002)
	Net.connection_failed.disconnect(on_fail)
	t.eq(told.size(), 1, "the player is told")
	t.check(String(told[0]).contains("another version") and String(told[0]).contains("0.0.9.1.full"), "which: %s" % str(told))
	t.check(_called(fake, ["leaveLobby", 2002]), "the lobby is left again")
	t.eq(Net.transport, "", "no connection made")
	t.eq(Net.lobby_id, 0, "no room")
	_done(fake)

func test_a_lobby_without_a_build_tag_is_another_version_too() -> void:
	var fake := _steam()
	fake.data[2003] = {}
	fake.owner[2003] = 9009
	var told := []
	var on_fail := func(why): told.append(why)
	Net.connection_failed.connect(on_fail)
	Net.join_steam(2003)
	Net.connection_failed.disconnect(on_fail)
	t.check(told.size() == 1 and String(told[0]).contains("another version"), "an older game's lobby: told, not joined (%s)" % str(told))
	_done(fake)

func test_a_friends_invite_while_in_a_room_leaves_that_room_first() -> void:
	var fake := _steam()
	Net.host_steam(true)
	var mine := Net.lobby_id
	fake.data[2004] = {"ver": Net.build_tag()}
	fake.owner[2004] = 9009
	var left := [0]
	var on_gone := func(): left[0] += 1
	Net.disconnected.connect(on_gone)
	fake.join_requested.emit(2004, 1234)   # Steam's "Join Game" in the friends list or the overlay
	Net.disconnected.disconnect(on_gone)
	t.check(_called(fake, ["leaveLobby", mine]), "the room one was in is left")
	t.eq(left[0], 1, "the game is told it left (the match ends, the screen changes)")
	t.eq(Net.lobby_id, 2004, "and the friend's room is joined")
	t.eq((Net.multiplayer.multiplayer_peer as FakePeer).made, "client:9009", "as a guest")
	var again := fake.calls.size()
	fake.join_requested.emit(2004, 1234)
	t.eq(fake.calls.size(), again, "the same invite twice joins nothing twice")
	_done(fake)

func test_a_build_without_the_multiplayer_extension_says_so_and_does_not_fail() -> void:
	var fake := _steam(false)
	t.check(Net.steam_ready and not Net.steam_available(), "Steam runs, but its lobbies are off")
	t.check(Net.steam_problem.begins_with("Steam is running"), "with the reason: %s" % Net.steam_problem)
	var told := []
	var on_fail := func(why): told.append(why)
	Net.connection_failed.connect(on_fail)
	Net.host_steam(true)
	Net.join_steam(2005)
	Net.list_steam_lobbies()
	Net.connection_failed.disconnect(on_fail)
	t.eq(told.size(), 2, "hosting and joining are each answered")
	t.check(fake.calls.filter(func(c): return c[0] == "createLobby" or c[0] == "joinLobby").is_empty(), "no lobby is made or joined")
	_done(fake)

func test_a_peer_that_cannot_be_made_leaves_the_lobby_again() -> void:
	var fake := _steam()
	Net.steam_peer_factory = func(): return null
	var told := []
	var on_fail := func(why): told.append(why)
	Net.connection_failed.connect(on_fail)
	Net.host_steam(true)
	Net.connection_failed.disconnect(on_fail)
	t.eq(told.size(), 1, "told")
	t.check(_called(fake, ["leaveLobby", 1001]), "the lobby just made is closed, not left open with nobody serving it")
	t.eq(Net.lobby_id, 0, "no room")
	t.eq(Net.transport, "", "no transport")
	_done(fake)

func test_a_friends_invite_that_started_the_game_is_read_from_its_command_line() -> void:
	t.eq(Net.lobby_from_args(PackedStringArray(["+connect_lobby", "109775241234567890"])), 109775241234567890, "the lobby id after +connect_lobby")
	t.eq(Net.lobby_from_args(PackedStringArray(["--windowed", "+connect_lobby", "77", "--x"])), 77, "among other arguments")
	t.eq(Net.lobby_from_args(PackedStringArray(["--windowed"])), 0, "none")
	t.eq(Net.lobby_from_args(PackedStringArray(["+connect_lobby"])), 0, "no id")
	t.eq(Net.lobby_from_args(PackedStringArray(["+connect_lobby", "abc"])), 0, "not an id")
	Net.launch_lobby = 555
	t.eq(Net.take_launch_lobby(), 555, "taken once")
	t.eq(Net.take_launch_lobby(), 0, "and not again")

func test_a_guest_of_another_build_is_turned_away_and_one_of_this_build_is_not() -> void:
	var joined := []
	var on_join := func(id, _info): joined.append(id)
	Net.peer_joined.connect(on_join)
	Net.transport = "test"   # (the offline peer: this game is id 1, the host)
	Net._receive("hello", {"name": "Old", "ver": "0.0.1.1.full", "loadout": {"main": "axe"}}, 11)
	Net._receive("hello", {"name": "Older", "loadout": {"main": "axe"}}, 12)
	Net._receive("hello", {"name": "Demo", "ver": Net.build_tag().replace("full", "demo"), "loadout": {"main": "axe"}}, 13)
	t.eq(joined, [], "another version, no version, or the other edition: none comes in")
	Net._receive("hello", {"name": "Same", "ver": Net.build_tag(), "loadout": {"main": "axe"}}, 14)
	t.eq(joined, [14], "the same build does")
	Net.peer_joined.disconnect(on_join)
	Net.peers.erase(14)
	Net.transport = ""

func test_a_guest_turned_away_for_his_version_is_told_which() -> void:
	var gone := [0]
	var on_gone := func(): gone[0] += 1
	Net.disconnected.connect(on_gone)
	Net.leave_reason = ""
	Net._receive("kicked", {"why": "version", "ver": "9.9.9.1.full"}, 1)   # (a guest's view: no transport)
	Net.disconnected.disconnect(on_gone)
	t.eq(gone[0], 1, "he is out of the room")
	t.check(Net.leave_reason.contains("another version") and Net.leave_reason.contains("9.9.9.1.full"), "told why: %s" % Net.leave_reason)
	Net.leave_reason = ""
	Net._receive("kicked", {}, 1)
	t.eq(Net.leave_reason, "The host removed you from the room", "a plain removal reads as it did")
	Net.leave_reason = ""

func test_the_steam_report_says_what_is_there_and_what_is_not() -> void:
	var fake := _steam()
	var text := "\n".join(Net.steam_report())
	t.check(text.contains("signed in as Tester") and text.contains("Steam multiplayer: READY"), "ready: %s" % text.substr(0, 200))
	t.check(not text.contains("MISSING"), "every call it needs is there")
	t.check(text.contains("Multiplayer extension (SteamMultiplayerPeer): found") and text.contains("peer call create_host: yes") and text.contains("peer call create_client: yes"), "the peer's two calls are there: %s" % text.substr(0, 400))
	_done(fake)
	var bare := "\n".join(Net.steam_report())
	t.check(bare.contains("NOT FOUND") and bare.contains("not available"), "without Steam: says so (%s)" % bare.replace("\n", " | ").substr(0, 160))

func test_the_steam_report_names_a_peer_that_lacks_a_call_the_game_makes() -> void:
	var fake := _steam()
	Net.steam_peer_factory = func(): return PartialPeer.new()
	var text := "\n".join(Net.steam_report())
	t.check(text.contains("peer call create_host: yes") and text.contains("peer call create_client: MISSING"), "says which one: %s" % text.substr(0, 400))
	t.check(text.contains("peer call get_steam64_from_peer_id: no (optional"), "the kick's call is optional and says so")
	_done(fake)
