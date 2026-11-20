extends "res://tests/net_guest.gd"
## The guest's side of net_steam_host: finds the room in Steam's lobby list (the game asks for its own lobbies of this
## build), and joins it. After a kick (KICK=1) it finds the room again and knocks again.

const Loop := preload("res://tests/steam_loopback.gd")
var fake: Object

func _join(port: int) -> Variant:
	if fake == null:
		fake = Loop.install(OS.get_environment("STEAM_FAKE_DIR"), 76561198000000002, "Guest", port)
	if not Net.steam_available():
		return "NO STEAM: %s" % Net.steam_problem
	var found := []
	var on := func(list: Array): found.assign(list)
	Net.lobbies.connect(on)
	var t0 := Time.get_ticks_msec()
	while found.is_empty() and Time.get_ticks_msec() - t0 < 15000:
		Net.list_steam_lobbies()
		await get_tree().create_timer(0.4).timeout
	Net.lobbies.disconnect(on)
	if found.is_empty():
		return "no lobby in the list"
	print("GUEST lobby list ", found)
	Net.join_steam(int(found[0].id))
	return "joining lobby %d (%s, %d player)" % [found[0].id, found[0].name, found[0].players]
