extends "res://tests/net_host.gd"
## The two-process network test over the Steam path (`-- --probe net_steam_host`, with net_steam_guest on the other
## side): the same bout as net_host, but the room is a Steam lobby: Net.host_steam, its data, its rich presence, the
## hello with the build tag and everything after it. Steam itself is tests/steam_loopback.gd (a folder shared by the two
## processes, STEAM_FAKE_DIR); the bytes go over ENet on localhost. What it does not show: Valve's real calls and relay.

const Loop := preload("res://tests/steam_loopback.gd")
var fake: Object

func _open(port: int) -> Variant:
	fake = Loop.install(OS.get_environment("STEAM_FAKE_DIR"), 76561198000000001, "Host", port)
	if not Net.steam_available():
		return "NO STEAM: %s" % Net.steam_problem
	Net.host_steam(true)
	var t0 := Time.get_ticks_msec()
	while Net.transport == "" and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	var l: int = Net.lobby_id
	print("HOST lobby ", l, " game ", fake.getLobbyData(l, "game"), " ver ", fake.getLobbyData(l, "ver"), " name ", fake.getLobbyData(l, "name"),
		" owner ", fake.getLobbyOwner(l) == 76561198000000001, " presence ", fake.presence.get("connect", ""))
	return "steam lobby " + ("ok" if Net.transport == "steam" and l != 0 else "FAILED")
