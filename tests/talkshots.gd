extends Node
## A gladiator talking (`-- --probe talkshots`, needs a display): his mouth shut, a crack, open
## and wide (Physique.talk, as the proximity voice drives it), close on his face. PNGs to SHOT_DIR.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
	m.set_process(false)
	var cam: Camera3D = m.cam
	var e = m.spawn_fighter({"kind": "bot", "name": "Talker", "loadout": {"main": "gladius", "off": ""}, "team": 0, "pos": Vector3(0, 0, 2), "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	m.me.f.teleport(Vector3(0, 0, -10))
	for i in 120:
		await get_tree().physics_frame
	var f: Fighter = e.f
	for state in [0, 1, 2, 3]:
		Physique.talk(f, state)
		var c: Vector3 = f.head.global_position
		var fwd: Vector3 = f.head.global_transform.basis.z   # (the face is the grid's far z: +z)
		# (The face is the head's front: whichever way it looks, the camera stands before it.)
		var front := Vector3(fwd.x, 0.0, fwd.z).normalized() if absf(fwd.y) < 0.9 else Vector3(0, 0, -1)
		cam.fov = 35.0
		cam.global_position = c + (front * 0.85 + Vector3(0, 0.05, 0) + front.cross(Vector3.UP) * 0.18)
		cam.look_at(c + Vector3(0, -0.02, 0), Vector3.UP)
		for k in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("talk_%d.png" % state))
		print("saved talk_", state)
	get_tree().quit()
