extends Node
## Menu screenshots (`-- --probe uishots`, needs a display): the Bread & Circuses lobby, a day
## of a run, and the gods' blessing choice. PNGs go to SHOT_DIR.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	Save.set_value("circus_run", null)
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for step in [["ui_circus_lobby", null], ["ui_circus_day", "day"], ["ui_circus_blessing", "bless"]]:
		match step[1]:
			"day":
				var run := Circus.new_run(menu.ludus())
				run.day = 2
				run.bout = 1
				run.blessings = ["mars", "fortuna"]
				run.inventory = {"thunderPot": 2, "bread": 1}
				Save.set_value("circus_run", run)
			"bless":
				var run2 = menu.circus_run()
				run2.pending_blessing = ["venus", "vulcan", "pluto"]
				Save.set_value("circus_run", run2)
		menu.show_screen("circus")
		for i in 90:
			await get_tree().physics_frame
		get_viewport().get_texture().get_image().save_png(out.path_join(step[0] + ".png"))
		print("saved ", step[0])
	Save.set_value("circus_run", null)
	get_tree().quit()
