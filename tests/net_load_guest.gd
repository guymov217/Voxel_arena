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

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17777
	Net.my_name = "Guest%d" % (OS.get_process_id() % 1000)
	Net.join_enet(OS.get_environment("NET_HOST") if OS.get_environment("NET_HOST") != "" else "127.0.0.1", port)
	Net.message.connect(_on)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000:
		await get_tree().physics_frame
	print("GUEST timeout")
	get_tree().quit(1)

func _on(type: String, data, _from: int) -> void:
	match type:
		"start":
			m = Match.new()
			add_child(m)
			m.setup({"mode": data.mode, "stage": data.stage, "role": "guest", "headless": true, "autopilot": true})
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
			last_snap = Time.get_ticks_msec()
			c0 = load("res://tests/net_load_host.gd").cpu_seconds()
			w0 = Time.get_ticks_usec()
		"spawn":
			if m: m.guest_spawn(data)
		"snap":
			snaps += 1
			var now := Time.get_ticks_msec()
			if snaps > 40:
				gaps.append(now - last_snap)
				worst_gap = maxi(worst_gap, now - last_snap)
			last_snap = now
			if m: m.apply_snapshot(data)
		"vox":
			if m: m.guest_vox(data)
		"bye":
			var got: float = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA) / 1024.0
			gaps.sort()
			var secs: float = (Time.get_ticks_usec() - w0) / 1e6
			var cpu: float = (load("res://tests/net_load_host.gd").cpu_seconds() - c0) / maxf(0.1, secs) * 100.0
			print("GUEST SUMMARY %s snapshot msgs %.0f/s gap p95 %d ms worst %d ms | received %.0f KB/s | cpu %.0f%% of a core" % [Net.my_name, snaps / maxf(1.0, secs), gaps[int(gaps.size() * 0.95)] if gaps.size() else -1, worst_gap, got / maxf(1.0, secs), cpu])
			get_tree().quit(0)

static func _avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(1, a.size())
