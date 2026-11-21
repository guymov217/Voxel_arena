extends Node
## The delay a guest feels, host side (`-- --probe net_lat_host`, with one `-- --probe net_lat_guest`): a yard with the guest in it,
## both games held to a frame rate as a game with a window is (NET_FPS, 60; the load is the yard's own: its keepers and fighters).
## The guest presses forward and times how long his own man takes to move on his own screen; he prints what he found, the host
## only keeps the room going. NET_PORT, NET_SECONDS (how long it may run, 90).

var m: Match

func _ready() -> void:
	Engine.max_fps = int(OS.get_environment("NET_FPS")) if OS.get_environment("NET_FPS") != "" else 60
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17781
	var secs := int(OS.get_environment("NET_SECONDS")) if OS.get_environment("NET_SECONDS") != "" else 90
	print("HOST listen ", Net.host_enet(port))
	Net.my_name = "Host"
	var t0 := Time.get_ticks_msec()
	while Net.peers.is_empty() and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	var peers := []
	for id in Net.peers:
		peers.append({"id": id, "name": Net.peers[id].name, "loadout": {"main": "axe"}})
	Net.send_all("start", {"mode": "yard"})
	m = Match.new()
	add_child(m)
	m.setup({"mode": "yard", "role": "host", "headless": true, "name": "Host", "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": peers})
	print("HOST yard up with ", peers.size(), " guest; entities ", m.entities.size())
	var t1 := Time.get_ticks_msec()
	var left := false
	var gid: int = Net.peers.keys()[0] if not Net.peers.is_empty() else -1
	var ge = null
	for e in m.entities:
		if e.kind == "remote" and int(e.peer) == gid:
			ge = e
	# What the host itself sees of each press: the step its input was in, and the step his man had moved 2 cm (his answer to it).
	var lats := []
	var hand_lats := []
	var h_in := -1.0
	var h_p0 := Vector3.ZERO
	var t_in := -1.0
	var p0 := Vector3.ZERO
	while Time.get_ticks_msec() - t1 < secs * 1000:
		await get_tree().physics_frame
		if ge != null and is_instance_valid(ge.f):
			# (NET_HAND on the guest: the weapon of his right hand 3 cm on after his hand's mark went across the pane)
			var wr = ge.f.weapons.get("R")
			var mkx := float(((Net.inputs.get(gid, {}) as Dictionary).get("main", {"x": 0.0}) as Dictionary).get("x", 0.0))
			if wr != null and is_instance_valid(wr):
				if h_in == -1.0:
					if mkx > 0.5:
						h_in = Time.get_ticks_usec()
						h_p0 = wr.global_position
				elif h_in == -2.0:
					if mkx < 0.3:
						h_in = -1.0
				elif (wr.global_position - h_p0).length() > 0.03:
					hand_lats.append((Time.get_ticks_usec() - h_in) / 1000.0)
					h_in = -2.0
			var mz := float((Net.inputs.get(gid, {}) as Dictionary).get("mz", 0.0))
			var pos: Vector3 = ge.f.torso.global_position
			if t_in == -1.0:
				if mz > 0.5:
					t_in = Time.get_ticks_usec()
					p0 = pos
			elif t_in == -2.0:
				if mz < 0.5:
					t_in = -1.0
			elif Vector2(pos.x - p0.x, pos.z - p0.z).length() > 0.02:
				lats.append((Time.get_ticks_usec() - t_in) / 1000.0)
				print("MOVED %d %.6f" % [lats.size() - 1, Time.get_unix_time_from_system()])
				t_in = -2.0
			elif mz < 0.5:
				t_in = -1.0   # (let go before he moved: not counted)
		if Net.peers.is_empty() and Time.get_ticks_msec() - t1 > 3000:
			left = true
			break
	lats.sort()
	if not lats.is_empty():
		var sum := 0.0
		for v in lats:
			sum += v
		print("HOST his input in, his man 2 cm on: n=%d min %.0f median %.0f mean %.0f worst %.0f ms" % [lats.size(), lats[0], lats[lats.size() / 2], sum / lats.size(), lats[-1]])
	hand_lats.sort()
	if not hand_lats.is_empty():
		print("HOST his hand's mark in, his weapon 3 cm on: n=%d min %.0f median %.0f worst %.0f ms" % [hand_lats.size(), hand_lats[0], hand_lats[hand_lats.size() / 2], hand_lats[-1]])
	print("HOST done (the guest ", "left" if left else "was still here", ")")
	Net.send_all("bye", {})
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)
