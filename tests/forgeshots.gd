extends Node
## The forge (`-- --probe forgeshots`, needs a display): the cards (an axe with two twists) and
## the voxel tools, My designs and the help, saved to SHOT_DIR.

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
	f._save_design()
	f._show_mode("gallery")
	for i in 30:
		await get_tree().process_frame
	await _save(f, "gallery")
	f._show_mode("help")
	await _save(f, "help")
	f._take()
	get_tree().quit()
