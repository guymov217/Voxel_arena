extends Node
## Screenshots (`-- --probe shot`, needs a display): the menu, then a fight seen from the
## player's camera. Saves PNGs to SHOT_DIR.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("godot_menu.png"))
	menu.show_screen("yard")
	for i in 5:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("godot_yard.png"))
	menu.start({"mode": "campaign", "stage": int(OS.get_environment("SHOT_STAGE")) if OS.get_environment("SHOT_STAGE") != "" else 1, "autopilot": true})
	menu.match_.me.bot = Bot.new(menu.match_.me.f, 0.9, "standard", 1)
	for i in (int(OS.get_environment("SHOT_QUICK")) if OS.get_environment("SHOT_QUICK") != "" else 120 * 6):
		await get_tree().physics_frame
	if OS.get_environment("SHOT_WIDE") != "":
		menu.match_.cam.follow(null, 0.0, 0.0, 10.0)
		menu.match_.cam.set_process(false)
		menu.match_.set_process(false)
		menu.match_.cam.global_position = Vector3(0, 6.5, -13.5)
		menu.match_.cam.look_at(Vector3(0, 2.0, 6), Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("godot_fight.png"))
	if OS.get_environment("SHOT_QUICK") != "":
		get_tree().quit()
		return
	for i in 120 * 6:
		await get_tree().physics_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("godot_fight2.png"))
	get_tree().quit()
