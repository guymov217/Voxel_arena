extends Node
## The players' names over their heads (`-- --probe tagshots`, needs a display): two guests
## stand in the yard with the host; the shot looks at them. PNG to SHOT_DIR/tags.png.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "name": "Guy"})
	m.set_process(false)
	var a = m.spawn_fighter({"kind": "remote", "peer": 7, "name": "Marcus", "loadout": {"main": "gladius", "off": ""}, "team": 0, "pos": Vector3(-1.2, 0, 2.5), "yaw": PI})
	var b = m.spawn_fighter({"kind": "remote", "peer": 8, "name": "Livia the Swift", "loadout": {"main": "spear", "off": ""}, "team": 0, "pos": Vector3(1.2, 0, 2.5), "yaw": PI})
	for e in [a, b]:
		e.erase("bot")
		e.drive = func(_e): return {"main": {"x": 0.0, "y": -0.9}, "off": {"x": 0.0, "y": -0.9}}
	m.me.f.teleport(Vector3(0, 0, -1.5))
	for i in 90:
		await get_tree().physics_frame
		m._update_tags()
	m.cam.fov = 45.0
	m.cam.global_position = Vector3(0, 1.9, -3.2)
	m.cam.look_at(Vector3(0, 1.3, 2.5), Vector3.UP)
	m._update_tags()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("tags.png"))
	print("saved tags")
	get_tree().quit()
