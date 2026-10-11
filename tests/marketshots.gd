extends Node
## The market screen (`-- --probe marketshots`, needs a display): each tab, with the items'
## pictures made, saved to SHOT_DIR.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for tab in (OS.get_environment("SHOT_ONLY").split(",", false) if OS.get_environment("SHOT_ONLY") != "" else PackedStringArray(["throw", "place", "self"])):
		menu.market_tab = tab
		menu.show_screen("market")
		for i in 40:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("market_%s.png" % tab))
		print("saved market_", tab, " thumbs ", Thumbs.cache.size())
	get_tree().quit()
