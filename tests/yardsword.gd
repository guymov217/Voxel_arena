extends Node
## A sword bought at the smith in the yard, then a run with it (user: the new sword went down
## through the floor and he ran with it half under the sand). Each weapon in WEAPONS is put in
## his hand as the smith's purchase does (Fighter.rearm), he runs off with it, and the lowest
## corner of the blade is followed: how far under the sand it goes, and for how long.
## HANDS: where the sword hand is held as he runs ("rest" at the guard, "low" down by the sand,
## "side" low and out). `-- --probe yardsword`. WEAPONS (the smith's blades), RUN_S (4).

func _low(w: Weapon) -> float:
	var box: AABB = w.local_box()
	var lo := INF
	for i in 8:
		lo = minf(lo, (w.global_transform * box.get_endpoint(i)).y)
	return lo

func _ready() -> void:
	var names: Array = Array((OS.get_environment("WEAPONS") if OS.get_environment("WEAPONS") != "" else "gladius,longsword,dagger,axe,spear,zweihander").split(","))
	var run_s := float(OS.get_environment("RUN_S")) if OS.get_environment("RUN_S") != "" else 4.0
	var hands := {"rest": {"x": 0.1, "y": 0.15}, "low": {"x": 0.1, "y": -1.3}, "side": {"x": 0.7, "y": -1.0}}
	var which: Array = Array((OS.get_environment("HANDS") if OS.get_environment("HANDS") != "" else "rest,low,side").split(","))
	for combo in names.map(func(n): return which.map(func(h): return [n, h])).reduce(func(a, b): return a + b, []):
		var nm: String = combo[0]
		var hand: Dictionary = hands[combo[1]]
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "yard", "loadout_override": {"main": "", "off": ""}, "headless": true, "seed": 1, "decrees": [], "hazards": []})
		var f: Fighter = m.me.f
		var run := [false]
		var yaw0 := f.yaw
		m.me.drive = func(_e): return {"mz": 1.0 if run[0] else 0.0, "sprint": run[0], "main": hand, "off": {"x": -0.35, "y": 0.1}, "look": {"yaw": yaw0, "pitch": 0.0}}
		for i in 180:
			await get_tree().physics_frame
		f.rearm(Data.preset(String(nm)), null)
		var w: Weapon = f.weapons.R
		if w == null:
			print("%-10s not in the presets" % nm)
			m.queue_free()
			continue
		var first := _low(w)
		var worst := INF
		var under_t := 0.0
		var at_buy_worst := INF
		for i in 60:
			await get_tree().physics_frame
			at_buy_worst = minf(at_buy_worst, _low(w))
		run[0] = true
		for i in int(run_s * 120):
			await get_tree().physics_frame
			if not is_instance_valid(w):
				break
			var lo := _low(w)
			worst = minf(worst, lo)
			if lo < -0.03:
				under_t += 1.0 / 120.0
		print("%-10s %-5s on buying %+.3f m, first half second %+.3f, running: lowest %+.3f m, %.2f s more than 3 cm under" % [nm, combo[1], first, at_buy_worst, worst, under_t])
		m.queue_free()
		await get_tree().physics_frame
	get_tree().quit()
