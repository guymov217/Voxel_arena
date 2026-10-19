extends Node
## Every menu screen in turn (`-- --probe menushots`, needs a display): the main menu, the
## fights, training, multiplayer, options, controls, the gladiator, Bread & Circuses and the
## forge (quick start and by hand), and the options' graphics tab. PNGs go to SHOT_DIR as
## menu_<screen>.png.

const SCREENS := ["main", "fights", "training", "mp", "options", "controls", "gladiator", "circus"]

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 30:
		await get_tree().process_frame
	for s in SCREENS:
		menu.show_screen(s)
		for i in 45:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("menu_%s.png" % s))
		print("saved ", s)
	menu.show_screen("main")
	var f = load("res://scripts/ui/forge.gd").new()
	menu.add_child(f)
	f.open(Data.preset("gladius").duplicate(true), 400, func(_d, _c): pass)
	for i in 45:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("menu_forge.png"))
	print("saved forge")
	f._show_mode("voxels")
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("menu_forge_voxels.png"))
	print("saved forge voxels")
	f.queue_free()
	menu.options_tab = "graphics"
	menu.show_screen("options")
	for i in 45:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("menu_options_graphics.png"))
	print("saved options graphics")
	get_tree().quit()
