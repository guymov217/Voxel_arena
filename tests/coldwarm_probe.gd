extends Node
## What a man costs to build the first time in a game and the second (`-- --probe coldwarm_probe`; env ARMOR (helmet,lorica,greaves,manica), MAIN (gladius), OFF (scutum)): the caches the builds keep (Fighter._listed,
## FineBody._shell_maps, FineArmor._shells, the sculpts) are what a game's first fight pays and its second does not.
func _build(m: Match, armor: Array) -> float:
	var t0 := Time.get_ticks_usec()
	var e = m.spawn_fighter({"kind": "bot", "name": "Warm", "loadout": {"main": OS.get_environment("MAIN") if OS.get_environment("MAIN") != "" else "gladius", "off": OS.get_environment("OFF") if OS.get_environment("OFF") != "" else "scutum", "armor": armor}, "team": 0, "pos": Vector3(0, 0, 0), "yaw": 0.0})
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	m._remove_entity(e)
	return ms

func _ready() -> void:
	seed(3)
	var armor: Array = (OS.get_environment("ARMOR") if OS.get_environment("ARMOR") != "" else "helmet,lorica,greaves,manica").split(",")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": false, "seed": 3, "decrees": [], "hazards": []})
	if OS.get_environment("WARM") == "apart":
		# The menu's warm-up (Menu._prewarm): one man built apart over the frames, out of the world, and let go.
		var spec := {"kind": "bot", "name": "Warm", "loadout": {"main": "gladius", "off": "scutum", "armor": armor}, "team": 0, "pos": Vector3(0, 0, 0), "yaw": 0.0}
		var t0 := Time.get_ticks_usec()
		var worst := 0.0
		var last := t0
		var f = await m._build_apart(spec)
		print("COLDWARM the warm-up man built apart in %.0f ms over frames" % (float(Time.get_ticks_usec() - t0) / 1000.0))
		if f != null:
			f.queue_free()
		await get_tree().process_frame
	var first := _build(m, armor)
	await get_tree().process_frame
	var second := _build(m, armor)
	await get_tree().process_frame
	var third := _build(m, armor)
	print("COLDWARM a man in %s: the first %.0f ms, the second %.0f, the third %.0f" % [str(armor), first, second, third])
	get_tree().quit()
