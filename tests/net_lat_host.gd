extends Node
## The delay a guest feels, host side (`-- --probe net_lat_host`, with one `-- --probe net_lat_guest`): a yard with the guest in it,
## both games held to a frame rate as a game with a window is (NET_FPS, 60; the load is the yard's own: its keepers and fighters).
## The guest presses forward and times how long his own man takes to move on his own screen; he prints what he found, the host
## only keeps the room going. NET_PORT, NET_SECONDS (how long it may run, 90).

var m: Match
var _tgt_on := false

func _ready() -> void:
	# NET_FAIR: the yard stands in for a fight of people against each other, and in a fight no man is let sleep (Match._human_idle is the yard's own):
	# what is measured is the hold of the host's hands and the road of the guest's, nothing else.
	if OS.get_environment("NET_FAIR") != "":
		Match.human_idle_on = false
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
		peers.append({"id": id, "name": Net.peers[id].name, "loadout": {"main": "gladius"}})
	Net.send_all("start", {"mode": "yard"})
	m = Match.new()
	add_child(m)
	m.setup({"mode": "yard", "role": "host", "headless": true, "name": "Host", "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": peers})
	print("HOST yard up with ", peers.size(), " guest; entities ", m.entities.size())
	# NET_FAIR=1: the room is taken to be people fighting each other, so every man's hands are held for the slowest friend's trip (Match._fair_active).
	if OS.get_environment("NET_FAIR") != "":
		m.fair_force = true
	if OS.get_environment("NET_OWN") != "":
		_own_swings.call_deferred(int(OS.get_environment("NET_OWN")))
	if OS.get_environment("NET_TGT") != "":
		_target_walk.call_deferred(float(OS.get_environment("NET_TGT")))
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
		if _tgt_on and m.me != null and is_instance_valid(m.me.f):
			var tp: Vector3 = m.me.f.torso.global_position
			print("TGT_H %.6f %.4f %.4f" % [Time.get_unix_time_from_system(), tp.x, tp.z])
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
					print("HMOVED %d %.6f" % [hand_lats.size() - 1, Time.get_unix_time_from_system()])
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

## The host's own man swings his main hand across the pane the same way a guest's is swung (net_lat_guest.gd `_hand`), NET_OWN times,
## timed from his press to his weapon's moving 3 cm in the physics: what a guest's swing is to be as quick as (the host's hands are
## held too, when NET_FAIR says people are fighting).
func _own_swings(reps: int) -> void:
	await get_tree().create_timer(6.0).timeout
	var rest := {"mx": 0.0, "mz": 0.0, "look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.1, "y": 0.15}}
	var swing := {"mx": 0.0, "mz": 0.0, "look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.7, "y": 0.5}}
	var out := []
	for rep in reps:
		m.probe_input = rest
		await get_tree().create_timer(1.6).timeout
		var w = m.me.f.weapons.get("R")
		if w == null or not is_instance_valid(w):
			print("HOST OWN no weapon in his right hand")
			return
		await get_tree().create_timer(randf_range(0.0, 0.05)).timeout
		var p0: Vector3 = w.global_position
		var t0 := Time.get_ticks_usec()
		m.probe_input = swing
		var ms := -1.0
		while Time.get_ticks_usec() - t0 < 2000000:
			await get_tree().physics_frame
			if (w.global_position - p0).length() > 0.03:
				ms = (Time.get_ticks_usec() - t0) / 1000.0
				break
		print("OWN %d %.1f ms" % [rep, ms])
		if ms >= 0.0:
			out.append(ms)
		m.probe_input = rest
		await get_tree().create_timer(1.0).timeout
	out.sort()
	if not out.is_empty():
		print("HOST OWN SWING n=%d min %.0f median %.0f worst %.0f ms" % [out.size(), out[0], out[out.size() / 2], out[-1]])

## NET_TGT=seconds: the host's own man walks to and fro (a second one way, a pause, a second back, a pause) for that long, and every physics
## step of it his torso is logged (TGT_H) with the system clock: the guest logs what his screen shows of him (net_lat_guest.gd _track) and
## tools/lat_tgt.py says how far the picture is from where the host's man is by the time a blow of the guest's lands.
func _target_walk(secs: float) -> void:
	await get_tree().create_timer(6.0).timeout
	var look := {"yaw": 0.0, "pitch": 0.0}
	var hand := {"x": 0.1, "y": 0.15}
	var fwd := {"mx": 0.0, "mz": 1.0, "look": look, "main": hand}
	var back := {"mx": 0.0, "mz": -1.0, "look": look, "main": hand}
	var stand := {"mx": 0.0, "mz": 0.0, "look": look, "main": hand}
	var t0 := Time.get_ticks_msec()
	_tgt_on = true
	print("TGT_START %.6f" % Time.get_unix_time_from_system())
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0) and m != null:
		for step in [[fwd, 1.0], [stand, 0.7], [back, 1.0], [stand, 0.7]]:
			m.probe_input = step[0]
			await get_tree().create_timer(float(step[1])).timeout
	m.probe_input = stand
	_tgt_on = false
	print("TGT_END %.6f" % Time.get_unix_time_from_system())
