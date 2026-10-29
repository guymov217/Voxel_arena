extends Node
## The smith's screen in the yard (`-- --probe smithui`, needs a display): PNG to SHOT_DIR, and
## whether the window fits the screen.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var sz := OS.get_environment("SMITH_SIZE").split("x")
	if sz.size() == 2:
		get_tree().root.content_scale_size = Vector2i(int(sz[0]), int(sz[1]))
		get_tree().root.size = Vector2i(int(sz[0]), int(sz[1]))
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 10:
		await get_tree().process_frame
	menu.show_screen("yard")
	for i in 20:
		await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size
	var r: Rect2 = menu.panel.get_global_rect()
	print("SMITHUI viewport %s panel %s right edge %.0f fits %s" % [vp, r, r.end.x, r.end.x <= vp.x + 1.0])
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(out.path_join("smith_ui.png"))
	get_tree().quit()
