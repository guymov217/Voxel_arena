extends Node
## The forge (`-- --probe forgeshots`, needs a display): the cards (an axe with two twists) and
## the voxel tools, a change and what it did by the bars, My designs, saved to SHOT_DIR.

func _save(f, name_: String) -> void:
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("forge_%s.png" % name_))
	print("saved ", name_)

func _ready() -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.open(Data.preset("gladius").duplicate(true), 0, func(d, c): print("took ", d.name if d else null, " cost ", c))
	await _save(f, "start")
	f._pick_base("axe")
	f._toggle_pick(f.dealt[0])
	f._toggle_pick(f.dealt[1])
	await _save(f, "cards")
	f._show_mode("voxels")
	await _save(f, "voxels")
	# A change: lead put on the head; the bars show what it did (▲ / ▼) for a moment.
	var top := -100
	for k in f.cells:
		top = maxi(top, k.y)
	var add := []
	for k in f.cells.keys():
		if k.y >= top - 4:
			add.append(k + Vector3i(0, 0, 1))
			add.append(k + Vector3i(0, 0, -1))
	f.mat = "lead"
	f.job = "blunt"
	f._place(add)
	await _save(f, "change")
	f._save_design()
	f._show_mode("gallery")
	for i in 30:
		await get_tree().process_frame
	await _save(f, "gallery")
	f._take()
	get_tree().quit()
