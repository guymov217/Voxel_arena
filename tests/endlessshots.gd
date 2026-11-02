extends Node
## The endless arena on screen (`-- --probe endlessshots`, needs a display): the main menu with
## its entry, its own screen, its armour, the Arena's card, a wave on the sand with the HUD's
## line, and the rewards between waves. PNGs go to SHOT_DIR as endless_<what>.png. DEMO=1: as
## the demo has it; PICK_LANG=de: in that language.

func _shot(what: String) -> void:
	var lang := OS.get_environment("PICK_LANG")
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("endless_%s%s.png" % [what, ("_" + lang) if lang != "" else ""]))
	print("saved ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	var st = Save.get_value("settings", {})
	st = st if st is Dictionary else {}
	st["quality"] = OS.get_environment("QUALITY") if OS.get_environment("QUALITY") != "" else "low"
	Save.set_value("settings", st)
	if OS.get_environment("DEMO") != "":
		Edition.forced = true
	if OS.get_environment("PICK_LANG") != "":
		Loc.apply(OS.get_environment("PICK_LANG"))
	Save.set_value("endless", {"best": 7, "daily": {"day": Time.get_date_string_from_system(true), "best": 4}})
	Save.set_value("endless_kit", {"main": "gladius", "off": "dagger", "armor": ["helmet", "manica"], "pots": ["thunderPot", "nailPot"], "daily": true})
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	await _frames(30)
	# MATCH_ONLY=1: the bout alone (a software renderer takes seconds a frame over the arena).
	if OS.get_environment("MATCH_ONLY") == "":
		for s in ["main", "endless", "endless_armour", "fights"]:
			menu.show_screen(s)
			await _frames(60)
			_shot(s)
	menu.show_screen("endless")
	await _frames(10)
	menu._start_endless()
	await _frames(30)
	var en: Endless = menu.match_.modes.endless
	en.update(Endless.START_DELAY + 0.1)
	var wf := int(OS.get_environment("WAVE_FRAMES")) if OS.get_environment("WAVE_FRAMES") != "" else 150
	await _frames(wf)
	_shot("wave")
	for e in menu.match_.enemies():
		e.f.die("wounds")
	await _frames(maxi(12, wf / 4))
	_shot("offer")
	get_tree().paused = false
	get_tree().quit()
