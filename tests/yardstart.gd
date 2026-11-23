extends Node
## The yard's start with a host and seven friends (the user's playtest: "match setup: yard as host, 8 men in 1484 ms"), as a screen's game has it (STAGE=1: the friends' men
## and the yard's people come in over the frames) or as before (STAGE=0): what the start costs, the worst frame after it, and when the last man is in
## (`-- --probe yardstart`, headless; env STAGE, FRIENDS (7)).
func _ready() -> void:
	seed(7)
	var n := int(OS.get_environment("FRIENDS")) if OS.get_environment("FRIENDS") != "" else 7
	var peers := []
	for i in n:
		var p: Dictionary = Friends.PERSONAS[i % Friends.PERSONAS.size()]
		peers.append({"id": 2 + i, "name": String(p.name), "loadout": {"main": String(p.main), "off": String(p.off), "armor": ["helmet", "lorica"] if i % 2 == 0 else []}, "kit": {}})
	var m := Match.new()
	m.stage_always = OS.get_environment("STAGE") == "1"
	add_child(m)
	var t0 := Time.get_ticks_usec()
	m.setup({"mode": "yard", "role": "host", "headless": false, "name": "Ann", "seed": 5, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "scutum", "armor": ["helmet", "lorica"]}, "peers": peers})
	var setup_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var worst := 0.0
	var last := Time.get_ticks_usec()
	var t1 := last
	var friends_at := -1.0
	var all_at := -1.0
	var keepers := 0
	for id in Yard.stations():
		if Yard.STATIONS[id].has("npc"):
			keepers += 1
	for i in 1500:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - last) / 1000.0)
		last = now
		if friends_at < 0.0 and m.coming == 0 and m.humans().size() >= 1 + n:
			friends_at = float(now - t1) / 1000.0
		if all_at < 0.0 and m.coming == 0 and m.yard.dummies.size() == Yard.DUMMIES.size() and m.yard.keepers.size() == keepers:
			all_at = float(now - t1) / 1000.0
		if all_at >= 0.0 and float(now - t1) / 1000.0 > all_at + 300.0:
			break
	print("YARDSTART stage=%s friends=%d: setup %.0f ms (men in after it: %d), friends all in after %.0f ms, everyone after %.0f ms, worst frame after setup %.1f ms" % [OS.get_environment("STAGE"), n, setup_ms, m.humans().size(), friends_at, all_at, worst])
	if OS.get_environment("TEARDOWN") == "1":
		var nodes := _count(m)
		var td0 := Time.get_ticks_usec()
		m.queue_free()
		await get_tree().process_frame
		var td1 := Time.get_ticks_usec()
		await get_tree().process_frame
		var td2 := Time.get_ticks_usec()
		print("YARDSTART teardown of %d nodes: the frame that frees them %.0f ms, the next %.0f ms" % [nodes, float(td1 - td0) / 1000.0, float(td2 - td1) / 1000.0])
	get_tree().quit()

func _count(n: Node) -> int:
	var c := 1
	for k in n.get_children():
		c += _count(k)
	return c
