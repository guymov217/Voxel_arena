extends Node
## What a ringing head sees (`-- --probe dazeshots`, needs a display): the arena as a clear head sees it, and as a head rung to CONC (default 0.8) does (daze_<n>.png in SHOT_DIR), the view swimming and closing in.

func _shot(path: String) -> void:
	for i in 6:
		await get_tree().process_frame
	RenderingServer.render_loop_enabled = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	RenderingServer.render_loop_enabled = false

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var conc := float(OS.get_environment("CONC")) if OS.get_environment("CONC") != "" else 0.8
	# (A software renderer takes minutes a frame of an arena on high: the arena drawn light.)
	var st = Save.get_value("settings", {})
	st = st if st is Dictionary else {}
	st["quality"] = "low"
	Save.set_value("settings", st)
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	for i in 20:
		await get_tree().process_frame
	menu.start({"mode": "campaign", "stage": 2})
	for i in 160:
		await get_tree().physics_frame
	var f = menu.match_.me.f
	f.concussion = 0.0
	f.eye_hurt = 0.0
	await _shot(out.path_join("daze_clear.png"))
	f.concussion = conc
	await _shot(out.path_join("daze_rung.png"))
	print("saved")
	get_tree().quit()
