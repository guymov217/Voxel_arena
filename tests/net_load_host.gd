extends Node
## Network load test, host side (`-- --probe net_load_host`, with NET_GUESTS guests running
## `-- --probe net_load_guest`): a campaign bout (or, with NET_MODE=ffa|teams|pvp|..., that arena mode) with
## every guest in it, run for NET_SECONDS, and each second what it costs the host: physics time per step,
## what goes out on the wire, the size of a snapshot. Prints LOAD lines and a summary, and how long
## the steps took one after another (STEPS: the median, the 99th, the worst, and how many were over a
## frame at 60, at 30 and over a tenth of a second: a stall is a step that is long, not a mean that is high).

var m: Match

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17777
	var want := int(OS.get_environment("NET_GUESTS")) if OS.get_environment("NET_GUESTS") != "" else 3
	var secs := int(OS.get_environment("NET_SECONDS")) if OS.get_environment("NET_SECONDS") != "" else 20
	var stage := int(OS.get_environment("NET_STAGE")) if OS.get_environment("NET_STAGE") != "" else 6
	var mode := OS.get_environment("NET_MODE") if OS.get_environment("NET_MODE") != "" else "campaign"
	print("HOST listen ", Net.host_enet(port))
	Net.my_name = "Host"
	var t0 := Time.get_ticks_msec()
	while Net.peers.size() < want and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	print("HOST peers ", Net.peers.size(), " of ", want)
	var peers := []
	for id in Net.peers:
		peers.append({"id": id, "name": Net.peers[id].name, "loadout": {"main": ["axe", "gladius", "spear", "mace"][peers.size() % 4]}})
	Net.send_all("start", {"mode": mode, "stage": stage})
	m = Match.new()
	add_child(m)
	m.stage_always = OS.get_environment("NET_NOSTAGE") == ""   # (a host with a screen brings a wave in over the frames; NET_NOSTAGE=1 builds as before)
	m.setup({"mode": mode, "stage": stage, "role": "host", "headless": true, "autopilot": true, "peers": peers, "seed": 9})
	var enet := (multiplayer.multiplayer_peer as ENetMultiplayerPeer).host
	Net.stats_on = true
	enet.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var all_kb := []
	var snap_b := []
	var cpus := []
	var rates := []
	var gaps := []   # ms from one physics step to the next, over the whole run
	var last_step := Time.get_ticks_usec()
	for s in secs:
		var w0 := Time.get_ticks_usec()
		var c0 := cpu_seconds()
		var ticks := 0
		while Time.get_ticks_usec() - w0 < 1000000:
			await get_tree().physics_frame
			ticks += 1
			var now_us := Time.get_ticks_usec()
			gaps.append((now_us - last_step) / 1000.0)
			last_step = now_us
		var wall := (Time.get_ticks_usec() - w0) / 1e6
		var cpu := (cpu_seconds() - c0) / wall * 100.0
		var sent: float = enet.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA) / 1024.0 / wall
		var sb := var_to_bytes(m.snapshot()).size()
		snap_b.append(sb)
		cpus.append(cpu)
		rates.append(ticks / wall)
		all_kb.append(sent)
		print("LOAD s=%d entities=%d steps %.0f/s (of 120) cpu %.0f%% of a core | sent %.0f KB/s (%.0f per guest) | snapshot %d B" % [s, m.entities.size(), ticks / wall, cpu, sent, sent / maxf(1, Net.peers.size()), sb])
	gaps.sort()
	var over16 := 0
	var over33 := 0
	var over100 := 0
	for g in gaps:
		over16 += 1 if g > 16.7 else 0
		over33 += 1 if g > 33.3 else 0
		over100 += 1 if g > 100.0 else 0
	if not gaps.is_empty():
		print("HOST STEPS n=%d median %.1f ms, p99 %.1f ms, worst %.1f ms | over 16.7 ms: %d, over 33 ms: %d, over 100 ms: %d" % [gaps.size(), gaps[gaps.size() / 2], gaps[int(gaps.size() * 0.99)], gaps[-1], over16, over33, over100])
	var by := Net.stats.keys()
	by.sort_custom(func(a, b): return Net.stats[a] > Net.stats[b])
	var steps_total := 0.0
	for r in rates:
		steps_total += r
	print("HOST BYTES per step: ", ", ".join(by.slice(0, 10).map(func(k): return "%s %d" % [k, Net.stats[k] / maxf(1.0, steps_total)])))
	print("HOST SUMMARY guests=%d entities=%d steps %.0f/s cpu %.0f%% of a core | sent avg %.0f KB/s, %.0f KB/s per guest | snapshot avg %d B" % [Net.peers.size(), m.entities.size(), _avg(rates), _avg(cpus), _avg(all_kb), _avg(all_kb) / maxf(1, Net.peers.size()), int(_avg(snap_b))])
	Net.send_all("bye", {})
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)

## The CPU this process has used (Linux: /proc/self/stat, utime + stime), in seconds.
static func cpu_seconds() -> float:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return 0.0
	var parts := f.get_line().split(")")[-1].strip_edges().split(" ")
	return (float(parts[11]) + float(parts[12])) / 100.0

static func _avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(1, a.size())
