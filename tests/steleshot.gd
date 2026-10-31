extends Node
## The stele by the gate in the yard, close up (`-- --probe steleshot`, needs a display):
## SHOT_DIR/stele.png. STAGE=n: the bout it announces.

func _ready() -> void:
	if OS.get_environment("STAGE") != "":
		Save.set_value("stage", int(OS.get_environment("STAGE")))
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	for i in 40:
		await get_tree().process_frame
	var root: Node3D = m.yard.next_root
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.current = true
	var fwd: Vector3 = root.global_transform.basis.z
	cam.global_position = root.global_position + fwd * 3.0 + Vector3(0, 1.6, 0) + root.global_transform.basis.x * 0.5
	cam.look_at(root.global_position + Vector3(0, 1.6, 0), Vector3.UP)
	cam.fov = 50.0
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("stele.png"))
	print("saved stele")
	get_tree().quit()
