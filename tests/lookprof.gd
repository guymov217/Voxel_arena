extends Node
## Where the look's time goes, headless (`-- --probe lookprof`, STYLE=human or strong): eight men
## standing as in lookperf; the frame's script time as it is, then with the parts' own drawing
## step off; the faces' life and the parts' drawing step timed by themselves; the nodes there.

var m

func _avg_process(n: int) -> float:
	var s := 0.0
	for i in n:
		await get_tree().process_frame
		s += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	return s / n

func _ready() -> void:
	var style := OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "human"
	Physique.forced = style
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "decrees": [], "hazards": [], "seed": 11})
	m.me.f.teleport(Vector3(0, 0, -16))
	var weapons := ["gladius", "axe", "spear", "warhammer", "longsword", "mace", "trident", "zweihander"]
	var men := []
	for i in 8:
		var a := TAU * float(i) / 8.0
		var pos := Vector3(sin(a) * 2.4, 0.1, cos(a) * 2.4)
		var t := Time.get_ticks_usec()
		var e = m.spawn_fighter({"kind": "bot", "name": "Bench %d" % i, "loadout": {"main": weapons[i % weapons.size()], "off": "", "armor": ["helmet", "manica"] if i % 2 == 0 else []}, "team": i % 2, "pos": pos, "yaw": atan2(-pos.x, -pos.z), "diff": 0.8})
		print("LOOKPROF %s spawn %d (%s): %.1f ms" % [style, i, str(e.f.get_meta("build", "")), float(Time.get_ticks_usec() - t) / 1000.0])
		men.append(e)
	for e in men:
		e.erase("bot")
		e.drive = func(_e): return {}
	for i in 60:
		await get_tree().process_frame
	print("LOOKPROF %s nodes %d" % [style, get_tree().get_node_count()])
	var base := await _avg_process(240)
	print("LOOKPROF %s script as it is: %.2f ms" % [style, base])
	# The parts' own drawing step (VoxelPart._process) off.
	for e in men:
		for p in e.f.parts:
			p.set_process(false)
	var no_parts := await _avg_process(240)
	print("LOOKPROF %s script, parts' step off: %.2f ms" % [style, no_parts])
	for e in men:
		for p in e.f.parts:
			p.set_process(true)
	# Each kind of node's own step off in turn (what of the frame is whose).
	for cls in ["Match", "Weapon", "Combat", "Fx", "Atmosphere", "KillCam", "Arena", "PlayerInput", "Fighter"]:
		var off := []
		var stack: Array = [get_tree().root]
		while not stack.is_empty():
			var nd: Node = stack.pop_back()
			if nd.get_script() and String(nd.get_script().get_global_name()) == cls and nd.is_processing():
				off.append(nd)
			stack.append_array(nd.get_children())
		for nd in off:
			nd.set_process(false)
		var t_off := await _avg_process(120)
		for nd in off:
			nd.set_process(true)
		print("LOOKPROF %s script, %s's step off (%d): %.2f ms" % [style, cls, off.size(), t_off])
	var again := await _avg_process(240)
	print("LOOKPROF %s script as it is, again: %.2f ms" % [style, again])
	# Each by itself, as many times as the frames above.
	var dt := 1.0 / 60.0
	var t0 := Time.get_ticks_usec()
	for i in 240:
		for e in men:
			Physique.live(e.f, dt)
	print("LOOKPROF %s faces' life: %.3f ms a frame" % [style, float(Time.get_ticks_usec() - t0) / 1000.0 / 240.0])
	t0 = Time.get_ticks_usec()
	for i in 240:
		for e in men:
			for p in e.f.parts:
				p._process(dt)
	print("LOOKPROF %s parts' step: %.3f ms a frame" % [style, float(Time.get_ticks_usec() - t0) / 1000.0 / 240.0])
	var head: VoxelPart = men[0].f.head
	if not head.fine.is_empty():
		t0 = Time.get_ticks_usec()
		for i in 20:
			FineHead.mood(head, i % 2 == 0, false, 0)
		print("LOOKPROF %s a blink drawn on the fine face: %.3f ms" % [style, float(Time.get_ticks_usec() - t0) / 1000.0 / 20.0])
	# Each process callback's owner, counted by class (what runs every frame).
	var counts := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_processing() or n.is_physics_processing():
			var k := n.get_class() + ("(" + String(n.get_script().get_global_name()) + ")" if n.get_script() else "")
			counts[k] = int(counts.get(k, 0)) + 1
		stack.append_array(n.get_children())
	print("LOOKPROF %s processing: %s" % [style, str(counts)])
	get_tree().quit()
