extends Node
## The fight's hotbar (`-- --probe hotbarshot`, needs a display): a training fight with a bag
## of nine kinds of things, saved to SHOT_DIR.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu.start({"mode": "training", "training": {"enemy": "none"}, "inventory_override": {"thunderPot": 2, "greekFire": 1, "bandage": 3, "bread": 1, "wine": 2, "bananas": 1, "darts": 4, "anvil": 1, "cheese": 1}})
	for i in 60:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("hotbar.png"))
	print("saved hotbar")
	get_tree().quit()
