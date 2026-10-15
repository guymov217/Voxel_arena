extends Node
## Every beast caught mid-stride (`-- --probe gaitshots`, needs a display): each walks at a man
## from across the arena and is shot from the side as it goes. PNGs to SHOT_DIR/gait_<species>.png.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("SHOT_ONLY")
	for sp in Data.beasts:
		if only != "" and only != sp:
			continue
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
		m.me.f.visible = false
		m.me.f.teleport(Vector3(0, 0, -2.0))
		m.set_process(false)
		var e = m.spawn_beast({"beast": sp, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 9.0), "yaw": PI})
		var f = e.f
		var cam: Camera3D = m.cam
		cam.fov = 40.0
		for i in 150:
			f.target = m.me.f
			await get_tree().physics_frame
			var tp: Vector3 = f.torso.global_position
			# Shot when it is well under way and still a few paces off.
			if i > 60 and tp.z < 6.5:
				break
		var box := AABB(f.torso.global_position, Vector3.ZERO)
		for p in f.parts:
			if is_instance_valid(p) and not p.severed:
				box = box.merge(AABB(p.global_position - p.half_ext, p.half_ext * 2.0))
		var c := box.get_center()
		var r := box.size.length() * 0.5
		cam.global_position = c + Vector3(1.0, 0.25, 0.15).normalized() * (r * 2.3 + 0.5)
		cam.look_at(c, Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("gait_%s.png" % sp))
		print("saved gait_", sp)
		m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
