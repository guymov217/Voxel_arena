extends Node
## The delay a guest feels, guest side (see net_lat_host): in the host's yard he lets go of his hands, presses forward at a time the
## frames do not know (NET_REPS times) and times, by the clock, how long it is until his own man has moved on his own screen (NET_MOVE
## metres, 2 cm), what the picture of the others is behind the host, and what the game's own ping says. Prints LAT lines and a
## summary (milliseconds): min, median, mean, 90th, worst. NET_MAX_MEDIAN: the median it may not pass (the run fails).

var m: Match
var started := false

func _ready() -> void:
	Engine.max_fps = int(OS.get_environment("NET_FPS")) if OS.get_environment("NET_FPS") != "" else 60
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17781
	Net.my_name = "Guest"
	Net.join_enet("127.0.0.1", port)
	Net.message.connect(_on)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
	print("GUEST timeout")
	get_tree().quit(1)

func _on(type: String, data, _from: int) -> void:
	match type:
		"start":
			if m == null:
				m = Match.new()
				add_child(m)
				m.setup({"mode": data.mode, "role": "guest", "headless": true, "seed": 1, "decrees": [], "hazards": []})
		"spawn":
			if m:
				m.guest_spawn(data)
				if not started and m.me != null and is_instance_valid(m.me.f):
					started = true
					_measure.call_deferred()
		"despawn":
			if m and data is Dictionary:
				m.guest_despawn(int(data.get("id", -1)))
		"snap":
			if m:
				m.apply_snapshot(data)
		"bye":
			get_tree().quit(0)

func _torso() -> Vector3:
	return m.me.f.torso.global_position

func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout

func _measure() -> void:
	var reps := int(OS.get_environment("NET_REPS")) if OS.get_environment("NET_REPS") != "" else 30
	var move := float(OS.get_environment("NET_MOVE")) if OS.get_environment("NET_MOVE") != "" else 0.02
	var hands := {"mx": 0.0, "mz": 0.0, "look": {"yaw": 0.0, "pitch": 0.0}}
	var press := {"mx": 0.0, "mz": 1.0, "look": {"yaw": 0.0, "pitch": 0.0}}
	m.probe_input = hands
	await _wait(3.0)   # (the yard's men come in, he settles on his feet)
	# How still he stands: the measure is a move past that.
	var lo := _torso()
	var hi := lo
	for i in 60:
		await get_tree().physics_frame
		var p := _torso()
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	var sway := maxf(hi.x - lo.x, hi.z - lo.z)
	print("GUEST at rest he sways %.1f mm; counted as moved: %.0f mm" % [sway * 1000.0, maxf(move, sway * 3.0) * 1000.0])
	move = maxf(move, sway * 3.0)
	var lats := []
	for rep in reps:
		await _wait(randf_range(0.0, 0.05))   # (the time of the press is no multiple of anyone's frame)
		var p0 := _torso()
		var t0 := Time.get_ticks_usec()
		m.probe_input = press
		var ms := -1.0
		while Time.get_ticks_usec() - t0 < 2500000:
			await get_tree().physics_frame
			var p := _torso()
			if Vector2(p.x - p0.x, p.z - p0.z).length() > move:
				ms = (Time.get_ticks_usec() - t0) / 1000.0
				break
		m.probe_input = hands
		print("LAT %d %.1f ms (ping %d)" % [rep, ms, Net.ping_ms])
		if ms >= 0.0:
			lats.append(ms)
		await _wait(1.6)   # (he stops, and stands)
	lats.sort()
	var limit := float(OS.get_environment("NET_MAX_MEDIAN")) if OS.get_environment("NET_MAX_MEDIAN") != "" else 0.0
	if lats.is_empty():
		print("GUEST SUMMARY no move seen")
		get_tree().quit(1)
		return
	else:
		var sum := 0.0
		for v in lats:
			sum += v
		print("GUEST SUMMARY n=%d min %.0f median %.0f mean %.0f p90 %.0f worst %.0f ms | ping %d ms, snapshots %.0f/s, longest wait %d ms" % [lats.size(), lats[0], lats[lats.size() / 2], sum / lats.size(), lats[int(lats.size() * 0.9)], lats[-1], Net.ping_ms, Net.snap_rate, Net.snap_gap])
	if limit > 0.0 and lats[lats.size() / 2] > limit:
		print("GUEST FAIL: the median %.0f ms is over %.0f ms" % [lats[lats.size() / 2], limit])
		get_tree().quit(1)
		return
	get_tree().quit(0)
