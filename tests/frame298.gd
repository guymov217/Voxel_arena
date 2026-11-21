extends Node
## What the frame's own work costs the host with N men in the Ludus yard: the scripts' `_process` of every node (the men's drawing, the match's tags
## and rows), one frame to a physics step. `-- --probe frame298`, headless but with the men's drawing switched on (Fighter.process_in_headless: a game
## with no screen draws nothing); what the graphics card is asked is not in it. Prints the process phase's wall time (mean, median, p99, worst), what of
## it is the men's drawing and the match's (what F3 says as "in the frame", FpsMeter) and how many of the men sleep.
## env: N (men, 8), BEHAVIOR (idle|walk|brawl), SECS (game seconds, 6), IDLE (0: the men standing still are not let sleep), ARM_LOD, ARMOR, NONPC (1: no keepers).

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

var t_start := 0
var spans := PackedInt32Array()
class StartMark extends Node:
	var owner_: Node
	func _process(_dt: float) -> void:
		owner_.t_start = Time.get_ticks_usec()
class EndMark extends Node:
	var owner_: Node
	func _process(_dt: float) -> void:
		if owner_.t_start > 0:
			owner_.spans.append(Time.get_ticks_usec() - owner_.t_start)

func _ready() -> void:
	var n_men := int(_env("N", "8"))
	var behavior := _env("BEHAVIOR", "idle")
	var secs := float(_env("SECS", "6"))
	seed(7)
	Fighter.arm_lod_on = _env("ARM_LOD", "1") != "0"
	Match.human_idle_on = _env("IDLE", "1") != "0"
	Fighter.process_in_headless = true
	var m := Match.new()
	add_child(m)
	var lo := {"main": "gladius", "off": "scutum", "armor": ["helmet", "lorica", "manica", "greaves"] if _env("ARMOR", "1") != "0" else []}
	m.setup({"mode": "yard", "headless": false, "seed": 7, "decrees": [], "hazards": [], "loadout": lo, "role": "host"})
	m.me.drive = func(_e): return {}
	if _env("NONPC", "0") == "1":
		for e in m.entities.duplicate():
			if e.kind == "npc":
				m._remove_entity(e)
	var heading := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n_men - 1:
		var a := TAU * float(i) / float(maxi(1, n_men - 1))
		var spec := {"kind": "bot", "name": "F%d" % i, "loadout": lo.duplicate(true), "team": 10 + i, "pos": Vector3(cos(a) * 3.0, 0.1, sin(a) * 3.0 + 4.0), "yaw": a + PI}
		var e = m.spawn_fighter(spec)
		if behavior != "brawl":
			e.erase("bot")
			heading[e.id] = rng.randf() * TAU
			if behavior == "idle":
				e.drive = func(_e): return {}
			else:
				e.drive = func(en):
					var id: int = en.id
					if rng.randf() < 0.01:
						heading[id] = rng.randf() * TAU
					return {"mz": 1.0, "look": {"yaw": heading[id], "pitch": 0.0}}
	var sm := StartMark.new()
	sm.owner_ = self
	sm.process_priority = -100000
	add_child(sm)
	var em := EndMark.new()
	em.owner_ = self
	em.process_priority = 100000
	add_child(em)
	for i in int(_env("WARM", "360")):
		await get_tree().process_frame
	spans.clear()
	FpsMeter.prof_on = true   # (what F3 reads: the men's drawing and the match's, in microseconds)
	FpsMeter.prof_men_us = 0
	FpsMeter.prof_match_us = 0
	var frames := int(secs * 120.0)
	for i in frames:
		await get_tree().process_frame
	FpsMeter.prof_on = false
	var s := Array(spans)
	s.sort()
	var mean := 0.0
	for v in s:
		mean += float(v)
	mean /= maxf(1.0, float(s.size()))
	var asleep := 0
	for e in m.entities:
		if e.kind != "npc" and (e.get("hidle", false) or e.get("idle", false)) and is_instance_valid(e.f) and e.f.draw_rest_ready:
			asleep += 1
	print("FRAME n=%d %s: the scripts' frame %.2f ms (median %.2f, p99 %.2f, worst %.2f); the men's drawing %.2f ms, the match %.2f ms; %d of the men drawn at rest" % [
		n_men, behavior, mean / 1000.0, s[s.size() / 2] / 1000.0, s[int(s.size() * 0.99)] / 1000.0, s[s.size() - 1] / 1000.0,
		FpsMeter.prof_men_us / 1000.0 / float(frames), FpsMeter.prof_match_us / 1000.0 / float(frames), asleep])
	get_tree().quit()
