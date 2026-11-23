extends Node
## The endless arena with eight players, and what the foes' gate does to the host's step (`-- --probe gate298`, headless, with `--fixed-fps 120`: the steps run back to back,
## their wall time is their cost): the host's man and seven more, all played by the bots, against the waves of the arena (Endless.plan for eight), brought in as a game with
## a screen brings them (stage_always). GATE=0: the gate off (as the arena was: sixteen on the sand). Prints every 10 s of play: the wave, the men and the foes alive, those
## held at the gate, what a step has cost (Net.step_ms, smoothed), and at the end the mean step and how many were over the 8.33 ms there are.
## env: SECS (90), GATE (1), ARMOR (1).
func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _ready() -> void:
	seed(7)
	var secs := float(_env("SECS", "90"))
	var lo := {"main": "gladius", "off": "scutum", "armor": ["helmet", "lorica", "manica", "greaves"] if _env("ARMOR", "1") != "0" else []}
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "endless", "role": "host", "headless": true, "autopilot": true, "seed": 7, "decrees": [], "hazards": [], "loadout": lo})
	m.stage_always = true
	if _env("GATE", "1") == "0":
		m.gate_cost_ms = 0.0
	for i in 7:
		var e = m.spawn_fighter({"kind": "local", "name": "P%d" % i, "loadout": lo.duplicate(true), "team": 0, "pos": Vector3(cos(TAU * float(i) / 7.0) * 3.0, 0.1, sin(TAU * float(i) / 7.0) * 3.0 - 6.0), "yaw": 0.0})
		e.bot = Bot.new(e.f, 0.8, "standard", 99 + i)
	print("GATE298 humans %d, gate %s" % [m.humans().size(), "on" if _env("GATE", "1") != "0" else "off"])
	var times := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	var over := 0
	var n := 0
	var sum := 0.0
	for i in int(secs * 120.0):
		await get_tree().physics_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		if i > 240:
			sum += ms
			n += 1
			if ms > 8.33:
				over += 1
		if i % 1200 == 1199:
			var men := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.alive).size()
			var foes := m.enemies().filter(func(e): return is_instance_valid(e.f) and e.f.alive).size()
			print("GATE298 %3ds  wave %s  men %2d  foes %2d  held %d  coming %d  a step %.1f ms" % [(i + 1) / 120, str(m.modes.endless.wave), men, foes, m.gate_held, m.coming, Net.step_ms])
	print("GATE298 mean step %.2f ms, %.0f%% of the steps over 8.33 ms" % [sum / float(maxi(1, n)), 100.0 * float(over) / float(maxi(1, n))])
	get_tree().quit()
