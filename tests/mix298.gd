extends Node
## (scratch) What a step costs with a given mix of men, foes, beasts and great foes on the sand (`-- --probe mix298`, env MIX, e.g.
## "men:8,foe:8" "men:4,beast:wolf*2,great:cyclops"; --fixed-fps 120, one step to a frame, one worker thread: the wall time of a step is its cost).
## With RT=1 (no --fixed-fps; `taskset -c 0` for one core) it runs in real time with the frames at 60 a second at most and the men's drawing on (Fighter.process_in_headless),
## and says how many of the 120 steps a second the game takes and how many frames, the slowest frames and how long the worst second was (what the graphics card and the
## engine's own drawing add to a frame is not in it).
const SECONDS := 8.0
var frame_ms := []
var measuring := false
var delta_min := 1e9
var delta_max := 0.0
func _process(delta: float) -> void:
	if measuring:
		frame_ms.append(delta * 1000.0)

func _physics_process(delta: float) -> void:
	if measuring:
		delta_min = minf(delta_min, delta)
		delta_max = maxf(delta_max, delta)

func _ready() -> void:
	var spec := OS.get_environment("MIX")
	var rt := OS.get_environment("RT") == "1"
	if OS.get_environment("PACE") == "0":
		Net.overload_on = false   # (the engine's four steps to a frame, as before the two)
	if rt:
		Engine.max_fps = 60
		Fighter.process_in_headless = true
		if OS.get_environment("CAP") != "":
			Engine.max_physics_steps_per_frame = int(OS.get_environment("CAP"))   # (the steps a frame may take: 4 in the project)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 7, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -20))
	var weapons := ["gladius", "axe", "mace", "spear"]
	var foes := ["recruit", "shieldbearer", "brute", "murmillo"]
	var list := []   # [kind, arg]
	for tok in spec.split(","):
		var kv := tok.split(":")
		var arg := kv[1]
		var n := 1
		if arg.contains("*"):
			var a := arg.split("*")
			arg = a[0]
			n = int(a[1])
		if kv[0] == "men" or kv[0] == "foe":
			n = int(arg)
			arg = ""
		for i in n:
			list.append([kv[0], arg])
	var total := list.size()
	var radius := 5.0 + 0.35 * maxf(0.0, total - 8.0)
	var men_i := 0
	var foe_i := 0
	for i in total:
		var a := TAU * i / total
		var pos := Vector3(sin(a) * radius, 0.1, cos(a) * radius)
		var kind: String = list[i][0]
		var arg: String = list[i][1]
		if kind == "men":
			m.spawn_fighter({"kind": "bot", "name": "P%d" % men_i, "loadout": {"main": weapons[men_i % 4], "off": "roundShield" if men_i % 4 == 0 else ""}, "team": 0, "pos": pos, "yaw": a + PI, "diff": 0.8})
			men_i += 1
		elif kind == "foe":
			var sp: Dictionary = m.enemy_spec({"e": foes[foe_i % foes.size()]}, 0, 1)
			sp.pos = pos
			sp.yaw = a + PI
			m.spawn_fighter(sp)
			foe_i += 1
		elif kind == "beast":
			m.spawn_beast({"beast": arg, "team": Match.ENEMY_TEAM, "pos": pos, "yaw": a + PI})
		elif kind == "great":
			var sp2: Dictionary = m.enemy_spec({"e": arg}, 0, 1)
			sp2.pos = pos
			sp2.yaw = a + PI
			m.spawn_fighter(sp2)
	if rt:
		await _real_time(spec, m)
		return
	for k in 120:
		await get_tree().physics_frame
	var steps := int(SECONDS * 120.0)
	# profile_funcs.py: clear
	var gaps := []
	var t_prev := Time.get_ticks_usec()
	for k in steps:
		await get_tree().physics_frame
		var t_now := Time.get_ticks_usec()
		gaps.append((t_now - t_prev) / 1000.0)
		t_prev = t_now
	var sum := 0.0
	for g in gaps:
		sum += float(g)
	gaps.sort()
	var mean: float = sum / gaps.size()
	var alive := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.alive).size()
	print("MIX %-34s %2d on the sand (%2d alive at the end): a step %.2f ms (median %.2f, p99 %.2f, worst %.2f) -> keeps up %.0f/120" % [spec, m.entities.size(), alive, mean, gaps[gaps.size() / 2], gaps[int(gaps.size() * 0.99)], gaps[-1], minf(120.0, 1000.0 / mean)])
	# profile_funcs.py: print
	get_tree().quit(0)

func _real_time(spec: String, m: Match) -> void:
	var secs := int(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 8
	var warm := int(OS.get_environment("WARM")) if OS.get_environment("WARM") != "" else 2
	for s in warm:
		var w0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - w0 < 1000000:
			await get_tree().physics_frame
	measuring = true
	var steps_s := []
	var frames_s := []
	for s in secs:
		var w0 := Time.get_ticks_usec()
		var fr0 := Engine.get_process_frames()
		var ticks := 0
		while Time.get_ticks_usec() - w0 < 1000000:
			await get_tree().physics_frame
			ticks += 1
		var wall := (Time.get_ticks_usec() - w0) / 1e6
		steps_s.append(ticks / wall)
		frames_s.append(float(Engine.get_process_frames() - fr0) / wall)
	measuring = false
	var fs := frame_ms.duplicate()
	fs.sort()
	var over33 := fs.filter(func(x): return x > 33.4).size()
	var alive := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.alive).size()
	print("MIXRT %-30s %2d on the sand (%2d alive at the end): %3.0f steps a second of 120, %2.0f frames a second (lowest second %2.0f); a step %.4f..%.4f ms of game time; the engine's cap now %d" % [
		spec, m.entities.size(), alive, _avg(steps_s), _avg(frames_s), frames_s.min(), delta_min * 1000.0, delta_max * 1000.0, Engine.max_physics_steps_per_frame])
	get_tree().quit(0)

static func _avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(1, a.size())
