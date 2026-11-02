extends Node
## The smith's counter with prosthetics on it (`-- --probe prosmithui`, needs a display): a
## veteran with a blade arm the smith has refitted, a hook of his master's work and the
## physician's peg, scrolled down to them. PNG to SHOT_DIR/pro_smith.png.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var body0 = Save.get_value("body", {})
	var coins0 = Save.get_value("coins", null)
	Save.set_value("body", Body.sanitize({"missing": ["forearmR", "forearmL", "shinL"], "prosthetics": {"forearmR": "blade", "forearmL": "hook", "shinL": "peg"}, "pro_up": {"forearmR": 1, "forearmL": 2}}))
	Save.set_value("coins", 160)
	# (The menu's picture behind the panel at its lightest: a software renderer draws it slowly.)
	Save.set_value("settings", {"quality": "low"})
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 3:
		await get_tree().process_frame
	menu.smith_tab = "weapons"
	menu.show_screen("yard")
	print("smith screen up")
	for i in 10:
		await get_tree().process_frame
	for sc in menu.find_children("*", "ScrollContainer", true, false):
		for l in sc.find_children("*", "Label", true, false):
			if String(l.text) == Loc.t("YOUR PROSTHETICS"):
				sc.scroll_vertical = 100000
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("pro_smith.png"))
	print("saved pro_smith")
	Save.set_value("body", body0 if body0 is Dictionary else {})
	if coins0 != null:
		Save.set_value("coins", coins0)
	get_tree().quit()
