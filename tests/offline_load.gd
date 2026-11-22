extends Node
## A fight of eight offline (#298): the player's man (an autopilot) and seven bots in a free for all, the way the game starts a solo fight, with no room
## and no guests (`-- --probe offline_load`, headless; env OFF_SECS (12 s measured), OFF_WARM (2 s not counted), OFF_BOTS (7), OFF_MODE (ffa), OFF_SEED,
## OFF_FPS (the frames a second at most, as a window's vsync: 0, none)). Prints what the steps cost one after another, how many of the 120 a second the
## game really takes and how many frames, as tests/net_load_host.gd does for a room of the same eight, so that the two can be set side by side.
var m: Match

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _ready() -> void:
	var secs := int(_env("OFF_SECS", "12"))
	var warm := int(_env("OFF_WARM", "2"))
	var bots := int(_env("OFF_BOTS", "7"))
	var mode := _env("OFF_MODE", "ffa")
	if _env("OFF_FPS", "0") != "0":
		Engine.max_fps = int(_env("OFF_FPS", "0"))
	m = Match.new()
	add_child(m)
	m.setup({"mode": mode, "headless": true, "autopilot": true, "bots": bots, "seed": int(_env("OFF_SEED", "9")), "decrees": [], "hazards": []})
	print("OFFLINE role=%s men=%d (%d bots) mode=%s" % [m.role, m.entities.size(), m.entities.filter(func(e): return e.kind == "bot").size(), mode])
	var gaps := []
	var rates := []
	var cpus := []
	var alive_n := []
	var frame_rates := []
	var last_step := Time.get_ticks_usec()
	for s in warm + secs:
		var w0 := Time.get_ticks_usec()
		var c0 := cpu_seconds()
		var fr0 := Engine.get_process_frames()
		var ticks := 0
		while Time.get_ticks_usec() - w0 < 1000000:
			await get_tree().physics_frame
			ticks += 1
			var now_us := Time.get_ticks_usec()
			if s >= warm:
				gaps.append((now_us - last_step) / 1000.0)
			last_step = now_us
		var wall := (Time.get_ticks_usec() - w0) / 1e6
		if s >= warm:
			frame_rates.append(float(Engine.get_process_frames() - fr0) / wall)
		var alive := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.alive).size()
		if s >= warm:
			rates.append(ticks / wall)
			cpus.append((cpu_seconds() - c0) / wall * 100.0)
			alive_n.append(alive)
		print("LOAD s=%d alive=%d of %d steps %.0f/s (of 120) cpu %.0f%% of a core%s" % [s, alive, m.entities.size(), ticks / wall, (cpu_seconds() - c0) / wall * 100.0, "" if s >= warm else " (warm-up)"])
	var sorted := gaps.duplicate()
	sorted.sort()
	var mean := 0.0
	for g in gaps:
		mean += float(g)
	mean /= maxf(1.0, float(gaps.size()))
	print("OFFLINE STEPS n=%d mean %.2f ms, median %.1f ms, p99 %.1f ms, worst %.1f ms" % [gaps.size(), mean, sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.99)], sorted[-1]])
	print("OFFLINE SUMMARY men=%d steps %.0f/s cpu %.0f%% of a core | alive on average %.1f" % [m.entities.size(), _avg(rates), _avg(cpus), _avg(alive_n)])
	print("OFFLINE FRAMES %.0f a second on average (lowest second %.0f)" % [_avg(frame_rates), frame_rates.min() if not frame_rates.is_empty() else 0.0])
	get_tree().quit(0)

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
