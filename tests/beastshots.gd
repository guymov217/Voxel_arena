extends Node
## A portrait of every beast species (`-- --probe beastshots`, needs a display): each is let into
## an empty arena, given a moment to land and stand, and framed three-quarters from the front with
## the stands behind it. PNGs go to SHOT_DIR as beast_NN_<species>.png; SHOT_ONLY picks one.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("SHOT_ONLY")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
	m.me.f.visible = false
	m.me.f.global_position = Vector3(0, 0, -12)
	m.set_process(false)
	var cam: Camera3D = m.cam
	var n := 0
	for sp in Data.beasts:
		n += 1
		if only != "" and only != sp:
			continue
		var e = m.spawn_beast({"beast": sp, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 2.0), "yaw": PI * 0.85, "harmless": true})
		# A portrait: it stands still.
		e.f.sp = e.f.sp.duplicate()
		e.f.sp.speed = 0.0
		e.f.sp.lunge = 0.0
		e.f.sp.ai = "statue"
		for i in 150:
			await get_tree().physics_frame
		var f = e.f
		# Frame it by its real size: the box around all its parts (wings, necks, tails included).
		var box := AABB(f.torso.global_position, Vector3.ZERO)
		for p in f.parts:
			if is_instance_valid(p) and not p.severed:
				box = box.merge(AABB(p.global_position - p.half_ext, p.half_ext * 2.0))
		var feet := []
		for p in f.parts:
			if is_instance_valid(p) and p.def.get("lower", false):
				var lo := INF
				for sx in [-1, 1]:
					for sy in [-1, 1]:
						for sz in [-1, 1]:
							lo = minf(lo, (p.global_transform * (p.half_ext * Vector3(sx, sy, sz))).y)
				feet.append(snappedf(lo, 0.001))
		for p in f.parts:
			if is_instance_valid(p) and p.def.get("leg", false) and not p.def.get("lower", false):
				print("thigh ", p.part_name, " top ", snappedf((p.global_transform * Vector3(0, p.half_ext.y, 0)).y, 0.001), " body bottom ", snappedf(f.torso.global_position.y - f.torso.half_ext.y, 0.001), " hip ", snappedf((f.torso.global_transform * p.pa).y, 0.001))
				break
		print("feet ", sp, " ", feet, " torso ", snappedf(f.torso.global_position.y, 0.001))
		var c := box.get_center()
		var r := box.size.length() * 0.5
		if OS.get_environment("SHOT_HEAD") != "" and f.head:
			c = f.head.global_position
			r = f.head.half_ext.length() * 1.6
		var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
		var look := fwd.rotated(Vector3.UP, float(OS.get_environment("SHOT_ANGLE")) if OS.get_environment("SHOT_ANGLE") != "" else 0.75)
		cam.fov = 45.0
		cam.global_position = c + look * ((0.0 if OS.get_environment("SHOT_HEAD") != "" else 0.6) + r * 2.0) + Vector3(0, r * 0.18, 0)
		cam.look_at(c, Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		var nm := "beast_%02d_%s" % [n, sp]
		get_viewport().get_texture().get_image().save_png(out.path_join(nm + ".png"))
		print("saved ", nm)
		m.entities.erase(e)
		m.combat.fighters.erase(f)
		f.queue_free()
		await get_tree().physics_frame
	get_tree().quit()
