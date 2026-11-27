extends Node
## The forge's Select tool, its pinned weapon and its rating on screen (`-- --probe forgeshots2`, needs a display): a pick on a gladius, the bars against a pinned weapon after a change, the
## rating's place with a made-up verdict, saved to SHOT_DIR (forge2_<name>.png). FS_LANG: a language code (Loc.LANGS).

func _shot(name_: String) -> void:
	for i in 8:
		await get_tree().process_frame
	RenderingServer.render_loop_enabled = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("forge2_%s.png" % name_))
	RenderingServer.render_loop_enabled = false
	print("saved ", name_)

func _ready() -> void:
	if OS.get_environment("FS_LANG") != "":
		Loc.apply(OS.get_environment("FS_LANG"))
	var F = load("res://scripts/ui/forge.gd")
	F.pinned = {}
	var f = F.new()
	add_child(f)
	f.free_build = true
	f.open(Data.preset("gladius").duplicate(true), 0, func(_d, _c): pass)
	f._show_mode("voxels")
	f.tool = "select"
	f._toolbar_ui()
	var top := -100
	for k in f.cells:
		top = maxi(top, k.y)
	# The upper half of the blade picked.
	var pick := {}
	for k in f.cells:
		if k.y >= top - 10 and String(f.cells[k][1]) != "grip":
			pick[k] = true
	f._set_sel(pick)
	await _shot("select")
	# Pinned as it is, then lead on the head: the bars against the pin.
	f._pin_now()
	f.tool = "build"
	f._toolbar_ui()
	var add := []
	for k in f.cells.keys():
		if k.y >= top - 4:
			add.append(k + Vector3i(0, 0, 1))
			add.append(k + Vector3i(0, 0, -1))
	f.mat = "lead"
	f.job = "blunt"
	f._place(add)
	await _shot("pin")
	# A made-up verdict, the strip under it.
	WeaponRating._table = {"version": 1, "stamp": WeaponRating.stamp(), "presets": {}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 30:
		WeaponRating._table.presets["w%d" % i] = {"score": 25.0 + rng.randf() * 50.0}
	var bouts := []
	for i in 6:
		bouts.append({"foe": "gladiator", "won": i < 4, "dmg": 60.0 + i, "taken": 30.0 if i < 4 else 90.0, "secs": 15.0, "hits": 5, "big": 22.0})
	var key: String = WeaponRating.key(f._design_now())
	f.rating = {"key": key, "pid": 0, "state": "done", "done": 6, "of": 6, "result": WeaponRating.clean_result({"state": "done", "of": 6, "bouts": bouts})}
	f.rating.result.rank = WeaponRating.rank(float(f.rating.result.summary.score))
	f._show_mode("voxels")
	await get_tree().process_frame
	(f.side_box.get_parent() as ScrollContainer).scroll_vertical = 100000
	await _shot("rating")
	# The same, under way.
	f.rating = {"key": key, "pid": 0, "state": "running", "done": 2, "of": 6, "result": {}}
	f._rating_refresh()
	await _shot("running")
	get_tree().quit()
