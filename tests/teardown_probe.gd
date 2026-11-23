extends Node
## What a match is made of at its end and what freeing it costs (`-- --probe teardown_probe`; env MODE (endless), MEN (8), SECS (20), STAGE (0/1: stage_always), DRAW (1: a real renderer, run under Xvfb with --disable-render-loop)).
## Builds MEN players (a bot each), fights SECS seconds (game time), counts the nodes by class, then frees the match in one frame and prints how long that frame took.
func _census(n: Node, by_class: Dictionary, by_child: Dictionary, top: Node) -> int:
	var c := 1
	by_class[n.get_class()] = int(by_class.get(n.get_class(), 0)) + 1
	for k in n.get_children():
		c += _census(k, by_class, by_child, top)
	return c

func _ready() -> void:
	seed(7)
	var mode := OS.get_environment("MODE") if OS.get_environment("MODE") != "" else "endless"
	var men := int(OS.get_environment("MEN")) if OS.get_environment("MEN") != "" else 8
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 20.0
	var peers := []
	for i in men - 1:
		peers.append({"id": 2 + i, "name": "P%d" % i, "loadout": {"main": ["gladius", "axe", "spear", "mace"][i % 4], "off": "scutum" if i % 2 == 0 else "", "armor": ["helmet", "lorica"] if i % 2 == 0 else []}, "kit": {}})
	var m := Match.new()
	m.stage_always = OS.get_environment("STAGE") == "1"
	add_child(m)
	var t0 := Time.get_ticks_usec()
	m.setup({"mode": mode, "role": "host", "headless": OS.get_environment("DRAW") != "1", "name": "Ann", "seed": 5, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "scutum", "armor": ["helmet", "lorica"]}, "peers": peers, "autopilot": true})
	print("TEARDOWN setup of %s with %d men: %.0f ms (humans in: %d, coming %d)" % [mode, men, float(Time.get_ticks_usec() - t0) / 1000.0, m.humans().size(), m.coming])
	for e in m.humans():
		if e.kind == "remote" and not e.has("bot"):
			e.bot = Bot.new(e.f, 0.7, "standard", 1)
	var frames := int(secs * 60.0)
	for i in frames:
		await get_tree().process_frame
	var by_class := {}
	var by_child := {}
	var total := _census(m, by_class, by_child, m)
	var kids := {}
	for k in m.get_children():
		var cn := _census(k, {}, {}, k)
		kids[k.get_class() + ":" + (k.name as String).left(18)] = cn
	var pairs := []
	for k in kids:
		pairs.append([int(kids[k]), k])
	pairs.sort_custom(func(a, b): return a[0] > b[0])
	print("TEARDOWN %d nodes, %d men, bodies %d" % [total, m.entities.size(), int(by_class.get("RigidBody3D", 0))])
	print("TEARDOWN by class: ", str(by_class))
	print("TEARDOWN biggest children of the match: ", str(pairs.slice(0, 12)))
	if OS.get_environment("EACH") == "1":
		# One child at a time, freed at once: what each costs to let go.
		var rows := []
		for k in m.get_children().duplicate():
			var cname: String = k.get_class() + ":" + (k.name as String).left(20)
			var nn := _census(k, {}, {}, k)
			var a := Time.get_ticks_usec()
			k.free()
			rows.append([float(Time.get_ticks_usec() - a) / 1000.0, nn, cname])
		rows.sort_custom(func(x, y): return x[0] > y[0])
		var sum := 0.0
		for r in rows:
			sum += float(r[0])
		print("TEARDOWN each, freed at once: total %.0f ms over %d children; the dearest: %s" % [sum, rows.size(), str(rows.slice(0, 14))])
		var agg := {}
		for r in rows:
			var cls: String = String(r[2]).split(":")[0]
			agg[cls] = [float(agg.get(cls, [0.0, 0])[0]) + float(r[0]), int(agg.get(cls, [0.0, 0])[1]) + int(r[1])]
		print("TEARDOWN by class of child: ", str(agg))
	if OS.get_environment("FRAMEEACH") == "1":
		# One child at a time, freed at once, and the frame after it timed: which removal makes the frame that follows long.
		var rows2 := []
		for k in m.get_children().duplicate():
			var cname2: String = k.get_class() + ":" + (k.name as String).left(20)
			var nn2 := _census(k, {}, {}, k)
			var a2 := Time.get_ticks_usec()
			k.free()
			var b2 := Time.get_ticks_usec()
			await get_tree().process_frame
			rows2.append([snappedf(float(Time.get_ticks_usec() - b2) / 1000.0, 0.1), snappedf(float(b2 - a2) / 1000.0, 0.1), nn2, cname2])
		rows2.sort_custom(func(x, y): return x[0] > y[0])
		print("TEARDOWN the frame after each free [frame ms, free ms, nodes, child]: ", str(rows2.slice(0, 14)))
	var fr_ms := []
	for i in 4:
		var a3 := Time.get_ticks_usec()
		await get_tree().process_frame
		fr_ms.append(snappedf(float(Time.get_ticks_usec() - a3) / 1000.0, 0.1))
	print("TEARDOWN four ordinary frames before: ", str(fr_ms))
	var td0 := Time.get_ticks_usec()
	m.queue_free()
	await get_tree().process_frame
	var td1 := Time.get_ticks_usec()
	print("TEARDOWN the frame that frees it: %.0f ms" % (float(td1 - td0) / 1000.0))
	var after := []
	for i in 4:
		var a4 := Time.get_ticks_usec()
		await get_tree().process_frame
		after.append(snappedf(float(Time.get_ticks_usec() - a4) / 1000.0, 0.1))
	print("TEARDOWN four frames after: ", str(after))
	get_tree().quit()
