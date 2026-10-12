extends Node
## How the arena looks (`-- --probe lookshots`, needs a display): a training bout seen from the
## player's camera, from low on the sand, and wide from the stands. Saves PNGs to SHOT_DIR,
## named with SHOT_TAG.

func _save(name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("%s_%s.png" % [OS.get_environment("SHOT_TAG"), name_]))
	print("saved ", name_)

func _ready() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu.start({"mode": "training", "arena": OS.get_environment("SHOT_ARENA") if OS.get_environment("SHOT_ARENA") != "" else "colosseum", "training": {"enemy": "gladiator", "behaviour": "moves", "weapon": "axe"}})
	var m: Match = menu.match_
	for i in 120 * 3:
		await get_tree().physics_frame
	await _save("player")
	m.set_process(false)
	var cam: Camera3D = m.cam
	cam.set_process(false)
	cam.global_position = Vector3(2.5, 0.7, -3.5)
	cam.look_at(m.me.f.torso.global_position + Vector3(0, 0.2, 3), Vector3.UP)
	await _save("low")
	cam.global_position = Vector3(0, 6.5, -13.5)
	cam.look_at(Vector3(0, 2.0, 6), Vector3.UP)
	await _save("wide")
	cam.global_position = Vector3(0, 1.6, 0)
	cam.look_at(Vector3(0, 9, 14), Vector3.UP)
	await _save("sky")
	get_tree().quit()
