extends Node
## Network load test, host side (`-- --probe net_load_host`, with NET_GUESTS guests running
## `-- --probe net_load_guest`): a campaign bout with every guest in it, run for NET_SECONDS, and
## each second what it costs the host: physics time per step, what goes out on the wire, the
## size of a snapshot. Prints LOAD lines and a summary.

var m: Match

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17777
	var want := int(OS.get_environment("NET_GUESTS")) if OS.get_environment("NET_GUESTS") != "" else 3
	var secs := int(OS.get_environment("NET_SECONDS")) if OS.get_environment("NET_SECONDS") != "" else 20
	var stage := int(OS.get_environment("NET_STAGE")) if OS.get_environment("NET_STAGE") != "" else 6
	print("HOST listen ", Net.host_enet(port))
	Net.my_name = "Host"
	var t0 := Time.get_ticks_msec()
	while Net.peers.size() < want and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	print("HOST peers ", Net.peers.size(), " of ", want)
	var peers := []
	for id in Net.peers:
		peers.append({"id": id, "name": Net.peers[id].name, "loadout": {"main": ["axe", "gladius", "spear", "mace"][peers.size() % 4]}})
	Net.send_all("start", {"mode": "campaign", "stage": stage})
	m = Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": stage, "role": "host", "headless": true, "autopilot": true, "peers": peers, "seed": 9})
	var enet := (multiplayer.multiplayer_peer as ENetMultiplayerPeer).host
	enet.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var all_ms := []
	var all_kb := []
	var snap_b := []
	for s in secs:
		var ms := []
		for i in 120:
			var a := Time.get_ticks_usec()
			await get_tree().physics_frame
			ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		var sent: float = enet.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA) / 1024.0
		var sb := var_to_bytes(m.snapshot()).size()
		snap_b.append(sb)
		ms.sort()
		all_ms.append_array(ms)
		all_kb.append(sent)
		print("LOAD s=%d entities=%d physics avg %.1f ms p95 %.1f ms max %.1f ms | sent %.0f KB/s (%.0f per guest) | snapshot %d B" % [s, m.entities.size(), _avg(ms), ms[int(ms.size() * 0.95)], ms[-1], sent, sent / maxf(1, Net.peers.size()), sb])
	all_ms.sort()
	print("HOST SUMMARY guests=%d entities=%d physics avg %.1f ms p95 %.1f ms (budget 8.3 ms) | sent avg %.0f KB/s, %.0f KB/s per guest | snapshot avg %d B" % [Net.peers.size(), m.entities.size(), _avg(all_ms), all_ms[int(all_ms.size() * 0.95)], _avg(all_kb), _avg(all_kb) / maxf(1, Net.peers.size()), int(_avg(snap_b))])
	Net.send_all("bye", {})
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)

static func _avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(1, a.size())
