extends Node
## (scratch) What a step costs with a given mix of men, foes, beasts and great foes on the sand (`-- --probe mix298`, env MIX, e.g.
## "men:8,foe:8" "men:4,beast:wolf*2,great:cyclops"; --fixed-fps 120, one step to a frame, one worker thread: the wall time of a step is its cost).
const SECONDS := 8.0
func _ready() -> void:
	var spec := OS.get_environment("MIX")
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
	for k in 120:
		await get_tree().physics_frame
	var steps := int(SECONDS * 120.0)
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
	get_tree().quit(0)
