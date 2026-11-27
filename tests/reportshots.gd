extends Node
## The bout's report on its screen (`-- --probe reportshots`, needs a display): a made-up bout for one man, two, four and eight, each as it fills (rep_<n>_mid.png) and as it ends (rep_<n>.png).
## SHOT_DIR: where the PNGs go, REP_N: the men (comma list: 1,2,4,8), REP_LANG: a language code (Loc.LANGS), REP_LOST: 1 for a bout lost.

const NAMES := ["Marcus", "Livia", "Brutus", "Aelia", "Titus", "Valeria", "Gaius Julius Caesar the Long-Named", "Nero"]

func _report(n: int, lost: bool) -> Dictionary:
	var rows := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + n
	for i in n:
		rows.append({"name": NAMES[i], "kills": rng.randi_range(0, 7), "dmg": rng.randi_range(40, 400), "hurt": rng.randi_range(20, 220), "big": rng.randi_range(14, 60), "hits": rng.randi_range(5, 40),
			"cut": rng.randi_range(0, 4), "limbs": rng.randi_range(0, 2), "lifts": rng.randi_range(0, 2), "fav": rng.randi_range(20, 95), "earned": 0, "alive": i != 2 or n == 1})
	var purse := {"each": 148, "base": 90, "rounds": 20, "crowd": 28, "fav": 10, "favourite": NAMES[1] if n > 1 else ""}
	var shares := BoutReport.split(rows.map(func(r): return maxf(0.0, float(r.fav) - 20.0)), purse.crowd)
	for i in n:
		rows[i].earned = int(shares[i]) + (purse.fav if String(rows[i].name) == String(purse.favourite) else 0)
	return {"rows": rows, "purse": purse, "secs": 161.4, "won": not lost}

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var lang := OS.get_environment("REP_LANG")
	if lang != "":
		Loc.apply(lang)
	# (A software renderer takes minutes a frame of an arena on high: the arena drawn light.)
	if OS.get_environment("REP_ARENA") != "":
		var st = Save.get_value("settings", {})
		st = st if st is Dictionary else {}
		st["quality"] = "low"
		Save.set_value("settings", st)
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	for i in 20:
		await get_tree().process_frame
	var which := (OS.get_environment("REP_N") if OS.get_environment("REP_N") != "" else "1,2,4,8").split(",")
	# REP_ARENA=1: over the arena of a bout begun (the report held over it as the game holds it: Menu._report_wait).
	if OS.get_environment("REP_ARENA") != "":
		menu.start({"mode": "campaign", "stage": 2})
		for i in 140:
			await get_tree().physics_frame
		var n1 := int(which[0])
		menu.report_wait = false
		var r := {"won": true, "stage": 2, "report": _report(n1, false)}
		menu._report_wait(r, menu.match_)
		await get_tree().create_timer(3.4).timeout
		await _shot(out.path_join("rep_arena_%d.png" % n1))
		print("saved arena ", n1)
		get_tree().quit()
		return
	for w in which:
		var n := int(w)
		var lost := OS.get_environment("REP_LOST") != ""
		menu.report_info = {"report": _report(n, lost), "title": Loc.t("You fall") if lost else Loc.t("Stage %d cleared") % 5}
		menu.report_wait = true
		menu.show_screen("report")
		await get_tree().create_timer(0.7).timeout
		await _shot(out.path_join("rep_%d_mid.png" % n))
		await get_tree().create_timer(2.6).timeout
		await _shot(out.path_join("rep_%d.png" % n))
		print("saved ", n)
	get_tree().quit()

## The frame as it is now (the render loop is off in a run under --disable-render-loop: on for the two frames it takes).
func _shot(path: String) -> void:
	RenderingServer.render_loop_enabled = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	RenderingServer.render_loop_enabled = false
