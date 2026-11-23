extends Node
## A campaign bout's start with a host and three friends, as a screen's game has it (STAGE=1: the foes come in over the frames) or as before (STAGE=0),
## cold (every cache empty) or WARM=1 (after a yard of the same men, as the game has it): what the start costs, and the worst frame after it
## (`-- --probe startbout`, headless; env BOUT (43), STAGE, WARM).
func _bout(stage_n: int) -> Match:
	var m := Match.new()
	m.stage_always = OS.get_environment("STAGE") == "1"
	add_child(m)
	m.setup({"mode": "campaign", "stage": stage_n, "role": "host", "headless": false, "name": "Ann", "seed": 5, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "scutum", "armor": ["helmet", "lorica"]}, "peers": [{"id": 2, "name": "Bob", "loadout": {"main": "axe", "armor": ["helmet"]}}, {"id": 3, "name": "Cy", "loadout": {"main": "spear", "armor": []}}, {"id": 4, "name": "Di", "loadout": {"main": "gladius", "armor": ["lorica"]}}]})
	return m

func _ready() -> void:
	seed(7)
	var bout := int(OS.get_environment("BOUT")) if OS.get_environment("BOUT") != "" else 43
	if OS.get_environment("WARM") == "1":
		var y := Match.new()
		add_child(y)
		y.setup({"mode": "yard", "role": "host", "headless": false, "name": "Ann", "seed": 5, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "scutum", "armor": ["helmet", "lorica"]}, "peers": [{"id": 2, "name": "Bob", "loadout": {"main": "axe", "armor": ["helmet"]}}, {"id": 3, "name": "Cy", "loadout": {"main": "spear", "armor": []}}, {"id": 4, "name": "Di", "loadout": {"main": "gladius", "armor": ["lorica"]}}]})
		await get_tree().process_frame
		y.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var m := _bout(bout)
	var setup_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var want: int = (Data.stage(bout, 4).rounds[0] as Array).size()
	var n0 := m.enemies().size()
	var worst := 0.0
	var last := Time.get_ticks_usec()
	var t1 := Time.get_ticks_usec()
	var all_at := -1.0
	for i in 900:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - last) / 1000.0)
		last = now
		if all_at < 0.0 and m.enemies().size() >= want and m.coming == 0:
			all_at = float(now - t1) / 1000.0
		if all_at >= 0.0 and i > 30 and float(now - t1) / 1000.0 > all_at + 300.0:
			break
	print("STARTBOUT stage=%s warm=%s: setup %.0f ms (foes in after it: %d of %d), all in after %.0f ms, worst frame after setup %.1f ms" % [OS.get_environment("STAGE"), OS.get_environment("WARM"), setup_ms, n0, want, all_at, worst])
	get_tree().quit()
