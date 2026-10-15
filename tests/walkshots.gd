extends Node
## A man walking (`-- --probe walkshots`, needs a display): a gladiator walks across the sand,
## photographed from the side every half second, to check he stands on his legs and does not
## float. PNGs to SHOT_DIR/walk_<n>.png.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(-6, 0, -6))
	m.set_process(false)
	var e = m.spawn_fighter({"kind": "bot", "name": "Walker", "loadout": {"main": "gladius", "off": "roundShield"}, "team": 1, "pos": Vector3(-4, 0, 0), "yaw": PI * 0.5})
	e.erase("bot")
	var phase := [0]
	e.drive = func(_e): return {"mz": 1.0, "sprint": phase[0] >= 3, "main": {"x": 0.1, "y": 0.1}}
	var cam: Camera3D = m.cam
	cam.fov = 40.0
	var n := 0
	for i in 6 * 60:
		await get_tree().physics_frame
		if i % 60 == 30:
			phase[0] += 1
			var tp: Vector3 = e.f.torso.global_position
			cam.global_position = tp + Vector3(0, 0.1, 4.2)
			cam.look_at(Vector3(tp.x, 0.8, tp.z), Vector3.UP)
			await get_tree().process_frame
			await get_tree().process_frame
			n += 1
			get_viewport().get_texture().get_image().save_png(out.path_join("walk_%d.png" % n))
			var sole_l: Vector3 = e.f.by_name.shinL.global_transform * Vector3(0, -4 * Fighter.V * e.f.S, 0)
			var sole_r: Vector3 = e.f.by_name.shinR.global_transform * Vector3(0, -4 * Fighter.V * e.f.S, 0)
			print("walk %d torso.y %.2f soles y %.2f %.2f v %.2f" % [n, tp.y, sole_l.y, sole_r.y, e.f.torso.linear_velocity.length()])
	get_tree().quit()
