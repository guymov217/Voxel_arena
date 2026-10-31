extends Node
## Training through the menu with a save whose numbers came back as floats (JSON): what the
## screen shows is what is spawned.
func _ready() -> void:
	Save.set_value("training", {"enemy": "lion", "count": 3.0, "difficulty": 0.5})
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 10:
		await get_tree().process_frame
	menu.show_screen("training")
	await get_tree().process_frame
	print("TRAIN shown count=", menu.training.count, " ", typeof(menu.training.count))
	menu._start_training()
	for i in 60:
		await get_tree().physics_frame
	print("TRAIN spawned=", menu.match_.enemies().size())
	get_tree().quit()
