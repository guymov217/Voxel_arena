extends Node
## Network load test, guest side (see net_load_host): joins, plays the bout as a bot, and says
## how the game came in: snapshots a second, the longest wait between two, what came in on the
## wire, and its own physics time per step.

var m: Match
var snaps := 0
var last_snap := 0
var worst_gap := 0
var gaps := []
var c0 := 0.0
var w0 := 0
var took := {}      # message type -> [count, total ms, worst ms]: how long the game was held up taking it in
var step_gaps := [] # ms between physics steps once the bout is on

func _took(type: String, t0_us: int) -> void:
	var ms := (Time.get_ticks_usec() - t0_us) / 1000.0
	var r: Array = took.get(type, [0, 0.0, 0.0])
	r[0] += 1
	r[1] += ms
	r[2] = maxf(r[2], ms)
	took[type] = r

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17777
	Net.my_name = "Guest%d" % (OS.get_process_id() % 1000)
	Net.join_enet(OS.get_environment("NET_HOST") if OS.get_environment("NET_HOST") != "" else "127.0.0.1", port)
	Net.message.connect(_on)
	var t0 := Time.get_ticks_msec()
	var last_us := Time.get_ticks_usec()
	while Time.get_ticks_msec() - t0 < 240000:
		await get_tree().physics_frame
		var now_us := Time.get_ticks_usec()
		if m != null:
			step_gaps.append((now_us - last_us) / 1000.0)
		last_us = now_us
	print("GUEST timeout")
	get_tree().quit(1)

func _on(type: String, data, _from: int) -> void:
	match type:
		"start":
			m = Match.new()
			add_child(m)
			m.stage_always = OS.get_environment("NET_NOSTAGE") == ""   # (a guest with a screen builds over the frames: NET_NOSTAGE=1 builds as before)
			m.setup({"mode": data.mode, "stage": data.stage, "role": "guest", "headless": true, "autopilot": true})
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
			last_snap = Time.get_ticks_msec()
			c0 = load("res://tests/net_load_host.gd").cpu_seconds()
			w0 = Time.get_ticks_usec()
		"spawn":
			var t_us := Time.get_ticks_usec()
			if m: m.guest_spawn(data)
			_took("spawn", t_us)
		"snap":
			# (The rows of one snapshot come in messages in the same moment, one fighter or two to a message: a snapshot is
			# the first message after a pause of 6 ms, as Net counts them.)
			var now := Time.get_ticks_msec()
			if now - last_snap > 6:
				snaps += 1
				if snaps > 40:
					gaps.append(now - last_snap)
					worst_gap = maxi(worst_gap, now - last_snap)
			last_snap = now
			var t_us := Time.get_ticks_usec()
			if m: m.apply_snapshot(data)
			_took("snap", t_us)
		"vox":
			var t_us := Time.get_ticks_usec()
			if m: m.guest_vox(data)
			_took("vox", t_us)
		"bye":
			var got: float = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA) / 1024.0
			gaps.sort()
			var secs: float = (Time.get_ticks_usec() - w0) / 1e6
			var cpu: float = (load("res://tests/net_load_host.gd").cpu_seconds() - c0) / maxf(0.1, secs) * 100.0
			step_gaps.sort()
			var parts := []
			for k in took:
				parts.append("%s n=%d total %.0f ms worst %.1f ms" % [k, took[k][0], took[k][1], took[k][2]])
			if not step_gaps.is_empty():
				print("GUEST STEPS %s median %.1f ms, p99 %.1f ms, worst %.1f ms, over 33 ms: %d, over 100 ms: %d | took in: %s" % [Net.my_name, step_gaps[step_gaps.size() / 2], step_gaps[int(step_gaps.size() * 0.99)], step_gaps[-1], step_gaps.filter(func(g): return g > 33.3).size(), step_gaps.filter(func(g): return g > 100.0).size(), "; ".join(parts)])
			print("GUEST SUMMARY %s snapshots %.0f/s gap p95 %d ms worst %d ms | received %.0f KB/s | cpu %.0f%% of a core" % [Net.my_name, snaps / maxf(1.0, secs), gaps[int(gaps.size() * 0.95)] if gaps.size() else -1, worst_gap, got / maxf(1.0, secs), cpu])
			get_tree().quit(0)

static func _avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(1, a.size())
